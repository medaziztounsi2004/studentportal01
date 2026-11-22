import 'dart:ui';
import 'package:flutter/material.dart';
import '../../widgets/bouncing_wrapper.dart';
import '../../providers/nav_bar_provider.dart';
import '../../widgets/absences_skeleton.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/arabic_typography.dart';
import '../../../core/theme/responsive.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../data/services/offline_cache_service.dart';
import '../../../data/services/core_data_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/student_context_provider.dart' as ctx;
import '../../widgets/semester_navigator.dart';
import '../../widgets/locked_semester_card.dart';
import '../../widgets/empty_state_glass_card.dart';
import '../../../data/models/absence_model.dart';

// Selected semester provider (dynamic from DB)
final absencesTrimesterProvider = StateProvider<int>((ref) => 1);

// Loading state for absences refresh
final absencesRefreshingProvider = StateProvider<bool>((ref) => false);

// Search provider
final absencesSearchProvider = StateProvider<String>((ref) => '');

// Get semesters for current enrollment - now uses shared provider
final absencesSemestersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final semesters = await ref.watch(ctx.semestersProvider.future);
  return semesters.map<Map<String, dynamic>>((s) => <String, dynamic>{
    'id': s.id,
    'name': s.name,
    'number': s.number,
    'is_current': s.isCurrent,
    'start_date': s.startDate?.toIso8601String(),
    'end_date': s.endDate?.toIso8601String(),
  }).toList();
});

List<SubjectAbsenceSummary>? getCachedAbsencesForScreen({
  String? enrollmentId,
  String? userId,
  required int semesterNumber,
}) {
  final cacheKey = 'absences_screen_${enrollmentId ?? 'default'}_$semesterNumber';
  final cached = OfflineCacheService.instance.getListOfMaps(cacheKey)
      ?? (userId != null ? OfflineCacheService.instance.getListOfMaps('absences_screen_${userId}_$semesterNumber') : null)
      ?? OfflineCacheService.instance.getListOfMaps('absences_screen_latest_$semesterNumber')
      ?? OfflineCacheService.instance.getListOfMaps('absences_screen_latest');
  if (cached != null && cached.isNotEmpty) {
    return cached.map((s) => SubjectAbsenceSummary.fromJson(s)).toList();
  }
  return null;
}

// Real absences provider - fetches from database
final absencesProvider = FutureProvider.family<List<SubjectAbsenceSummary>, int>((ref, semesterNumber) async {
  final authState = ref.watch(authProvider);
  final studentCtx = ref.watch(ctx.studentContextProvider).valueOrNull;
  
  final enrollmentId = authState.enrollment?.id 
      ?? studentCtx?.enrollmentId 
      ?? (OfflineCacheService.instance.getMap('cached_enrollment')?['id'] as String?)
      ?? 'default';
  final userId = authState.user?.id 
      ?? studentCtx?.userId
      ?? OfflineCacheService.instance.getMap('cached_user')?['id'] as String?;
  final cacheKey = 'absences_screen_${enrollmentId}_$semesterNumber';

  List<SubjectAbsenceSummary>? getCachedAbsences() => getCachedAbsencesForScreen(
    enrollmentId: enrollmentId,
    userId: userId,
    semesterNumber: semesterNumber,
  );

  // Fast offline return
  if (ConnectivityService.instance.isOffline) {
    final cachedList = getCachedAbsences();
    if (cachedList != null && cachedList.isNotEmpty) return cachedList;
  }

  if (!authState.isAuthenticated && studentCtx == null) {
    debugPrint('absencesProvider: Not authenticated, checking cache');
    final cachedList = getCachedAbsences();
    if (cachedList != null) return cachedList;
    return [];
  }
  
  final studentCtxAsync = await ref.watch(ctx.studentContextProvider.future).timeout(
    const Duration(seconds: 4),
    onTimeout: () => null,
  );
  final semesters = await ref.watch(absencesSemestersProvider.future).timeout(
    const Duration(seconds: 4),
    onTimeout: () => <Map<String, dynamic>>[],
  );

  final allSemesters = await ref.watch(ctx.semestersProvider.future).timeout(
    const Duration(seconds: 4),
    onTimeout: () => <SemesterInfo>[],
  );
  if (isSemesterLocked(semesterNumber, allSemesters)) {
    debugPrint('absencesProvider: Semester $semesterNumber is locked, returning empty');
    return [];
  }

  final schoolId = authState.user?.schoolId 
      ?? studentCtxAsync?.schoolId 
      ?? (OfflineCacheService.instance.getMap('cached_user')?['school_id'] as String?)
      ?? authState.enrollment?.classInfo?.schoolId;
  
  final semester = semesters.firstWhere(
    (s) => s['number'] == semesterNumber,
    orElse: () => <String, dynamic>{},
  );
  
  final semesterId = semester['id'] as String?;
  if (semesterId == null) {
    debugPrint('absencesProvider: Semester $semesterNumber not found, checking cache');
    final cachedList = getCachedAbsences();
    if (cachedList != null) return cachedList;
    return [];
  }

  // Parse semester date bounds to filter absences strictly to this semester
  DateTime? semesterStart;
  DateTime? semesterEnd;
  final semInfo = allSemesters.where((s) => s.number == semesterNumber).firstOrNull;
  if (semInfo?.startDate != null) {
    semesterStart = semInfo!.startDate;
  } else if (semester['start_date'] != null) {
    semesterStart = DateTime.tryParse(semester['start_date'] as String);
  }
  if (semInfo?.endDate != null) {
    semesterEnd = semInfo!.endDate;
  } else if (semester['end_date'] != null) {
    semesterEnd = DateTime.tryParse(semester['end_date'] as String);
  }
  
  final supabase = Supabase.instance.client;
  
  try {
    double warningPercent = 20.0;
    double criticalPercent = 30.0;
    double eliminationPercent = 50.0;
    String warningMessage = 'Attention! Vous approchez du seuil d\'absences autorisé.';
    String criticalMessage = 'Attention! Vous avez dépassé le seuil critique d\'absences.';
    String eliminationMessage = 'Vous avez été éliminé de la session principale des examens.';
    
    if (schoolId != null) {
      final thresholdResponse = await supabase
          .from('absence_thresholds')
          .select()
          .eq('school_id', schoolId)
          .maybeSingle()
          .timeout(const Duration(seconds: 3));
      
      if (thresholdResponse != null) {
        warningPercent = (thresholdResponse['warning_percent'] as num?)?.toDouble() ?? 20.0;
        criticalPercent = (thresholdResponse['critical_percent'] as num?)?.toDouble() ?? 30.0;
        eliminationPercent = (thresholdResponse['elimination_percent'] as num?)?.toDouble() ?? 50.0;
        warningMessage = thresholdResponse['warning_message'] as String? ?? warningMessage;
        criticalMessage = thresholdResponse['critical_message'] as String? ?? criticalMessage;
        eliminationMessage = thresholdResponse['elimination_message'] as String? ?? eliminationMessage;
      }
    }
    
    final classId = studentCtxAsync?.classId 
        ?? authState.enrollment?.classId 
        ?? (OfflineCacheService.instance.getMap('cached_enrollment')?['class_id'] as String?);
    
    if (classId == null || classId.isEmpty) {
      final cachedList = getCachedAbsences();
      if (cachedList != null) return cachedList;
      return [];
    }
    
    final subjectOfferingsResponse = await supabase
        .from('subject_offerings')
        .select('''
          id,
          subject_id,
          total_hours,
          weekly_ci_hours,
          weekly_tp_hours,
          weeks,
          subjects (
            id,
            code,
            name
          )
        ''')
        .eq('semester_id', semesterId)
        .eq('class_id', classId)
        .eq('is_active', true);
    
    final rawOfferings = List<Map<String, dynamic>>.from(subjectOfferingsResponse);
    
    if (rawOfferings.isEmpty) {
      debugPrint('absencesProvider: No subject offerings found');
      return [];
    }

    // Deduplicate subject offerings by subject_id to prevent duplicate database entries from inflating total semester hours
    final Map<String, Map<String, dynamic>> dedupedMap = {};
    final Map<String, String> offeringIdToCanonicalId = {};
    for (final so in rawOfferings) {
      final sId = so['subject_id']?.toString() ?? so['id']?.toString() ?? '';
      final soId = so['id']?.toString() ?? '';
      if (!dedupedMap.containsKey(sId)) {
        dedupedMap[sId] = so;
        offeringIdToCanonicalId[soId] = soId;
      } else {
        final existingHours = (dedupedMap[sId]!['total_hours'] as num?)?.toDouble() ?? 0;
        final currentHours = (so['total_hours'] as num?)?.toDouble() ?? 0;
        if (currentHours > existingHours) {
          final oldCanonicalId = dedupedMap[sId]!['id']?.toString() ?? '';
          dedupedMap[sId] = so;
          offeringIdToCanonicalId[soId] = soId;
          if (oldCanonicalId.isNotEmpty) {
            offeringIdToCanonicalId[oldCanonicalId] = soId;
          }
        } else {
          final canonicalId = dedupedMap[sId]!['id']?.toString() ?? soId;
          offeringIdToCanonicalId[soId] = canonicalId;
        }
      }
    }
    final subjectOfferings = dedupedMap.values.toList();
    
    // Fetch teacher assignments for this class
    final Map<String, Map<String, String>> teacherMap = {};
    try {
      final teacherResp = await supabase
          .from('teacher_assignments')
          .select('subject_id, teacher_id, users!teacher_id(full_name, photo_url)')
          .eq('class_id', classId)
          .eq('is_active', true);
      
      for (final ta in (teacherResp as List)) {
        final subjectId = ta['subject_id'] as String?;
        final teacherData = ta['users'] as Map<String, dynamic>?;
        if (subjectId != null) {
          teacherMap[subjectId] = {
            'name': teacherData?['full_name'] as String? ?? '',
            'photo': teacherData?['photo_url'] as String? ?? '',
          };
        }
      }
    } catch (e) {
      debugPrint('absencesProvider: Error fetching teacher_assignments: $e');
    }
    
    List<Map<String, dynamic>> absenceRecords = [];
    try {
      dynamic resp;
      if (enrollmentId.isNotEmpty && enrollmentId != 'default' && userId != null && userId.isNotEmpty) {
        resp = await supabase
            .from('absence_records')
            .select('subject_offering_id, hours_absent, student_id, enrollment_id, date, subject_offerings(id, subject_id, semester_id)')
            .or('enrollment_id.eq.$enrollmentId,student_id.eq.$userId')
            .timeout(const Duration(seconds: 4));
      } else if (enrollmentId.isNotEmpty && enrollmentId != 'default') {
        resp = await supabase
            .from('absence_records')
            .select('subject_offering_id, hours_absent, student_id, enrollment_id, date, subject_offerings(id, subject_id, semester_id)')
            .eq('enrollment_id', enrollmentId)
            .timeout(const Duration(seconds: 4));
      } else if (userId != null && userId.isNotEmpty) {
        resp = await supabase
            .from('absence_records')
            .select('subject_offering_id, hours_absent, student_id, enrollment_id, date, subject_offerings(id, subject_id, semester_id)')
            .eq('student_id', userId)
            .timeout(const Duration(seconds: 4));
      }
      if (resp != null) {
        absenceRecords = List<Map<String, dynamic>>.from(resp);
      }
    } catch (e) {
      debugPrint('absencesProvider: Error fetching absence_records with or filter: $e');
      try {
        final fallback = await supabase
            .from('absence_records')
            .select('subject_offering_id, hours_absent, date')
            .eq('enrollment_id', enrollmentId)
            .timeout(const Duration(seconds: 4));
        absenceRecords = List<Map<String, dynamic>>.from(fallback);
      } catch (_) {}
    }

    final subjectIdToOfferingId = <String, String>{};
    for (final so in subjectOfferings) {
      final sId = so['subject_id'] as String?;
      final soId = so['id'] as String;
      if (sId != null) subjectIdToOfferingId[sId] = soId;
    }
    
    final absencesBySubject = <String, double>{};
    for (final record in absenceRecords) {
      // Filter out absences outside of this semester's date range
      final rawDate = record['date'] as String?;
      if (rawDate != null && rawDate.isNotEmpty) {
        final parsedDate = DateTime.tryParse(rawDate);
        if (parsedDate != null) {
          if (semesterStart != null && parsedDate.isBefore(DateTime(semesterStart.year, semesterStart.month, semesterStart.day))) {
            continue;
          }
          if (semesterEnd != null && parsedDate.isAfter(DateTime(semesterEnd.year, semesterEnd.month, semesterEnd.day, 23, 59, 59))) {
            continue;
          }
        }
      }

      final soId = record['subject_offering_id'] as String?;
      final hours = (record['hours_absent'] as num?)?.toDouble() ?? 0;
      if (soId != null) {
        final canonicalId = offeringIdToCanonicalId[soId] ?? soId;
        if (subjectOfferings.any((so) => so['id'] == canonicalId)) {
          absencesBySubject[canonicalId] = (absencesBySubject[canonicalId] ?? 0) + hours;
        } else {
          // Check if subject_id matches an offering for this class/semester
          final relSubjectId = (record['subject_offerings'] as Map<String, dynamic>?)?['subject_id'] as String?;
          if (relSubjectId != null && subjectIdToOfferingId.containsKey(relSubjectId)) {
            final targetSoId = subjectIdToOfferingId[relSubjectId]!;
            absencesBySubject[targetSoId] = (absencesBySubject[targetSoId] ?? 0) + hours;
          }
        }
      }
    }
    
    final List<SubjectAbsenceSummary> summaries = [];
    
    for (final so in subjectOfferings) {
      final soId = so['id'] as String;
      final subject = so['subjects'] as Map<String, dynamic>?;
      final totalHours = (so['total_hours'] as num?)?.toDouble() ?? 0;
      final weeklyCi = (so['weekly_ci_hours'] as num?)?.toDouble() ?? 0;
      final weeklyTp = (so['weekly_tp_hours'] as num?)?.toDouble() ?? 0;
      final weeks = (so['weeks'] as num?)?.toInt() ?? 14;
      
      final absentHours = absencesBySubject[soId] ?? 0;
      final rawPercent = totalHours > 0 ? (absentHours / totalHours) * 100.0 : 0.0;
      final absencePercent = rawPercent.clamp(0.0, 100.0);
      
      AbsenceLevel level = AbsenceLevel.normal;
      String? message;
      
      if (absencePercent >= eliminationPercent) {
        level = AbsenceLevel.eliminated;
        message = eliminationMessage;
      } else if (absencePercent >= criticalPercent) {
        level = AbsenceLevel.critical;
        message = criticalMessage;
      } else if (absencePercent >= warningPercent) {
        level = AbsenceLevel.warning;
        message = warningMessage;
      }
      
      final subjectId = so['subject_id'] as String?;
      final teacher = subjectId != null ? teacherMap[subjectId] : null;
      
      summaries.add(SubjectAbsenceSummary(
        subjectOfferingId: soId,
        subjectName: subject?['name'] as String? ?? 'MatiÃƒÂ¨re inconnue',
        subjectCode: subject?['code'] as String?,
        totalHours: totalHours,
        weeklyCiHours: weeklyCi,
        weeklyTpHours: weeklyTp,
        weeks: weeks,
        totalAbsentHours: absentHours,
        absencePercent: absencePercent,
        level: level,
        warningMessage: message,
        teacherName: teacher?['name'],
        teacherPhotoUrl: teacher?['photo'],
      ));
    }
    
    summaries.sort((a, b) => b.absencePercent.compareTo(a.absencePercent));
    
    if (summaries.isNotEmpty) {
      OfflineCacheService.instance.setJson(
        cacheKey,
        summaries.map((s) => s.toJson()).toList(),
      );
      if (userId != null) {
        OfflineCacheService.instance.setJson(
          'absences_screen_${userId}_$semesterNumber',
          summaries.map((s) => s.toJson()).toList(),
        );
      }
      OfflineCacheService.instance.setJson(
        'absences_screen_latest_$semesterNumber',
        summaries.map((s) => s.toJson()).toList(),
      );
      OfflineCacheService.instance.setJson(
        'absences_screen_latest',
        summaries.map((s) => s.toJson()).toList(),
      );
    }
    ConnectivityService.instance.reportNetworkSuccess();
    return summaries;
  } catch (e) {
    debugPrint('absencesProvider error: $e');
    ConnectivityService.instance.reportNetworkError(e);

    final cachedList = getCachedAbsences();
    if (cachedList != null) return cachedList;
    return [];
  }
});

class AbsencesScreen extends ConsumerStatefulWidget {
  const AbsencesScreen({super.key});

  @override
  ConsumerState<AbsencesScreen> createState() => _AbsencesScreenState();
}

class _AbsencesScreenState extends ConsumerState<AbsencesScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late AnimationController _searchAnimationController;
  bool _isSearching = false;
  String _searchQuery = '';
  static const Color _accentColor = Color(0xFFEC4899);

  @override
  void initState() {
    super.initState();
    _searchAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim();
      });
    });
  }

  @override
  void dispose() {
    if (_isSearching) {
      ref.read(backSwipeInterceptorProvider.notifier).state = null;
    }
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchAnimationController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (_isSearching) {
        _searchAnimationController.forward();
        ref.read(backSwipeInterceptorProvider.notifier).state = () {
          _toggleSearch();
          return true;
        };
        Future.delayed(const Duration(milliseconds: 150), () {
          _searchFocusNode.requestFocus();
        });
      } else {
        ref.read(backSwipeInterceptorProvider.notifier).state = null;
        _searchAnimationController.reverse();
        _searchController.clear();
        _searchFocusNode.unfocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selectedTrimester = ref.watch(absencesTrimesterProvider);
    final absencesAsync = ref.watch(absencesProvider(selectedTrimester));
    final isRefreshing = ref.watch(absencesRefreshingProvider);
    final semesters = ref.watch(ctx.semestersProvider).valueOrNull ?? [];
    final isLocked = isSemesterLocked(selectedTrimester, semesters);
    final studentCtx = ref.watch(ctx.studentContextProvider).valueOrNull;
    final authState = ref.watch(authProvider);
    final userId = authState.user?.id 
        ?? studentCtx?.userId
        ?? OfflineCacheService.instance.getMap('cached_user')?['id'] as String?;
    final enrollmentId = authState.enrollment?.id 
        ?? studentCtx?.enrollmentId 
        ?? (OfflineCacheService.instance.getMap('cached_enrollment')?['id'] as String?)
        ?? 'default';

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
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () async {
              ref.read(absencesRefreshingProvider.notifier).state = true;
              try {
                ref.invalidate(ctx.studentContextProvider);
                ref.invalidate(ctx.semestersProvider);
                ref.invalidate(absencesSemestersProvider);
                // ignore: unused_result
                await ref.refresh(absencesProvider(selectedTrimester).future);
              } finally {
                ref.read(absencesRefreshingProvider.notifier).state = false;
              }
            },
            color: _accentColor,
            backgroundColor: Colors.white,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                if (_isSearching) _toggleSearch();
              },
              onHorizontalDragUpdate: (details) {
                if (_isSearching) {
                  final isRtl = Directionality.of(context) == TextDirection.rtl;
                  if (isRtl) {
                    if ((details.primaryDelta ?? 0) > 8) _toggleSearch();
                  } else {
                    if ((details.primaryDelta ?? 0) < -8) _toggleSearch();
                  }
                }
              },
              child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppResponsive.horizontalPadding(context),
                      20,
                      AppResponsive.horizontalPadding(context),
                      16,
                    ),
                    child: _buildAnimatedHeader(l10n),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppResponsive.horizontalPadding(context),
                    ),
                    child: DynamicSemesterNav(
                      selectedSemesterNumber: selectedTrimester,
                      onChanged: (v) => ref.read(absencesTrimesterProvider.notifier).state = v,
                      accentColor: const Color(0xFFEC4899),
                      secondaryColor: const Color(0xFFF43F5E),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 20)),

                if (isLocked)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: LockedSemesterCard(
                      startDate: semesters
                          .where((s) => s.number == selectedTrimester)
                          .firstOrNull
                          ?.startDate,
                      moduleType: LockedModuleType.absences,
                    ),
                  )
                else if (isRefreshing)
                  const AbsencesCardsSkeleton()
                else
                absencesAsync.when(
                  data: (absences) => _buildContent(context, absences, l10n),
                  loading: () => const AbsencesCardsSkeleton(),
                  error: (error, stack) {
                    final cached = getCachedAbsencesForScreen(
                      enrollmentId: enrollmentId,
                      userId: userId,
                      semesterNumber: selectedTrimester,
                    );
                    if (cached != null && cached.isNotEmpty) {
                      return _buildContent(context, cached, l10n);
                    }
                    return SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                            const SizedBox(height: 16),
                            Text('Erreur: $error'),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedHeader(AppLocalizations l10n) {
    return AnimatedBuilder(
      animation: _searchAnimationController,
      builder: (context, child) {
        final slideValue = _searchAnimationController.value;
        final fadeOut = 1.0 - slideValue;
        final fadeIn = slideValue;
        final screenW = MediaQuery.sizeOf(context).width;
        final scale = (screenW / 440.0).clamp(0.72, 1.15);
        final iconBoxSize = (56.0 * scale).clamp(44.0, 56.0);
        final iconSize = (28.0 * scale).clamp(22.0, 28.0);
        final titleSize = (28.0 * (1.0 + (scale - 1.0) * 0.75)).clamp(19.0, 28.0);
        final subtitleSize = (14.0 * (1.0 + (scale - 1.0) * 0.75)).clamp(11.5, 14.0);
        final searchBtnSize = (50.0 * scale).clamp(44.0, 50.0);
        final isAr = l10n.locale.languageCode == 'ar';
        final headerBlur = slideValue * 14.0;

        return SizedBox(
          height: 76,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Normal header - slides out and blurs on hiding / un-blurs on showing
              Transform.translate(
                offset: Offset(-60 * slideValue, 0),
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: headerBlur,
                    sigmaY: headerBlur,
                  ),
                  child: Opacity(
                    opacity: fadeOut.clamp(0.0, 1.0),
                    child: Row(
                    children: [
                      Transform.scale(
                        scale: 1.0 - (0.3 * slideValue),
                        child: Container(
                          width: iconBoxSize,
                          height: iconBoxSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFEC4899), Color(0xFFF43F5E)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFEC4899).withValues(alpha: 0.4),
                                blurRadius: 20 * scale,
                                offset: Offset(0, 8 * scale),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.event_busy_rounded,
                            color: Colors.white,
                            size: iconSize,
                          ),
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
                                l10n.absences,
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
                              l10n.absencesSubtitle,
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
                      BouncingWrapper(
                        shrinkScale: 0.86,
                        hitPadding: const EdgeInsets.all(8),
                        onTap: _toggleSearch,
                        child: Container(
                          width: searchBtnSize,
                          height: searchBtnSize,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.95),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.08),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.10),
                                blurRadius: 16,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.search_rounded,
                            color: Colors.grey[800],
                            size: (26 * scale).clamp(22.0, 26.0),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
              // Search bar - starts exactly at search button level and expands across
              LayoutBuilder(
                builder: (context, constraints) {
                  final totalWidth = constraints.maxWidth;
                  final searchOriginOffset = isAr
                      ? -(totalWidth - searchBtnSize)
                      : (totalWidth - searchBtnSize);
                  return Transform.translate(
                    offset: Offset(
                      searchOriginOffset * (1.0 - slideValue),
                      0,
                    ),
                    child: Opacity(
                      opacity: fadeIn.clamp(0.0, 1.0),
                      child: Row(
                    children: [
                      BouncingWrapper(
                        shrinkScale: 0.86,
                        hitPadding: const EdgeInsets.all(8),
                        onTap: _toggleSearch,
                        child: Container(
                          width: searchBtnSize,
                          height: searchBtnSize,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.95),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.08),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.10),
                                blurRadius: 16,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.grey[800],
                            size: (26 * scale).clamp(22.0, 26.0),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Search field - pill shaped
                      Expanded(
                        child: Container(
                          height: searchBtnSize,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.98),
                            borderRadius: BorderRadius.circular(searchBtnSize / 2),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.08),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.10),
                                blurRadius: 18,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const SizedBox(width: 16),
                              Icon(
                                Icons.search_rounded,
                                color: Colors.grey[600],
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Center(
                                  child: TextField(
                                    controller: _searchController,
                                    focusNode: _searchFocusNode,
                                    cursorColor: Colors.grey[800],
                                    textAlignVertical: TextAlignVertical.center,
                                    style: ArabicTypography.bodyStyle(
                                      context,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey[900],
                                    ),
                                    decoration: InputDecoration(
                                      hintText: l10n.search,
                                      hintStyle: ArabicTypography.bodyStyle(
                                        context,
                                        color: Colors.grey[500],
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      filled: false,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      isDense: true,
                                      isCollapsed: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                              ),
                              if (_searchController.text.isNotEmpty)
                                GestureDetector(
                                  onTap: () {
                                    _searchController.clear();
                                  },
                                  child: Container(
                                    margin: const EdgeInsetsDirectional.only(end: 8),
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[200],
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: Colors.grey[600],
                                      size: 22,
                                    ),
                                  ),
                                )
                              else
                                const SizedBox(width: 16),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, List<SubjectAbsenceSummary> absences, AppLocalizations l10n) {
    if (absences.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyStateGlassCard(
          icon: Icons.event_available_rounded,
          gradientColors: const [Color(0xFFEC4899), Color(0xFFF43F5E)],
          title: l10n.noAbsences,
          subtitle: l10n.noAbsencesDesc,
        ),
      );
    }

    final filtered = _searchQuery.isEmpty
        ? absences
        : absences.where((a) {
            final q = _searchQuery.toLowerCase();
            return a.subjectName.toLowerCase().contains(q) ||
                (a.subjectCode?.toLowerCase().contains(q) ?? false);
          }).toList();

    final totalAbsent = absences.fold<double>(0, (s, a) => s + a.totalAbsentHours);
    final totalHours = absences.fold<double>(0, (s, a) => s + a.totalHours);
    final rawPercent = totalHours > 0 ? (totalAbsent / totalHours) * 100.0 : 0.0;
    final overallPercent = rawPercent.clamp(0.0, 100.0);
    final criticalCount = absences.where((a) => a.level == AbsenceLevel.critical || a.level == AbsenceLevel.eliminated).length;

    if (filtered.isEmpty) {
      return SliverToBoxAdapter(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppResponsive.horizontalPadding(context),
              ),
              child: _buildSummaryCard(totalAbsent, totalHours, overallPercent, criticalCount),
            ),
            const SizedBox(height: 16),
            EmptyStateGlassCard(
              icon: Icons.search_off_rounded,
              gradientColors: const [Color(0xFF64748B), Color(0xFF475569)],
              title: l10n.noResults,
              subtitle: l10n.noSearchResultsDesc,
            ),
            const SizedBox(height: 120),
          ],
        ),
      );
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppResponsive.horizontalPadding(context),
        ),
        child: Column(
          children: [
            _buildSummaryCard(totalAbsent, totalHours, overallPercent, criticalCount),
            const SizedBox(height: 36),
            ...filtered.map((a) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _GlassyAbsenceCard(
                absence: a,
                onTap: () => context.go('/absences/${a.subjectOfferingId}'),
              ),
            )),
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(double totalAbsent, double totalHours, double overallPercent, int criticalCount) {
    final l10n = AppLocalizations.of(context);
    final isGood = overallPercent < 15;
    final gradientColors = const [Color(0xFFEC4899), Color(0xFFF43F5E)];

    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: gradientColors[0].withValues(alpha: 0.6),
                blurRadius: 60,
                offset: const Offset(0, 24),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.overallAbsenceRate,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          overallPercent.toStringAsFixed(1),
                          style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold, height: 1),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 6, left: 4),
                          child: Text('%', style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${totalAbsent.toStringAsFixed(0)} ${l10n.translate('hour_unit')} / ${totalHours.toStringAsFixed(0)} ${l10n.translate('hour_unit')}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isGood ? Icons.check_circle_rounded : Icons.warning_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  if (criticalCount > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '$criticalCount ${l10n.critical}${criticalCount > 1 ? 's' : ''}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Glassy Absence Card
class _GlassyAbsenceCard extends StatelessWidget {
  final SubjectAbsenceSummary absence;
  final VoidCallback? onTap;

  const _GlassyAbsenceCard({required this.absence, this.onTap});

  @override
  Widget build(BuildContext context) {
    Color levelColor;
    IconData levelIcon;
    
    switch (absence.level) {
      case AbsenceLevel.normal:
        levelColor = const Color(0xFF10B981);
        levelIcon = Icons.check_circle_rounded;
        break;
      case AbsenceLevel.warning:
        levelColor = const Color(0xFFF59E0B);
        levelIcon = Icons.warning_rounded;
        break;
      case AbsenceLevel.critical:
        levelColor = const Color(0xFFF97316);
        levelIcon = Icons.error_rounded;
        break;
      case AbsenceLevel.eliminated:
        levelColor = const Color(0xFFEF4444);
        levelIcon = Icons.cancel_rounded;
        break;
    }

    return BouncingWrapper(
      shrinkScale: 0.94,
      overshootScale: 1.055,
      delayNavigation: true,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 50,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 52,
                            height: 52,
                            child: CircularProgressIndicator(
                              value: (absence.absencePercent / 100).clamp(0.0, 1.0),
                              strokeWidth: 4,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation(levelColor),
                            ),
                          ),
                          Text(
                            '${absence.absencePercent.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: levelColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            absence.subjectName == 'Matière inconnue' || absence.subjectName.contains('inconnue')
                                ? AppLocalizations.of(context).unknownSubject
                                : absence.subjectName,
                            style: ArabicTypography.subtitleStyle(
                              context,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (absence.subjectCode != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    absence.subjectCode!,
                                    style: ArabicTypography.bodyStyle(
                                      context,
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              Text(
                                '${absence.totalAbsentHours.toStringAsFixed(0)} ${AppLocalizations.of(context).translate('hour_unit')} / ${absence.totalHours.toStringAsFixed(0)} ${AppLocalizations.of(context).translate('hour_unit')}',
                                style: ArabicTypography.bodyStyle(
                                  context,
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                          if (absence.teacherName != null && absence.teacherName!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 10,
                                  backgroundColor: Colors.grey.shade200,
                                  backgroundImage: absence.teacherPhotoUrl != null && absence.teacherPhotoUrl!.isNotEmpty
                                      ? NetworkImage(absence.teacherPhotoUrl!)
                                      : null,
                                  child: (absence.teacherPhotoUrl == null || absence.teacherPhotoUrl!.isEmpty)
                                      ? Icon(Icons.person, size: 12, color: Colors.grey.shade500)
                                      : null,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  absence.teacherName!,
                                  style: ArabicTypography.bodyStyle(
                                    context,
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(levelIcon, color: levelColor, size: 24),
                    ),
                  ],
                ),
                if (absence.warningMessage != null) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(levelIcon, size: 14, color: levelColor),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            absence.warningMessage!,
                            style: TextStyle(fontSize: 11, color: levelColor, fontWeight: FontWeight.w600, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 11,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${absence.weeks} ${AppLocalizations.of(context).weeks}',
                      style: ArabicTypography.bodyStyle(
                        context,
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
