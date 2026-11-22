import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../providers/absences_provider.dart';
import '../../widgets/admin_sidebar.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/user_avatar.dart';

bool _dateFormattingInitialized = false;

void _ensureDateFormatting() {
  if (!_dateFormattingInitialized) {
    initializeDateFormatting('fr_FR', null);
    _dateFormattingInitialized = true;
  }
}

// ==================== STUDENT ABSENCES SCREEN ====================
class StudentAbsencesScreen extends ConsumerStatefulWidget {
  final String studentId;

  const StudentAbsencesScreen({super.key, required this.studentId});

  @override
  ConsumerState<StudentAbsencesScreen> createState() =>
      _StudentAbsencesScreenState();
}

class _StudentAbsencesScreenState extends ConsumerState<StudentAbsencesScreen> {
  bool _isActionInProgress = false;
  String _searchQuery = '';
  String _sortField = 'date'; // 'date', 'matiere', 'status'
  bool _sortAscending = false;
  int _selectedMonthOffset = 0;
  final _searchController = TextEditingController();
  final Set<String> _selectedAbsences = {};
  int _page = 0;
  int _perPage = 10;

  Widget _buildHeaderIconButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
    bool isActive = false,
  }) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
      color: isActive ? const Color(0xFF655DD5) : AppColors.textTertiary,
      style: IconButton.styleFrom(
        backgroundColor: isActive ? const Color(0xFFF5F3FF) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isActive ? const Color(0xFF655DD5).withOpacity(0.2) : Colors.transparent,
          ),
        ),
      ),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }

  @override
  void initState() {
    super.initState();
    _ensureDateFormatting();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(studentAbsencesProvider(widget.studentId));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: '/absences'),
          Expanded(
            child: _isActionInProgress
                ? const StudentAbsencesSkeletonLoader()
                : asyncData.when(
                    loading: () => const StudentAbsencesSkeletonLoader(),
              error: (e, _) => Center(
                child: Container(
                  padding: const EdgeInsets.all(32),
                  margin: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.error.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 48,
                        color: AppColors.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        UserFriendlyError.format(
                          e,
                          fallback: 'Unable to load student absences right now. Please try again.',
                        ),
                        style: TextStyle(color: AppColors.error),
                      ),
                    ],
                  ),
                ),
              ),
              data: (data) => _buildContent(context, data),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== MAIN CONTENT ====================
  Widget _buildContent(BuildContext context, StudentAbsencesData data) {
    final user = data.user;
    final fullName = user['full_name'] as String? ?? 'Étudiant';
    final enrollments = (user['enrollments'] as List?) ?? const [];
    final className = enrollments.isNotEmpty
        ? (enrollments.first as Map<String, dynamic>?)?['classes']?['name'] as String?
        : null;

    final filteredAbsences = data.absences.where((a) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return a.studentName.toLowerCase().contains(q) ||
          (a.subjectName?.toLowerCase().contains(q) ?? false) ||
          (a.reason?.toLowerCase().contains(q) ?? false) ||
          DateFormat('d MMM yyyy', 'fr_FR').format(a.date).toLowerCase().contains(q) ||
          DateFormat('dd/MM/yyyy').format(a.date).contains(q);
    }).toList();

    filteredAbsences.sort((a, b) {
      int comparison = 0;
      if (_sortField == 'date') {
        comparison = a.date.compareTo(b.date);
      } else if (_sortField == 'matiere') {
        comparison = (a.subjectName ?? '').compareTo(b.subjectName ?? '');
      } else if (_sortField == 'status') {
        final aJust = a.justified ? 1 : 0;
        final bJust = b.justified ? 1 : 0;
        comparison = aJust.compareTo(bJust);
      }
      int result = _sortAscending ? comparison : -comparison;
      if (result != 0) return result;
      final cCmp = b.createdAt.compareTo(a.createdAt);
      if (cCmp != 0) return cCmp;
      return a.id.compareTo(b.id);
    });

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(fullName, className),
              const SizedBox(height: 24),
              SizedBox(
                height: 440,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildPresenceCalendar(data)),
                    const SizedBox(width: 24),
                    Expanded(child: _buildAbsenceStatsCard(data)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildAbsenceListSection(filteredAbsences),
            ],
          ),
        ),
        if (_selectedAbsences.isNotEmpty)
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(child: _buildFloatingBulkBar()),
          ),
      ],
    );
  }

  // ==================== HEADER ====================
  Widget _buildHeader(String fullName, String? className) {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.slate100)),
      ),
      child: Row(
        children: [
          _iconButton(
            icon: Icons.arrow_back_rounded,
            onTap: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/absences');
              }
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Historique d\'absences',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  '$fullName${className != null ? ' • $className' : ''}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
const SizedBox.shrink(),
        ],
      ),
    );
  }

  // ==================== STUDENT INFO CARD ====================
  Widget _buildStudentInfoCard(
    BuildContext context,
    StudentAbsencesData data,
  ) {
    final user = data.user;
    final fullName = user['full_name'] as String? ?? 'Étudiant';
    final photoUrl = user['photo_url'] as String?;
    final studentCode = user['student_code'] as String?;
    final email = user['email'] as String?;
    final phone = user['phone'] as String?;
    final gender = user['gender'] as String?;
    final nationality = user['nationality'] as String?;

    int? age;
    final dob = DateTime.tryParse(user['date_of_birth']?.toString() ?? '');
    if (dob != null) {
      final now = DateTime.now();
      age = now.year - dob.year;
      if (now.month < dob.month ||
          (now.month == dob.month && now.day < dob.day)) {
        age--;
      }
    }

    String? className;
    String? niveauName;
    final enrollments = (user['enrollments'] as List?) ?? const [];
    if (enrollments.isNotEmpty) {
      final first = enrollments.first as Map<String, dynamic>?;
      final classes = first?['classes'] as Map<String, dynamic>?;
      className = classes?['name'] as String?;
      final niveaux = classes?['niveaux'] as Map<String, dynamic>?;
      niveauName = niveaux?['name'] as String?;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppShadows.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          UserAvatar(
            name: fullName,
            photoUrl: photoUrl,
            radius: 40,
            gender: gender == 'F' ? 'F' : null,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fullName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.slate800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (studentCode != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    studentCode,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.slate400,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (niveauName != null)
                      _infoChip(Icons.stairs_rounded, 'Niveau: $niveauName'),
                    if (className != null)
                      _infoChip(Icons.school_rounded, className),
                    if (gender != null)
                      _infoChip(
                        gender == 'M' ? Icons.male_rounded : Icons.female_rounded,
                        gender == 'M' ? 'Masculin' : 'Féminin',
                      ),
                    if (age != null)
                      _infoChip(Icons.cake_rounded, '$age ans'),
                    if (nationality != null)
                      _infoChip(Icons.flag_rounded, nationality),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (email != null)
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: email));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('$email copié!'),
                        duration: const Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.email_outlined,
                        size: 12,
                        color: AppColors.slate500,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          email,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.slate500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              if (phone != null) ...[
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: phone));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('$phone copié!'),
                        duration: const Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.phone_outlined,
                        size: 12,
                        color: AppColors.slate500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        phone,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.slate500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.slate100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.slate600),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.slate700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== PRESENCE CALENDAR ====================
  Widget _buildPresenceCalendar(StudentAbsencesData data) {
    final now = DateTime.now();
    final targetMonth = now.month + _selectedMonthOffset;
    final targetDate = DateTime(now.year, targetMonth, 1);
    const frenchMonths = [
      'Janvier',
      'Février',
      'Mars',
      'Avril',
      'Mai',
      'Juin',
      'Juillet',
      'Août',
      'Septembre',
      'Octobre',
      'Novembre',
      'Décembre',
    ];
    final monthLabel =
        '${frenchMonths[targetDate.month - 1]} ${targetDate.year}';

    return Container(
      decoration: _cardDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Calendrier des absences',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.slate800,
                ),
              ),
              const Spacer(),
              _miniIconBtn(
                icon: Icons.chevron_left_rounded,
                onTap: () => setState(() => _selectedMonthOffset--),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 120),
                child: Text(
                  monthLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.slate500,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _miniIconBtn(
                icon: Icons.chevron_right_rounded,
                onTap: _selectedMonthOffset < 0
                    ? () => setState(() => _selectedMonthOffset++)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: _buildCalendarGrid(data, targetDate),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(AppColors.error, 'Absent'),
              const SizedBox(width: 14),
              _legendDot(AppColors.warning, 'Justifié'),
              const SizedBox(width: 14),
              _legendDot(AppColors.success, 'Présent'),
              const SizedBox(width: 14),
              _legendDot(AppColors.slate200, 'Pas de cours'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid(StudentAbsencesData data, DateTime targetDate) {
    final year = targetDate.year;
    final month = targetDate.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday; // 1=Mon

    final Map<int, String> absenceMap = {};
    for (final abs in data.absences) {
      final d = abs.date;
      if (d.year == year && d.month == month) {
        absenceMap[d.day] = abs.justified ? 'justified' : 'absent';
      }
    }

    const dayLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: dayLabels
              .map(
                (d) => Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: const TextStyle(
                        color: AppColors.slate400,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          childAspectRatio: 1.32,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 5,
          crossAxisSpacing: 5,
          children: [
            for (int i = 1; i < firstWeekday; i++) const SizedBox(),
            for (int day = 1; day <= daysInMonth; day++)
              _buildDayCell(day, absenceMap[day], DateTime(year, month, day)),
          ],
        ),
      ],
    );
  }

  Widget _buildDayCell(int day, String? absenceStatus, DateTime date) {
    final isWeekend = date.weekday == 6 || date.weekday == 7;
    final isToday =
        date.year == DateTime.now().year &&
            date.month == DateTime.now().month &&
            date.day == DateTime.now().day;

    Color bgColor;
    Color textColor;

    if (absenceStatus == 'absent') {
      bgColor = AppColors.error;
      textColor = Colors.white;
    } else if (absenceStatus == 'justified' ||
        absenceStatus == 'justifié') {
      bgColor = AppColors.warning;
      textColor = Colors.white;
    } else if (absenceStatus != null) {
      bgColor = AppColors.success;
      textColor = Colors.white;
    } else if (isWeekend) {
      bgColor = const Color(0xFFF1F5F9);
      textColor = const Color(0xFF94A3B8);
    } else if (date.isAfter(DateTime.now())) {
      bgColor = const Color(0xFFF8FAFC);
      textColor = const Color(0xFFCBD5E1);
    } else {
      bgColor = AppColors.success.withValues(alpha: 0.12);
      textColor = const Color(0xFF15803D);
    }

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: isToday
            ? Border.all(color: AppColors.primary, width: 1.5)
            : null,
      ),
      child: Center(
        child: Text(
          '$day',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(color: AppColors.slate500, fontSize: 11),
        ),
      ],
    );
  }

  // ==================== ABSENCE STATS CARD (ICON-BASED) ====================
  Widget _buildAbsenceStatsCard(StudentAbsencesData data) {
    final total = data.totalAbsences;
    final justified = data.justifiedCount;
    final unjustified = data.unjustifiedCount;
    final hours = data.totalHours.toStringAsFixed(1);
    final justifiedPct = total > 0 ? (justified / total) * 100 : 0.0;

    Color justifiedColor;
    if (justifiedPct >= 75) {
      justifiedColor = AppColors.success;
    } else if (justifiedPct >= 50) {
      justifiedColor = AppColors.warning;
    } else {
      justifiedColor = AppColors.error;
    }

    return Container(
      decoration: _cardDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Statistiques',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.slate800,
                ),
              ),
              const Spacer(),
              Text(
                '${data.totalHours.toStringAsFixed(0)}h total',
                style: const TextStyle(
                  color: AppColors.slate500,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(child: _buildDonutChart(justifiedPct, justifiedColor)),
          const SizedBox(height: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _statsIconItem(
                  'Total absences',
                  '$total',
                  Icons.event_busy_outlined,
                  AppColors.primary,
                  AppColors.primarySoft,
                  labelIcon: Icons.list_alt_rounded,
                ),
                const SizedBox(height: 6),
                _statsIconItem(
                  'Justifiées',
                  '$justified',
                  Icons.verified_outlined,
                  AppColors.primary,
                  AppColors.primarySoft,
                  labelIcon: Icons.check_circle_outline,
                ),
                const SizedBox(height: 6),
                _statsIconItem(
                  'Non justifiées',
                  '$unjustified',
                  Icons.cancel_outlined,
                  AppColors.primary,
                  AppColors.primarySoft,
                  labelIcon: Icons.highlight_off_rounded,
                ),
                const SizedBox(height: 6),
                _statsIconItem(
                  'Heures manquées',
                  '${hours}h',
                  Icons.timer_outlined,
                  AppColors.primary,
                  AppColors.primarySoft,
                  labelIcon: Icons.schedule_rounded,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDonutChart(double percentage, Color color) {
    return SizedBox(
      width: 130,
      height: 130,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 130,
            height: 130,
            child: CircularProgressIndicator(
              value: percentage / 100,
              strokeWidth: 10,
              backgroundColor: AppColors.slate100,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${percentage.toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.slate800,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Justifiées',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.slate500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statsIconItem(
    String label,
    String value,
    IconData icon,
    Color color,
    Color bgColor, {
    IconData? labelIcon,
  }) {
    final displayIcon = labelIcon ?? icon;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(displayIcon, size: 14, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.slate500,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.slate800,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== ABSENCE LIST SECTION ====================
  Widget _buildAbsenceListSection(List<AbsenceModel> absences) {
    final sorted = [...absences]..sort((a, b) {
      final cmp = b.date.compareTo(a.date);
      if (cmp != 0) return cmp;
      final cCmp = b.createdAt.compareTo(a.createdAt);
      if (cCmp != 0) return cCmp;
      return a.id.compareTo(b.id);
    });
    final totalPages = _perPage > 0 ? (sorted.length / _perPage).ceil() : 1;
    final clampedPage =
        _page.clamp(0, totalPages == 0 ? 0 : totalPages - 1);
    final start = clampedPage * _perPage;
    final end = (start + _perPage).clamp(0, sorted.length);
    final pageAbsences = sorted.sublist(start, end);
    final allSelected = pageAbsences.isNotEmpty &&
        pageAbsences.every((a) => _selectedAbsences.contains(a.id));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFE5E7EB)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.history_rounded,
                    color: AppColors.primary,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Historique détaillé',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${sorted.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() {
                      _searchQuery = v;
                      _page = 0;
                      _selectedAbsences.clear();
                    }),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Rechercher (matière, motif...)',
                      hintStyle: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 18,
                        color: AppColors.textTertiary,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _page = 0;
                                });
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AppColors.slate50,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 0,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.slate200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.slate200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: AppColors.primary.withOpacity(0.5),
                          width: 1.5,
                        ),
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                PopupMenuButton<String>(
                  tooltip: 'Trier',
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 8,
                  offset: const Offset(0, 40),
                  onSelected: (value) {
                    setState(() {
                      if (_sortField == value) {
                        _sortAscending = !_sortAscending;
                      } else {
                        _sortField = value;
                        _sortAscending = true;
                      }
                      _page = 0;
                    });
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'date',
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 16,
                            color: _sortField == 'date' ? const Color(0xFF655DD5) : AppColors.textTertiary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Date ${_sortField == 'date' ? (_sortAscending ? '↑' : '↓') : ''}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _sortField == 'date' ? FontWeight.bold : FontWeight.normal,
                              color: _sortField == 'date' ? const Color(0xFF655DD5) : AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'matiere',
                      child: Row(
                        children: [
                          Icon(
                            Icons.book_rounded,
                            size: 16,
                            color: _sortField == 'matiere' ? const Color(0xFF655DD5) : AppColors.textTertiary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Matière ${_sortField == 'matiere' ? (_sortAscending ? '↑' : '↓') : ''}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _sortField == 'matiere' ? FontWeight.bold : FontWeight.normal,
                              color: _sortField == 'matiere' ? const Color(0xFF655DD5) : AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'status',
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 16,
                            color: _sortField == 'status' ? const Color(0xFF655DD5) : AppColors.textTertiary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Statut ${_sortField == 'status' ? (_sortAscending ? '↑' : '↓') : ''}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _sortField == 'status' ? FontWeight.bold : FontWeight.normal,
                              color: _sortField == 'status' ? const Color(0xFF655DD5) : AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  child: _buildHeaderIconButton(
                    icon: Icons.filter_list_rounded,
                    tooltip: 'Trier',
                    isActive: true,
                  ),
                ),
              ],
            ),
          ),

          // ── Bulk action bar (now floating - see _buildFloatingBulkBar) ──

          // ── Column headers ──
          if (sorted.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.border.withOpacity(0.3),
                  ),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Checkbox(
                      value: allSelected,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selectedAbsences.addAll(
                              pageAbsences.map((a) => a.id),
                            );
                          } else {
                            for (final a in pageAbsences) {
                              _selectedAbsences.remove(a.id);
                            }
                          }
                        });
                      },
                      activeColor: AppColors.primary,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: _headerLabel('DATE'),
                  ),
                  Expanded(
                    flex: 3,
                    child: _headerLabel('MATIÈRE'),
                  ),
                  Expanded(
                    flex: 3,
                    child: _headerLabel('ENSEIGNANT'),
                  ),
                  SizedBox(
                    width: 130,
                    child: _headerLabelCenter('STATUT'),
                  ),
                  SizedBox(
                    width: 60,
                    child: _headerLabelCenter('ACTIONS'),
                  ),
                ],
              ),
            ),

          // ── Rows / Empty state ──
          if (sorted.isEmpty)
            _buildEmptyAbsenceState()
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < pageAbsences.length; i++) ...[
                  _buildAbsenceRow(pageAbsences[i]),
                  if (i < pageAbsences.length - 1)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.border.withOpacity(0.3),
                    ),
                ],
              ],
            ),

          // ── Pagination footer ──
          if (sorted.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFB),
                border: Border(
                  top: BorderSide(
                    color: AppColors.border.withOpacity(0.3),
                  ),
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    'Afficher par ',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _perPage,
                        isDense: true,
                        borderRadius: BorderRadius.circular(10),
                        dropdownColor: Colors.white,
                        elevation: 4,
                        menuMaxHeight: 200,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 14,
                          color: AppColors.textTertiary,
                        ),
                        items: [10, 20, 50]
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(
                                  '$v',
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
                              _perPage = v;
                              _page = 0;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Page ${clampedPage + 1} sur ${totalPages == 0 ? 1 : totalPages}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: clampedPage > 0
                              ? () => setState(() => _page--)
                              : null,
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(5),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.chevron_left,
                              size: 18,
                              color: clampedPage > 0
                                  ? AppColors.textSecondary
                                  : AppColors.textTertiary,
                            ),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 24,
                          color: AppColors.border,
                        ),
                        InkWell(
                          onTap: clampedPage < totalPages - 1
                              ? () => setState(() => _page++)
                              : null,
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(5),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: clampedPage < totalPages - 1
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
            ),
        ],
      ),
    );
  }

  Widget _headerLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textTertiary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _headerLabelCenter(String text) {
    return Center(
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textTertiary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildEmptyAbsenceState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFFFDF2F8),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.event_busy_rounded,
              size: 40,
              color: Color(0xFFEC4899),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Aucune absence enregistrée',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.slate700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _searchQuery.isNotEmpty
                ? 'Aucun résultat pour "$_searchQuery"'
                : 'Cet étudiant n\'a aucune absence dans l\'historique.',
            style: const TextStyle(fontSize: 13, color: AppColors.slate400),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ==================== ABSENCE ROW (LISTE-DES-ETUDIANTS STYLE) ====================
  Widget _buildAbsenceRow(AbsenceModel absence) {
    final isSelected = _selectedAbsences.contains(absence.id);
    final dateStr = DateFormat('d MMM yyyy', 'fr_FR').format(absence.date);
    final isJustified = absence.justified;

    return InkWell(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedAbsences.remove(absence.id);
          } else {
            _selectedAbsences.add(absence.id);
          }
        });
      },
      child: Container(
        color: isSelected ? AppColors.primary.withOpacity(0.04) : null,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Checkbox(
                value: isSelected,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selectedAbsences.add(absence.id);
                    } else {
                      _selectedAbsences.remove(absence.id);
                    }
                  });
                },
                activeColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            // ── DATE COLUMN ──
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.slate100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.calendar_today_rounded,
                      color: AppColors.slate600,
                      size: 15,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      dateStr,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // ── MATIÈRE COLUMN ──
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.menu_book_rounded,
                      color: AppColors.primary,
                      size: 15,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          absence.subjectName ?? 'Matière non spécifiée',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (absence.hoursAbsent > 0) ...[
                          const SizedBox(height: 1),
                          Text(
                            '${absence.hoursAbsent}h d\'absence',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── ENSEIGNANT COLUMN ──
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  UserAvatar(
                    name: absence.teacherName ?? '?',
                    photoUrl: absence.teacherPhotoUrl,
                    radius: 13,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      absence.teacherName ?? 'Non assigné',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.slate700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 130,
              child: Center(
                child: _buildStatusBadge(isJustified, absence.hoursAbsent),
              ),
            ),
            SizedBox(
              width: 60,
              child: Center(
                child: PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_horiz,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
                  tooltip: 'Actions',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 8,
                  offset: const Offset(-160, 40),
                  onSelected: (value) async {
                    if (value == 'toggle_justified') {
                      await _toggleJustified(absence);
                    } else if (value == 'delete') {
                      await _deleteAbsence(absence);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'toggle_justified',
                      height: 40,
                      child: Row(
                        children: [
                          Icon(
                            isJustified
                                ? Icons.close_outlined
                                : Icons.check_circle_outlined,
                            size: 18,
                            color: const Color(0xFF655DD5),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            isJustified
                                ? 'Marquer non justifiée'
                                : 'Marquer justifiée',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      height: 40,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: AppColors.error,
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Supprimer',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(bool isJustified, double hours) {
    final Color bg;
    final Color fg;
    final IconData icon;
    final String label;

    if (isJustified) {
      bg = const Color(0xFFECFDF5);
      fg = const Color(0xFF059669);
      icon = Icons.check_circle_rounded;
      label = 'Justifiée';
    } else {
      bg = const Color(0xFFFEF2F2);
      fg = const Color(0xFFDC2626);
      icon = Icons.cancel_rounded;
      label = 'Non justifiée';
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== ACTIONS ====================
  Future<void> _toggleJustified(AbsenceModel absence) async {
    setState(() => _isActionInProgress = true);
    try {
      await SupabaseConfig.adminClient
          .from('absence_records')
          .update({'justified': !absence.justified})
          .eq('id', absence.id);
      ref.invalidate(studentAbsencesProvider(widget.studentId));
      await ref.read(studentAbsencesProvider(widget.studentId).future);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              absence.justified
                  ? 'Absence marquée non justifiée'
                  : 'Absence marquée justifiée',
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFriendlyError.format(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _deleteAbsence(AbsenceModel absence) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: AppColors.errorSoft, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
              ),
              const SizedBox(width: 12),
              const Text('Supprimer l\'absence ?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Voulez-vous vraiment supprimer l\'absence de "${absence.studentName}" ?'),
              const SizedBox(height: 6),
              const Text(
                'Cette action est irréversible.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Supprimer', style: TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _isActionInProgress = true);
    try {
      await SupabaseConfig.adminClient
          .from('absence_records')
          .delete()
          .eq('id', absence.id);
      ref.invalidate(studentAbsencesProvider(widget.studentId));
      await ref.read(studentAbsencesProvider(widget.studentId).future);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Absence supprimée'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFriendlyError.format(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  // ==================== BULK ACTIONS ====================
  Future<void> _bulkToggleJustified(bool justified) async {
    if (_selectedAbsences.isEmpty) return;
    final ids = _selectedAbsences.toList();
    setState(() => _isActionInProgress = true);
    try {
      await SupabaseConfig.adminClient
          .from('absence_records')
          .update({'justified': justified})
          .inFilter('id', ids);
      ref.invalidate(studentAbsencesProvider(widget.studentId));
      await ref.read(studentAbsencesProvider(widget.studentId).future);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              justified
                  ? '${ids.length} absence(s) marquée(s) justifiée(s)'
                  : '${ids.length} absence(s) marquée(s) non justifiée(s)',
            ),
            backgroundColor: justified ? AppColors.success : AppColors.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFriendlyError.format(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _bulkDelete() async {
    if (_selectedAbsences.isEmpty) return;
    final count = _selectedAbsences.length;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: AppColors.errorSoft, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
              ),
              const SizedBox(width: 12),
              Text('Supprimer $count absence${count > 1 ? 's' : ''} ?', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Voulez-vous vraiment supprimer $count absence(s) ?'),
              const SizedBox(height: 6),
              const Text(
                'Cette action est irréversible.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: Text('Supprimer $count', style: const TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    final ids = _selectedAbsences.toList();
    setState(() => _isActionInProgress = true);
    try {
      await SupabaseConfig.adminClient
          .from('absence_records')
          .delete()
          .inFilter('id', ids);
      ref.invalidate(studentAbsencesProvider(widget.studentId));
      await ref.read(studentAbsencesProvider(widget.studentId).future);
      if (mounted) {
        setState(() => _selectedAbsences.clear());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count absence(s) supprimée(s)'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFriendlyError.format(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  // ==================== FLOATING BULK BAR ====================
  Widget _buildFloatingBulkBar() {
    final count = _selectedAbsences.length;

    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(10),
      color: const Color(0xFF111827),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Count badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: Colors.white.withOpacity(0.15))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: const Color(0xFF655DD5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        '$count',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Sélectionnés',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white),
                  ),
                ],
              ),
            ),
            // Actions
            _buildSelectionAction(
              Icons.check_circle_outline_rounded,
              'Justifier',
              Colors.white70,
              () => _bulkToggleJustified(true),
            ),
            _buildSelectionAction(
              Icons.cancel_outlined,
              'Non justifier',
              Colors.white70,
              () => _bulkToggleJustified(false),
            ),
            _buildSelectionAction(
              Icons.delete_outline,
              'Supprimer',
              const Color(0xFFFCA5A5),
              _bulkDelete,
            ),
            // Close button
            Container(
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: Colors.white.withOpacity(0.15))),
              ),
              child: IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.white60),
                onPressed: () => setState(() => _selectedAbsences.clear()),
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
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
          ],
        ),
      ),
    );
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

  Widget _outlineButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 4,
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
                Icon(icon, size: 16, color: AppColors.slate500),
                const SizedBox(width: 8),
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
        decoration: BoxDecoration(
          color: AppColors.slate100,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 16,
          color: onTap != null ? AppColors.slate500 : AppColors.slate300,
        ),
      ),
    );
  }
}