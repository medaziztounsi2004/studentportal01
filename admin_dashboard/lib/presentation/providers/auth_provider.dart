import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/error_messages.dart';
import '../../data/models/user_model.dart';

final authProvider = NotifierProvider<AuthNotifier, AdminAuthState>(AuthNotifier.new);

class AdminAuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final UserModel? user;
  final String? errorMessage;
  final bool accessDenied;
  final String? schoolSubscriptionStatus;
  final bool schoolIsActive;

  bool get isSchoolSuspended =>
      !schoolIsActive || schoolSubscriptionStatus == 'suspended';

  AdminAuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    this.user,
    this.errorMessage,
    this.accessDenied = false,
    this.schoolSubscriptionStatus,
    this.schoolIsActive = true,
  });

  AdminAuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    UserModel? user,
    String? errorMessage,
    bool? accessDenied,
    String? schoolSubscriptionStatus,
    bool? schoolIsActive,
  }) {
    return AdminAuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
      errorMessage: errorMessage,
      accessDenied: accessDenied ?? this.accessDenied,
      schoolSubscriptionStatus:
          schoolSubscriptionStatus ?? this.schoolSubscriptionStatus,
      schoolIsActive: schoolIsActive ?? this.schoolIsActive,
    );
  }
}

class AuthNotifier extends Notifier<AdminAuthState> {
  @override
  AdminAuthState build() {
    _init();
    return AdminAuthState();
  }

  SupabaseClient get _supabase => Supabase.instance.client;
  RealtimeChannel? _schoolChannel;
  RealtimeChannel? _subChannel;

  void _init() {
    _supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn) {
        _loadUserData();
      } else if (data.event == AuthChangeEvent.signedOut) {
        _schoolChannel?.unsubscribe();
        _subChannel?.unsubscribe();
        state = AdminAuthState();
      }
    });
    if (_supabase.auth.currentSession != null) _loadUserData();
  }

  void _subscribeToSchoolChanges(String schoolId) {
    _schoolChannel?.unsubscribe();
    _subChannel?.unsubscribe();

    _schoolChannel = _supabase
        .channel('admin_school_changes_$schoolId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
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
            state = state.copyWith(schoolIsActive: isActive);
          },
        )
        .subscribe();

    _subChannel = _supabase
        .channel('admin_school_sub_changes_$schoolId')
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
            final status = newSub['status']?.toString() ?? 'active';
            state = state.copyWith(schoolSubscriptionStatus: status);
          },
        )
        .subscribe();
  }

  Future<void> _loadUserData() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    state = state.copyWith(isLoading: true);
    try {
      final resp = await _supabase.from('users').select().eq('id', userId).single();
      final user = UserModel.fromJson(resp);
      if (!['admin', 'staff', 'owner', 'manager', 'super_admin'].contains(user.role)) {
        await _supabase.auth.signOut(scope: SignOutScope.local);
        final message = 'Access denied. This dashboard is for school administrators only.';
        state = AdminAuthState(accessDenied: true, errorMessage: message);
        return;
      }

      // Check master SaaS school subscription & active kill-switch
      String? subStatus = 'active';
      bool schoolIsActive = true;
      if (user.schoolId != null) {
        _subscribeToSchoolChanges(user.schoolId!);
        try {
          final schoolRow = await _supabase
              .from('schools')
              .select('is_active, school_subscriptions(status)')
              .eq('id', user.schoolId!)
              .maybeSingle();
          if (schoolRow != null) {
            schoolIsActive = schoolRow['is_active'] as bool? ?? true;
            final subs = schoolRow['school_subscriptions'] as List?;
            if (subs != null && subs.isNotEmpty) {
              subStatus = (subs.first as Map)['status']?.toString();
            }
          }
        } catch (_) {}
      }

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        user: user,
        errorMessage: null,
        accessDenied: false,
        schoolSubscriptionStatus: subStatus,
        schoolIsActive: schoolIsActive,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: UserFriendlyError.format(
          e,
          fallback: 'Unable to load your account right now. Please try again.',
        ),
      );
    }
  }

  Future<bool> checkSchoolStatus() async {
    final schoolId = state.user?.schoolId;
    if (schoolId == null) return true;

    try {
      final schoolRow = await _supabase
          .from('schools')
          .select('is_active, school_subscriptions(status)')
          .eq('id', schoolId)
          .maybeSingle();

      if (schoolRow != null) {
        final isActive = schoolRow['is_active'] as bool? ?? true;
        String? subStatus = 'active';
        final subs = schoolRow['school_subscriptions'] as List?;
        if (subs != null && subs.isNotEmpty) {
          subStatus = (subs.first as Map)['status']?.toString();
        }
        final isSuspended = !isActive || subStatus == 'suspended';
        state = state.copyWith(
          schoolIsActive: isActive,
          schoolSubscriptionStatus: subStatus,
        );
        return !isSuspended;
      }
      return true;
    } catch (_) {
      return !state.isSchoolSuspended;
    }
  }

  Future<String?> completeForcedPasswordChange(String newPassword) async {
    final userId = state.user?.id ?? _supabase.auth.currentUser?.id;
    if (userId == null) return 'Session expirée';
    try {
      await _supabase.auth.updateUser(UserAttributes(password: newPassword));
      await _supabase.from('users').update({
        'force_password_change': false,
        'initial_password': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
      if (state.user != null) {
        state = state.copyWith(
          user: state.user!.copyWith(
            forcePasswordChange: false,
            initialPassword: null,
          ),
        );
      }
      return null;
    } catch (e) {
      return UserFriendlyError.format(e);
    }
  }

  Future<bool> signIn(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null, accessDenied: false);
    try {
      await _supabase.auth.signInWithPassword(email: email, password: password);
      await _loadUserData();
      return state.isAuthenticated;
    } on AuthException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: UserFriendlyError.format(
          e,
          fallback: 'Unable to sign in. Please check your credentials and try again.',
        ),
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: UserFriendlyError.format(
          e,
          fallback: 'Unable to sign in right now. Please try again.',
        ),
      );
      return false;
    }
  }

  Future<void> signOut({bool global = false}) async {
    _schoolChannel?.unsubscribe();
    _subChannel?.unsubscribe();
    try {
      await _supabase.auth.signOut(
        scope: global ? SignOutScope.global : SignOutScope.local,
      );
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
    state = AdminAuthState();
  }

  void clearError() { state = state.copyWith(errorMessage: null, accessDenied: false); }
}