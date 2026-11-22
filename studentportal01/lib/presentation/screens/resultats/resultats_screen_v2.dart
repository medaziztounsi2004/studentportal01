import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';
import '../../widgets/bouncing_wrapper.dart';
import '../../providers/nav_bar_provider.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/arabic_typography.dart';
import '../../../core/theme/responsive.dart';
import '../../../data/models/grade_model.dart';
import '../../widgets/semester_navigator.dart';
import '../../widgets/resultats_skeleton.dart';
import '../../widgets/locked_semester_card.dart';
import '../../widgets/empty_state_glass_card.dart';
import '../../../data/services/offline_cache_service.dart';

import '../../providers/student_context_provider.dart' show studentContextProvider, semestersProvider;
// Import providers from the original file
import 'resultats_screen.dart' show gradesProvider, resultatsSemesterProvider, resultatsRefreshingProvider;

/// Premium Redesigned Results Screen - iOS 26 Style with Navbar
class ResultatsScreenV2 extends ConsumerStatefulWidget {
  const ResultatsScreenV2({super.key});

  @override
  ConsumerState<ResultatsScreenV2> createState() => _ResultatsScreenV2State();
}

class _ResultatsScreenV2State extends ConsumerState<ResultatsScreenV2>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  late AnimationController _searchAnimationController;
  bool _isSearching = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
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
        _searchQuery = '';
        _searchFocusNode.unfocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selectedSemester = ref.watch(resultatsSemesterProvider);
    final gradesAsync = ref.watch(gradesProvider(selectedSemester));
    final isRefreshing = ref.watch(resultatsRefreshingProvider);
    final semesters = ref.watch(semestersProvider).valueOrNull ?? [];
    final isLocked = isSemesterLocked(selectedSemester, semesters);

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
            color: const Color(0xFF2563EB),
            backgroundColor: Colors.white,
            onRefresh: () async {
              ref.read(resultatsRefreshingProvider.notifier).state = true;
              try {
                ref.invalidate(studentContextProvider);
                ref.invalidate(semestersProvider);
                // ignore: unused_result
                await ref.refresh(gradesProvider(selectedSemester).future);
              } finally {
                ref.read(resultatsRefreshingProvider.notifier).state = false;
              }
            },
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
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // Header with animated search
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(context.horizontalPadding, 20, context.horizontalPadding, 16),
                  child: _buildAnimatedHeader(l10n),
                ),
              ),

              // Dynamic Semester Navigator (fetches from DB)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.horizontalPadding),
                  child: DynamicSemesterNav(
                    selectedSemesterNumber: selectedSemester,
                    accentColor: const Color(0xFF3B82F6),
                    secondaryColor: const Color(0xFF2563EB),
                    onChanged: (v) =>
                        ref.read(resultatsSemesterProvider.notifier).state = v,
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 20)),

              // Content
              if (isLocked)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: LockedSemesterCard(
                    startDate: semesters
                        .where((s) => s.number == selectedSemester)
                        .firstOrNull
                        ?.startDate,
                    moduleType: LockedModuleType.grades,
                  ),
                )
              else if (isRefreshing)
                const ResultatsCardsSkeleton()
              else
              gradesAsync.when(
                data: (grades) {
                  return _buildContent(context, grades, selectedSemester, l10n);
                },
                loading: () => const ResultatsCardsSkeleton(),
                error: (error, stack) {
                  final cached = OfflineCacheService.instance.getListOfMaps('cached_grades_sem_$selectedSemester');
                  if (cached != null && cached.isNotEmpty) {
                    try {
                      final cachedGrades = cached.map((m) => SubjectGradesSummary.fromJson(m)).toList();
                      return _buildContent(context, cachedGrades, selectedSemester, l10n);
                    } catch (_) {}
                  }
                  return SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.red.shade300,
                          ),
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

        final iconBoxSize = (56 * context.responsiveScale).clamp(44.0, 56.0);
        final iconInnerSize = (28 * context.responsiveScale).clamp(22.0, 28.0);
        final searchBtnSize = (50.0 * context.responsiveScale).clamp(44.0, 50.0);
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
                              colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF3B82F6).withValues(alpha: 0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.bar_chart_rounded,
                            color: Colors.white,
                            size: iconInnerSize,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                l10n.resultats,
                                style: ArabicTypography.headerStyle(
                                  context,
                                  fontSize: context.sp(28),
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF1F2937),
                                  letterSpacing: -0.8,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.resultsSubtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ArabicTypography.subtitleStyle(
                                context,
                                fontSize: context.sp(14),
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1F2937),
                              ),
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
                            size: (26 * context.responsiveScale).clamp(22.0, 26.0),
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
                final isRtl = Directionality.of(context) == TextDirection.rtl;
                final searchOriginOffset = isRtl
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
                            size: (26 * context.responsiveScale).clamp(22.0, 26.0),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
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
                                    onChanged: (value) =>
                                        setState(() => _searchQuery = value),
                                    style: ArabicTypography.bodyStyle(
                                      context,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey[900],
                                    ),
                                    decoration: InputDecoration(
                                      hintText: AppLocalizations.of(context).search,
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
                              if (_searchQuery.isNotEmpty)
                                GestureDetector(
                                  onTap: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
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

  Widget _buildContent(
    BuildContext context,
    List<SubjectGradesSummary> grades,
    int semester,
    AppLocalizations l10n,
  ) {
    if (grades.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(context, semester: semester),
      );
    }

    // Filter grades based on search
    var filteredGrades = grades;
    if (_searchQuery.isNotEmpty) {
      filteredGrades = grades
          .where(
            (g) =>
                g.subjectName.toLowerCase().contains(_searchQuery) ||
                (g.subjectCode?.toLowerCase().contains(_searchQuery) ?? false),
          )
          .toList();
    }

    // Check if ALL subjects have complete results
    final allCompleted = grades.every((g) => g.average != null);

    // Calculate average ONLY if all subjects are completed
    double? semesterAverage;
    if (allCompleted) {
      double totalWeighted = 0;
      double totalCoeff = 0;
      for (final g in grades) {
        if (g.average != null) {
          totalWeighted += g.average! * g.coefficient;
          totalCoeff += g.coefficient;
        }
      }
      semesterAverage = totalCoeff > 0 ? totalWeighted / totalCoeff : null;
    }

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(context.horizontalPadding, 0, context.horizontalPadding, 140),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          // Semester Average Card (only if all completed)
          if (allCompleted && semesterAverage != null) ...[
            _GlassySemesterCard(
              average: semesterAverage,
              semester: semester,
              isValidated: semesterAverage >= 10,
            ),
            const SizedBox(height: 20),
          ] else ...[
            _buildPendingResultsCard(context, grades),
            const SizedBox(height: 20),
          ],

          // Section title
          Text(
            l10n.translate('details_par_matiere'),
            style: ArabicTypography.subtitleStyle(
              context,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade800,
            ),
          ),

          const SizedBox(height: 16),

          // Subject Cards
          if (filteredGrades.isNotEmpty) ...[
            ...filteredGrades.map(
              (subject) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _GlassySubjectCard(subject: subject),
              ),
            ),
            const SizedBox(height: 20),
          ] else
            EmptyStateGlassCard(
              horizontalMargin: 0,
              icon: Icons.search_off_rounded,
              gradientColors: const [Color(0xFF3B82F6), Color(0xFF2563EB)],
              title: l10n.noResults,
              subtitle: l10n.noSearchResultsDesc,
            ),
        ]),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, {int? semester}) {
    final semTitle = semester != null ? 'le Trimestre $semester' : 'ce trimestre';

    return EmptyStateGlassCard(
      alignment: const Alignment(0, -0.45),
      icon: Icons.bar_chart_rounded,
      gradientColors: const [Color(0xFF3B82F6), Color(0xFF2563EB)],
      title: 'Aucun résultat disponible',
      subtitle: 'Les notes pour $semTitle n\'ont pas encore été publiées par l\'établissement.',
    );
  }

  /// Hero Progress Card — blue gradient matching the header icon glow
  Widget _buildPendingResultsCard(
    BuildContext context,
    List<SubjectGradesSummary> grades,
  ) {
    final l10n = AppLocalizations.of(context);
    final completedCount = grades.where((g) => g.average != null).length;
    final totalCount = grades.length;
    final progress = totalCount > 0 ? completedCount / totalCount : 0.0;

    final rightBoxSize = (96 * context.responsiveScale).clamp(64.0, 96.0);
    final rightInnerCircle = (64 * context.responsiveScale).clamp(44.0, 64.0);
    final rightIconSize = (36 * context.responsiveScale).clamp(24.0, 36.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: Container(
        padding: EdgeInsets.all(AppResponsive.cardPadding(context, base: 28.0)),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
          ),
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.5),
              blurRadius: 50,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Content
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.translate('progression_semestre'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.8),
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '$completedCount',
                                  style: const TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    height: 1,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '/ $totalCount',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                size: 14,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  l10n.translate('matieres_completes'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Right circle icon
                    Container(
                      width: rightBoxSize,
                      height: rightBoxSize,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: rightInnerCircle,
                          height: rightInnerCircle,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          child: Icon(
                            Icons.task_alt_rounded,
                            color: const Color(0xFF3B82F6),
                            size: rightIconSize,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.white.withValues(alpha: 0.6),
                    ),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}




// Glassy Semester Average Card - NO BORDER
class _GlassySemesterCard extends StatelessWidget {
  final double average;
  final int semester;
  final bool isValidated;

  const _GlassySemesterCard({
    required this.average,
    required this.semester,
    required this.isValidated,
  });

  @override
  Widget build(BuildContext context) {
    final gradientColors = isValidated
        ? [const Color(0xFF3B82F6), const Color(0xFF2563EB)]
        : [const Color(0xFFEF4444), const Color(0xFFDC2626)];

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          padding: EdgeInsets.all(AppResponsive.cardPadding(context, base: 24.0)),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
            borderRadius: BorderRadius.circular(24),
            // NO BORDER
            boxShadow: [
              BoxShadow(
                color: gradientColors[1].withValues(alpha: 0.45),
                blurRadius: 30,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Moyenne Trimestre $semester',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            average.toStringAsFixed(2),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 44,
                              fontWeight: FontWeight.bold,
                              height: 1,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6, left: 4),
                            child: Text(
                              '/20',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isValidated
                          ? Icons.check_circle_rounded
                          : Icons.warning_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isValidated
                            ? Icons.verified_rounded
                            : Icons.cancel_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isValidated ? 'Trimestre validé' : 'Trimestre non validé',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Glassy Subject Card — web design style
class _GlassySubjectCard extends StatefulWidget {
  final SubjectGradesSummary subject;

  const _GlassySubjectCard({required this.subject});

  @override
  State<_GlassySubjectCard> createState() => _GlassySubjectCardState();
}

class _GlassySubjectCardState extends State<_GlassySubjectCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(
      begin: 0,
      end: 0.5,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasAverage = widget.subject.average != null;
    final grade = widget.subject.average ?? 0;
    final gradeColor = !hasAverage
        ? Colors.grey.shade400
        : grade >= 10
        ? const Color(0xFF00B087)
        : const Color(0xFFEF4444);
    final gradeBgColor = gradeColor.withValues(alpha: 0.1);

    final badgeSize = (64 * context.responsiveScale).clamp(52.0, 64.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 30,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              // Header
              BouncingWrapper(
                shrinkScale: 0.96,
                overshootScale: 1.03,
                onTap: () {
                  setState(() => _isExpanded = !_isExpanded);
                  if (_isExpanded) {
                    _controller.forward();
                  } else {
                    _controller.reverse();
                  }
                },
                child: Padding(
                  padding: EdgeInsets.all(AppResponsive.cardPadding(context, base: 20.0)),
                  child: Row(
                    children: [
                      // Average badge
                      Container(
                        width: badgeSize,
                        height: badgeSize,
                        decoration: BoxDecoration(
                          color: gradeBgColor,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: hasAverage
                              ? Text(
                                  grade.toStringAsFixed(1),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: gradeColor,
                                    fontSize: 18,
                                  ),
                                )
                              : Icon(
                                  Icons.pending_outlined,
                                  color: gradeColor,
                                  size: 24,
                                ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Subject info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.subject.subjectName,
                              style: ArabicTypography.subtitleStyle(
                                context,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (widget.subject.subjectCode != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      widget.subject.subjectCode!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE1F0FF),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${l10n.coeffLabel} ${widget.subject.coefficient.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF0066FF),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (widget.subject.teacherName != null &&
                                widget.subject.teacherName!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 10,
                                    backgroundColor: Colors.grey.shade200,
                                    backgroundImage:
                                        widget.subject.teacherPhotoUrl !=
                                                null &&
                                            widget
                                                .subject
                                                .teacherPhotoUrl!
                                                .isNotEmpty
                                        ? NetworkImage(
                                            widget.subject.teacherPhotoUrl!,
                                          )
                                        : null,
                                    child:
                                        (widget.subject.teacherPhotoUrl ==
                                                null ||
                                            widget
                                                .subject
                                                .teacherPhotoUrl!
                                                .isEmpty)
                                        ? Icon(
                                            Icons.person,
                                            size: 12,
                                            color: Colors.grey.shade500,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    widget.subject.teacherName!,
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
                      // Expand button
                      RotationTransition(
                        turns: _rotationAnimation,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.expand_more_rounded,
                            color: Colors.grey.shade600,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Expanded content
              SizeTransition(
                sizeFactor: _expandAnimation,
                child: _buildExpandedContent(gradeColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedContent(Color gradeColor) {
    final l10n = AppLocalizations.of(context);
    final cardPad = AppResponsive.cardPadding(context, base: 20.0);
    return Container(
      padding: EdgeInsets.fromLTRB(cardPad, 0, cardPad, cardPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: Colors.grey.shade200, height: 1),
          const SizedBox(height: 16),
          // Weights display
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.pie_chart_rounded,
                  size: 18,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.subject.weightsDisplay,
                    style: ArabicTypography.bodyStyle(
                      context,
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Components
          ...widget.subject.components.map((component) {
            final isGraded =
                component.status == 'OK' && component.grade != null;
            final compGrade = component.grade ?? 0;
            final compColor = !isGraded
                ? Colors.grey.shade400
                : compGrade >= 10
                ? const Color(0xFF00B087)
                : const Color(0xFFEF4444);

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  // Grade badge
                  Container(
                    width: 60,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: compColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        component.displayGrade,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: compColor,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Component name and weight
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.formatGradeComponentName(component.componentName),
                          style: ArabicTypography.bodyStyle(
                            context,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        Text(
                          '${l10n.translate('weight_label')}: ${component.weightPercent.toStringAsFixed(0)}%',
                          style: ArabicTypography.bodyStyle(
                            context,
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Progress bar or "À venir" badge
                  if (isGraded)
                    SizedBox(
                      width: 48,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: compGrade / 20,
                          backgroundColor: compColor.withValues(alpha: 0.1),
                          valueColor: AlwaysStoppedAnimation(compColor),
                          minHeight: 6,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        l10n.translate('badge_upcoming'),
                        style: ArabicTypography.bodyStyle(
                          context,
                          fontSize: 10,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
