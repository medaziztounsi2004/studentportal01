import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/arabic_typography.dart';
import '../../../core/theme/responsive.dart';
import '../../../data/models/timetable_model.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../data/services/offline_cache_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/student_context_provider.dart';
import '../../widgets/semester_navigator.dart';
import '../../widgets/bouncing_wrapper.dart';
import '../../widgets/emploi_skeleton.dart';
import '../../widgets/ios_bounce_zoom_transition.dart';
import '../../widgets/locked_semester_card.dart';
import '../../providers/nav_bar_provider.dart';

final emploiSemesterProvider = StateProvider<int>((ref) => 1);

// Timetable type selection provider: 'regular' vs 'exam'
final emploiTypeProvider = StateProvider<String>((ref) => 'regular');

// Loading state for emploi refresh
final emploiRefreshingProvider = StateProvider<bool>((ref) => false);

// Detect if currently in an exam period
final isExamPeriodProvider = FutureProvider<bool>((ref) async {
  if (ConnectivityService.instance.isOffline) return false;
  try {
    final contextAsync = await ref.watch(studentContextProvider.future).timeout(
      const Duration(seconds: 3),
      onTimeout: () => null,
    );
    if (contextAsync == null || contextAsync.schoolId.isEmpty) return false;

    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final examCheck = await Supabase.instance.client
        .rpc('get_active_exam_period', params: {
      'p_school_id': contextAsync.schoolId,
      'p_date': todayStr,
    }).timeout(const Duration(seconds: 3));
    if (examCheck != null) return true;

    // Fallback direct query on exam_periods table
    final directCheck = await Supabase.instance.client
        .from('exam_periods')
        .select('id')
        .eq('school_id', contextAsync.schoolId)
        .or('is_active.eq.true,and(start_date.lte.$todayStr,end_date.gte.$todayStr)')
        .maybeSingle()
        .timeout(const Duration(seconds: 3));

    return directCheck != null;
  } catch (_) {
    return false;
  }
});

String _parseTime(String time) {
  if (time.length >= 5) {
    return time.substring(0, 5);
  }
  if (time.length == 4) {
    return '0$time';
  }
  return time;
}

final Map<String, Color> _presetSubjectColors = {
  'ARABE': const Color(0xFFF59E0B), // Orange / Amber like Pic 2
  'AR': const Color(0xFFF59E0B),
  'MATH': const Color(0xFF10B981),  // Emerald Green like Pic 2
  'FRANCAIS': const Color(0xFFEC4899), // Pink like Pic 2
  'FR': const Color(0xFFEC4899),
  'ANGLAIS': const Color(0xFFEA580C), // Orange like Pic 2
  'ANG': const Color(0xFFEA580C),
  'EN': const Color(0xFFEA580C),
  'PHYSIQUE': const Color(0xFF06B6D4), // Cyan like Pic 2
  'PHYS': const Color(0xFF06B6D4),
  'SVT': const Color(0xFF3B82F6),   // Blue like Pic 2
  'HISTOIRE': const Color(0xFFE11D48), // Magenta / Rose like Pic 2
  'HIST': const Color(0xFFE11D48),
  'GEO': const Color(0xFFEF4444),   // Crimson Red like Pic 2
  'INFO': const Color(0xFF84CC16),  // Lime Green like Pic 2
  'TECH': const Color(0xFFF59E0B),  // Amber like Pic 2
  'ED_ISL': const Color(0xFF14B8A6), // Teal like Pic 2
  'ISL': const Color(0xFF14B8A6),
  'ED_CIV': const Color(0xFF6366F1), // Indigo like Pic 2
  'CIV': const Color(0xFF6366F1),
  'SPORT': const Color(0xFF8B5CF6), // Purple like Pic 2
};

final List<Color> _appColorPalette = const [
  Color(0xFFF59E0B), // Amber
  Color(0xFF10B981), // Emerald
  Color(0xFFEC4899), // Pink
  Color(0xFFEA580C), // Orange
  Color(0xFF06B6D4), // Cyan
  Color(0xFF3B82F6), // Blue
  Color(0xFFE11D48), // Rose
  Color(0xFFEF4444), // Red
  Color(0xFF84CC16), // Lime
  Color(0xFF14B8A6), // Teal
  Color(0xFF8B5CF6), // Violet
  Color(0xFF6366F1), // Indigo
];

Color _getSubjectColor(String subjectCode) {
  final codeUpper = subjectCode.trim().toUpperCase();
  for (final entry in _presetSubjectColors.entries) {
    if (codeUpper == entry.key || codeUpper.startsWith(entry.key) || codeUpper.contains(entry.key)) {
      return entry.value;
    }
  }
  final hash = codeUpper.codeUnits.fold(0, (prev, elem) => prev + elem);
  return _appColorPalette[hash % _appColorPalette.length];
}

List<TimetableSlotModel>? getCachedTimetableForScreen({
  String? classId,
  String selectedType = 'regular',
  int selectedSemesterNumber = 1,
}) {
  final cacheKey = classId != null 
      ? 'timetable_screen_${classId}_${selectedType}_$selectedSemesterNumber'
      : 'timetable_screen_${selectedType}_$selectedSemesterNumber';

  final cached = OfflineCacheService.instance.getListOfMaps(cacheKey)
      ?? (classId != null ? OfflineCacheService.instance.getListOfMaps('timetable_screen_${classId}_regular_$selectedSemesterNumber') : null)
      ?? OfflineCacheService.instance.getListOfMaps('timetable_screen_latest_$selectedSemesterNumber')
      ?? OfflineCacheService.instance.getListOfMaps('timetable_screen_latest');
  if (cached != null && cached.isNotEmpty) {
    return cached.map((s) => TimetableSlotModel.fromJson(s)).toList();
  }
  return null;
}

final timetableProvider = FutureProvider<List<TimetableSlotModel>>((ref) async {
  final authState = ref.watch(authProvider);
  final contextAsync = await ref.watch(studentContextProvider.future);

  final classId = contextAsync?.classId 
      ?? authState.enrollment?.classId 
      ?? (OfflineCacheService.instance.getMap('cached_enrollment')?['class_id'] as String?);

  final isExamPeriodActive = await ref.watch(isExamPeriodProvider.future);
  final selectedType = isExamPeriodActive ? 'exam' : 'regular';
  final selectedSemesterNumber = ref.watch(emploiSemesterProvider);

  try {
    final allSemesters = await ref.watch(semestersProvider.future);
    if (isSemesterLocked(selectedSemesterNumber, allSemesters)) {
      return [];
    }
  } catch (_) {}

  final cacheKey = classId != null 
      ? 'timetable_screen_${classId}_${selectedType}_$selectedSemesterNumber'
      : 'timetable_screen_${selectedType}_$selectedSemesterNumber';

  List<TimetableSlotModel>? getCachedTimetable() => getCachedTimetableForScreen(
    classId: classId,
    selectedType: selectedType,
    selectedSemesterNumber: selectedSemesterNumber,
  );

  // Instant offline return
  if (ConnectivityService.instance.isOffline) {
    final cachedList = getCachedTimetable();
    if (cachedList != null && cachedList.isNotEmpty) return cachedList;
  }

  if (classId == null) {
    final cachedList = getCachedTimetable();
    if (cachedList != null) return cachedList;
    return [];
  }

  final supabase = Supabase.instance.client;

  try {
    // Direct, canonical and resilient query for timetable slots of this student's class
    var query = supabase
        .from('timetable_slots')
        .select('''
          *,
          subject_offerings!inner (
            id, class_id, subject_id, teacher_id, semester_id,
            subjects (name, code),
            semesters (id, name, number, is_current)
          )
        ''')
        .eq('subject_offerings.class_id', classId);

    if (selectedType == 'exam') {
      query = query.inFilter('timetable_type', ['exam', 'examen', 'Exam', 'Examen']);
    } else {
      query = query.or('timetable_type.eq.regular,timetable_type.is.null');
    }

    final slotsResp = await query
        .order('day_of_week')
        .order('start_time')
        .timeout(const Duration(seconds: 4));

    final allSlotsList = slotsResp as List;
    if (allSlotsList.isEmpty) {
      final cached = OfflineCacheService.instance.getListOfMaps(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        return cached.map((s) => TimetableSlotModel.fromJson(s)).toList();
      }
      return [];
    }

    // Filter strictly by selected semester number
    final activeSlots = allSlotsList.where((slot) {
      final sem = slot['subject_offerings']?['semesters'] as Map<String, dynamic>?;
      if (sem == null) return false;
      final num = sem['number'] as int?;
      return num == selectedSemesterNumber;
    }).toList();

    if (activeSlots.isEmpty) {
      final cached = OfflineCacheService.instance.getListOfMaps(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        return cached.map((s) => TimetableSlotModel.fromJson(s)).toList();
      }
      return [];
    }

    // Resolve teacher names/photos from teacher_assignments
    final Map<String, String> subjectClassTeacherMap = {};
    final Map<String, String> subjectClassTeacherPhotoMap = {};
    try {
      final teacherAssResp = await supabase
          .from('teacher_assignments')
          .select(
              'subject_id, class_id, teacher_id, users!teacher_id(full_name, photo_url)')
          .eq('is_active', true);

      for (final ta in (teacherAssResp as List)) {
        final subjectId = ta['subject_id'] as String?;
        final clsId = ta['class_id'] as String?;
        final teacherData = ta['users'] as Map<String, dynamic>?;
        if (subjectId != null && clsId != null) {
          subjectClassTeacherMap['${subjectId}_$clsId'] =
              teacherData?['full_name'] as String? ?? '';
          subjectClassTeacherPhotoMap['${subjectId}_$clsId'] =
              teacherData?['photo_url'] as String? ?? '';
        }
      }
    } catch (_) {}

    final list = activeSlots.map((json) {
      final offering = json['subject_offerings'] as Map<String, dynamic>?;
      final subject = offering?['subjects'] as Map<String, dynamic>?;

      final subjectId = offering?['subject_id'] as String?;
      final teacherKey = subjectId != null ? '${subjectId}_$classId' : null;

      final teacherNameFromAssignment =
          teacherKey != null ? subjectClassTeacherMap[teacherKey] : null;
      final teacherPhotoFromAssignment =
          teacherKey != null ? subjectClassTeacherPhotoMap[teacherKey] : null;

      final teacherName = (teacherNameFromAssignment?.isNotEmpty == true)
          ? teacherNameFromAssignment
          : (json['teacher_name'] as String?);
      final teacherPhoto = (teacherPhotoFromAssignment?.isNotEmpty == true)
          ? teacherPhotoFromAssignment
          : null;

      final subjectName = (json['subject_name'] as String?) ??
          (subject?['name'] as String?) ??
          (json['title'] as String?) ??
          'Matière';
      final subjectCode = (json['subject_code'] as String?) ??
          (subject?['code'] as String?) ??
          subjectName;

      return TimetableSlotModel(
        id: (json['id'] as String?) ?? '',
        subjectOfferingId: (json['subject_offering_id'] as String?) ?? '',
        groupId: json['group_id'] as String?,
        dayOfWeek: (json['day_of_week'] as String?) ?? 'monday',
        startTime: _parseTime((json['start_time'] as String?) ?? '08:00'),
        endTime: _parseTime((json['end_time'] as String?) ?? '09:00'),
        room: json['room'] as String?,
        teacherName: teacherName,
        teacherPhotoUrl: teacherPhoto,
        sessionType: json['session_type'] as String? ?? 'CI',
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
        subjectName: subjectName,
        subjectCode: subjectCode,
      );
    }).toList();

    if (list.isNotEmpty) {
      OfflineCacheService.instance.setJson(
        cacheKey,
        list.map((s) => s.toJson()).toList(),
      );
      OfflineCacheService.instance.setJson(
        'timetable_screen_latest_$selectedSemesterNumber',
        list.map((s) => s.toJson()).toList(),
      );
      OfflineCacheService.instance.setJson(
        'timetable_screen_latest',
        list.map((s) => s.toJson()).toList(),
      );
    }
    ConnectivityService.instance.reportNetworkSuccess();
    return list;
  } catch (e) {
    debugPrint('timetableProvider error: $e');
    ConnectivityService.instance.reportNetworkError(e);

    final cachedList = getCachedTimetable();
    if (cachedList != null) return cachedList;
    return [];
  }
});

const List<String> _timeSlots = [
  '08:00', '09:00', '10:00', '11:00', '12:00', '13:00', '14:00', '15:00', '16:00',
];
const List<String> _dayKeys = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
const List<String> _dayLabels = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];
const List<String> _fullDayLabels = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'];

String _getDayLabel(int dayIndex, bool isFullScreen, String langCode) {
  if (langCode == 'ar') {
    const arShort = ['إثن', 'ثلا', 'أرب', 'خمي', 'جمع', 'سبت'];
    const arFull = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
    if (dayIndex >= 0 && dayIndex < 6) {
      return isFullScreen ? arFull[dayIndex] : arShort[dayIndex];
    }
  } else if (langCode == 'en') {
    const enShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const enFull = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    if (dayIndex >= 0 && dayIndex < 6) {
      return isFullScreen ? enFull[dayIndex] : enShort[dayIndex];
    }
  }
  return isFullScreen ? _fullDayLabels[dayIndex] : _dayLabels[dayIndex];
}

class EmploiScreen extends ConsumerStatefulWidget {
  const EmploiScreen({super.key});

  @override
  ConsumerState<EmploiScreen> createState() => _EmploiScreenState();
}

class _EmploiScreenState extends ConsumerState<EmploiScreen>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late final AnimationController _expandAnimationController;
  late final Animation<double> _expandFadeAnimation;
  late final Animation<double> _expandScaleAnimation;

  @override
  void initState() {
    super.initState();
    _expandAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      reverseDuration: const Duration(milliseconds: 280),
    );
    _expandFadeAnimation = CurvedAnimation(
      parent: _expandAnimationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _expandScaleAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _expandAnimationController,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );
  }

  @override
  void dispose() {
    if (_isExpanded) {
      ref.read(timetableExpandedProvider.notifier).state = false;
      ref.read(backSwipeInterceptorProvider.notifier).state = null;
    }
    _expandAnimationController.dispose();
    super.dispose();
  }

  void _setExpanded(bool expanded) {
    if (expanded) {
      if (!_isExpanded) {
        ref.read(timetableExpandedProvider.notifier).state = true;
        ref.read(backSwipeInterceptorProvider.notifier).state = () {
          _setExpanded(false);
          return true;
        };
        setState(() {
          _isExpanded = true;
        });
        _expandAnimationController.forward(from: 0.0);
      }
    } else {
      if (_isExpanded) {
        ref.read(timetableExpandedProvider.notifier).state = false;
        ref.read(backSwipeInterceptorProvider.notifier).state = null;
        _expandAnimationController.reverse().then((_) {
          if (mounted) {
            setState(() {
              _isExpanded = false;
            });
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final timetableAsync = ref.watch(timetableProvider);
    final selectedSemester = ref.watch(emploiSemesterProvider);
    final isExamPeriodActive = ref.watch(isExamPeriodProvider).valueOrNull ?? false;
    final selectedType = isExamPeriodActive ? 'exam' : 'regular';
    final isRefreshing = ref.watch(emploiRefreshingProvider);
    final semesters = ref.watch(semestersProvider).valueOrNull ?? [];
    final isLocked = isSemesterLocked(selectedSemester, semesters);
    final studentCtx = ref.watch(studentContextProvider).valueOrNull;
    final authState = ref.watch(authProvider);
    final classId = studentCtx?.classId 
        ?? authState.enrollment?.classId 
        ?? (OfflineCacheService.instance.getMap('cached_enrollment')?['class_id'] as String?);

    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF8F0FC),
              Color(0xFFF0E6F8),
              Color(0xFFEAF0FA),
              Color(0xFFF4F8FC),
              Color(0xFFFAFCFD),
            ],
            stops: [0.0, 0.25, 0.5, 0.75, 1.0],
          ),
        ),
        child: PopScope(
          canPop: !_isExpanded,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_isExpanded) {
              _setExpanded(false);
              return;
            }
          },
          child: Stack(
            children: [
              SafeArea(
                bottom: false,
                child: RefreshIndicator(
                  color: const Color(0xFFEA580C),
                  backgroundColor: Colors.white,
                  onRefresh: () async {
                    ref.read(emploiRefreshingProvider.notifier).state = true;
                    try {
                      ref.invalidate(studentContextProvider);
                      ref.invalidate(semestersProvider);
                      ref.invalidate(isExamPeriodProvider);
                      // ignore: unused_result
                      await ref.refresh(timetableProvider.future);
                    } finally {
                      ref.read(emploiRefreshingProvider.notifier).state = false;
                    }
                  },
                  child: CustomScrollView(
                    clipBehavior: Clip.none,
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Builder(
                          builder: (context) {
                            final screenW = MediaQuery.sizeOf(context).width;
                            final scale = (screenW / 440.0).clamp(0.72, 1.15);
                            final iconBoxSize = (56.0 * scale).clamp(44.0, 56.0);
                            final iconSize = (28.0 * scale).clamp(22.0, 28.0);
                            final titleSize = (28.0 * (1.0 + (scale - 1.0) * 0.75)).clamp(19.0, 28.0);
                            final subtitleSize = (14.0 * (1.0 + (scale - 1.0) * 0.75)).clamp(11.5, 14.0);
                            final actionBtnSize = (48.0 * scale).clamp(40.0, 48.0);
                            final isAr = Localizations.localeOf(context).languageCode == 'ar';

                            return Padding(
                              padding: EdgeInsets.fromLTRB(
                                AppResponsive.horizontalPadding(context),
                                20,
                                AppResponsive.horizontalPadding(context),
                                16,
                              ),
                              child: SizedBox(
                                height: 72,
                                child: Row(
                                  children: [
                                    Container(
                                      width: iconBoxSize,
                                      height: iconBoxSize,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: const LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [Color(0xFFEA580C), Color(0xFFF97316)],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFFEA580C).withValues(alpha: 0.4),
                                            blurRadius: 20 * scale,
                                            offset: Offset(0, 8 * scale),
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        selectedType == 'exam'
                                            ? Icons.school_rounded
                                            : Icons.calendar_month_rounded,
                                        color: Colors.white,
                                        size: iconSize,
                                      ),
                                    ),
                                    SizedBox(width: (16 * scale).clamp(10.0, 16.0)),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: isAr
                                                ? Alignment.centerRight
                                                : Alignment.centerLeft,
                                            child: Text(
                                              selectedType == 'exam'
                                                  ? (isAr
                                                      ? 'جدول الامتحانات'
                                                      : (Localizations.localeOf(context).languageCode == 'en'
                                                          ? 'Exam Timetable'
                                                          : 'Emploi d\'examen'))
                                                  : l10n.emploi,
                                              style: ArabicTypography.headerStyle(
                                                context,
                                                fontSize: titleSize,
                                                fontWeight: FontWeight.w900,
                                                color: const Color(0xFF1F2937),
                                                letterSpacing: -0.8,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            selectedType == 'exam'
                                                ? l10n.examTimetableSubtitle
                                                : l10n.emploiSubtitle,
                                            style: ArabicTypography.subtitleStyle(
                                              context,
                                              fontSize: subtitleSize,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFF1F2937),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!isLocked) ...[
                                      SizedBox(width: (12 * scale).clamp(8.0, 12.0)),
                                      BouncingWrapper(
                                        shrinkScale: 0.86,
                                        overshootScale: 1.10,
                                        onTap: () => _setExpanded(true),
                                        child: Container(
                                          width: actionBtnSize,
                                          height: actionBtnSize,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.white,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.08),
                                                blurRadius: 16,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: Icon(
                                            Icons.fullscreen_rounded,
                                            color: const Color(0xFFEA580C),
                                            size: (24 * scale).clamp(20.0, 24.0),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppResponsive.horizontalPadding(context),
                          ),
                          child: DynamicSemesterNav(
                            selectedSemesterNumber: selectedSemester,
                            accentColor: const Color(0xFFEA580C),
                            secondaryColor: const Color(0xFFF97316),
                            onChanged: (v) => ref
                                .read(emploiSemesterProvider.notifier)
                                .state = v,
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 16)),
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: isLocked
                            ? LockedSemesterCard(
                                startDate: semesters
                                    .where((s) => s.number == selectedSemester)
                                    .firstOrNull
                                    ?.startDate,
                                moduleType: LockedModuleType.timetable,
                              )
                            : isRefreshing
                                ? const EmploiSkeleton()
                                : timetableAsync.when(
                          loading: () => const EmploiSkeleton(),
                          error: (e, _) {
                            final cachedSlots = getCachedTimetableForScreen(
                              classId: classId,
                              selectedType: selectedType,
                              selectedSemesterNumber: selectedSemester,
                            );
                            if (cachedSlots != null && cachedSlots.isNotEmpty) {
                              return _buildScrollableTimetable(context, cachedSlots);
                            }
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.error_outline,
                                      size: 48, color: Colors.red.shade300),
                                  const SizedBox(height: 16),
                                  Text('Erreur: $e',
                                      style: TextStyle(color: Colors.grey.shade600)),
                                ],
                              ),
                            );
                          },
                          data: (slots) {
                            final semObj = semesters
                                .where((s) => s.number == selectedSemester)
                                .firstOrNull;

                            if (slots.isNotEmpty) {
                              return _buildScrollableTimetable(context, slots);
                            }

                            return _buildEmptyState(
                              context,
                              isExam: selectedType == 'exam',
                              isFuture: false,
                              startDate: semObj?.startDate,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Blur the background page as the timetable expands (BackdropFilter: cheap GPU pass)
              if (_isExpanded)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _expandAnimationController,
                    builder: (context, _) {
                      final blur = _expandFadeAnimation.value * 16.0;
                      return IgnorePointer(
                        child: ClipRect(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX: blur,
                              sigmaY: blur,
                              tileMode: TileMode.clamp,
                            ),
                            child: Container(
                              color: Colors.black.withValues(
                                alpha: _expandFadeAnimation.value * 0.20,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (_isExpanded)
                timetableAsync.when(
                  data: (slots) => Positioned.fill(
                    child: FadeTransition(
                      opacity: _expandFadeAnimation,
                      child: ScaleTransition(
                        scale: _expandScaleAnimation,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFFF8F0FC),
                                Color(0xFFF0E6F8),
                                Color(0xFFEAF0FA),
                                Color(0xFFF4F8FC),
                                Color(0xFFFAFCFD),
                              ],
                              stops: [0.0, 0.25, 0.5, 0.75, 1.0],
                            ),
                          ),
                          child: SafeArea(
                            child: Stack(
                              children: [
                                Center(
                                  child: ZoomableTimetable(
                                    child: _buildScrollableTimetable(
                                      context,
                                      slots,
                                      isFullScreen: true,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 16,
                                  right: 20,
                                  child: BouncingWrapper(
                                    shrinkScale: 0.86,
                                    overshootScale: 1.10,
                                    onTap: () => _setExpanded(false),
                                    child: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.12),
                                            blurRadius: 12,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.close_rounded,
                                        size: 24,
                                        color: Color(0xFF1F2937),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScrollableTimetable(BuildContext context, List<TimetableSlotModel> slots, {bool isFullScreen = false}) {
    final container = Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
      margin: isFullScreen 
          ? const EdgeInsets.fromLTRB(16, 100, 16, 20)
          : const EdgeInsets.fromLTRB(24, 0, 24, 140),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final availableHeight = constraints.maxHeight;

          const timeColWidth = 35.0;
          final headerHeight = isFullScreen ? 75.0 : 40.0;
          
          final dayColWidth = (availableWidth - timeColWidth) / _dayKeys.length;
          final calculatedHeight = isFullScreen
              ? MediaQuery.of(context).size.height - 100
              : (MediaQuery.of(context).size.height * 0.68).clamp(580.0, 750.0);
          final gridHeight = (availableHeight.isInfinite || availableHeight <= 0)
              ? calculatedHeight - headerHeight
              : availableHeight - headerHeight;
          final rowHeight = gridHeight / _timeSlots.length;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: availableWidth,
                height: gridHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Base tap catcher for empty cells in the timetable
                    if (!isFullScreen)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _setExpanded(true),
                        ),
                      ),
                    ...List.generate(_timeSlots.length * 2 + 1, (i) {
                      final isHour = i % 2 == 0;
                      return Positioned(
                        left: timeColWidth,
                        right: 0,
                        bottom: i * (rowHeight / 2),
                        child: Container(
                          height: isHour ? 1.5 : 0.5,
                          color: isHour 
                              ? Colors.grey.withValues(alpha: 0.35) 
                              : Colors.grey.withValues(alpha: 0.1),
                        ),
                      );
                    }),
                    ...List.generate(_dayKeys.length + 1, (i) {
                      return Positioned(
                        left: timeColWidth + i * dayColWidth,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 1.0,
                          color: Colors.grey.withValues(alpha: 0.2),
                        ),
                      );
                    }),
                    // Current time - highlight remaining study time with green gradient
                    if (_isCurrentTimeInRange())
                      Positioned(
                        left: timeColWidth,
                        right: 0,
                        bottom: _getCurrentTimePosition(rowHeight),
                        top: 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                const Color(0xFFEA580C).withValues(alpha: 0.10),
                                const Color(0xFFEA580C).withValues(alpha: 0.03),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ...List.generate(_timeSlots.length, (i) {
                      final isCurrentHour = _isCurrentHour(i);
                      return Positioned(
                        left: 0,
                        bottom: i * rowHeight,
                        width: timeColWidth,
                        height: rowHeight,
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 2),
                            child: RotatedBox(
                              quarterTurns: 3,
                              child: Text(
                                _timeSlots[i],
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isCurrentHour ? FontWeight.w800 : FontWeight.w600,
                                  color: isCurrentHour ? const Color(0xFFEA580C) : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    ...slots.map((s) {
                      final dayIndex = _dayKeys.indexOf(s.dayOfWeek.toLowerCase());
                      if (dayIndex == -1) return const SizedBox.shrink();

                      final startMin = _timeToMinutes(s.startTime);
                      final endMin = _timeToMinutes(s.endTime);
                      final dayStartMin = _timeToMinutes(_timeSlots.first); 
                      
                      final visibleStartMin = startMin < dayStartMin ? dayStartMin : startMin;
                      
                      final bottom = ((visibleStartMin - dayStartMin) / 60) * rowHeight;
                      final height = ((endMin - visibleStartMin) / 60) * rowHeight;

                      return Positioned(
                        left: timeColWidth + dayIndex * dayColWidth,
                        bottom: bottom,
                        width: dayColWidth,
                        height: height,
                        child: _buildSlotCell(s, height, dayColWidth),
                      );
                    }),
                  ],
                ),
              ),
              Container(
                height: headerHeight,
                width: availableWidth,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.grey.withValues(alpha: 0.15), width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(width: timeColWidth),
                    ...List.generate(_dayKeys.length, (dayIndex) {
                      final isToday = DateTime.now().weekday == dayIndex + 1;
                      return SizedBox(
                        width: dayColWidth,
                        child: Center(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: Text(
                              _getDayLabel(dayIndex, isFullScreen, Localizations.localeOf(context).languageCode),
                              style: TextStyle(
                                fontSize: isFullScreen ? 12 : 13,
                                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                                color: isToday ? const Color(0xFFEA580C) : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ));

    final interactiveContainer = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: !isFullScreen ? () => _setExpanded(true) : null,
      child: container,
    );

    if (isFullScreen) {
      return interactiveContainer;
    }

    return SizedBox(
      height: (MediaQuery.of(context).size.height * 0.68).clamp(580.0, 750.0),
      child: interactiveContainer,
    );
  }

  String _cleanRoomName(String? room) {
    if (room == null || room.trim().isEmpty) return '';
    String text = room.trim();
    // If it contains "Salle", "Labo", "Atelier", "Amphi", extract that part:
    final match = RegExp(
      r'(Salle\s*[A-Z0-9]+|Labo\s*[A-Z0-9]+|Atelier\s*[A-Z0-9]+|Amphi\s*[A-Z0-9]+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) {
      return match.group(1)!;
    }
    // Remove Block prefix (e.g. "Bloc A - ", "Bloc B - ")
    text = text.replaceAll(RegExp(r'^Bloc\s+[A-Z0-9]+\s*[-·]\s*', caseSensitive: false), '');
    // Remove "Principal - " or "Principal · "
    text = text.replaceAll(RegExp(r'^Principal\s*[-·]\s*', caseSensitive: false), '');
    // Remove prefixes like "S1 · ", "S2 · "
    text = text.replaceAll(RegExp(r'^S\d+\s*[-·]\s*', caseSensitive: false), '');
    if (text.contains('·')) {
      return text.split('·').last.trim();
    }
    return text.trim();
  }

  String _formatDetailLocation(String? room) {
    if (room == null || room.trim().isEmpty) return '';
    String text = room.trim();
    if (text.toLowerCase().startsWith('salle:')) {
      text = text.substring(6).trim();
    }
    // Remove "Principal" or "- Principal" or "· Principal"
    text = text.replaceAll(RegExp(r'[-·]?\s*\bPrincipal\b\s*[-·]?', caseSensitive: false), '·');
    // Shorten "Xème étage" or "Xer étage" to "Xème" / "Xer"
    text = text.replaceAllMapped(
      RegExp(r'(\d+(?:ème|er))\s+étage', caseSensitive: false),
      (match) => match.group(1)!,
    );
    // Clean double separators like "· ·" or "- ·"
    text = text.replaceAll(RegExp(r'\s*[-·]\s*[-·]\s*'), ' · ');
    text = text.replaceAll(RegExp(r'^\s*[-·]\s*|\s*[-·]\s*$'), '');
    return text.trim();
  }

  String _getSubjectDisplay(TimetableSlotModel slot) {
    if (slot.subjectName != null && slot.subjectName!.trim().isNotEmpty) {
      final name = slot.subjectName!.trim();
      if (name.length <= 14) return name.toUpperCase();
    }
    if (slot.subjectCode != null && slot.subjectCode!.trim().isNotEmpty) {
      return slot.subjectCode!.trim().toUpperCase();
    }
    return (slot.subjectName ?? '').toUpperCase();
  }

  Widget _buildSlotCell(TimetableSlotModel slot, double height, double width) {
    final color = _getSubjectColor(slot.subjectCode ?? slot.subjectName ?? 'DEFAULT');
    final timeRange = '${_formatTime(slot.startTime)}–${_formatTime(slot.endTime)}';
    final roomText = _cleanRoomName(slot.room);
    final subjectText = _getSubjectDisplay(slot);
    final teacherText = slot.teacherName?.trim();

    return Directionality(
      textDirection: TextDirection.ltr,
      child: BouncingWrapper(
        shrinkScale: 0.90,
        overshootScale: 1.055,
        onTap: () {
          _showSlotDetails(context, slot, color, timeRange);
        },
      child: Container(
        margin: const EdgeInsets.all(2.5),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.25),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRect(
          child: RotatedBox(
            quarterTurns: 3,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 1. Subject Name (FIRST / TOP)
                  Text(
                    subjectText,
                    style: const TextStyle(
                      fontSize: 12.0,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                  ),
                  // 2. Room Name (SECOND)
                  if (roomText.isNotEmpty) ...[
                    const SizedBox(height: 1.5),
                    Text(
                      roomText,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                      maxLines: 1,
                    ),
                  ],
                  // 3. Teacher Name + Avatar (THIRD, if present)
                  if (teacherText != null && teacherText.isNotEmpty) ...[
                    const SizedBox(height: 1.5),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.3),
                            image: (slot.teacherPhotoUrl != null && slot.teacherPhotoUrl!.isNotEmpty)
                                ? DecorationImage(
                                    image: NetworkImage(slot.teacherPhotoUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: (slot.teacherPhotoUrl == null || slot.teacherPhotoUrl!.isEmpty)
                              ? const Center(
                                  child: Icon(
                                    Icons.person_rounded,
                                    size: 8,
                                    color: Colors.white,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 3.5),
                        Flexible(
                          child: Text(
                            teacherText,
                            style: TextStyle(
                              fontSize: 8.5,
                              fontStyle: FontStyle.italic,
                              color: Colors.white.withValues(alpha: 0.90),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  // 4. Time Range (FOURTH / BOTTOM)
                  const SizedBox(height: 1.5),
                  Text(
                    timeRange,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
  }

  void _showSlotDetails(BuildContext context, TimetableSlotModel slot, Color color, String timeRange) {
    final l10n = AppLocalizations.of(context);
    final fullName = (slot.subjectName != null && slot.subjectName!.trim().isNotEmpty)
        ? slot.subjectName!.trim()
        : (slot.subjectCode ?? 'Matière');
    final detailLocation = _formatDetailLocation(slot.room);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 340),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final screenWidth = MediaQuery.sizeOf(dialogContext).width;
        final screenHeight = MediaQuery.sizeOf(dialogContext).height;
        return Center(
          child: RotatedBox(
            quarterTurns: 3,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (screenHeight * 0.72).clamp(280.0, 390.0),
                maxHeight: (screenWidth * 0.90).clamp(240.0, 380.0),
              ),
              child: Dialog(
                insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          fullName,
                          style: ArabicTypography.headerStyle(
                            dialogContext,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.access_time_filled_rounded, size: 16, color: color),
                          const SizedBox(width: 6),
                          Text(
                            timeRange,
                            style: ArabicTypography.bodyStyle(
                              dialogContext,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1F2937),
                            ),
                          ),
                          if (detailLocation.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Container(
                              width: 4,
                              height: 4,
                              decoration: const BoxDecoration(
                                color: Color(0xFF9CA3AF),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFF6B7280)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                detailLocation,
                                style: ArabicTypography.bodyStyle(
                                  dialogContext,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF374151),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      Divider(height: 1, color: Colors.grey.shade200),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 17,
                              backgroundColor: Colors.grey.shade200,
                              backgroundImage: slot.teacherPhotoUrl != null
                                  ? NetworkImage(slot.teacherPhotoUrl!)
                                  : null,
                              child: slot.teacherPhotoUrl == null
                                  ? const Icon(Icons.person, color: Color(0xFF9CA3AF), size: 18)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    l10n.translate('teacher'),
                                    style: ArabicTypography.subtitleStyle(
                                      dialogContext,
                                      fontSize: 10.5,
                                      color: const Color(0xFF9CA3AF),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    slot.teacherName ?? l10n.translate('not_assigned'),
                                    style: ArabicTypography.bodyStyle(
                                      dialogContext,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF1F2937),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: BouncingWrapper(
                          shrinkScale: 0.94,
                          overshootScale: 1.05,
                          onTap: () => Navigator.of(dialogContext).pop(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 9),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.28),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Text(
                              l10n.closeLabel,
                              style: (Localizations.localeOf(dialogContext).languageCode == 'ar'
                                  ? GoogleFonts.cairo(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.white)
                                  : const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.white)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return buildIosBounceZoomTransition(
          context: context,
          animation: animation,
          child: child,
          backdropSigma: 8.0,
          maxFlightBlur: 14.0,
        );
      },
    );
  }

  String _formatTime(String time) {
    final parts = time.split(':');
    return '${parts[0]}:${parts[1]}';
  }

  int _timeToMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  bool _isCurrentTimeInRange() {
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final startMinutes = _timeToMinutes(_timeSlots.first);
    final endMinutes = _timeToMinutes(_timeSlots.last) + 60; // Add 1 hour for the last slot
    return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
  }

  double _getCurrentTimePosition(double rowHeight) {
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final startMinutes = _timeToMinutes(_timeSlots.first);
    return ((currentMinutes - startMinutes) / 60) * rowHeight;
  }

  bool _isCurrentHour(int slotIndex) {
    final now = DateTime.now();
    final currentHour = now.hour;
    final slotHour = _timeToMinutes(_timeSlots[slotIndex]) ~/ 60;
    return currentHour == slotHour;
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required bool isExam,
    bool isFuture = false,
    DateTime? startDate,
  }) {
    final l10n = AppLocalizations.of(context);
    final String title;
    final String subtitle;
    if (isFuture) {
      final lang = Localizations.localeOf(context).languageCode;
      final formattedDate = startDate != null
          ? ArabicTypography.toLatinDigits(DateFormat('d MMMM yyyy', lang).format(startDate))
          : null;
      title = l10n.upcomingSemester;
      subtitle = formattedDate != null
          ? l10n.translate('timetable_available_from', {'date': formattedDate})
          : l10n.translate('timetable_available_start');
    } else if (isExam) {
      title = l10n.noExamsScheduled;
      subtitle = l10n.noExamsDesc;
    } else {
      title = l10n.timetableNotAvailable;
      subtitle = l10n.timetableNotAvailableDesc;
    }

    return Align(
      alignment: const Alignment(0, -0.45),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: isFuture
                        ? const [Color(0xFFFF2B6D), Color(0xFFE11D48)]
                        : isExam
                            ? const [Color(0xFFEA580C), Color(0xFFF97316)]
                            : const [Color(0xFFEA580C), Color(0xFFF97316)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isFuture
                              ? const Color(0xFFFF2B6D)
                              : isExam
                                  ? const Color(0xFFEA580C)
                                  : const Color(0xFFEA580C))
                          .withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(
                  isFuture
                      ? Icons.calendar_month_rounded
                      : isExam
                          ? Icons.school_rounded
                          : Icons.calendar_today_rounded,
                  size: 34,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: ArabicTypography.headerStyle(
                  context,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1F2937),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: ArabicTypography.bodyStyle(
                  context,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF6B7280),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pinch-to-zoom viewer with bounce-back spring animation:
/// 1. Zoom around the pinch point, so you can zoom anywhere on the timetable.
/// 2. Keep the timetable inside the screen (boundaryMargin: EdgeInsets.zero).
/// 3. Snap back with a spring animation if scale goes below minScale or above maxScale.
/// 4. Double tap to zoom in at tap point or reset to 1.0.
class ZoomableTimetable extends StatefulWidget {
  final Widget child;
  const ZoomableTimetable({super.key, required this.child});

  @override
  State<ZoomableTimetable> createState() => _ZoomableTimetableState();
}

class _ZoomableTimetableState extends State<ZoomableTimetable>
    with SingleTickerProviderStateMixin {
  static const double _minScale = 1.0; // normal size
  static const double _maxScale = 4.0; // max allowed zoom
  static const double _overshoot = 0.6; // how far below 1 / above max it can stretch

  final _controller = TransformationController();
  late final AnimationController _anim;
  Animation<Matrix4>? _animation;
  Offset _doubleTapPos = Offset.zero;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..addListener(() {
        if (_animation != null) _controller.value = _animation!.value;
      });
  }

  @override
  void dispose() {
    _anim.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 target) {
    _animation = Matrix4Tween(begin: _controller.value, end: target).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutBack), // slight bounce
    );
    _anim.forward(from: 0);
  }

  void _onInteractionStart(ScaleStartDetails details) {
    if (_anim.isAnimating) {
      _anim.stop();
    }
  }

  // When the fingers lift, snap back into the allowed range.
  void _onInteractionEnd(ScaleEndDetails details) {
    final scale = _controller.value.getMaxScaleOnAxis();

    if (scale < _minScale) {
      _animateTo(Matrix4.identity()); // back to normal size and centered
    } else if (scale > _maxScale) {
      final size = context.size ?? MediaQuery.of(context).size;
      final focal = _controller.toScene(
        Offset(size.width / 2, size.height / 2),
      );
      final m = Matrix4.identity()
        ..translateByDouble(focal.dx, focal.dy, 0.0, 1.0)
        ..scaleByDouble(_maxScale / scale, _maxScale / scale, 1.0, 1.0)
        ..translateByDouble(-focal.dx, -focal.dy, 0.0, 1.0);
      _animateTo(_controller.value * m);
    }
  }

  // Double tap: zoom in at the tap point, or reset if already zoomed.
  void _onDoubleTap() {
    if (_anim.isAnimating) _anim.stop();
    final scale = _controller.value.getMaxScaleOnAxis();
    if (scale > 1.05) {
      _animateTo(Matrix4.identity());
    } else {
      const target = 2.5;
      final p = _doubleTapPos;
      _animateTo(
        Matrix4.identity()
          ..translateByDouble(-p.dx * (target - 1), -p.dy * (target - 1), 0.0, 1.0)
          ..scaleByDouble(target, target, 1.0, 1.0),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: _minScale - _overshoot, // allows stretching below 1 (the bounce)
        maxScale: _maxScale + _overshoot, // allows stretching above max
        boundaryMargin: EdgeInsets.zero, // content can't be dragged off screen
        onInteractionStart: _onInteractionStart,
        onInteractionEnd: _onInteractionEnd,
        child: Center(
          child: widget.child,
        ),
      ),
    );
  }
}
