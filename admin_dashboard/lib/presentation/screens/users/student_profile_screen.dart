import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/admin_sidebar.dart';
import '../../widgets/user_avatar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../widgets/ios_loader.dart';
import '../../widgets/skeleton_loader.dart';

// Comprehensive student profile provider
final studentProfileProvider =
    FutureProvider.family<StudentProfileData?, String>((ref, studentId) async {
      final supabase = Supabase.instance.client;

      try {
        // Get user basic info
        final userResponse = await supabase
            .from('users')
            .select()
            .eq('id', studentId)
            .maybeSingle();

        if (userResponse == null) return null;

        // Get all enrollments (to calculate years at school)
        final enrollments = await supabase
            .from('enrollments')
            .select('*, classes(name, level, academic_year), groups(name)')
            .eq('user_id', studentId)
            .order('created_at', ascending: false);

        // Get current enrollment
        final currentEnrollment = await supabase
            .from('enrollments')
            .select('*, classes(name, level, academic_year), groups(name)')
            .eq('user_id', studentId)
            .maybeSingle();

        // Get suggestions
        final suggestions = await supabase
            .from('suggestions')
            .select('id, subject, status, suggestion_type, created_at')
            .eq('student_id', studentId)
            .order('created_at', ascending: false);

        // Collect all enrollment IDs for this student
        final List<String> enrollmentIds = [];
        if (currentEnrollment != null && currentEnrollment['id'] != null) {
          enrollmentIds.add(currentEnrollment['id'].toString());
        }
        for (final e in (enrollments as List)) {
          final idStr = e['id']?.toString();
          if (idStr != null && !enrollmentIds.contains(idStr)) {
            enrollmentIds.add(idStr);
          }
        }

        // Get absences specifically for this student
        final now = DateTime.now();
        final startOfMonth = DateTime(now.year, now.month, 1);
        final endOfMonth = DateTime(now.year, now.month + 1, 0);

        List<Map<String, dynamic>> monthlyAbsences = [];
        int totalAbsences = 0;
        try {
          final absResp = await supabase
              .from('absence_records')
              .select('id, date, hours_absent, justified, reason')
              .eq('student_id', studentId)
              .order('date', ascending: false);
          monthlyAbsences = (absResp as List).cast<Map<String, dynamic>>();

          if (monthlyAbsences.isEmpty && enrollmentIds.isNotEmpty) {
            final fallbackResp = await supabase
                .from('absence_records')
                .select('id, date, hours_absent, justified, reason')
                .inFilter('enrollment_id', enrollmentIds)
                .order('date', ascending: false);
            monthlyAbsences = (fallbackResp as List).cast<Map<String, dynamic>>();
          }
          totalAbsences = monthlyAbsences.length;
        } catch (_) {}

        // Get payment history specifically for this student
        List<Map<String, dynamic>> payments = [];
        double paymentAccuracy = 0;
        int onTimePayments = 0;
        int latePayments = 0;
        double totalPaid = 0;
        double totalDue = 0;

        try {
          if (enrollmentIds.isNotEmpty) {
            final pResp = await supabase
                .from('payments')
                .select('amount, status, due_date, paid_at, description, created_at, payment_plans!inner(enrollment_id)')
                .inFilter('payment_plans.enrollment_id', enrollmentIds)
                .order('created_at', ascending: false);
            payments = (pResp as List).cast<Map<String, dynamic>>();
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

          final totalPaymentCount = onTimePayments + latePayments;
          if (totalPaymentCount > 0) {
            paymentAccuracy = (onTimePayments / totalPaymentCount) * 100;
          }
        } catch (_) {}

        // Get grades specifically for this student
        List<Map<String, dynamic>> grades = [];
        try {
          if (enrollmentIds.isNotEmpty) {
            final gResp = await supabase
                .from('grades')
                .select('id, grade_value, status, subjects(name)')
                .inFilter('enrollment_id', enrollmentIds)
                .order('created_at', ascending: false)
                .limit(20);
            grades = (gResp as List).cast<Map<String, dynamic>>();
          }
        } catch (_) {}

        // Get timetable
        List<Map<String, dynamic>> timetable = [];
        try {
          timetable = await supabase
              .from('timetable_slots')
              .select('*, subject_offerings(subjects(name))')
              .order('day_of_week')
              .order('start_time');
        } catch (_) {}

        // Get class messages
        List<Map<String, dynamic>> messages = [];
        try {
          if (currentEnrollment != null) {
            messages = await supabase
                .from('announcements_class')
                .select('id, title, body, published_at')
                .eq('class_id', currentEnrollment['class_id'])
                .order('published_at', ascending: false)
                .limit(5);
          }
        } catch (_) {}

        // Calculate years at school
        final yearsAtSchool = (enrollments as List).length;
        final firstEnrollment = enrollments.isNotEmpty
            ? enrollments.last
            : null;
        DateTime? enrolledSince;
        if (firstEnrollment != null && firstEnrollment['created_at'] != null) {
          enrolledSince = DateTime.tryParse(firstEnrollment['created_at']);
        }

        return StudentProfileData(
          user: userResponse,
          currentEnrollment: currentEnrollment,
          enrollments: (enrollments as List).cast<Map<String, dynamic>>(),
          suggestions: (suggestions as List)
              .cast<Map<String, dynamic>>()
              .where((s) {
                final type = s['suggestion_type']?.toString().toLowerCase() ?? '';
                final subject = s['subject']?.toString() ?? '';
                return type != 'bug_report' && type != 'bug' && !subject.contains('[BUG REPORT');
              })
              .toList(),
          monthlyAbsences: monthlyAbsences,
          totalAbsences: totalAbsences,
          payments: payments,
          paymentAccuracy: paymentAccuracy,
          onTimePayments: onTimePayments,
          latePayments: latePayments,
          totalPaid: totalPaid,
          totalDue: totalDue,
          grades: grades,
          timetable: timetable,
          messages: messages,
          yearsAtSchool: yearsAtSchool,
          enrolledSince: enrolledSince,
        );
      } catch (e) {
        debugPrint('Error loading student profile: $e');
        return null;
      }
    });

class StudentProfileData {
  final Map<String, dynamic> user;
  final Map<String, dynamic>? currentEnrollment;
  final List<Map<String, dynamic>> enrollments;
  final List<Map<String, dynamic>> suggestions;
  final List<Map<String, dynamic>> monthlyAbsences;
  final int totalAbsences;
  final List<Map<String, dynamic>> payments;
  final double paymentAccuracy;
  final int onTimePayments;
  final int latePayments;
  final double totalPaid;
  final double totalDue;
  final List<Map<String, dynamic>> grades;
  final List<Map<String, dynamic>> timetable;
  final List<Map<String, dynamic>> messages;
  final int yearsAtSchool;
  final DateTime? enrolledSince;

  StudentProfileData({
    required this.user,
    this.currentEnrollment,
    this.enrollments = const [],
    this.suggestions = const [],
    this.monthlyAbsences = const [],
    this.totalAbsences = 0,
    this.payments = const [],
    this.paymentAccuracy = 0,
    this.onTimePayments = 0,
    this.latePayments = 0,
    this.totalPaid = 0,
    this.totalDue = 0,
    this.grades = const [],
    this.timetable = const [],
    this.messages = const [],
    this.yearsAtSchool = 0,
    this.enrolledSince,
  });
}

class StudentProfileScreen extends ConsumerStatefulWidget {
  final String studentId;
  final String? studentName;

  const StudentProfileScreen({
    super.key,
    required this.studentId,
    this.studentName,
  });

  @override
  ConsumerState<StudentProfileScreen> createState() =>
      _StudentProfileScreenState();
}

class _StudentProfileScreenState extends ConsumerState<StudentProfileScreen> {
  bool _isUploadingPhoto = false;
  bool _showPassword = false; // Toggle to show/hide initial password

  Future<void> _uploadProfilePhoto() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() => _isUploadingPhoto = true);

      final file = result.files.first;
      if (file.bytes == null) return;

      final supabase = Supabase.instance.client;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = 'profiles/${widget.studentId}/${timestamp}_${file.name}';

      await supabase.storage.from('avatars').uploadBinary(path, file.bytes!);
      final url = supabase.storage.from('avatars').getPublicUrl(path);

      await supabase
          .from('users')
          .update({'photo_url': url})
          .eq('id', widget.studentId);

      ref.invalidate(studentProfileProvider(widget.studentId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo mise à jour'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFriendlyError.format(
                e,
                fallback: 'Unable to update the photo right now. Please try again.',
              ),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _removeProfilePhoto() async {
    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('users')
          .update({'photo_url': null})
          .eq('id', widget.studentId);

      ref.invalidate(studentProfileProvider(widget.studentId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo supprimée'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFriendlyError.format(
                e,
                fallback: 'Unable to update the photo right now. Please try again.',
              ),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(studentProfileProvider(widget.studentId));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Row(
        children: [
          const AdminSidebar(currentRoute: '/users'),
          Expanded(
            child: profileAsync.when(
              loading: () => const StudentProfileSkeletonLoader(),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error, size: 48, color: AppColors.error),
                    const SizedBox(height: 16),
                    Text(
                      UserFriendlyError.format(
                        e,
                        fallback: 'Unable to load this student profile right now. Please try again.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(
                        studentProfileProvider(widget.studentId),
                      ),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
              data: (data) {
                if (data == null) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person_off,
                          size: 64,
                          color: AppColors.slate300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Étudiant non trouvé',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  );
                }
                return _buildContent(context, data);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, StudentProfileData data) {
    return Column(
      children: [
        _buildTopBar(context, data),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _buildProfileHeader(context, data),
              _buildQuickStats(context, data),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cardWidth = (constraints.maxWidth - 40) / 3;
                    final cardHeight = cardWidth / 1.2;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: cardWidth, height: cardHeight, child: _buildAttendanceCard(context, data)),
                        const SizedBox(width: 20),
                        SizedBox(width: cardWidth, height: cardHeight, child: _buildPaymentCard(context, data)),
                        const SizedBox(width: 20),
                        SizedBox(width: cardWidth, height: cardHeight, child: _buildAcademicCard(context, data)),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              _buildQuickAccessSection(context, data),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: _buildSuggestionsCard(context, data)),
                    const SizedBox(width: 20),
                    Expanded(flex: 1, child: _buildMessagesCard(context, data)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context, StudentProfileData data) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(color: AppColors.shadow, blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Retour',
          ),
          const SizedBox(width: 12),
          Text(
            'Profil Étudiant',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          ElevatedButton.icon(
            icon: const Icon(Icons.send, size: 18),
            label: const Text('Envoyer message'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: AppColors.textOnPrimary,
            ),
            onPressed: () {
              debugPrint('Student Profile: Navigating to announcements with studentId: ${widget.studentId}');
              context.go(
                '/announcements',
                extra: {
                  'initialScope': 'student',
                  'preSelectedStudentId': widget.studentId,
                },
              );
            },
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('Modifier'),
            onPressed: () {
              // TODO: Open edit dialog
            },
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'export':
                  // TODO: Export student data
                  break;
                case 'delete':
                  // TODO: Delete student
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export',
                child: Text('Exporter données'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Supprimer', style: TextStyle(color: AppColors.error)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, StudentProfileData data) {
    final user = data.user;
    final enrollment = data.currentEnrollment;
    final classInfo = enrollment?['classes'] as Map<String, dynamic>?;
    final groupInfo = enrollment?['groups'] as Map<String, dynamic>?;

    return Container(
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF6366F1).withOpacity(0.9),
            const Color(0xFF8B5CF6).withOpacity(0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.3),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Stack(
              children: [
                // Background pattern
                Positioned(
                  right: -50,
                  top: -50,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.textOnPrimary.withOpacity(0.1),
                    ),
                  ),
                ),
                Positioned(
                  left: -30,
                  bottom: -30,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.textOnPrimary.withOpacity(0.05),
                    ),
                  ),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Row(
                    children: [
                      // Profile Photo with Edit Options
                      Stack(
                        children: [
                          UserAvatar(
                            name: user['full_name'] ?? 'A',
                            photoUrl: user['photo_url'],
                            radius: 60,
                            borderColor: AppColors.textOnPrimary,
                            borderWidth: 4,
                            gender: user['gender'] == 'F' ? 'F' : null,
                          ),
                          // Photo edit buttons
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: PopupMenuButton<String>(
                              icon: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.shadow,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: _isUploadingPhoto
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: IosLoader.small(),
                                      )
                                    : const Icon(
                                        Icons.camera_alt,
                                        size: 18,
                                        color: Color(0xFF6366F1),
                                      ),
                              ),
                              onSelected: (value) {
                                if (value == 'upload') _uploadProfilePhoto();
                                if (value == 'remove') _removeProfilePhoto();
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'upload',
                                  child: Row(
                                    children: [
                                      Icon(Icons.upload, size: 18),
                                      SizedBox(width: 8),
                                      Text('Télécharger photo'),
                                    ],
                                  ),
                                ),
                                if (user['photo_url'] != null)
                                  const PopupMenuItem(
                                    value: 'remove',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.delete,
                                          size: 18,
                                          color: AppColors.error,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Supprimer photo',
                                          style: TextStyle(color: AppColors.error),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 32),
                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  user['full_name'] ?? 'N/A',
                                  style: const TextStyle(
                                    color: AppColors.textOnPrimary,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.textOnPrimary.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'Étudiant',
                                    style: TextStyle(
                                      color: AppColors.textOnPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Student code
                            if (user['student_code'] != null)
                              Text(
                                'ID: ${user['student_code']}',
                                style: TextStyle(
                                  color: AppColors.textOnPrimary.withOpacity(0.9),
                                  fontSize: 16,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            const SizedBox(height: 16),
                            // Info chips - including Niveau, Classe, Gender, Age, Nationality prominently
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                // Gender
                                if (user['gender'] != null)
                                  _InfoChipLight(
                                    icon: user['gender'] == 'M'
                                        ? Icons.male
                                        : Icons.female,
                                    label: user['gender'] == 'M'
                                        ? 'Masculin'
                                        : 'Féminin',
                                  ),
                                // Age (calculated from date_of_birth)
                                if (user['date_of_birth'] != null)
                                  Builder(
                                    builder: (context) {
                                      final dob = DateTime.tryParse(
                                        user['date_of_birth']?.toString() ?? '',
                                      );
                                      if (dob == null) return const SizedBox.shrink();
                                      final now = DateTime.now();
                                      int age = now.year - dob.year;
                                      if (now.month < dob.month ||
                                          (now.month == dob.month &&
                                              now.day < dob.day)) {
                                        age--;
                                      }
                                      return _InfoChipLight(
                                        icon: Icons.cake,
                                        label: '$age ans',
                                      );
                                    },
                                  ),
                                // Nationality
                                if (user['nationality'] != null)
                                  _InfoChipLight(
                                    icon: Icons.flag,
                                    label: user['nationality'],
                                  ),
                                // Niveau (educational level)
                                if (user['niveau_code'] != null ||
                                    user['niveau'] != null)
                                  _InfoChipLight(
                                    icon: Icons.stairs,
                                    label:
                                        'Niveau: ${user['niveau_code'] ?? user['niveau'] ?? 'N/A'}',
                                  ),
                                // Section (for secondary)
                                if (user['section_code'] != null)
                                  _InfoChipLight(
                                    icon: Icons.category,
                                    label: 'Section: ${user['section_code']}',
                                  ),
                                // Current Class
                                if (classInfo != null)
                                  _InfoChipLight(
                                    icon: Icons.school,
                                    label:
                                        'Classe: ${classInfo['name'] ?? 'N/A'}',
                                  ),
                                if (groupInfo != null)
                                  _InfoChipLight(
                                    icon: Icons.group,
                                    label: 'Groupe ${groupInfo['name'] ?? ''}',
                                  ),
                                // Date of birth
                                if (user['date_of_birth'] != null)
                                  Builder(
                                    builder: (context) {
                                      final dob = DateTime.tryParse(
                                        user['date_of_birth']?.toString() ?? '',
                                      );
                                      if (dob == null) return const SizedBox.shrink();
                                      return _InfoChipLight(
                                        icon: Icons.calendar_today,
                                        label: DateFormat('d MMM yyyy', 'fr_FR').format(dob),
                                      );
                                    },
                                  ),
                                if (data.yearsAtSchool > 0)
                                  _InfoChipLight(
                                    icon: Icons.timeline,
                                    label:
                                        '${data.yearsAtSchool} ${data.yearsAtSchool == 1 ? 'année' : 'années'} à l\'école',
                                  ),
                              ],
                            ),
                            // Login Credentials Section (for managers)
                            if (user['initial_password'] != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.textOnPrimary.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.textOnPrimary.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.lock_outline,
                                      color: AppColors.textOnPrimary,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Mot de passe initial',
                                          style: TextStyle(
                                            color: AppColors.textOnPrimary.withOpacity(
                                              0.7,
                                            ),
                                            fontSize: 10,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _showPassword
                                              ? (user['initial_password'] ?? '')
                                              : '••••••••',
                                          style: const TextStyle(
                                            color: AppColors.textOnPrimary,
                                            fontFamily: 'monospace',
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 12),
                                    IconButton(
                                      icon: Icon(
                                        _showPassword
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        color: AppColors.textOnPrimary.withOpacity(0.8),
                                        size: 20,
                                      ),
                                      tooltip: _showPassword
                                          ? 'Masquer'
                                          : 'Afficher',
                                      onPressed: () => setState(
                                        () => _showPassword = !_showPassword,
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      padding: EdgeInsets.zero,
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.copy,
                                        color: AppColors.textOnPrimary.withOpacity(0.8),
                                        size: 18,
                                      ),
                                      tooltip: 'Copier',
                                      onPressed: () {
                                        if (user['initial_password'] != null) {
                                          Clipboard.setData(
                                            ClipboardData(
                                              text: user['initial_password'],
                                            ),
                                          );
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Mot de passe copié!',
                                              ),
                                              duration: Duration(seconds: 1),
                                            ),
                                          );
                                        }
                                      },
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Contact Info Column
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (user['email'] != null)
                            _ContactInfo(
                              icon: Icons.email,
                              label: user['email'],
                            ),
                          if (user['phone'] != null) ...[
                            const SizedBox(height: 8),
                            _ContactInfo(
                              icon: Icons.phone,
                              label: user['phone'],
                            ),
                          ],
                          if (user['address'] != null) ...[
                            const SizedBox(height: 8),
                            _ContactInfo(
                              icon: Icons.location_on,
                              label: user['address'],
                            ),
                          ],
                          const SizedBox(height: 16),
                          if (data.enrolledSince != null)
                            Text(
                              'Inscrit depuis ${DateFormat('MMM yyyy').format(data.enrolledSince!)}',
                              style: TextStyle(
                                color: AppColors.textOnPrimary.withOpacity(0.7),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
               ],
             ),
     );
  }

  Widget _buildInitialsAvatar(Map<String, dynamic> user) {
    final name = user['full_name'] ?? 'A';
    final initials = name
        .split(' ')
        .map((s) => s.isNotEmpty ? s[0] : '')
        .take(2)
        .join()
        .toUpperCase();
    return Container(
      color: const Color(0xFF8B5CF6),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: AppColors.textOnPrimary,
            fontSize: 40,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStats(BuildContext context, StudentProfileData data) {
    // 1. Absences color: 0 -> green (#10B981), 1-2 -> amber (#F59E0B), >2 -> red (#EF4444)
    final totalAbs = data.totalAbsences;
    final absColor = totalAbs == 0
        ? const Color(0xFF10B981)
        : (totalAbs <= 2 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));
    final absIcon = totalAbs == 0 ? Icons.event_available_outlined : Icons.event_busy_outlined;

    // 2. Payé color: if paid > 0 -> green (#10B981); if paid == 0 && due > 0 -> red (#EF4444); else slate (#64748B)
    final totalPaid = data.totalPaid;
    final totalDue = data.totalDue;
    final payColor = (totalPaid > 0)
        ? const Color(0xFF10B981)
        : (totalDue > 0 ? const Color(0xFFEF4444) : const Color(0xFF64748B));

    // 3. En attente (Debt): if due == 0 -> green (#10B981) (0 debt is great!); if due > 0 -> red (#EF4444) (unpaid debt!)
    final dueColor = totalDue == 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final dueIcon = totalDue == 0 ? Icons.check_circle_outline : Icons.schedule_outlined;
    final dueLabel = totalDue == 0 ? 'À jour (0 dû)' : 'En attente';

    // 4. Moyenne color: >= 10.0 -> green (#10B981); 8.0-9.9 -> amber (#F59E0B); < 8.0 -> red (#EF4444); N/A -> slate (#64748B)
    double? avgGrade;
    final scored = data.grades.where((g) => g['grade_value'] != null).toList();
    if (scored.isNotEmpty) {
      final sum = scored.map((g) => (g['grade_value'] as num).toDouble()).reduce((a, b) => a + b);
      avgGrade = sum / scored.length;
    }
    final gradeColor = avgGrade == null
        ? const Color(0xFF64748B)
        : (avgGrade >= 10.0
            ? const Color(0xFF10B981)
            : (avgGrade >= 8.0 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444)));
    final gradeValue = avgGrade != null ? '${avgGrade.toStringAsFixed(1)} / 20' : 'N/A';

    // 5. Suggestions color: if pending -> amber (#F59E0B); if resolved -> green (#10B981); if 0 -> slate (#64748B)
    final bool hasPending = data.suggestions.any((s) => s['status'] == 'pending');
    final bool hasResolved = data.suggestions.isNotEmpty && !hasPending;
    final suggColor = hasPending
        ? const Color(0xFFF59E0B)
        : (hasResolved ? const Color(0xFF10B981) : const Color(0xFF64748B));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _QuickStatCard(
            icon: Icons.message_outlined,
            label: hasPending ? 'Suggestions (attente)' : 'Suggestions',
            value: '${data.suggestions.length}',
            color: suggColor,
          ),
          const SizedBox(width: 16),
          _QuickStatCard(
            icon: absIcon,
            label: totalAbs == 0 ? 'Absences (parfait)' : 'Absences',
            value: '$totalAbs',
            color: absColor,
          ),
          const SizedBox(width: 16),
          _QuickStatCard(
            icon: Icons.check_circle_outline,
            label: 'Total Payé',
            value: '${totalPaid.toStringAsFixed(0)} TND',
            color: payColor,
          ),
          const SizedBox(width: 16),
          _QuickStatCard(
            icon: dueIcon,
            label: dueLabel,
            value: '${totalDue.toStringAsFixed(0)} TND',
            color: dueColor,
          ),
          const SizedBox(width: 16),
          _QuickStatCard(
            icon: Icons.grade_outlined,
            label: avgGrade != null ? (avgGrade >= 10.0 ? 'Moyenne (admis)' : 'Moyenne (alerte)') : 'Moyenne',
            value: gradeValue,
            color: gradeColor,
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceCard(BuildContext context, StudentProfileData data) {
    // Build attendance graph for current month
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;

    // Create daily attendance data
    Map<int, double> dailyAbsences = {};
    for (final absence in data.monthlyAbsences) {
      if (absence['date'] != null) {
        final date = DateTime.tryParse(absence['date']?.toString() ?? '');
        if (date == null) continue;
        final day = date.day;
        dailyAbsences[day] =
            (dailyAbsences[day] ?? 0) +
            ((absence['hours_absent'] as num?)?.toDouble() ?? 0);
      }
    }

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.event_busy, color: Color(0xFFEF4444)),
              ),
              const SizedBox(width: 12),
              const Text(
                'Présence ce mois',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  // TODO: Navigate to full attendance
                },
                child: const Text('Voir tout'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Simple bar chart
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(daysInMonth, (index) {
                final day = index + 1;
                final hours = dailyAbsences[day] ?? 0;
                final hasAbsence = hours > 0;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: hasAbsence ? (hours * 10).clamp(10, 80) : 4,
                          decoration: BoxDecoration(
                            color: hasAbsence
                                ? const Color(0xFFEF4444)
                                : AppColors.slate200,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (day % 5 == 0 || day == 1)
                          Text(
                            '$day',
                            style: TextStyle(
                              fontSize: 8,
                              color: AppColors.slate500,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('MMMM yyyy', 'fr').format(now),
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: data.totalAbsences > 5
                      ? AppColors.errorSoft
                      : AppColors.successSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${data.totalAbsences} absences totales',
                  style: TextStyle(
                    color: data.totalAbsences > 5 ? AppColors.error : AppColors.success,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentCard(BuildContext context, StudentProfileData data) {
    Color accuracyColor;
    String accuracyLabel;
    IconData accuracyIcon;

    if (data.paymentAccuracy >= 90) {
      accuracyColor = const Color(0xFF10B981);
      accuracyLabel = 'Excellent';
      accuracyIcon = Icons.verified;
    } else if (data.paymentAccuracy >= 70) {
      accuracyColor = const Color(0xFF3B82F6);
      accuracyLabel = 'Bon';
      accuracyIcon = Icons.thumb_up;
    } else if (data.paymentAccuracy >= 50) {
      accuracyColor = const Color(0xFFF59E0B);
      accuracyLabel = 'Moyen';
      accuracyIcon = Icons.warning;
    } else {
      accuracyColor = const Color(0xFFEF4444);
      accuracyLabel = 'À améliorer';
      accuracyIcon = Icons.error;
    }

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.payment, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              const Text(
                'Paiements',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  // TODO: Navigate to payments
                },
                child: const Text('Voir tout'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Payment accuracy badge
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: accuracyColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accuracyColor.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Icon(accuracyIcon, color: accuracyColor, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    '${data.paymentAccuracy.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: accuracyColor,
                    ),
                  ),
                  Text(
                    'Ponctualité paiement',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accuracyColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      accuracyLabel,
                      style: const TextStyle(
                        color: AppColors.textOnPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // Payment stats
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'À temps',
                  value: '${data.onTimePayments}',
                  color: AppColors.success,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'En retard',
                  value: '${data.latePayments}',
                  color: AppColors.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAcademicCard(BuildContext context, StudentProfileData data) {
    double average = 0;
    if (data.grades.isNotEmpty) {
      final values = data.grades
          .map((g) => (g['grade_value'] as num?)?.toDouble() ?? 0)
          .toList();
      average = values.reduce((a, b) => a + b) / values.length;
    }

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.grade, color: Color(0xFF8B5CF6)),
              ),
              const SizedBox(width: 12),
              const Text(
                'Résultats',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  // TODO: Navigate to grades
                },
                child: const Text('Voir tout'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Average display
          Center(
            child: Column(
              children: [
                Text(
                  average > 0 ? average.toStringAsFixed(2) : 'N/A',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: _getGradeColor(average),
                  ),
                ),
                Text(
                  '/20',
                  style: TextStyle(fontSize: 18, color: AppColors.slate500),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getGradeColor(average).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _getGradeLabel(average),
                    style: TextStyle(
                      color: _getGradeColor(average),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Recent grades
          if (data.grades.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: data.grades.take(3).map((g) {
                final value = (g['grade_value'] as num?)?.toDouble() ?? 0;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getGradeColor(value).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    value.toStringAsFixed(1),
                    style: TextStyle(
                      color: _getGradeColor(value),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickAccessSection(
    BuildContext context,
    StudentProfileData data,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Accès rapide',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _QuickAccessButton(
                icon: Icons.grade,
                label: 'Résultats',
                color: const Color(0xFF8B5CF6),
                onTap: () {
                  // TODO: Navigate to results page for this student
                },
              ),
              _QuickAccessButton(
                icon: Icons.payment,
                label: 'Paiements',
                color: const Color(0xFF10B981),
                onTap: () {
                  // TODO: Navigate to payments page
                },
              ),
              _QuickAccessButton(
                icon: Icons.message,
                label: 'Messages',
                color: const Color(0xFF3B82F6),
                onTap: () {
                  // TODO: Navigate to messages for this class
                },
              ),
              _QuickAccessButton(
                icon: Icons.lightbulb,
                label: 'Suggestions',
                color: const Color(0xFFF59E0B),
                onTap: () {
                  // TODO: Navigate to suggestions
                },
              ),
              _QuickAccessButton(
                icon: Icons.calendar_month,
                label: 'Emploi du temps',
                color: const Color(0xFFEC4899),
                onTap: () {
                  // TODO: Navigate to timetable
                },
              ),
              _QuickAccessButton(
                icon: Icons.event_busy,
                label: 'Absences',
                color: const Color(0xFFEF4444),
                onTap: () {
                  // TODO: Navigate to absences
                },
              ),
              _QuickAccessButton(
                icon: Icons.folder,
                label: 'Documents',
                color: const Color(0xFF06B6D4),
                onTap: () {
                  // TODO: Navigate to documents
                },
              ),
              _QuickAccessButton(
                icon: Icons.history,
                label: 'Historique',
                color: const Color(0xFF64748B),
                onTap: () {
                  // TODO: Navigate to activity history
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsCard(BuildContext context, StudentProfileData data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: AppColors.shadow, blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.lightbulb,
                  color: Color(0xFFF59E0B),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Suggestions envoyées',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.slate100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${data.suggestions.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          if (data.suggestions.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Aucune suggestion',
                  style: TextStyle(color: AppColors.slate500),
                ),
              ),
            )
          else
            ...data.suggestions
                .take(5)
                .map((s) => _SuggestionItem(suggestion: s)),
        ],
      ),
    );
  }

  Widget _buildMessagesCard(BuildContext context, StudentProfileData data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: AppColors.shadow, blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.message,
                  color: Color(0xFF3B82F6),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Messages de classe',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          if (data.messages.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Aucun message',
                  style: TextStyle(color: AppColors.slate500),
                ),
              ),
            )
          else
            ...data.messages
                .take(3)
                .map(
                  (m) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m['title'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          m['published_at'] != null
                              ? () {
                                  final parsed = DateTime.tryParse(
                                    m['published_at']?.toString() ?? '',
                                  );
                                  if (parsed == null) return '';
                                  return DateFormat('d MMM yyyy', 'fr_FR').format(parsed);
                                }()
                              : '',
                          style: TextStyle(
                            color: AppColors.slate500,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Color _getGradeColor(double grade) {
    if (grade >= 16) return const Color(0xFF10B981);
    if (grade >= 14) return const Color(0xFF3B82F6);
    if (grade >= 12) return const Color(0xFFF59E0B);
    if (grade >= 10) return const Color(0xFFEF4444);
    return const Color(0xFF6B7280);
  }

  String _getGradeLabel(double grade) {
    if (grade >= 16) return 'Excellent';
    if (grade >= 14) return 'Très bien';
    if (grade >= 12) return 'Bien';
    if (grade >= 10) return 'Passable';
    if (grade > 0) return 'Insuffisant';
    return 'Non noté';
  }
}

// Helper Widgets

class _InfoChipLight extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChipLight({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.textOnPrimary.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textOnPrimary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: AppColors.textOnPrimary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ContactInfo extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ContactInfo({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textOnPrimary.withOpacity(0.8)),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: AppColors.textOnPrimary.withOpacity(0.9), fontSize: 12),
        ),
      ],
    );
  }
}

class _QuickStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _QuickStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: AppColors.shadow, blurRadius: 10),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;

  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: AppColors.shadow, blurRadius: 15),
        ],
      ),
      child: child,
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      ],
    );
  }
}

class _QuickAccessButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAccessButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.slate200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionItem extends StatelessWidget {
  final Map<String, dynamic> suggestion;

  const _SuggestionItem({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final status = suggestion['status'] as String? ?? 'sent';
    final createdAt = suggestion['created_at'] != null
        ? DateTime.tryParse(suggestion['created_at'])
        : null;

    Color statusColor;
    String statusLabel;

    switch (status) {
      case 'replied':
        statusColor = AppColors.success;
        statusLabel = 'Répondu';
        break;
      case 'read':
        statusColor = AppColors.primary;
        statusLabel = 'Lu';
        break;
      default:
        statusColor = AppColors.warning;
        statusLabel = 'Envoyé';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.slate100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.message_outlined,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion['subject'] ?? 'N/A',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (createdAt != null)
                  Text(
                    DateFormat("d MMM yyyy 'à' HH:mm", 'fr_FR').format(createdAt),
                    style: TextStyle(color: AppColors.slate500, fontSize: 11),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
