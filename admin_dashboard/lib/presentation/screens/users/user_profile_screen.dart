import '../../../data/services/user_management_service.dart';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../widgets/admin_sidebar.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/ios_loader.dart';
import '../../widgets/skeleton_loader.dart';
import '../../../data/models/user_model.dart';
import '../../providers/users_provider.dart';
import '../../widgets/avatar_cropper_dialog.dart';
import 'user_form_dialog.dart';

// ==================== USER PROFILE DATA MODEL ====================
class UserProfileData {
  final Map<String, dynamic> user;
  final Map<String, dynamic>? enrollment;
  final String? className;
  final String? groupName;
  final int yearsAtSchool;
  final List<Map<String, dynamic>> suggestions;
  final List<Map<String, dynamic>> monthlyAbsences;
  final int totalAbsences;
  final int justifiedAbsences;
  final List<Map<String, dynamic>> payments;
  final double paymentAccuracy;
  final int onTimePayments;
  final int latePayments;
  final double totalPaid;
  final double totalDue;
  final List<Map<String, dynamic>> grades;
  final List<Map<String, dynamic>> timetable;
  final List<Map<String, dynamic>> messages;
  final List<Map<String, dynamic>> activityLog;

  UserProfileData({
    required this.user,
    this.enrollment,
    this.className,
    this.groupName,
    this.yearsAtSchool = 0,
    this.suggestions = const [],
    this.monthlyAbsences = const [],
    this.totalAbsences = 0,
    this.justifiedAbsences = 0,
    this.payments = const [],
    this.paymentAccuracy = 0,
    this.onTimePayments = 0,
    this.latePayments = 0,
    this.totalPaid = 0,
    this.totalDue = 0,
    this.grades = const [],
    this.timetable = const [],
    this.messages = const [],
    this.activityLog = const [],
  });
}

// ==================== PROFILE PROVIDER ====================
final userProfileDataProvider =
    FutureProvider.autoDispose.family<UserProfileData?, String>((
  ref,
  userId,
) async {
  final supabase = Supabase.instance.client;

  try {
    // Get user basic info
    final userResponse = await supabase
        .from('users')
        .select()
        .eq('id', userId)
        .maybeSingle();

    if (userResponse == null) return null;

    // Get enrollment info with class and niveau
    Map<String, dynamic>? enrollment;
    String? className;
    String? groupName;
    String? niveauCodeFromEnrollment;

    String? niveauNameFromEnrollment;
    String? sectionNameFromEnrollment;

    try {
      enrollment = await supabase
          .from('enrollments')
          .select(
            '*, classes(id, name, niveau_id, section_id, sections(id, name), niveaux(code, name)), groups(name)',
          )
          .eq('user_id', userId)
          .maybeSingle();

      debugPrint('Profile: Enrollment for $userId: $enrollment');
      if (enrollment != null) {
        final classInfo = enrollment['classes'] as Map<String, dynamic>?;
        className = classInfo?['name'];
        final niveauInfo = classInfo?['niveaux'] as Map<String, dynamic>?;
        niveauCodeFromEnrollment = niveauInfo?['code'];
        niveauNameFromEnrollment = niveauInfo?['name'];
        final sectionInfo = classInfo?['sections'] as Map<String, dynamic>?;
        sectionNameFromEnrollment = sectionInfo?['name'];
        groupName = enrollment['groups']?['name'];
        debugPrint(
          'Profile: className=$className, niveau=$niveauCodeFromEnrollment, groupName=$groupName',
        );
      }
    } catch (e) {
      debugPrint('Profile: Error loading enrollment: $e');
    }

    // Update user data with niveau from enrollment if not set
    final userData = Map<String, dynamic>.from(userResponse);
    if (userData['niveau_code'] == null && niveauCodeFromEnrollment != null) {
      userData['niveau_code'] = niveauCodeFromEnrollment;
    }
    if (niveauNameFromEnrollment != null) {
      userData['niveau_name'] = niveauNameFromEnrollment;
    }
    if (sectionNameFromEnrollment != null) {
      userData['section_name'] = sectionNameFromEnrollment;
    }

    // Calculate years at school
    int yearsAtSchool = 0;
    if (userResponse['created_at'] != null) {
      final createdAt = DateTime.tryParse(userResponse['created_at']);
      if (createdAt != null) {
        yearsAtSchool = DateTime.now().difference(createdAt).inDays ~/ 365;
        if (yearsAtSchool == 0) yearsAtSchool = 1;
      }
    }

    // Get suggestions
    List<Map<String, dynamic>> suggestions = [];
    try {
      final resp = await supabase
          .from('suggestions')
          .select('id, subject, status, suggestion_type, created_at')
          .eq('student_id', userId)
          .neq('suggestion_type', 'bug_report')
          .not('subject', 'ilike', '%[BUG REPORT%')
          .order('created_at', ascending: false)
          .limit(10);
      suggestions = (resp as List).cast<Map<String, dynamic>>();
    } catch (_) {}

    // Get all absences (for calendar display across months)
    final now = DateTime.now();
    List<Map<String, dynamic>> monthlyAbsences = [];
    int totalAbsences = 0;
    int justifiedAbsences = 0;

    try {
      final resp = await supabase
          .from('absence_records')
          .select('date, hours_absent, justified, enrollment_id')
          .order('date');
      monthlyAbsences = (resp as List).cast<Map<String, dynamic>>();
      // Count current month absences for stats
      final currentMonthAbsences = monthlyAbsences.where((a) {
        final d = DateTime.tryParse(a['date'] as String? ?? '');
        return d != null && d.year == now.year && d.month == now.month;
      }).toList();
      totalAbsences = currentMonthAbsences.length;
      justifiedAbsences = currentMonthAbsences
          .where((a) => a['justified'] == true)
          .length;
    } catch (_) {}

    // Get payments and calculate accuracy (filtered to this student's enrollments)
    List<Map<String, dynamic>> payments = [];
    double paymentAccuracy = 0;
    int onTimePayments = 0;
    int latePayments = 0;
    double totalPaid = 0;
    double totalDue = 0;

    try {
      final enrollmentsResp = await supabase
          .from('enrollments')
          .select('id')
          .eq('user_id', userId);
      final enrollmentIds = (enrollmentsResp as List)
          .map((e) => e['id'] as String)
          .toList();

      if (enrollmentIds.isNotEmpty) {
        final resp = await supabase
            .from('payments')
            .select('*, payment_plans!inner(id, plan_type, category, enrollment_id)')
            .inFilter('payment_plans.enrollment_id', enrollmentIds)
            .order('created_at', ascending: false);
        payments = (resp as List).cast<Map<String, dynamic>>();
        debugPrint('Profile: loaded ${payments.length} payments for $userId, enrollmentIds=$enrollmentIds');
      } else {
        debugPrint('Profile: no enrollments found for $userId');
      }

      for (final p in payments) {
        final amount = (p['amount'] as num?)?.toDouble() ?? 0;

        if (p['status'] == 'paid') {
          totalPaid += amount;
          if (p['due_date'] != null && p['paid_at'] != null) {
            final dueDate = DateTime.parse(p['due_date']);
            final paidAt = DateTime.parse(p['paid_at']);
            if (paidAt.isBefore(dueDate) || paidAt.isAtSameMomentAs(dueDate)) {
              onTimePayments++;
            } else {
              latePayments++;
            }
          } else {
            onTimePayments++;
          }
        } else {
          totalDue += amount;
          if (p['status'] == 'overdue') latePayments++;
        }
      }

      final total = onTimePayments + latePayments;
      if (total > 0) paymentAccuracy = (onTimePayments / total) * 100;
      debugPrint('Profile: totals for $userId -> totalPaid=$totalPaid, totalDue=$totalDue, payments=${payments.length}, accuracy=$paymentAccuracy');
    } catch (e, st) {
      debugPrint('Profile: error loading payments for $userId: $e');
      debugPrint('$st');
    }

    // Get grades
    List<Map<String, dynamic>> grades = [];
    try {
      final resp = await supabase
          .from('grades')
          .select('grade_value, status, subjects(name)')
          .order('created_at', ascending: false)
          .limit(10);
      grades = (resp as List).cast<Map<String, dynamic>>();
    } catch (_) {}

    // Get timetable
    List<Map<String, dynamic>> timetable = [];
    try {
      final resp = await supabase
          .from('timetable_slots')
          .select('*, subjects(name)')
          .order('day_of_week')
          .order('start_time');
      timetable = (resp as List).cast<Map<String, dynamic>>();
    } catch (_) {}

    // Get class messages
    List<Map<String, dynamic>> messages = [];
    try {
      if (enrollment != null && enrollment['class_id'] != null) {
        final resp = await supabase
            .from('announcements')
            .select('id, title, body, published_at')
            .order('published_at', ascending: false)
            .limit(5);
        messages = (resp as List).cast<Map<String, dynamic>>();
      }
    } catch (_) {}

    // Build activity log from real data
    List<Map<String, dynamic>> activityLog = [];
    for (final a in monthlyAbsences) {
      activityLog.add({
        'action': 'Absence',
        'details': a['justified'] == true
            ? 'Absence justifiée (${a['hours_absent'] ?? 1}h)'
            : 'Absence non justifiée (${a['hours_absent'] ?? 1}h)',
        'date': a['date'],
        'type': a['justified'] == true ? 'warning' : 'error',
      });
    }
    for (final p in payments) {
      activityLog.add({
        'action': 'Paiement',
        'details': '${p['description'] ?? 'Paiement'} - ${((p['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(3)} DT (${p['status'] ?? 'en attente'})',
        'date': p['paid_at'] ?? p['created_at'],
        'type': p['status'] == 'paid' ? 'success' : 'info',
      });
    }
    for (final s in suggestions) {
      activityLog.add({
        'action': 'Suggestion',
        'details': s['subject'] ?? 'Suggestion envoyée',
        'date': s['created_at'],
        'type': 'purple',
      });
    }
    for (final m in messages) {
      activityLog.add({
        'action': 'Annonce',
        'details': m['title'] ?? 'Annonce de classe',
        'date': m['published_at'],
        'type': 'info',
      });
    }
    activityLog.sort((a, b) {
      final dateA = DateTime.tryParse(a['date'] ?? '') ?? DateTime(2000);
      final dateB = DateTime.tryParse(b['date'] ?? '') ?? DateTime(2000);
      return dateB.compareTo(dateA);
    });

    return UserProfileData(
      user: userData,
      enrollment: enrollment,
      className: className,
      groupName: groupName,
      yearsAtSchool: yearsAtSchool,
      suggestions: suggestions,
      monthlyAbsences: monthlyAbsences,
      totalAbsences: totalAbsences,
      justifiedAbsences: justifiedAbsences,
      payments: payments,
      paymentAccuracy: paymentAccuracy,
      onTimePayments: onTimePayments,
      latePayments: latePayments,
      totalPaid: totalPaid,
      totalDue: totalDue,
      grades: grades,
      timetable: timetable,
      messages: messages,
      activityLog: activityLog,
    );
  } catch (e) {
    debugPrint('Error loading profile: $e');
    return null;
  }
});

// ==================== MAIN PROFILE SCREEN ====================
class UserProfileScreen extends ConsumerStatefulWidget {
  final String userId;
  final String? userName;
  final bool isDialogMode;
  final VoidCallback? onBack;

  const UserProfileScreen({
    super.key,
    required this.userId,
    this.userName,
    this.isDialogMode = false,
    this.onBack,
  });

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  bool _isUploadingPhoto = false;
  Uint8List? _optimisticPhotoBytes;
  String? _optimisticPhotoUrl;
  bool _showPassword = false;
  bool _isResettingPassword = false;
  bool _isTogglingAccountStatus = false;
  String? _optimisticAccountStatus;
  int _selectedMonthOffset = 0;
  int _activityPage = 1;
  int _activityPerPage = 10;
  RealtimeChannel? _userChannel;

  @override
  void initState() {
    super.initState();
    _subscribeToUserChanges();
  }

  @override
  void dispose() {
    _userChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToUserChanges() {
    try {
      _userChannel = Supabase.instance.client
          .channel('profile_realtime_${widget.userId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'users',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: widget.userId,
            ),
            callback: (payload) {
              debugPrint('ProfileScreen: Realtime user update received for ${widget.userId}');
              if (mounted) {
                ref.invalidate(userProfileDataProvider(widget.userId));
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('ProfileScreen: Error setting up realtime subscription: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileDataProvider(widget.userId));

    final content = profileAsync.when(
      loading: () => const StudentProfileSkeletonLoader(),
      error: (e, _) => Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.error.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.error.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                UserFriendlyError.format(
                  e,
                  fallback: 'Unable to load this profile right now. Please try again.',
                ),
                style: TextStyle(color: AppColors.error),
              ),
            ],
          ),
        ),
      ),
      data: (data) {
        if (data == null) return _buildNotFound();
        // Redirect teachers to their dedicated profile page
        if (data.user['role'] == 'teacher') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.go('/teachers/${widget.userId}');
          });
          return const Center(child: IosLoader(color: AppColors.primary));
        }
        return _buildProfile(context, data);
      },
    );

    if (widget.isDialogMode) {
      return Dialog.fullscreen(
        backgroundColor: AppColors.background,
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: content,
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: '/users'),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.slate300, AppColors.slate400]),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_off_rounded, size: 48, color: AppColors.textOnPrimary),
            ),
            const SizedBox(height: 24),
            Text('Utilisateur non trouvé',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.slate700)),
            const SizedBox(height: 8),
            Text("L'utilisateur demandé n'existe pas ou a été supprimé.",
                style: TextStyle(color: AppColors.slate500)),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(context),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back_rounded, color: AppColors.textOnPrimary),
                        SizedBox(width: 8),
                        Text('Retour', style: TextStyle(color: AppColors.textOnPrimary, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== MAIN PROFILE LAYOUT ====================
  Widget _buildProfile(BuildContext context, UserProfileData data) {
    final user = data.user;
    final fullName = user['full_name'] as String? ?? 'Nom inconnu';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _buildHeader(fullName, user),
          const SizedBox(height: 32),
          // 2-col grid: Left sidebar + Right content
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column (profile card + security)
              SizedBox(
                width: 360,
                child: Column(
                  children: [
                    _buildProfileCard(data),
                    const SizedBox(height: 24),
                    _buildSecurityCard(data),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              // Right Column (stats + calendar/payments + activity)
              Expanded(
                child: Column(
                  children: [
                    _buildStatsGrid(data),
                    const SizedBox(height: 32),
                    SizedBox(
                      height: 490,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildPresenceCalendar(data)),
                          const SizedBox(width: 32),
                          Expanded(child: _buildPaymentsCard(data)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildActivityLog(data),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== HEADER ====================
  Widget _buildHeader(String fullName, Map<String, dynamic> user) {
    final isStudent = user['role'] == 'student';
    final bool rawActive = user['is_active'] != false;
    final String rawStatus = (user['account_status'] as String? ?? 'active').toLowerCase();
    final bool isSuspended = _optimisticAccountStatus != null
        ? (_optimisticAccountStatus == 'paused_unpaid')
        : (!rawActive || rawStatus == 'paused_unpaid');

    return Container(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.slate100)),
      ),
      child: Row(
        children: [
          _iconButton(icon: Icons.arrow_back_rounded, onTap: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              context.go('/users');
            }
          }),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(fullName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: -0.3)),
                    if (isSuspended) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: const Text(
                          'Suspendu',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFDC2626)),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  isStudent ? 'Profil étudiant' : 'Profil utilisateur',
                  style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (isStudent)
                _brandOutlineButton(
                  label: 'Envoyer message élève',
                  icon: Icons.mail_outline_rounded,
                  onTap: () => _sendMessageToStudent(user),
                ),
              _brandOutlineButton(
                label: 'Réinitialiser mot de passe',
                icon: Icons.lock_reset_rounded,
                onTap: _isResettingPassword ? null : () => _resetPassword(user),
                isLoading: _isResettingPassword,
              ),
              if (isStudent) _buildAccountStatusButton(user),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: () => _showEditDialog(user),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Modifier', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6D4CF6),
                    foregroundColor: Colors.white,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    shadowColor: const Color(0xFF6D4CF6).withOpacity(0.3),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAccountStatusButton(Map<String, dynamic> user) {
    final bool rawActive = user['is_active'] != false;
    final String rawStatus = (user['account_status'] as String? ?? 'active').toLowerCase();

    final bool isPaused = _optimisticAccountStatus != null
        ? (_optimisticAccountStatus == 'paused_unpaid')
        : (!rawActive || rawStatus == 'paused_unpaid');

    return Container(
      decoration: BoxDecoration(
        color: isPaused ? const Color(0xFFFEF2F2) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _isTogglingAccountStatus
              ? null
              : () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    barrierColor: Colors.black.withOpacity(0.08),
                    builder: (dCtx) => BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                      child: AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isPaused ? AppColors.successSoft : AppColors.warningSoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isPaused ? Icons.check_circle_outline_rounded : Icons.pause_circle_outline_rounded,
                                color: isPaused ? AppColors.success : AppColors.warning,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                isPaused ? 'Activer le compte ?' : 'Suspendre le compte ?',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                        content: Text(
                          isPaused
                              ? 'Voulez-vous vraiment réactiver l\'accès à la plateforme pour cet élève ?'
                              : 'Voulez-vous vraiment suspendre l\'accès à la plateforme pour cet élève ?',
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                        actions: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(
                                height: 40,
                                child: TextButton(
                                  onPressed: () => Navigator.pop(dCtx, false),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF6B7280),
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: const Text(
                                    'Annuler',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                height: 40,
                                child: ElevatedButton(
                                  onPressed: () => Navigator.pop(dCtx, true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isPaused ? AppColors.success : AppColors.warning,
                                    foregroundColor: Colors.white,
                                    elevation: 2,
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: Text(
                                    isPaused ? 'Activer' : 'Suspendre',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                  if (confirm != true) return;

                  final nextStatus = isPaused ? 'active' : 'paused_unpaid';
                  final nextActive = isPaused;

                  // Instant optimistic UI update
                  setState(() {
                    _optimisticAccountStatus = nextStatus;
                    user['is_active'] = nextActive;
                    user['account_status'] = nextStatus;
                    _isTogglingAccountStatus = true;
                  });

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          nextStatus == 'paused_unpaid'
                              ? 'Accès élève suspendu.'
                              : 'Accès élève réactivé.',
                        ),
                        backgroundColor: nextStatus == 'paused_unpaid'
                            ? AppColors.warning
                            : AppColors.success,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }

                  try {
                    final okStatus = await UserManagementService.setAccountStatus(
                      userId: widget.userId,
                      accountStatus: nextStatus,
                    );
                    final okArchive = await UserManagementService.toggleArchive(
                      userIds: [widget.userId],
                      isActive: nextActive,
                    );
                    if (!mounted) return;
                    if (!okStatus && !okArchive) {
                      // Revert optimistic update on failure
                      setState(() {
                        _optimisticAccountStatus = isPaused ? 'paused_unpaid' : 'active';
                        user['is_active'] = !nextActive;
                        user['account_status'] = isPaused ? 'paused_unpaid' : 'active';
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Impossible de modifier le statut d\'accès.'),
                          backgroundColor: AppColors.error,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        ),
                      );
                    } else {
                      ref.invalidate(userProfileDataProvider(widget.userId));
                      ref.read(usersProvider.notifier).refresh(showLoading: false);
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() {
                        _optimisticAccountStatus = isPaused ? 'paused_unpaid' : 'active';
                        user['is_active'] = !nextActive;
                        user['account_status'] = isPaused ? 'paused_unpaid' : 'active';
                      });
                    }
                  } finally {
                    if (mounted) setState(() => _isTogglingAccountStatus = false);
                  }
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPaused ? Icons.lock_outline_rounded : Icons.verified_user_outlined,
                  size: 16,
                  color: isPaused ? const Color(0xFFDC2626) : const Color(0xFF15803D),
                ),
                const SizedBox(width: 7),
                Text(
                  isPaused ? 'Suspendu — Réactiver' : 'Accès actif',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isPaused ? const Color(0xFFDC2626) : const Color(0xFF15803D),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> user) {
    // Convert map to UserModel for editing
    final userModel = UserModel(
      id: user['id'] ?? widget.userId,
      schoolId: user['school_id'],
      role: user['role'] ?? 'student',
      fullName: user['full_name'] ?? '',
      email: user['email'] ?? '',
      phone: user['phone'],
      photoUrl: user['photo_url'],
      studentCode: user['student_code'],
      dateOfBirth: user['date_of_birth'] != null
          ? DateTime.tryParse(user['date_of_birth'].toString())
          : null,
      address: user['address'],
      gender: user['gender'],
      nationality: user['nationality'],
      niveau: user['niveau'],
      niveauCode: user['niveau_code'],
      sectionCode: user['section_code'],
      initialPassword: user['initial_password'],
      createdAt: user['created_at'] != null
          ? DateTime.parse(user['created_at'])
          : DateTime.now(),
      updatedAt: user['updated_at'] != null
          ? DateTime.parse(user['updated_at'])
          : DateTime.now(),
    );

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (ctx) => UserFormDialog(user: userModel),
    ).then((_) {
      // Refresh profile after dialog closes
      ref.invalidate(userProfileDataProvider(widget.userId));
    });
  }

  void _sendMessageToStudent(Map<String, dynamic> user) {
    // Navigate to announcements screen with student scope pre-selected
    context.go(
      '/announcements',
      extra: {'initialScope': 'student', 'preSelectedStudentId': user['id']},
    );
  }

  Future<void> _resetPassword(Map<String, dynamic> user) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          title: const Text('Réinitialiser le mot de passe'),
          content: Text(
            'Voulez-vous générer un nouveau mot de passe pour ${user['full_name']} ?',
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  height: 40,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6D4CF6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 2,
                    ),
                    child: const Text('Confirmer', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    setState(() => _isResettingPassword = true);

    try {
      final newPassword = await ref
          .read(usersProvider.notifier)
          .resetUserPassword(widget.userId);

      if (newPassword != null && mounted) {
        ref.invalidate(userProfileDataProvider(widget.userId));
        showDialog(
          context: context,
          barrierColor: Colors.black.withOpacity(0.08),
          builder: (ctx) => BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.check_circle, color: AppColors.success),
                const SizedBox(width: 12),
                const Text('Mot de passe réinitialisé'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nouveau mot de passe :'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.slate100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          newPassword,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: newPassword));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Mot de passe copié !'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6D4CF6),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Fermer'),
              ),
            ],
          ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFriendlyError.format(e)), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isResettingPassword = false);
    }
  }





  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copié !'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ==================== PROFILE CARD (LEFT SIDEBAR) ====================
  Widget _buildProfileCard(UserProfileData data) {
    final user = data.user;
    final photoUrl = user['photo_url'] as String?;
    final role = user['role'] as String? ?? 'student';
    final isStudent = role == 'student';
    final fullName = user['full_name'] as String? ?? 'Nom inconnu';
    final studentCode = user['student_code'] as String?;
    final niveauCode = user['niveau_code'] as String?;
    final sectionCode = user['section_code'] as String?;
    final legacyNiveau = user['niveau'] as String?;
    final niveauName = user['niveau_name'] as String?;
    final sectionName = user['section_name'] as String?;
    final gender = user['gender'] as String?;
    final String? nationality = user['nationality'] as String?;
    final String? dateOfBirth = user['date_of_birth'] as String?;

    final bool rawActive = user['is_active'] != false;
    final String rawStatus = (user['account_status'] as String? ?? 'active').toLowerCase();
    final bool isSuspended = _optimisticAccountStatus != null
        ? (_optimisticAccountStatus == 'paused_unpaid')
        : (!rawActive || rawStatus == 'paused_unpaid');

    String? dobFormatted;
    if (dateOfBirth != null) {
      final dob = DateTime.tryParse(dateOfBirth);
      if (dob != null) {
        dobFormatted = DateFormat('d MMMM yyyy', 'fr_FR').format(dob);
      }
    }

    final fullNiveau = (niveauName != null && niveauName.isNotEmpty) ? niveauName : (niveauCode ?? legacyNiveau);
    final fullSection = (sectionName != null && sectionName.isNotEmpty) ? sectionName : sectionCode;
    final niveauDisplay = (fullNiveau != null && fullNiveau.isNotEmpty) ? fullNiveau : '-';
    final classeDisplay = (data.className != null && data.className!.isNotEmpty) ? data.className! : (sectionCode ?? '-');

    return Container(
      decoration: _cardDecoration(),
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          // Avatar
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              if (_isUploadingPhoto)
                ShimmerLoading(
                  isLoading: true,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFE2E8F0),
                      border: Border.all(
                        color: const Color(0xFF6D4CF6).withOpacity(0.4),
                        width: 2,
                      ),
                    ),
                    child: _optimisticPhotoBytes != null
                        ? ClipOval(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.memory(
                                  _optimisticPhotoBytes!,
                                  fit: BoxFit.cover,
                                ),
                                Container(
                                  color: Colors.black.withOpacity(0.35),
                                ),
                                const Center(
                                  child: IosLoader(color: Colors.white, size: 28),
                                ),
                              ],
                            ),
                          )
                        : const Center(
                            child: IosLoader(color: Color(0xFF6D4CF6), size: 28),
                          ),
                  ),
                )
              else
                UserAvatar(
                  name: fullName,
                  photoUrl: _optimisticPhotoUrl ?? photoUrl,
                  imageBytes: _optimisticPhotoBytes,
                  radius: 50,
                  gender: data.user['gender'] as String?,
                ),
              GestureDetector(
                onTap: _isUploadingPhoto ? null : _pickAndUploadPhoto,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border, width: 2),
                    boxShadow: AppShadows.sm,
                  ),
                  child: _isUploadingPhoto
                      ? const IosLoader.small()
                      : Icon(Icons.camera_alt_rounded, size: 14, color: AppColors.slate500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Name
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: fullName));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Nom copié!'), duration: Duration(seconds: 1), behavior: SnackBarBehavior.floating),
              );
            },
            child: Text(fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.slate800), textAlign: TextAlign.center),
          ),
          if (isSuspended) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: const Text(
                'Suspendu',
                style: TextStyle(color: Color(0xFFDC2626), fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ],
          const SizedBox(height: 6),
          // Role badge (hidden for students per design)
          if (!isStudent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _getRoleColor(role).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(_getRoleLabel(role), style: TextStyle(color: _getRoleColor(role), fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          if (studentCode != null) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: studentCode));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ID copié!'), duration: Duration(seconds: 1), behavior: SnackBarBehavior.floating),
                );
              },
              child: Text(studentCode, style: TextStyle(color: AppColors.slate400, fontSize: 12, fontWeight: FontWeight.w500)),
            ),
          ],
          const SizedBox(height: 24),
          // Info Rows
          if (isStudent) ...[
            _profileInfoRow('Niveau', niveauDisplay),
            if (fullSection != null && fullSection.isNotEmpty)
              _profileInfoRow('Filière', fullSection),
            _profileInfoRow('Classe', classeDisplay),
            if (data.groupName != null && data.groupName!.isNotEmpty) _profileInfoRow('Groupe', data.groupName!),
            Builder(
              builder: (context) {
                String genderDisplay = '-';
                if (gender != null && gender.isNotEmpty) {
                  final g = gender.trim().toUpperCase();
                  if (g == 'M' || g == 'MASCULIN' || g == 'HOMME') {
                    genderDisplay = 'Masculin';
                  } else if (g == 'F' || g == 'FEMININ' || g == 'FÉMININ' || g == 'FEMME') {
                    genderDisplay = 'Féminin';
                  } else {
                    genderDisplay = gender;
                  }
                }
                return _profileInfoRow('Genre', genderDisplay);
              },
            ),
            if (dobFormatted != null) _profileInfoRow('Date de naissance', dobFormatted),
            _profileInfoRow('Nationalité', nationality ?? '-'),
          ] else ...[
            _profileInfoRow('Rôle', _getRoleLabel(role)),
            _profileInfoRow('Email', user['email'] ?? '-'),
            if (user['phone'] != null) _profileInfoRow('Téléphone', user['phone']),
            _profileInfoRow('Créé le', _formatDate(user['created_at'])),
          ],
          const SizedBox(height: 20),
          // Separator
          Divider(color: AppColors.border, thickness: 1),
          const SizedBox(height: 16),
          // Contact Rapide
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Contact Rapide', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.slate500)),
          ),
          const SizedBox(height: 12),
          _contactRow(Icons.email_outlined, user['email'] ?? '-'),
          const SizedBox(height: 8),
          _contactRow(Icons.phone_outlined, user['phone'] ?? '-'),
          if (user['address'] != null) ...[
            const SizedBox(height: 8),
            _contactRow(Icons.location_on_outlined, user['address']),
          ],
        ],
      ),
    );
  }

  Widget _profileInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(label, style: TextStyle(color: AppColors.slate400, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$label copié!'), duration: const Duration(seconds: 1), behavior: SnackBarBehavior.floating),
                  );
                },
                child: Row(
                  children: [
                    Expanded(child: Text(value, style: const TextStyle(color: AppColors.slate700, fontSize: 13, fontWeight: FontWeight.w600))),
                    const SizedBox(width: 4),
                    Icon(Icons.copy, size: 12, color: AppColors.slate300),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactRow(IconData icon, String text) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$text copié!'), duration: const Duration(seconds: 1), behavior: SnackBarBehavior.floating),
          );
        },
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 14, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: AppColors.slate600, fontSize: 13), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 4),
            Icon(Icons.copy, size: 12, color: AppColors.slate300),
          ],
        ),
      ),
    );
  }

  // ==================== SECURITY CARD ====================
  Widget _buildSecurityCard(UserProfileData data) {
    final user = data.user;
    final initialPassword = user['initial_password'] as String?;

    return Container(
      decoration: _cardDecoration(),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 18, color: AppColors.slate500),
              const SizedBox(width: 8),
              const Text('Sécurité', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.slate800)),
            ],
          ),
          const SizedBox(height: 16),
          Text('Mot de passe initial', style: TextStyle(color: AppColors.slate400, fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    initialPassword != null
                        ? (_showPassword ? initialPassword : '•' * initialPassword.length)
                        : 'Non défini',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: initialPassword != null ? 'monospace' : null,
                      color: initialPassword != null ? AppColors.slate700 : AppColors.slate400,
                    ),
                  ),
                ),
                if (initialPassword != null) ...[
                  _miniIconBtn(
                    icon: _showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    onTap: () => setState(() => _showPassword = !_showPassword),
                  ),
                  const SizedBox(width: 4),
                  _miniIconBtn(
                    icon: Icons.copy_outlined,
                    onTap: () => _copyToClipboard(initialPassword, 'Mot de passe'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== STATS GRID (EXACT TABLEAU DE BORD GOLDEN METRIC STYLE) ====================
  Widget _buildStatsGrid(UserProfileData data) {
    final cards = [
      _buildGoldenMetricCard(
        icon: Icons.event_busy_outlined,
        iconColor: const Color(0xFFEF4444),
        iconBgColor: const Color(0xFFFEF2F2),
        title: 'Absences ce mois',
        value: '${data.monthlyAbsences.length}',
        trend: '${data.totalAbsences} au total',
        trendLabel: 'sur l\'année',
        trendUp: data.monthlyAbsences.isEmpty,
        onTap: () => context.push('/student-absences/${widget.userId}'),
      ),
      _buildGoldenMetricCard(
        icon: Icons.verified_outlined,
        iconColor: const Color(0xFF10B981),
        iconBgColor: const Color(0xFFECFDF5),
        title: 'Justifiées',
        value: '${data.justifiedAbsences}',
        trend: data.totalAbsences > 0
            ? '${((data.justifiedAbsences / data.totalAbsences) * 100).toStringAsFixed(0)}%'
            : '100%',
        trendLabel: 'taux de justification',
        trendUp: true,
        onTap: () => context.push('/student-absences/${widget.userId}'),
      ),
      _buildGoldenMetricCard(
        icon: Icons.lightbulb_outline_rounded,
        iconColor: const Color(0xFFF59E0B),
        iconBgColor: const Color(0xFFFFFBEB),
        title: 'Suggestions',
        value: '${data.suggestions.length}',
        trend: data.suggestions.any((s) => s['status'] == 'pending') ? 'En attente' : 'Traité',
        trendLabel: 'statut récent',
        trendUp: true,
        onTap: () => context.go('/suggestions'),
      ),
      _buildGoldenMetricCard(
        icon: Icons.grade_outlined,
        iconColor: const Color(0xFF6D4CF6),
        iconBgColor: const Color(0xFFF5F3FF),
        title: 'Notes récentes',
        value: '${data.grades.length}',
        trend: data.grades.isNotEmpty ? 'Enregistrées' : 'Aucune',
        trendLabel: 'évaluations',
        trendUp: true,
        onTap: () => context.go('/grades'),
      ),
    ];

    return Row(
      children: [
        for (int i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }

  Widget _buildGoldenMetricCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String title,
    required String value,
    required String trend,
    required String trendLabel,
    required bool trendUp,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.015),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: iconColor),
                ),
                const Spacer(),
                const Icon(
                  Icons.arrow_outward_rounded,
                  size: 14,
                  color: Color(0xFFCBD5E1),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                letterSpacing: -0.6,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  trend,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: trendUp ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    trendLabel,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================== PRESENCE CALENDAR ====================
  Widget _buildPresenceCalendar(UserProfileData data) {
    final now = DateTime.now();
    final targetMonth = now.month + _selectedMonthOffset;
    final targetDate = DateTime(now.year, targetMonth, 1);
    const frenchMonths = ['Janvier','Février','Mars','Avril','Mai','Juin','Juillet','Août','Septembre','Octobre','Novembre','Décembre'];
    final monthLabel = '${frenchMonths[targetDate.month - 1]} ${targetDate.year}';

    return Container(
      decoration: _cardDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: title + Voir tout (same style as payment card)
          Row(
            children: [
              const Text('Présence ce mois', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.slate800)),
              const Spacer(),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => context.push('/student-absences/${widget.userId}'),
                  child: Text('Voir tout', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 38),
          // Month switcher on its own row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _miniIconBtn(icon: Icons.chevron_left_rounded, onTap: () => setState(() => _selectedMonthOffset--)),
              const SizedBox(width: 8),
              Text(monthLabel, style: TextStyle(color: AppColors.slate500, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              _miniIconBtn(icon: Icons.chevron_right_rounded, onTap: _selectedMonthOffset < 0 ? () => setState(() => _selectedMonthOffset++) : null),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildCalendarGrid(data, targetDate)),
          const SizedBox(height: 12),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(AppColors.success, 'Présent'),
              const SizedBox(width: 16),
              _legendDot(AppColors.error, 'Absent'),
              const SizedBox(width: 16),
              _legendDot(AppColors.warning, 'Justifié'),
              const SizedBox(width: 16),
              _legendDot(AppColors.slate200, 'Pas de cours'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid(UserProfileData data, DateTime targetDate) {
    final year = targetDate.year;
    final month = targetDate.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday; // 1=Mon

    // Build absence map for the month
    final Map<int, String> absenceMap = {};
    for (final abs in data.monthlyAbsences) {
      final dateStr = abs['date'] as String?;
      if (dateStr == null) continue;
      final d = DateTime.tryParse(dateStr);
      if (d != null && d.year == year && d.month == month) {
        final justified = abs['justified'] == true;
        absenceMap[d.day] = justified ? 'justified' : 'absent';
      }
    }

    final dayLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    return Column(
      children: [
        // Header row
        Row(
          children: dayLabels.map((d) => Expanded(
            child: Center(child: Text(d, style: TextStyle(color: AppColors.slate400, fontSize: 11, fontWeight: FontWeight.w600))),
          )).toList(),
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          childAspectRatio: 1.18,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 5,
          crossAxisSpacing: 5,
          children: [
            // Empty cells before first day
            for (int i = 1; i < firstWeekday; i++)
              const SizedBox(),
            // Day cells
            for (int day = 1; day <= daysInMonth; day++)
              _buildDayCell(day, absenceMap[day], DateTime(year, month, day)),
          ],
        ),
      ],
    );
  }

  Widget _buildDayCell(int day, String? absenceStatus, DateTime date) {
    final isWeekend = date.weekday == 6 || date.weekday == 7;
    final isToday = date.year == DateTime.now().year && date.month == DateTime.now().month && date.day == DateTime.now().day;

    Color bgColor;
    Color textColor;

    if (absenceStatus == 'absent') {
      bgColor = AppColors.error;
      textColor = Colors.white;
    } else if (absenceStatus == 'justified' || absenceStatus == 'justifié') {
      bgColor = AppColors.warning;
      textColor = Colors.white;
    } else if (absenceStatus != null) {
      // present or other status
      bgColor = AppColors.success;
      textColor = Colors.white;
    } else if (isWeekend) {
      bgColor = const Color(0xFFF1F5F9);
      textColor = const Color(0xFF94A3B8);
    } else if (date.isAfter(DateTime.now())) {
      bgColor = const Color(0xFFF8FAFC);
      textColor = const Color(0xFFCBD5E1);
    } else {
      // Past day with no record = present (was at school)
      bgColor = AppColors.success.withValues(alpha: 0.12);
      textColor = const Color(0xFF15803D);
    }

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: isToday ? Border.all(color: AppColors.primary, width: 1.5) : null,
      ),
      child: Center(
        child: Text('$day', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor)),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2.5))),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: AppColors.slate500, fontSize: 11)),
      ],
    );
  }

  // ==================== PAYMENTS CARD ====================
  Widget _buildPaymentsCard(UserProfileData data) {
    final totalDue = data.totalDue;
    final totalPaid = data.totalPaid;
    final totalAmount = totalPaid + totalDue;
    final pct = totalAmount > 0 ? (totalPaid / totalAmount * 100).clamp(0.0, 100.0) : 0.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.push('/payments', extra: {'studentId': widget.userId}),
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: _cardDecoration(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('Paiements', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.slate800)),
                  const Spacer(),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => context.push('/payments', extra: {'studentId': widget.userId}),
                      child: Text('Voir tout', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Donut chart
              Center(
                child: SizedBox(
                  width: 160,
                  height: 160,
                  child: CustomPaint(
                    painter: _DonutPainter(percentage: pct, color: pct >= 75 ? AppColors.success : (pct >= 50 ? AppColors.warning : AppColors.error)),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${pct.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.slate800)),
                          Text('Payé', style: TextStyle(color: AppColors.slate400, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _paymentItem('Total dû', '${totalDue.toStringAsFixed(0)} TND'),
              const SizedBox(height: 8),
              _paymentItem('Total payé', '${totalPaid.toStringAsFixed(0)} TND'),
              const SizedBox(height: 8),
              _paymentItem('Reste', '${(totalDue - totalPaid).clamp(0.0, double.infinity).toStringAsFixed(0)} TND'),
              const SizedBox(height: 8),
              _paymentItem('À temps', '${data.onTimePayments}'),
              const SizedBox(height: 8),
              _paymentItem('En retard', '${data.latePayments}'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paymentItem(String label, String value) {
    IconData icon;
    switch (label) {
      case 'Total dû':
        icon = Icons.account_balance_wallet_outlined;
        break;
      case 'Total payé':
        icon = Icons.check_circle_outline_rounded;
        break;
      case 'Reste':
        icon = Icons.error_outline_rounded;
        break;
      case 'À temps':
        icon = Icons.access_time_rounded;
        break;
      case 'En retard':
        icon = Icons.warning_amber_rounded;
        break;
      default:
        icon = Icons.circle_outlined;
    }
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: AppColors.slate500, fontSize: 13)),
        const Spacer(),
        Text(value, style: const TextStyle(color: AppColors.slate700, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  // ==================== ACTIVITY LOG ====================
  Widget _buildActivityLog(UserProfileData data) {
    final activities = data.activityLog;
    final totalItems = activities.length;
    final totalPages =
        _activityPerPage == -1 ? 1 : (totalItems / _activityPerPage).ceil();
    if (_activityPage > totalPages && totalPages > 0) {
      _activityPage = totalPages;
    }
    final startIndex =
        _activityPerPage == -1 ? 0 : (_activityPage - 1) * _activityPerPage;
    final endIndex = _activityPerPage == -1
        ? totalItems
        : (startIndex + _activityPerPage).clamp(0, totalItems);
    final pageActivities = (startIndex < totalItems)
        ? activities.sublist(startIndex, endIndex)
        : <Map<String, dynamic>>[];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
        boxShadow: AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: Row(
                children: [
                  const Text(
                    'Activité Récente',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.slate800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$totalItems activité${totalItems > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),

            if (activities.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(Icons.history_rounded,
                          size: 40, color: AppColors.slate300),
                      const SizedBox(height: 12),
                      Text(
                        'Aucune activité récente',
                        style: TextStyle(
                            color: AppColors.slate400, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // Table Header Row (Users table style)
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Color(0xFFE2E8F0)),
                    bottom: BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: _activityHeaderLabel('ACTION')),
                    Expanded(flex: 5, child: _activityHeaderLabel('DÉTAILS')),
                    Expanded(flex: 2, child: _activityHeaderLabel('DATE')),
                  ],
                ),
              ),

              // Table Body Rows (short fixed max-height, scrollable inside)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 215),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: pageActivities.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  itemBuilder: (context, index) {
                    final a = pageActivities[index];
                    final action = a['action'] as String? ?? '';
                    final type = a['type'] as String? ?? '';
                    final detail = (a['details'] ?? a['detail']) as String? ?? '';
                    final date = a['date'] as String? ?? '';

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {},
                        hoverColor: const Color(0xFFF9FAFB),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 11,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _activityBadge(action, type),
                                ),
                              ),
                              Expanded(
                                flex: 5,
                                child: Text(
                                  detail,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _formatActivityDate(date),
                                  style: const TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Bottom Pagination Footer (Exact Users table footer)
              _buildActivityPagination(totalItems),
            ],
          ],
        ),
      ),
    );
  }

  Widget _activityHeaderLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textTertiary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildActivityPagination(int totalItems) {
    final totalPages =
        _activityPerPage == -1 ? 1 : (totalItems / _activityPerPage).ceil();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFB),
        border: Border(top: BorderSide(color: AppColors.border.withOpacity(0.3))),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'Afficher par ',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _activityPerPage,
                isDense: true,
                borderRadius: BorderRadius.circular(10),
                dropdownColor: Colors.white,
                elevation: 4,
                menuMaxHeight: 200,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 14,
                  color: AppColors.textTertiary,
                ),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
                items: const [10, 20, 50, -1]
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(
                          v == -1 ? 'All' : '$v',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _activityPerPage = v;
                      _activityPage = 1;
                    });
                  }
                },
              ),
            ),
          ),
          const Spacer(),
          Text(
            'Page $_activityPage sur ${totalPages == 0 ? 1 : totalPages}',
            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: _activityPage > 1
                      ? () => setState(() => _activityPage--)
                      : null,
                  borderRadius:
                      const BorderRadius.horizontal(left: Radius.circular(5)),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.chevron_left,
                      size: 18,
                      color: _activityPage > 1
                          ? AppColors.textSecondary
                          : AppColors.textTertiary,
                    ),
                  ),
                ),
                Container(width: 1, height: 24, color: AppColors.border),
                InkWell(
                  onTap: _activityPage < totalPages
                      ? () => setState(() => _activityPage++)
                      : null,
                  borderRadius:
                      const BorderRadius.horizontal(right: Radius.circular(5)),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: _activityPage < totalPages
                          ? AppColors.textSecondary
                          : AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _activityBadge(String action, String type) {
    Color color;
    String label = action.isNotEmpty ? action : type;
    final lower = label.toLowerCase();
    if (lower.contains('absence') || type == 'error' || type == 'warning') {
      color = AppColors.error;
      label = 'Absence';
    } else if (lower.contains('note') || lower.contains('grade')) {
      color = AppColors.primary;
      label = 'Note';
    } else if (lower.contains('paiement') || lower.contains('payment') || type == 'success') {
      color = AppColors.success;
      label = 'Paiement';
    } else if (lower.contains('suggestion') || type == 'purple') {
      color = AppColors.warning;
      label = 'Suggestion';
    } else if (lower.contains('annonce') || lower.contains('message') || type == 'info') {
      color = const Color(0xFF8B5CF6);
      label = 'Annonce';
    } else {
      color = AppColors.slate400;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  String _formatActivityDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays}j';
    return DateFormat('d MMM yyyy', 'fr_FR').format(date);
  }

  // ==================== REUSABLE HELPERS ====================
  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
      boxShadow: AppShadows.card,
    );
  }

  Widget _iconButton({required IconData icon, required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 20, color: AppColors.slate600),
          ),
        ),
      ),
    );
  }



  Widget _brandOutlineButton({
    required String label,
    IconData? icon,
    VoidCallback? onTap,
    bool isLoading = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading)
                  const IosLoader.small(color: AppColors.slate500)
                else if (icon != null) ...[
                  Icon(icon, size: 16, color: AppColors.slate500),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.slate500,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniIconBtn({required IconData icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(6)),
        child: Icon(icon, size: 16, color: onTap != null ? AppColors.slate500 : AppColors.slate300),
      ),
    );
  }

  // ==================== PHOTO UPLOAD ====================
  Future<void> _pickAndUploadPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    // Show cropper dialog to position and frame the avatar perfectly
    final croppedBytes = await AvatarCropperDialog.show(
      context: context,
      rawImageBytes: file.bytes!,
    );
    if (croppedBytes == null) return; // User cancelled

    setState(() {
      _optimisticPhotoBytes = croppedBytes;
      _isUploadingPhoto = true;
    });

    try {
      final ext = 'png';
      final path = 'avatars/${widget.userId}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      final supabase = Supabase.instance.client;

      await supabase.storage.from('avatars').uploadBinary(
        path,
        croppedBytes,
        fileOptions: const FileOptions(upsert: true, contentType: 'image/png'),
      );

      final publicUrl = supabase.storage.from('avatars').getPublicUrl(path);

      await supabase
          .from('users')
          .update({'photo_url': publicUrl}).eq('id', widget.userId);

      if (mounted) {
        setState(() {
          _optimisticPhotoUrl = publicUrl;
        });
      }

      ref.invalidate(userProfileDataProvider(widget.userId));
      ref.invalidate(usersProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo de profil mise à jour avec succès !'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _optimisticPhotoBytes = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFriendlyError.format(e)), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  // ==================== KEPT HELPERS ====================
  Color _getRoleColor(String role) {
    switch (role) {
      case 'admin':
        return AppColors.error;
      case 'staff':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  String _getRoleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'Admin';
      case 'staff':
        return 'Manager';
      default:
        return 'Étudiant';
    }
  }


  String _formatDate(String? dateStr) {
    if (dateStr == null) return '-';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    return DateFormat('d MMM yyyy', 'fr_FR').format(date);
  }

  // ==================== STUDENT PAYMENTS DIALOG ====================
  void _showStudentPaymentsSheet(UserProfileData data) {
    final userId = widget.userId;
    final studentName = data.user['full_name'] as String? ?? 'Étudiant';
    final className = data.className;

    final paidAmount = data.totalPaid;
    final totalAmount = data.totalPaid + data.totalDue;
    final paidPayments = data.payments.where((p) => p['status'] == 'paid').length;
    final totalPayments = data.payments.length;
    final progressPercent = totalAmount > 0 ? (paidAmount / totalAmount * 100) : 0.0;

    showDialog(
      context: context,
      builder: (ctx) => _StudentPaymentsSheet(
        studentId: userId,
        studentName: studentName,
        photoUrl: data.user['photo_url'] as String? ?? data.user['photo'] as String? ?? data.user['avatar_url'] as String?,
        className: className,
        paidAmount: paidAmount,
        totalAmount: totalAmount,
        paidPayments: paidPayments,
        totalPayments: totalPayments,
        progressPercent: progressPercent,
      ),
    );
  }
}

// ==================== STUDENT PAYMENTS DIALOG WIDGET ====================
class _StudentPaymentsSheet extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String? photoUrl;
  final String? className;
  final double paidAmount;
  final double totalAmount;
  final int paidPayments;
  final int totalPayments;
  final double progressPercent;

  const _StudentPaymentsSheet({
    required this.studentId,
    required this.studentName,
    this.photoUrl,
    required this.className,
    required this.paidAmount,
    required this.totalAmount,
    required this.paidPayments,
    required this.totalPayments,
    required this.progressPercent,
  });

  @override
  State<_StudentPaymentsSheet> createState() => _StudentPaymentsSheetState();
}

class _StudentPaymentsSheetState extends State<_StudentPaymentsSheet> {
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _paymentPlans = [];
  bool _isLoading = true;
  String _selectedCategory = 'all';
  final Set<String> _selectedPaymentIds = {};
  double _paidAmount = 0;
  double _totalAmount = 0;
  int _paidPayments = 0;
  int _totalPayments = 0;

  @override
  void initState() {
    super.initState();
    _loadStudentPayments();
  }

  Future<void> _loadStudentPayments() async {
    try {
      final supabase = Supabase.instance.client;

      final enrollments = await supabase
          .from('enrollments')
          .select('id')
          .eq('user_id', widget.studentId);
      final enrollmentIds =
          (enrollments as List).map((e) => e['id'] as String).toList();

      if (enrollmentIds.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final plansResponse = await supabase
          .from('payment_plans')
          .select(
              'id, plan_type, category, enrollment_id, amount_total, created_at')
          .inFilter('enrollment_id', enrollmentIds)
          .order('created_at', ascending: false);

      final paymentsResponse = await supabase
          .from('payments')
          .select(
              '*, payment_plans!inner(id, plan_type, category, enrollment_id)')
          .inFilter('payment_plans.enrollment_id', enrollmentIds)
          .order('due_date', ascending: true);

      final seenIds = <String>{};
      final uniquePayments = <Map<String, dynamic>>[];
      for (final p in paymentsResponse as List) {
        final id = p['id']?.toString() ?? '';
        if (id.isNotEmpty && !seenIds.contains(id)) {
          seenIds.add(id);
          uniquePayments.add(Map<String, dynamic>.from(p));
        }
      }

      final paidAmount = uniquePayments
          .where((p) => p['status'] == 'paid')
          .fold<double>(0, (sum, p) => sum + (p['amount'] as num? ?? 0).toDouble());
      final totalAmount = uniquePayments
          .fold<double>(0, (sum, p) => sum + (p['amount'] as num? ?? 0).toDouble());
      final paidPayments = uniquePayments.where((p) => p['status'] == 'paid').length;
      final totalPayments = uniquePayments.length;

      setState(() {
        _paymentPlans = List<Map<String, dynamic>>.from(plansResponse);
        _payments = uniquePayments;
        _paidAmount = paidAmount;
        _totalAmount = totalAmount;
        _paidPayments = paidPayments;
        _totalPayments = totalPayments;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('StudentPaymentsSheet: error loading payments: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: SizedBox(
          width: 880,
          height: 680,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 40,
                      offset: const Offset(0, 20),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: _isLoading
                          ? const Center(child: IosLoader())
                          : _buildMonthlyTimelineView(),
                    ),
                  ],
                ),
              ),
              if (_selectedPaymentIds.isNotEmpty)
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: Center(child: _buildFloatingBulkBar()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingBulkBar() {
    final count = _selectedPaymentIds.length;

    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(10),
      color: const Color(0xFF111827),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: Colors.white.withOpacity(0.15))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: const Color(0xFF655DD5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Sélectionnés',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            _buildSelectionAction(
              Icons.check_circle_outline_rounded,
              'Marquer payé',
              Colors.white70,
              () => _bulkMarkPaid(),
            ),
            _buildSelectionAction(
              Icons.cancel_outlined,
              'Annuler',
              Colors.white70,
              () => _bulkCancel(),
            ),
            _buildSelectionAction(
              Icons.delete_outline,
              'Supprimer',
              const Color(0xFFFCA5A5),
              () => _bulkDelete(),
            ),
            Container(
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: Colors.white.withOpacity(0.15))),
              ),
              child: IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.white60),
                onPressed: () => setState(() => _selectedPaymentIds.clear()),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _bulkMarkPaid() async {
    final ids = _selectedPaymentIds.toList();
    final now = DateTime.now().toIso8601String();
    setState(() {
      for (var p in _payments) {
        if (ids.contains(p['id'])) {
          p['status'] = 'paid';
          p['paid_at'] = now;
        }
      }
      _selectedPaymentIds.clear();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paiements marqués comme payés'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }

    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('payments')
          .update({
            'status': 'paid',
            'paid_at': now,
          })
          .filter('id', 'in', '(${ids.join(',')})');
      _loadStudentPayments();
    } catch (e) {
      _loadStudentPayments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFriendlyError.format(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _bulkCancel() async {
    final ids = _selectedPaymentIds.toList();
    setState(() {
      for (var p in _payments) {
        if (ids.contains(p['id'])) {
          p['status'] = 'cancelled';
        }
      }
      _selectedPaymentIds.clear();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paiements annulés'),
          backgroundColor: AppColors.warning,
        ),
      );
    }

    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('payments')
          .update({'status': 'cancelled'})
          .filter('id', 'in', '(${ids.join(',')})');
      _loadStudentPayments();
    } catch (e) {
      _loadStudentPayments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFriendlyError.format(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _bulkDelete() async {
    final ids = _selectedPaymentIds.toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Supprimer les paiements ?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text('Voulez-vous vraiment supprimer ${ids.length} paiement(s) ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _payments.removeWhere((p) => ids.contains(p['id']));
      _selectedPaymentIds.clear();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paiements supprimés'),
          backgroundColor: AppColors.error,
        ),
      );
    }

    try {
      final supabase = Supabase.instance.client;
      await supabase.from('payments').delete().filter('id', 'in', '(${ids.join(',')})');
      _loadStudentPayments();
    } catch (e) {
      _loadStudentPayments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFriendlyError.format(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Widget _buildHeader() {
    final progress = _totalAmount > 0 ? (_paidAmount / _totalAmount) * 100 : 0.0;
    final isComplete = progress >= 100;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 32),
      child: Row(
        children: [
          UserAvatar(
            name: widget.studentName,
            photoUrl: widget.photoUrl,
            radius: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.studentName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      widget.className ?? 'Non assigné',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.slate400,
                      ),
                    ),
                    if (_paymentPlans.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _buildPaymentModeBadge(),
                    ],
                  ],
                ),
              ],
            ),
          ),
          _headerPill(
            '${_paidAmount.toStringAsFixed(0)} TND',
            'payé sur ${_totalAmount.toStringAsFixed(0)}',
          ),
          const SizedBox(width: 6),
          _headerPill(
            '$_paidPayments/$_totalPayments',
            'paiements',
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isComplete
                  ? const Color(0xFF10B981).withOpacity(0.08)
                  : AppColors.slate50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isComplete
                      ? Icons.check_circle_rounded
                      : Icons.schedule_rounded,
                  size: 12,
                  color: isComplete
                      ? const Color(0xFF10B981)
                      : AppColors.slate400,
                ),
                const SizedBox(width: 4),
                Text(
                  isComplete ? 'Soldé' : '${progress.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isComplete
                        ? const Color(0xFF10B981)
                        : AppColors.slate600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close_rounded, size: 20, color: AppColors.slate400),
          ),
        ],
      ),
    );
  }

  Widget _headerPill(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.slate800,
              ),
            ),
            TextSpan(
              text: ' $label',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.slate400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentModeBadge() {
    String planType = 'monthly';
    for (final p in _paymentPlans) {
      if (p['is_active'] != false) {
        planType = p['plan_type']?.toString() ?? 'monthly';
        break;
      }
    }
    if (_paymentPlans.isNotEmpty) {
      planType = _paymentPlans.first['plan_type']?.toString() ?? planType;
    }

    final String label;
    switch (planType) {
      case 'annual':
        label = 'Annuel';
        break;
      case 'semester':
      case 'trimester':
        label = 'Trimestriel';
        break;
      case 'semesterly':
        label = 'Semestriel';
        break;
      case 'monthly':
      default:
        label = 'Mensuel';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.slate100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  static const _monthNames = [
    '',
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  String _monthName(int month) =>
      month >= 1 && month <= 12 ? _monthNames[month] : '';


  Widget _buildMonthlyTimelineView() {
    final filteredPayments = _selectedCategory == 'all'
        ? _payments
        : _payments.where((p) {
            final plan = p['payment_plans'] as Map<String, dynamic>?;
            return plan?['category'] == _selectedCategory;
          }).toList();

    filteredPayments.sort((a, b) {
      final dateA = DateTime.tryParse(a['due_date'] ?? '') ?? DateTime(1970);
      final dateB = DateTime.tryParse(b['due_date'] ?? '') ?? DateTime(1970);
      return dateA.compareTo(dateB);
    });

    if (filteredPayments.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: _buildCategoryFilter(),
          ),
          const SizedBox(height: 20),
          Expanded(child: _buildEmptyState('Aucun paiement programmé', Icons.calendar_today)),
        ],
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCategoryFilter(),
          const SizedBox(height: 16),
          ...filteredPayments.map(
            (payment) => _buildPaymentTimelineCard(payment),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    final categories = [
      ('scolarite', 'Scolarité', Icons.school_rounded),
      ('transport', 'Transport', Icons.directions_bus_rounded),
      ('cantine', 'Cantine', Icons.restaurant_rounded),
      ('inscription', 'Inscription', Icons.assignment_rounded),
      ('uniforme', 'Uniforme', Icons.checkroom_rounded),
      ('activites', 'Activités', Icons.sports_soccer_rounded),
      ('autres', 'Autres', Icons.more_horiz_rounded),
    ];

    final visiblePayments = _payments
        .where((p) => _selectedCategory == 'all' ||
            (p['payment_plans']?['category'] == _selectedCategory))
        .toList();
    final allSelected = visiblePayments.isNotEmpty &&
        visiblePayments.every((p) => _selectedPaymentIds.contains(p['id']?.toString()));

    return Row(
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: allSelected,
            tristate: false,
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  _selectedPaymentIds.addAll(
                    visiblePayments.map((p) => p['id']?.toString() ?? ''),
                  );
                } else {
                  for (final p in visiblePayments) {
                    _selectedPaymentIds.remove(p['id']?.toString());
                  }
                }
              });
            },
            activeColor: const Color(0xFF655DD5),
            side: BorderSide(color: AppColors.slate300),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((cat) {
                final isSelected = _selectedCategory == cat.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: isSelected,
                    showCheckmark: false,
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(cat.$3, size: 15),
                        const SizedBox(width: 5),
                        Text(cat.$2),
                      ],
                    ),
                    selectedColor: const Color(0xFF655DD5).withOpacity(0.1),
                    checkmarkColor: const Color(0xFF655DD5),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: isSelected
                          ? const Color(0xFF655DD5)
                          : AppColors.slate600,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? const Color(0xFF655DD5).withOpacity(0.3)
                          : AppColors.slate200,
                    ),
                    onSelected: (_) => setState(() {
                      _selectedCategory =
                          _selectedCategory == cat.$1 ? 'all' : cat.$1;
                    }),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentTimelineCard(Map<String, dynamic> payment) {
    final status = payment['status'] ?? 'pending';
    final amount = (payment['amount'] as num? ?? 0).toDouble();
    final dueDate = DateTime.tryParse(payment['due_date'] ?? '');
    final paidAt = payment['paid_at'] != null
        ? DateTime.tryParse(payment['paid_at'])
        : null;
    final plan = payment['payment_plans'] as Map<String, dynamic>?;
    final category = payment['category'] ?? plan?['category'] ?? 'scolarite';

    final isOverdue = status == 'pending' &&
        dueDate != null &&
        dueDate.isBefore(DateTime.now());
    final isPaid = status == 'paid';

    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (isPaid) {
      statusColor = const Color(0xFF10B981);
      statusIcon = Icons.check_circle;
      statusText = 'Payé';
    } else if (isOverdue) {
      statusColor = const Color(0xFFEF4444);
      statusIcon = Icons.warning_rounded;
      statusText = 'En retard';
    } else {
      statusColor = const Color(0xFFF59E0B);
      statusIcon = Icons.access_time;
      statusText = 'En attente';
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _selectedPaymentIds.contains(payment['id']?.toString())
                ? const Color(0xFF655DD5).withOpacity(0.4)
                : isPaid
                    ? AppColors.slate100
                    : statusColor.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value:
                    _selectedPaymentIds.contains(payment['id']?.toString()),
                onChanged: (value) {
                  final id = payment['id']?.toString();
                  if (id == null) return;
                  setState(() {
                    if (value == true) {
                      _selectedPaymentIds.add(id);
                    } else {
                      _selectedPaymentIds.remove(id);
                    }
                  });
                },
                activeColor: const Color(0xFF655DD5),
                side: BorderSide(color: AppColors.slate300),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(width: 2),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _getCategoryColor(category).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _getCategoryIcon(category),
                color: _getCategoryColor(category),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getCategoryName(category),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.slate800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dueDate != null
                        ? 'Échéance: ${dueDate.day} ${_monthName(dueDate.month)} ${dueDate.year}'
                        : 'Date non définie',
                    style: TextStyle(
                      color: AppColors.slate400, fontSize: 12),
                  ),
                  if (paidAt != null)
                    Text(
                      'Payé le: ${paidAt.day} ${_monthName(paidAt.month)} ${paidAt.year}',
                      style: TextStyle(
                        color: AppColors.slate400,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${amount.toStringAsFixed(0)} TND',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.slate700,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 11, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz, size: 18, color: AppColors.slate400),
              tooltip: 'Actions',
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 8,
              offset: const Offset(-8, 32),
              onSelected: (action) => _handlePaymentAction(action, payment),
              itemBuilder: (context) => [
                _buildPopupItem('mark_paid', Icons.check_circle_outline_rounded, 'Marquer payé', const Color(0xFF10B981)),
                _buildPopupItem('edit', Icons.edit_outlined, 'Modifier', const Color(0xFF655DD5)),
                const PopupMenuDivider(height: 1),
                _buildPopupItem('cancel', Icons.close_rounded, 'Annuler', AppColors.error),
              ],
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildPopupItem(String value, IconData icon, String label, Color color) {
    return PopupMenuItem(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: value == 'cancel' ? AppColors.error : AppColors.slate700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePaymentAction(String action, Map<String, dynamic> payment) async {
    final paymentId = payment['id']?.toString();
    if (paymentId == null) return;

    try {
      final supabase = Supabase.instance.client;
      switch (action) {
        case 'mark_paid':
          final now = DateTime.now().toIso8601String();
          setState(() {
            payment['status'] = 'paid';
            payment['paid_at'] = now;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Paiement marqué comme payé'),
                backgroundColor: Color(0xFF10B981),
              ),
            );
          }
          await supabase
              .from('payments')
              .update({
                'status': 'paid',
                'paid_at': now,
              })
              .eq('id', paymentId);
          _loadStudentPayments();
          break;
        case 'edit':
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Édition à venir')),
            );
          }
          break;
        case 'cancel':
          final confirm = await showDialog<bool>(
            context: context,
            builder: (dCtx) => AlertDialog(
              title: const Text('Confirmer l\'annulation'),
              content: const Text('Voulez-vous vraiment annuler ce paiement ?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Non')),
                TextButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Oui, annuler')),
              ],
            ),
          );
          if (confirm == true) {
            setState(() {
              payment['status'] = 'cancelled';
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Paiement annulé'),
                  backgroundColor: AppColors.warning,
                ),
              );
            }
            await supabase
                .from('payments')
                .update({'status': 'cancelled'})
                .eq('id', paymentId);
            _loadStudentPayments();
          }
          break;
      }
    } catch (e) {
      _loadStudentPayments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFriendlyError.format(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  String _normalizeCategory(String? category) {
    if (category == null || category.trim().isEmpty) return 'autres';
    final c = category.toLowerCase().trim().replaceAll('é', 'e').replaceAll('è', 'e');
    if (c.contains('scolar') || c.contains('tuition')) return 'scolarite';
    if (c.contains('transp') || c.contains('bus')) return 'transport';
    if (c.contains('cantin') || c.contains('restau') || c.contains('repas')) return 'cantine';
    if (c.contains('inscript') || c.contains('regist') || c.contains('frais')) return 'inscription';
    if (c.contains('uniform') || c.contains('tenue') || c.contains('vetement') || c.contains('vêtement')) return 'uniforme';
    if (c.contains('activit') || c.contains('sport') || c.contains('club') || c.contains('culture')) return 'activites';
    return 'autres';
  }

  Color _getCategoryColor(String category) {
    switch (_normalizeCategory(category)) {
      case 'scolarite':
        return const Color(0xFF3B82F6);
      case 'transport':
        return const Color(0xFF10B981);
      case 'cantine':
        return const Color(0xFFF59E0B);
      case 'inscription':
        return const Color(0xFF8B5CF6);
      case 'uniforme':
        return const Color(0xFFEC4899);
      case 'activites':
        return const Color(0xFF14B8A6);
      case 'autres':
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (_normalizeCategory(category)) {
      case 'scolarite':
        return Icons.school_rounded;
      case 'transport':
        return Icons.directions_bus_rounded;
      case 'cantine':
        return Icons.restaurant_rounded;
      case 'inscription':
        return Icons.assignment_rounded;
      case 'uniforme':
        return Icons.checkroom_rounded;
      case 'activites':
        return Icons.sports_soccer_rounded;
      case 'autres':
      default:
        return Icons.more_horiz_rounded;
    }
  }

  String _getCategoryName(String category) {
    switch (_normalizeCategory(category)) {
      case 'scolarite':
        return 'Scolarité';
      case 'transport':
        return 'Transport';
      case 'cantine':
        return 'Cantine';
      case 'inscription':
        return 'Inscription';
      case 'uniforme':
        return 'Uniforme';
      case 'activites':
        return 'Activités';
      case 'autres':
      default:
        return 'Autres';
    }
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: AppColors.slate200),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: AppColors.textTertiary, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

// ==================== DONUT PAINTER ====================
class _DonutPainter extends CustomPainter {
  final double percentage;
  final Color color;

  _DonutPainter({required this.percentage, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    const strokeWidth = 14.0;

    // Background arc
    final bgPaint = Paint()
      ..color = AppColors.slate100
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius - strokeWidth / 2, bgPaint);

    // Foreground arc
    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final sweepAngle = 2 * pi * (percentage / 100);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      -pi / 2,
      sweepAngle,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.percentage != percentage || old.color != color;
}
