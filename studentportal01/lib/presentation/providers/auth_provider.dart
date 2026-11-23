import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/user_model.dart';
import '../../data/models/enrollment_model.dart';
import '../../data/models/school_model.dart';
import '../../core/services/connectivity_service.dart';
import '../../data/services/offline_cache_service.dart';

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

class AuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final UserModel? user;
  final SchoolModel? school;
  final EnrollmentModel? enrollment;
  final String? errorMessage;
  final bool accessDenied; // Non-student tried to login
  final bool schoolSuspended; // School SaaS subscription suspended

  AuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    this.user,
    this.school,
    this.enrollment,
    this.errorMessage,
    this.accessDenied = false,
    this.schoolSuspended = false,
  });

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    UserModel? user,
    SchoolModel? school,
    EnrollmentModel? enrollment,
    String? errorMessage,
    bool? accessDenied,
    bool? schoolSuspended,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
      school: school ?? this.school,
      enrollment: enrollment ?? this.enrollment,
      errorMessage: errorMessage,
      accessDenied: accessDenied ?? this.accessDenied,
      schoolSuspended: schoolSuspended ?? this.schoolSuspended,
    );
  }

  bool get isAccessLocked =>
      schoolSuspended || (user != null && user!.isSuspended);
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState(isLoading: true)) {
    _init();
  }

  final _supabase = Supabase.instance.client;
  RealtimeChannel? _userChannel;
  RealtimeChannel? _schoolChannel;
  RealtimeChannel? _schoolSubChannel;

  void _init() {
    debugPrint('AuthNotifier: Initializing...');
    
    // Immediately restore cached user if available for offline / instant launch
    _loadCachedUserImmediately();

    _supabase.auth.onAuthStateChange.listen(
      (data) {
        final event = data.event;
        final session = data.session;
        debugPrint('AuthNotifier: Auth event: $event, hasSession: ${session != null}');

        if (event == AuthChangeEvent.signedIn || event == AuthChangeEvent.initialSession) {
          if (session != null) {
            _loadUserData().then((_) {
              // Only subscribe to realtime after user data is loaded
              _subscribeToUserChanges();
            });
          } else {
            // Check if we have an offline cached user before giving up
            final cached = OfflineCacheService.instance.getMap('cached_user');
            if (cached == null) {
              debugPrint('AuthNotifier: No session on $event');
              state = AuthState(isLoading: false);
            }
          }
        } else if (event == AuthChangeEvent.signedOut) {
          _unsubscribeFromUserChanges(); // Clean up subscription
          state = AuthState();
        } else if (event == AuthChangeEvent.tokenRefreshed) {
          // Session refreshed, make sure we have user data
          if (state.user == null && session != null) {
            _loadUserData();
          }
        }
      },
      onError: (error) {
        // Silently ignore token refresh network errors — the app keeps working
        // with the existing session until connectivity is restored.
        debugPrint('AuthNotifier: Auth stream error (network?): $error');
        ConnectivityService.instance.reportNetworkError(error);
      },
    );

    // Check if already logged in (immediate check)
    final session = _supabase.auth.currentSession;
    debugPrint('AuthNotifier: Initial session check: ${session != null}');
    if (session != null) {
      _loadUserData().then((_) {
        // Only subscribe to realtime after user data is loaded
        _subscribeToUserChanges();
      });
    } else {
      // Wait for initialSession event, but set a timeout
      Future.delayed(const Duration(seconds: 2), () {
        if (state.isLoading && !state.isAuthenticated) {
          // Only mark unauthenticated if no cached user exists
          final cached = OfflineCacheService.instance.getMap('cached_user');
          if (cached == null) {
            debugPrint('AuthNotifier: Timeout waiting for session, marking as not authenticated');
            state = AuthState(isLoading: false);
          }
        }
      });
    }
  }

  void _loadCachedUserImmediately() {
    try {
      final cachedUserMap = OfflineCacheService.instance.getMap('cached_user');
      if (cachedUserMap != null) {
        final cachedEnrollmentMap = OfflineCacheService.instance.getMap('cached_enrollment');
        final cachedSchoolMap = OfflineCacheService.instance.getMap('cached_school');

        final user = UserModel.fromJson(cachedUserMap);
        final enrollment = cachedEnrollmentMap != null
            ? EnrollmentModel.fromJson(cachedEnrollmentMap)
            : null;
        final school = cachedSchoolMap != null
            ? SchoolModel.fromJson(cachedSchoolMap)
            : null;
        final cachedSchoolSuspended =
            OfflineCacheService.instance.getBool('cached_school_suspended') ??
            (school != null && (!school.isActive || school.isSuspended));

        state = AuthState(
          isLoading: false,
          isAuthenticated: true,
          user: user,
          enrollment: enrollment,
          school: school,
          schoolSuspended: cachedSchoolSuspended,
        );
        debugPrint('AuthNotifier: Loaded cached user on startup: ${user.fullName}');
      }
    } catch (e) {
      debugPrint('AuthNotifier: Error reading initial cached user: $e');
    }
  }

  /// Subscribe to real-time changes for the current user
  void _subscribeToUserChanges() {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Unsubscribe from previous channel if exists
      _unsubscribeFromUserChanges();

      debugPrint('AuthNotifier: Subscribing to real-time updates for user $userId');

      _userChannel = _supabase
          .channel('user_changes_$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'users',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: userId,
            ),
            callback: (payload) {
              debugPrint('AuthNotifier: Real-time update received for user!');
              debugPrint('AuthNotifier: New data: ${payload.newRecord}');
              
              // Update user data from the payload
              final newData = payload.newRecord;
              if (newData.isNotEmpty && state.user != null) {
                try {
                  final merged = {
                    ...state.user!.toJson(),
                    ...newData,
                  };
                  final updatedUser = UserModel.fromJson(merged);
                  state = state.copyWith(user: updatedUser);
                  OfflineCacheService.instance.setJson('cached_user', updatedUser.toJson());
                  debugPrint('AuthNotifier: User updated in real-time: ${updatedUser.fullName}, suspended=${updatedUser.isSuspended}');
                } catch (e) {
                  debugPrint('AuthNotifier: Error parsing real-time update: $e');
                  _loadUserData();
                }
              }
            },
          )
          .subscribe();

      // Also subscribe to school changes if schoolId is known
      final schoolId = state.user?.schoolId;
      if (schoolId != null) {
        _schoolChannel = _supabase
            .channel('school_changes_$schoolId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'schools',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'id',
                value: schoolId,
              ),
              callback: (payload) {
                final newSchool = payload.newRecord;
                final bool isActive = (newSchool['is_active'] as bool?) ?? true;
                final String? status = newSchool['status']?.toString();
                final bool isSuspended = !isActive || status == 'suspended' || status == 'inactive';
                debugPrint('AuthNotifier: Realtime school update: is_active=$isActive, status=$status');
                state = state.copyWith(schoolSuspended: isSuspended);
                OfflineCacheService.instance.setBool('cached_school_suspended', isSuspended);
              },
            )
            .subscribe();

        _schoolSubChannel = _supabase
            .channel('school_sub_changes_$schoolId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'school_subscriptions',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'school_id',
                value: schoolId,
              ),
              callback: (payload) {
                final newSub = payload.newRecord;
                final status = newSub['status']?.toString();
                final bool isSuspended = status == 'suspended';
                debugPrint('AuthNotifier: Realtime school_subscription update: status=$status');
                state = state.copyWith(schoolSuspended: isSuspended);
                OfflineCacheService.instance.setBool('cached_school_suspended', isSuspended);
              },
            )
            .subscribe();
      }
    } catch (e) {
      debugPrint('AuthNotifier: Error setting up realtime subscription: $e');
    }
  }

  /// Unsubscribe from real-time changes
  void _unsubscribeFromUserChanges() {
    if (_userChannel != null) {
      debugPrint('AuthNotifier: Unsubscribing from real-time user updates');
      _supabase.removeChannel(_userChannel!);
      _userChannel = null;
    }
    if (_schoolChannel != null) {
      debugPrint('AuthNotifier: Unsubscribing from real-time school updates');
      _supabase.removeChannel(_schoolChannel!);
      _schoolChannel = null;
    }
    if (_schoolSubChannel != null) {
      debugPrint('AuthNotifier: Unsubscribing from real-time school subscription updates');
      _supabase.removeChannel(_schoolSubChannel!);
      _schoolSubChannel = null;
    }
  }

  @override
  void dispose() {
    _unsubscribeFromUserChanges();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('AuthProvider: No current user ID');
      state = AuthState(isLoading: false);
      return;
    }

    debugPrint('AuthProvider: Loading user data for $userId');
    state = state.copyWith(isLoading: true);

    try {
      // Load user profile - use explicit column selection to avoid 406 errors
      Map<String, dynamic>? userResponse;
      
      try {
        userResponse = await _supabase
            .from('users')
            .select('id, school_id, role, full_name, email, phone, photo_url, student_code, date_of_birth, address, created_at, updated_at, niveau, niveau_code, section_code, niveau_id, section_id, initial_password, account_status, is_active')
            .eq('id', userId)
            .maybeSingle();
      } catch (e) {
        debugPrint('AuthProvider: Error fetching user (RLS issue?): $e');
        // Try using RPC function that bypasses RLS
        try {
          final rpcResult = await _supabase.rpc('get_current_user_data');
          if (rpcResult != null) {
            userResponse = rpcResult as Map<String, dynamic>;
          }
        } catch (rpcError) {
          debugPrint('AuthProvider: RPC fallback also failed: $rpcError');
        }
      }
      
      if (userResponse == null) {
        debugPrint('AuthProvider: No user profile found for ID $userId (offline or RLS)');
        final cachedUserMap = OfflineCacheService.instance.getMap('cached_user');
        if (cachedUserMap != null) {
          final cachedEnrollmentMap = OfflineCacheService.instance.getMap('cached_enrollment');
          final cachedSchoolMap = OfflineCacheService.instance.getMap('cached_school');
          final cachedUser = UserModel.fromJson(cachedUserMap);
          final cachedSchool = cachedSchoolMap != null
              ? SchoolModel.fromJson(cachedSchoolMap)
              : state.school;
          final cachedSchoolSuspended =
              OfflineCacheService.instance.getBool('cached_school_suspended') ??
              (cachedSchool != null && (!cachedSchool.isActive || cachedSchool.isSuspended)) ||
              state.schoolSuspended;

          // CRITICAL SECURITY GUARD:
          // If the student or school was already suspended, NEVER allow an offline fallback
          // to reactivate them into the app!
          final wasLocked = state.isAccessLocked ||
              cachedUser.isSuspended ||
              cachedSchoolSuspended;

          final effectiveUser = wasLocked && !cachedUser.isSuspended
              ? cachedUser.copyWith(accountStatus: 'paused_unpaid', isActive: false)
              : cachedUser;

          state = state.copyWith(
            isLoading: false,
            isAuthenticated: true,
            user: effectiveUser,
            enrollment: cachedEnrollmentMap != null
                ? EnrollmentModel.fromJson(cachedEnrollmentMap)
                : state.enrollment,
            school: cachedSchool,
            errorMessage: null,
            accessDenied: false,
            schoolSuspended: wasLocked ? (cachedSchoolSuspended || state.schoolSuspended) : false,
          );
          ConnectivityService.instance.reportNetworkError('Server unreachable / offline');
          debugPrint('AuthProvider: Used offline cache for user profile (wasLocked=$wasLocked)');
          return;
        }

        state = AuthState(
          isLoading: false,
          errorMessage: 'Profil utilisateur non trouvé. Veuillez contacter l\'administration.',
        );
        return;
      }
      
      debugPrint('AuthProvider: User loaded: ${userResponse['email']}, school_id: ${userResponse['school_id']}');
      final user = UserModel.fromJson(userResponse);

      // ============================================
      // STUDENT APP: ROLE CHECK - STUDENTS ONLY
      // ============================================
      if (user.role != 'student') {
        // Non-student trying to access student app
        debugPrint('AuthProvider: User is not a student, role=${user.role}');
        await _supabase.auth.signOut(scope: SignOutScope.local);
        state = AuthState(
          accessDenied: true,
          errorMessage: 'Access denied. This app is for students only. Please use the admin dashboard.',
        );
        return;
      }

      // Load enrollment - try RPC first (bypasses RLS), then fallback to direct query
      debugPrint('AuthProvider: Loading enrollment...');
      Map<String, dynamic>? enrollmentData;
      
      // Try RPC function first (most reliable, bypasses RLS)
      try {
        final rpcResult = await _supabase.rpc('get_my_enrollment_data');
        if (rpcResult != null) {
          enrollmentData = Map<String, dynamic>.from(rpcResult as Map);
          debugPrint('AuthProvider: Got enrollment from RPC: classId=${enrollmentData['class_id']}');
        }
      } catch (e) {
        debugPrint('AuthProvider: RPC get_my_enrollment_data failed: $e');
      }
      
      // Fallback to direct query if RPC failed
      if (enrollmentData == null) {
        try {
          final enrollmentResponse = await _supabase
              .from('enrollments')
              .select('id, user_id, class_id, group_id, academic_year_id, created_at')
              .eq('user_id', userId)
              .maybeSingle();
          
          if (enrollmentResponse != null) {
            // Fetch related data separately
            final classId = enrollmentResponse['class_id'] as String?;
            final groupId = enrollmentResponse['group_id'] as String?;
            final academicYearId = enrollmentResponse['academic_year_id'] as String?;
            
            Map<String, dynamic>? classData;
            Map<String, dynamic>? groupData;
            Map<String, dynamic>? academicYearData;
            
            // Fetch class info
            if (classId != null) {
              try {
                classData = await _supabase
                    .from('classes')
                    .select('id, school_id, name, room, capacity, is_active, created_at, niveau_id, section_id')
                    .eq('id', classId)
                    .maybeSingle();

                if (classData != null) {
                  // Resolve niveau if present
                  final classNiveauId = classData['niveau_id'] as String? ?? userResponse['niveau_id'] as String?;
                  if (classNiveauId != null) {
                    try {
                      final niveauResp = await _supabase
                          .from('niveaux')
                          .select('id, code, name, name_ar, cycle, has_sections')
                          .eq('id', classNiveauId)
                          .maybeSingle();
                      if (niveauResp != null) {
                        classData['niveaux'] = niveauResp;
                      }
                    } catch (_) {}
                  }

                  // Resolve section if present
                  final classSectionId = classData['section_id'] as String? ?? userResponse['section_id'] as String?;
                  if (classSectionId != null) {
                    try {
                      final sectionResp = await _supabase
                          .from('sections')
                          .select('id, code, name, name_ar')
                          .eq('id', classSectionId)
                          .maybeSingle();
                      if (sectionResp != null) {
                        classData['sections'] = sectionResp;
                      }
                    } catch (_) {}
                  }
                }
              } catch (e) {
                debugPrint('AuthProvider: Error fetching class: $e');
              }
            }
            
            // Fetch group info
            if (groupId != null) {
              try {
                groupData = await _supabase
                    .from('groups')
                    .select('id, name, class_id, created_at')
                    .eq('id', groupId)
                    .maybeSingle();
              } catch (e) {
                debugPrint('AuthProvider: Error fetching group: $e');
              }
            }
            
            // Fetch academic year info
            if (academicYearId != null) {
              try {
                academicYearData = await _supabase
                    .from('academic_years')
                    .select('id, school_id, name, start_date, end_date, is_current, created_at')
                    .eq('id', academicYearId)
                    .maybeSingle();
              } catch (e) {
                debugPrint('AuthProvider: Error fetching academic year: $e');
              }
            }
            
            // Build enrollment with nested data
            enrollmentData = {
              ...enrollmentResponse,
              'classes': classData,
              'groups': groupData,
              'academic_years': academicYearData,
            };
          }
        } catch (e) {
          debugPrint('AuthProvider: Error fetching enrollment directly: $e');
        }
      }

      EnrollmentModel? enrollment;
      if (enrollmentData != null && enrollmentData['class_id'] != null) {
        enrollment = EnrollmentModel.fromJson(enrollmentData);
        debugPrint('AuthProvider: Enrollment loaded, classId=${enrollment.classId}, schoolId=${enrollmentData['classes']?['school_id']}');
      } else {
        debugPrint('AuthProvider: No enrollment found for user');
      }

      SchoolModel? school;
      bool schoolSuspended = false;
      if (user.schoolId != null) {
        // Tier 1: Check authoritative check_user_access_status RPC
        try {
          final accessCheck = await _supabase.rpc('check_user_access_status');
          if (accessCheck != null && accessCheck is Map) {
            final isLocked = accessCheck['is_locked'] == true;
            final reason = accessCheck['reason']?.toString();
            if (isLocked && (reason == 'school_suspended' || reason == 'user_suspended')) {
              schoolSuspended = true;
            }
          }
        } catch (_) {}

        // Tier 2: Check authoritative check_school_active_status RPC
        try {
          final schoolCheck = await _supabase.rpc(
            'check_school_active_status',
            params: {'p_school_id': user.schoolId},
          );
          if (schoolCheck != null && schoolCheck is Map) {
            if (schoolCheck['is_suspended'] == true) {
              schoolSuspended = true;
            }
          }
        } catch (_) {}

        // Tier 3: Direct schools table query (isolated from join errors)
        try {
          final schoolResp = await _supabase
              .from('schools')
              .select('id, name, logo_url, address, phone, email, code, primary_color, secondary_color, is_active, status, created_at')
              .eq('id', user.schoolId!)
              .maybeSingle();
          if (schoolResp != null) {
            final isActiveSchool = schoolResp['is_active'] as bool? ?? true;
            final status = schoolResp['status']?.toString();
            if (!isActiveSchool || status == 'suspended' || status == 'inactive') {
              schoolSuspended = true;
            }
            school = SchoolModel.fromJson({
              ...schoolResp,
              'is_active': isActiveSchool,
              'is_suspended': schoolSuspended,
            });
            debugPrint('AuthProvider: School loaded: ${school.name}, code=${school.code}, suspended=$schoolSuspended');
          } else {
            schoolSuspended = true;
          }
        } catch (e) {
          debugPrint('AuthProvider: Error loading school branding: $e');
        }

        // Tier 4: Direct subscription check
        try {
          final subResp = await _supabase
              .from('school_subscriptions')
              .select('status')
              .eq('school_id', user.schoolId!)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
          if (subResp != null && subResp['status'] == 'suspended') {
            schoolSuspended = true;
          }
        } catch (_) {}
      }

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        user: user,
        school: school,
        enrollment: enrollment,
        errorMessage: null,
        accessDenied: false,
        schoolSuspended: schoolSuspended,
      );

      // Save to persistent offline cache
      OfflineCacheService.instance.setJson('cached_user', user.toJson());
      OfflineCacheService.instance.setBool('cached_school_suspended', schoolSuspended);
      if (enrollment != null) {
        OfflineCacheService.instance.setJson('cached_enrollment', enrollment.toJson());
      }
      if (school != null) {
        OfflineCacheService.instance.setJson('cached_school', school.toJson());
      }
      ConnectivityService.instance.reportNetworkSuccess();

      debugPrint('AuthProvider: Authentication complete, isAuthenticated=true, hasEnrollment=${enrollment != null}, school=${school?.name}');
    } catch (e, stack) {
      debugPrint('AuthProvider: Error loading user data: $e');
      debugPrint('AuthProvider: Stack: $stack');

      ConnectivityService.instance.reportNetworkError(e);

      // Offline / Server down fallback
      final cachedUserMap = OfflineCacheService.instance.getMap('cached_user');
      if (cachedUserMap != null) {
        final cachedEnrollmentMap = OfflineCacheService.instance.getMap('cached_enrollment');
        final cachedSchoolMap = OfflineCacheService.instance.getMap('cached_school');
        final cachedUser = UserModel.fromJson(cachedUserMap);
        final cachedSchool = cachedSchoolMap != null
            ? SchoolModel.fromJson(cachedSchoolMap)
            : state.school;
        final cachedSchoolSuspended =
            OfflineCacheService.instance.getBool('cached_school_suspended') ??
            (cachedSchool != null && (!cachedSchool.isActive || cachedSchool.isSuspended)) ||
            state.schoolSuspended;

        // CRITICAL SECURITY GUARD:
        // If the student or school was already suspended, NEVER allow an offline fallback
        // to reactivate them into the app!
        final wasLocked = state.isAccessLocked ||
            cachedUser.isSuspended ||
            cachedSchoolSuspended;

        final effectiveUser = wasLocked && !cachedUser.isSuspended
            ? cachedUser.copyWith(accountStatus: 'paused_unpaid', isActive: false)
            : cachedUser;

        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          user: effectiveUser,
          enrollment: cachedEnrollmentMap != null
              ? EnrollmentModel.fromJson(cachedEnrollmentMap)
              : state.enrollment,
          school: cachedSchool,
          errorMessage: null,
          accessDenied: false,
          schoolSuspended: wasLocked ? (cachedSchoolSuspended || state.schoolSuspended) : false,
        );
        debugPrint('AuthProvider: Preserved session from offline cache after error (wasLocked=$wasLocked)');
        return;
      }

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<bool> signIn(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null, accessDenied: false);

    try {
      await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      // _loadUserData will be called by auth state listener
      // Role check happens there
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.message,
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  Future<void> signOut({bool global = false}) async {
    try {
      await _supabase.auth.signOut(
        scope: global ? SignOutScope.global : SignOutScope.local,
      );
    } catch (_) {}
    try {
      await OfflineCacheService.instance.clearAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
    state = AuthState();
  }

  void clearError() {
    state = state.copyWith(errorMessage: null, accessDenied: false);
  }

  Future<bool> refreshUserData() async {
    debugPrint('AuthProvider: Refreshing user data...');
    // Force a fresh fetch by setting loading state
    state = state.copyWith(isLoading: true);
    await _loadUserData();
    final isLocked = state.isAccessLocked;
    debugPrint('AuthProvider: Refresh complete. isAccessLocked=$isLocked');
    return !isLocked;
  }

  Future<bool> updateProfilePhoto(String photoUrl) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      await _supabase
          .from('users')
          .update({'photo_url': photoUrl})
          .eq('id', userId);

      state = state.copyWith(
        user: state.user?.copyWith(photoUrl: photoUrl),
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Request password reset - sends request to admin
  /// Works for any email - admin will verify
  Future<void> requestPasswordReset(String email) async {
    try {
      // Use RPC function to bypass schema cache issues
      await _supabase.rpc('create_password_reset_request', params: {
        'p_email': email.trim().toLowerCase(),
      });
    } catch (e) {
      // If RPC doesn't exist, fall back to direct insert
      if (e.toString().contains('function') || e.toString().contains('rpc')) {
        // Try direct insert as fallback
        try {
          final userResp = await _supabase
              .from('users')
              .select('id, full_name')
              .eq('email', email.trim().toLowerCase())
              .maybeSingle();

          await _supabase.from('password_reset_requests').insert({
            'user_id': userResp?['id'],
            'email': email.trim().toLowerCase(),
            'full_name': userResp?['full_name'] ?? 'Inconnu',
            'status': 'pending',
          });
        } catch (insertError) {
          throw Exception('Impossible d\'envoyer la demande. Veuillez réessayer plus tard.');
        }
      } else {
        rethrow;
      }
    }
  }

  /// Change user password, update users.initial_password for admin dashboard, and alert admin
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = state.user;
    final email = user?.email ?? _supabase.auth.currentUser?.email;
    final userId = user?.id ?? _supabase.auth.currentUser?.id;

    if (email == null || userId == null) {
      throw 'user_not_connected';
    }

    // 1. Verify current password
    try {
      await _supabase.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );
    } on AuthException {
      throw 'current_password_incorrect';
    } catch (_) {
      throw 'current_password_incorrect';
    }

    // 2. Update Supabase Auth user password
    try {
      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('weak') ||
          e.message.toLowerCase().contains('character') ||
          e.message.toLowerCase().contains('least') ||
          e.message.toLowerCase().contains('length')) {
        throw 'password_too_short';
      }
      throw 'password_update_failed';
    } catch (_) {
      throw 'password_update_failed';
    }

    // 3. Clear temporary initial_password in public.users (never store plaintext user passwords permanently)
    try {
      await _supabase.from('users').update({
        'initial_password': newPassword,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      // Update in-memory user state
      if (state.user != null) {
        state = state.copyWith(
          user: state.user!.copyWith(initialPassword: newPassword),
        );
      }
    } catch (e) {
      debugPrint('AuthProvider: Failed to clear initial_password in users table: $e');
    }

    // 4. Alert the admin dashboard by logging into password_reset_requests
    try {
      await _supabase.from('password_reset_requests').insert({
        'user_id': userId,
        'email': email,
        'full_name': user?.fullName ?? 'Étudiant',
        'status': 'approved',
        'admin_notes': 'Mot de passe modifié par l\'étudiant depuis l\'application (mis à jour dans la fiche étudiant)',
        'new_password_sent': true,
        'processed_at': DateTime.now().toIso8601String(),
      });
    } catch (alertError) {
      debugPrint('AuthProvider: Failed to notify password_reset_requests: $alertError');
    }
  }
}

// Helper providers
final currentUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(authProvider).user;
});

final currentEnrollmentProvider = Provider<EnrollmentModel?>((ref) {
  return ref.watch(authProvider).enrollment;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});

final accessDeniedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).accessDenied;
});
