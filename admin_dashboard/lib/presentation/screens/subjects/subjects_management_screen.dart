import 'dart:typed_data';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart' show AppColors;
import '../../../core/utils/error_messages.dart';
import '../../providers/subjects_management_provider.dart';
import '../../widgets/admin_sidebar.dart';
import '../../widgets/admin_sort_dropdown.dart';
import '../../widgets/ios_loader.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/modern_animated_switch.dart';
import '../../../data/models/academic_models.dart';
import '../../../data/models/school_models.dart';
import '../../../data/models/user_model.dart';

const _brand = Color(0xFF6D4CF6);
const _brandLight = Color(0xFFF0ECFE);

class SubjectsManagementScreen extends ConsumerStatefulWidget {
  const SubjectsManagementScreen({super.key});
  @override
  ConsumerState<SubjectsManagementScreen> createState() =>
      _SubjectsManagementScreenState();
}

class _SubjectsManagementScreenState
    extends ConsumerState<SubjectsManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _sortKey = 'name_asc';

  // Selection state for bulk operations
  final Set<String> _selectedAssignmentIds = {};
  final Set<String> _selectedSubjectIds = {};

  // Accordion expansion maps – use backing nullable fields so that
  // web hot-reload can't leave them as JS-undefined (= Dart null).
  Map<String, bool>? _expandedNiveaux_;
  Map<String, bool> get _expandedNiveaux => _expandedNiveaux_ ??= {};

  Map<String, bool>? _expandedSections_;
  Map<String, bool> get _expandedSections => _expandedSections_ ??= {};

  // ── Filter drawer state ──
  bool _showFilterDrawer = false;
  final _filterSubjectSearch = TextEditingController();
  double _filterCoefMin = 1;
  double _filterCoefMax = 6;
  final Set<String> _filterNiveauIds = {};
  final Set<String> _filterSectionIds = {};

  Map<String, bool>? _filterNiveauExpanded_;
  Map<String, bool> get _filterNiveauExpanded => _filterNiveauExpanded_ ??= {};

  bool _filtersActive = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    // Clear search/filter state when page is (re)visited
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchController.clear();
      ref.read(subjectsManagementProvider.notifier).setSearch('');
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _filterSubjectSearch.dispose();
    super.dispose();
  }

  void _resetFilters() {
    setState(() {
      _filterSubjectSearch.clear();
      _filterCoefMin = 1;
      _filterCoefMax = 6;
      _filterNiveauIds.clear();
      _filterSectionIds.clear();
      _filtersActive = false;
    });
  }

  void _applyFilters() {
    setState(() {
      _filtersActive =
          _filterSubjectSearch.text.isNotEmpty ||
          _filterCoefMin > 1 ||
          _filterCoefMax < 6 ||
          _filterNiveauIds.isNotEmpty ||
          _filterSectionIds.isNotEmpty;
      _showFilterDrawer = false;
    });
  }

  List<SubjectModel> _applyLocalFilters(
    List<SubjectModel> subjects,
    SubjectsManagementState state,
  ) {
    var result = subjects;

    // Filter by subject name search
    if (_filterSubjectSearch.text.isNotEmpty) {
      final q = _filterSubjectSearch.text.toLowerCase();
      result = result
          .where(
            (s) =>
                s.name.toLowerCase().contains(q) ||
                (s.code?.toLowerCase().contains(q) ?? false),
          )
          .toList();
    }

    // Filter by coefficient range
    if (_filterCoefMin > 1 || _filterCoefMax < 6) {
      result = result.where((s) {
        final coef = s.defaultCoefficient ?? 1;
        return coef >= _filterCoefMin && coef <= _filterCoefMax;
      }).toList();
    }

    // Filter by niveau
    if (_filterNiveauIds.isNotEmpty) {
      final subjectIdsForNiveaux = state.assignments
          .where(
            (a) => _filterNiveauIds.contains(a.gradeLevelId),
          )
          .map((a) => a.subjectId)
          .toSet();
      result = result
          .where((s) => subjectIdsForNiveaux.contains(s.id))
          .toList();
    }

    // Filter by section
    if (_filterSectionIds.isNotEmpty) {
      final subjectIdsForSections = state.assignments
          .where(
            (a) =>
                a.sectionId != null && _filterSectionIds.contains(a.sectionId),
          )
          .map((a) => a.subjectId)
          .toSet();
      result = result
          .where((s) => subjectIdsForSections.contains(s.id))
          .toList();
    }

    return result;
  }

  // ignore: unused_element
  void _toggleSelection(String id) {
    setState(() {
      if (_selectedAssignmentIds.contains(id)) {
        _selectedAssignmentIds.remove(id);
      } else {
        _selectedAssignmentIds.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedAssignmentIds.clear();
    });
  }

  // ignore: unused_element
  void _selectAll(List<SubjectAssignmentModel> assignments) {
    setState(() {
      _selectedAssignmentIds.addAll(assignments.map((a) => a.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(subjectsManagementProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: Stack(
        children: [
          Row(
            children: [
              const AdminSidebar(currentRoute: '/subjects'),
              Expanded(
                child: AnimatedOpacity(
                  opacity: _showFilterDrawer ? 1.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Column(
                    children: [
                      _buildTopBar(context),
                      _buildTabBar(),
                      Expanded(
                        child: stateAsync.when(
                          loading: () =>
                              const SubjectsSkeletonLoader(),
                          error: (e, _) => _buildErrorState(e),
                          data: (state) => TabBarView(
                            controller: _tabController,
                            children: [
                              _buildSubjectsTab(context, state),
                              _buildAssignmentsTab(context, state),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Filter drawer overlay
          if (_showFilterDrawer) ...[
            // Blur overlay — full-app
            GestureDetector(
              onTap: () => setState(() => _showFilterDrawer = false),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(color: Colors.black.withOpacity(0.28)),
              ),
            ),
            // Drawer
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 420,
              child: stateAsync.when(
                loading: () => const SizedBox(),
                error: (_, __) => const SizedBox(),
                data: (state) => _buildFilterDrawer(state),
              ),
            ),
          ],
          // Floating selection bar for subjects
          if (_selectedSubjectIds.isNotEmpty)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: _buildFloatingSubjectSelectionBar(context, stateAsync),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFloatingSubjectSelectionBar(
    BuildContext context,
    AsyncValue<SubjectsManagementState> stateAsync,
  ) {
    final count = _selectedSubjectIds.length;
    final allSubjects = stateAsync.value?.subjects ?? [];

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
                border: Border(
                  right: BorderSide(color: Colors.white.withOpacity(0.15)),
                ),
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
                    'Sélectionnées',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            // Actions
            _buildSelectionAction(
              Icons.ios_share_rounded,
              'Exporter',
              Colors.white70,
              () async {
                final sel = allSubjects
                    .where((s) => _selectedSubjectIds.contains(s.id))
                    .toList();
                final rows = <List<String>>[
                  [
                    'Nom',
                    'Code',
                    'Catégorie',
                    'Coefficient par défaut',
                    'Statut',
                  ],
                  ...sel.map((s) => [
                        s.name,
                        s.code ?? '',
                        s.category ?? '',
                        (s.defaultCoefficient ?? 1.0).toString(),
                        s.isActive ? 'Actif' : 'Inactif',
                      ]),
                ];
                final csv = rows
                    .map((r) => r.map((c) => '"$c"').join(','))
                    .join('\n');
                await FilePicker.platform.saveFile(
                  dialogTitle: 'Exporter les matières',
                  fileName: 'matieres_selectionnees.csv',
                  type: FileType.custom,
                  allowedExtensions: ['csv'],
                  bytes: Uint8List.fromList(csv.codeUnits),
                );
              },
            ),
            _buildSelectionAction(
              Icons.delete_outline,
              'Supprimer',
              const Color(0xFFFCA5A5),
              () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  barrierColor: Colors.black.withOpacity(0.08),
                  builder: (dCtx) => BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      title: Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(color: AppColors.errorSoft, borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
                          ),
                          const SizedBox(width: 12),
                          const Text('Supprimer en masse ?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        ],
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Voulez-vous vraiment supprimer $count matière(s) sélectionnée(s) ?'),
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
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx, false),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF6B7280),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              ),
                              child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () => Navigator.pop(dCtx, true),
                              icon: const Icon(Icons.delete_outline, size: 16),
                              label: const Text('Supprimer', style: TextStyle(fontWeight: FontWeight.w700)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.error,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
                if (confirm == true) {
                  final ids = _selectedSubjectIds.toList();
                  for (final id in ids) {
                    await ref
                        .read(subjectsManagementProvider.notifier)
                        .deleteSubject(id);
                  }
                  setState(() => _selectedSubjectIds.clear());
                }
              },
            ),
            // Close button
            Container(
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: Colors.white.withOpacity(0.15)),
                ),
              ),
              child: IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.white60),
                onPressed: () => setState(() => _selectedSubjectIds.clear()),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionAction(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
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
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE9EAF2))),
      ),
      child: Row(
        children: [
          // Left: Title + subtitle
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Matières',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Gérer les matières, coefficients et affectations',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
          const Spacer(),
          // Right: Search + Filter + Add button
          SizedBox(
            width: 320,
            height: 40,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Rechercher par nom, code...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: Colors.grey.shade400,
                ),
                filled: true,
                fillColor: AppColors.slate50,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.primary.withOpacity(0.4), width: 1.5),
                ),
                suffixIcon: _searchController.text.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.slate50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text('⌘K', style: TextStyle(fontSize: 10, color: AppColors.textTertiary, fontFamily: 'monospace')),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(subjectsManagementProvider.notifier)
                              .setSearch('');
                          setState(() {});
                        },
                      ),
              ),
              onChanged: (v) {
                ref.read(subjectsManagementProvider.notifier).setSearch(v);
                setState(() {});
              },
            ),
          ),
          const SizedBox(width: 12),
          AdminSortDropdown<String>(
            value: _sortKey,
            tooltip: 'Trier les matières',
            onChanged: (v) => setState(() => _sortKey = v),
            options: const [
              SortOption(value: 'name_asc', label: 'Nom (A → Z)', icon: Icons.sort_by_alpha),
              SortOption(value: 'name_desc', label: 'Nom (Z → A)', icon: Icons.sort_by_alpha),
              SortOption(value: 'date_desc', label: 'Plus récent', icon: Icons.calendar_today_outlined),
              SortOption(value: 'date_asc', label: 'Plus ancien', icon: Icons.calendar_today_outlined),
              SortOption(value: 'coef_desc', label: 'Coefficient (Plus grand)', icon: Icons.trending_up),
              SortOption(value: 'coef_asc', label: 'Coefficient (Plus petit)', icon: Icons.trending_down),
              SortOption(value: 'code_asc', label: 'Code (A → Z)', icon: Icons.tag),
            ],
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.filter_list_rounded, size: 20),
            tooltip: 'Filtres',
            onPressed: () => setState(() => _showFilterDrawer = !_showFilterDrawer),
            color: (_showFilterDrawer || _filtersActive) ? AppColors.primary : AppColors.textTertiary,
            style: IconButton.styleFrom(
              backgroundColor: (_showFilterDrawer || _filtersActive) ? AppColors.primarySoft : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: (_showFilterDrawer || _filtersActive) ? AppColors.primary.withOpacity(0.2) : Colors.transparent),
              ),
            ),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: () => _showSubjectDialog(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text(
                'Ajouter une matière',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brand,
                foregroundColor: Colors.white,
                elevation: 2,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                shadowColor: _brand.withOpacity(0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  // ░░░  FILTER DRAWER  ░░░
  // ════════════════════════════════════════════════════════════
  Widget _buildFilterDrawer(SubjectsManagementState state) {
    // Group niveaux by cycle
    final collegeNiveaux =
        state.gradeLevels.where((g) => g.levelType == 'college').toList()
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final lyceeNiveaux =
        state.gradeLevels.where((g) => g.levelType != 'college').toList()
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    // Sections: only from selected niveaux that have hasSections
    final selectedNiveauxWithSections = state.gradeLevels
        .where((g) => _filterNiveauIds.contains(g.id) && g.hasSections)
        .toList();
    final filteredSections = <SectionModel>[];
    final seenFilteredIds = <String>{};
    for (final g in selectedNiveauxWithSections) {
      for (final s in g.sections) {
        if (seenFilteredIds.add(s.id)) filteredSections.add(s);
      }
    }

    // Section chip colors
    const chipColors = [
      (Color(0xFFF3EEFA), Color(0xFF7C3AED), Color(0xFFD5C4F7)), // purple
      (Color(0xFFE6F0FE), Color(0xFF2563EB), Color(0xFFBFD7FE)), // blue
      (Color(0xFFFEF7E6), Color(0xFFD97706), Color(0xFFFDE68A)), // amber
    ];

    return Material(
      elevation: 16,
      shadowColor: Colors.black.withOpacity(0.2),
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Filtrer les Matières',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => setState(() => _showFilterDrawer = false),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: const Color(0xFFF3F4F6),
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 18,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),

            // ── Scrollable content ──
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  // ── Matière search ──
                  const Text(
                    'Matière',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF374151),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _filterSubjectSearch,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Rechercher une matière...',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade400,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        size: 18,
                        color: Colors.grey.shade400,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 0,
                        horizontal: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _brand),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),

                  const SizedBox(height: 28),

                  // ── Coefficient range ──
                  Row(
                    children: [
                      const Text(
                        'Coefficient',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _brand.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_filterCoefMin.toStringAsFixed(_filterCoefMin == _filterCoefMin.roundToDouble() ? 0 : 1)} - ${_filterCoefMax.toStringAsFixed(_filterCoefMax == _filterCoefMax.roundToDouble() ? 0 : 1)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _brand,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Min: ${_filterCoefMin.toStringAsFixed(_filterCoefMin == _filterCoefMin.roundToDouble() ? 0 : 1)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: _brand,
                              inactiveTrackColor: _brand.withOpacity(0.15),
                              thumbColor: Colors.white,
                              overlayColor: _brand.withOpacity(0.1),
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 8,
                                elevation: 3,
                              ),
                              trackHeight: 5,
                            ),
                            child: RangeSlider(
                              values: RangeValues(
                                _filterCoefMin,
                                _filterCoefMax,
                              ),
                              min: 1,
                              max: 6,
                              divisions: 10,
                              onChanged: (v) => setState(() {
                                _filterCoefMin = v.start;
                                _filterCoefMax = v.end;
                              }),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Max: ${_filterCoefMax.toStringAsFixed(_filterCoefMax == _filterCoefMax.roundToDouble() ? 0 : 1)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Niveaux & Sections ──
                  const Text(
                    'Niveaux & Sections',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF374151),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        // Collège group
                        if (collegeNiveaux.isNotEmpty)
                          _buildNiveauGroup(
                            'Collège (7-9)',
                            collegeNiveaux,
                            collegeNiveaux.length,
                          ),
                        // Lycée group
                        if (lyceeNiveaux.isNotEmpty) ...[
                          if (collegeNiveaux.isNotEmpty)
                            const Divider(height: 1, color: Color(0xFFE5E7EB)),
                          _buildNiveauGroup(
                            'Lycée (1-4)',
                            lyceeNiveaux,
                            lyceeNiveaux.length,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ── Sections Spécifiques chips (only when selected niveau has sections) ──
                  if (filteredSections.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'SECTIONS SPÉCIFIQUES',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: filteredSections.asMap().entries.map((entry) {
                        final sec = entry.value;
                        final idx = entry.key;
                        final isSelected = _filterSectionIds.contains(sec.id);
                        final colors = idx < chipColors.length
                            ? chipColors[idx]
                            : (
                                const Color(0xFFF3F4F6),
                                const Color(0xFF6B7280),
                                const Color(0xFFE5E7EB),
                              );
                        return GestureDetector(
                          onTap: () => setState(() {
                            if (isSelected)
                              _filterSectionIds.remove(sec.id);
                            else
                              _filterSectionIds.add(sec.id);
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colors.$1
                                  : const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? colors.$3
                                    : const Color(0xFFE5E7EB),
                              ),
                            ),
                            child: Text(
                              sec.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isSelected
                                    ? colors.$2
                                    : const Color(0xFF6B7280),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),

            // ── Bottom actions ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: const BoxDecoration(
                color: Color(0xFFFAFAFB),
                border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: _resetFilters,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF374151),
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFFD1D5DB)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Réinitialiser',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: _brand,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: _brand.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _applyFilters,
                          borderRadius: BorderRadius.circular(12),
                          child: const Center(
                            child: Text(
                              'Appliquer',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNiveauGroup(
    String title,
    List<GradeLevelModel> niveaux,
    int count,
  ) {
    final isExpanded =
        _filterNiveauExpanded[title] ?? (title.startsWith('Collège'));
    return Column(
      children: [
        // Header
        InkWell(
          onTap: () =>
              setState(() => _filterNiveauExpanded[title] = !isExpanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: const Color(0xFFF9FAFB),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: isExpanded
                      ? const Color(0xFF6B7280)
                      : const Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Items
        if (isExpanded)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Column(
              children: niveaux.map((g) {
                final isSelected = _filterNiveauIds.contains(g.id);
                return InkWell(
                  onTap: () => setState(() {
                    if (isSelected)
                      _filterNiveauIds.remove(g.id);
                    else
                      _filterNiveauIds.add(g.id);
                  }),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 20,
                      top: 6,
                      bottom: 6,
                      right: 8,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          child: isSelected
                              ? Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: _brand,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                )
                              : Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFFD1D5DB),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          g.name,
                          style: TextStyle(
                            fontSize: 13,
                            color: isSelected
                                ? const Color(0xFF111827)
                                : const Color(0xFF6B7280),
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE9EAF2))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: _brand,
          unselectedLabelColor: const Color(0xFF6B7280),
          indicatorColor: _brand,
          indicatorWeight: 2,
          indicatorSize: TabBarIndicatorSize.label,
          tabAlignment: TabAlignment.start,
          labelPadding: const EdgeInsets.symmetric(horizontal: 12),
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.book_outlined, size: 16),
                  SizedBox(width: 6),
                  Text('Toutes les Matières'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.layers_outlined, size: 16),
                  SizedBox(width: 6),
                  Text('Affectations par Niveau'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: AppColors.error.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            UserFriendlyError.format(
              error,
              fallback: 'Unable to load subjects right now. Please try again.',
            ),
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () =>
                ref.read(subjectsManagementProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  // ==================== SUBJECTS TAB ====================
  Widget _buildSubjectsTab(
    BuildContext context,
    SubjectsManagementState state,
  ) {
    final rawSubjects = _filtersActive
        ? _applyLocalFilters(state.filteredSubjects, state)
        : state.filteredSubjects;
    final subjects = List<SubjectModel>.from(rawSubjects);
    switch (_sortKey) {
      case 'name_desc':
        subjects.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case 'date_desc':
        subjects.sort((a, b) {
          final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });
        break;
      case 'date_asc':
        subjects.sort((a, b) {
          final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return da.compareTo(db);
        });
        break;
      case 'coef_desc':
        subjects.sort((a, b) => (b.defaultCoefficient ?? 1).compareTo(a.defaultCoefficient ?? 1));
        break;
      case 'coef_asc':
        subjects.sort((a, b) => (a.defaultCoefficient ?? 1).compareTo(b.defaultCoefficient ?? 1));
        break;
      case 'code_asc':
        subjects.sort((a, b) => (a.code ?? '').compareTo(b.code ?? ''));
        break;
      case 'name_asc':
      default:
        subjects.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
    }

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: _brand,
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Liste des Matières',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: Checkbox(
                      value: subjects.isNotEmpty &&
                          subjects.every((s) => _selectedSubjectIds.contains(s.id)),
                      activeColor: const Color(0xFF655DD5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      side: BorderSide(
                        color: Colors.grey.shade400,
                        width: 1.5,
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedSubjectIds.addAll(subjects.map((s) => s.id));
                          } else {
                            _selectedSubjectIds.clear();
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Tout sélectionner',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9999),
                  border: Border.all(color: const Color(0xFFECECF3)),
                ),
                child: Center(
                  child: Text(
                    '${subjects.length} matière(s)',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: subjects.isEmpty
                ? _buildEmptyState(
                    'Aucune matière',
                    Icons.book_outlined,
                    () => _showSubjectDialog(),
                  )
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          childAspectRatio: 0.82,
                          crossAxisSpacing: 24,
                          mainAxisSpacing: 24,
                        ),
                    itemCount: subjects.length + 1,
                    itemBuilder: (ctx, i) {
                      if (i == subjects.length) return _buildAddSubjectCard();
                      return _buildSubjectCard(subjects[i], state);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectCard(
    SubjectModel subject,
    SubjectsManagementState state,
  ) {
    final niveauNames = state.assignments
        .where((a) => a.subjectId == subject.id)
        .map((a) => a.gradeLevelName)
        .whereType<String>()
        .toSet()
        .toList();
    // Get unique teacher IDs for this subject
    final teacherIds = state.teacherAssignments
        .where((a) => a.subjectId == subject.id)
        .map((a) => a.teacherId)
        .toSet()
        .toList();
    // Resolve actual UserModel teachers (for avatar consistency)
    final teachers = teacherIds
        .map((id) => state.teachers.where((t) => t.id == id).firstOrNull)
        .whereType<UserModel>()
        .toList();
    final classCount = state.teacherAssignments
        .where((a) => a.subjectId == subject.id)
        .map((a) => a.className)
        .whereType<String>()
        .toSet()
        .length;
    final color = _getSubjectColor(subject.code);
    // Get exam types for this school
    final examTypes = state.examTypes;

    String _shortenNiveau(String name) {
      final lower = name.toLowerCase();
      if (lower.contains('6ème') || lower.contains('6')) return '6ème';
      if (lower.contains('5ème') || lower.contains('5')) return '5ème';
      if (lower.contains('4ème') || lower.contains('4')) return '4ème';
      if (lower.contains('3ème') || lower.contains('3')) return '3ème';
      if (lower.contains('2ème') || lower.contains('2')) return '2ème';
      if (lower.contains('1ère') || lower.contains('1')) return '1ère';
      if (lower.contains('terminal')) return 'Term.';
      if (name.length > 6) return '${name.substring(0, 5)}.';
      return name;
    }

    return InkWell(
      onTap: () => _showSubjectDetailOverlay(subject, state),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFECECF3)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF111827).withOpacity(0.06),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Code badge & Checkbox ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        subject.code ??
                            subject.name.substring(0, 2).toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: color,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _selectedSubjectIds.contains(subject.id),
                      activeColor: const Color(0xFF655DD5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      side: BorderSide(
                        color: Colors.grey.shade300,
                        width: 1.5,
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selectedSubjectIds.add(subject.id);
                          } else {
                            _selectedSubjectIds.remove(subject.id);
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // ── Subject name ──
              Text(
                subject.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 5),
              // ── Coef chip + category ──
              Row(
                children: [
                  Container(
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        'Coef. ${subject.defaultCoefficient?.toStringAsFixed(0) ?? '1'}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                  if (subject.category != null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        subject.category!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7280),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              // ── NIVEAUX ──
              const Row(
                children: [
                  Icon(
                    Icons.school_outlined,
                    size: 12,
                    color: Color(0xFF9CA3AF),
                  ),
                  SizedBox(width: 4),
                  Text(
                    'NIVEAUX',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9CA3AF),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              niveauNames.isEmpty
                  ? Container(
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F3F7),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: const Center(
                        widthFactor: 1,
                        child: Text(
                          'Tous niveaux',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ),
                    )
                  : Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        ...niveauNames
                            .take(3)
                            .map(
                              (n) => Container(
                                height: 20,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF2F3F7),
                                  borderRadius: BorderRadius.circular(9999),
                                ),
                                child: Center(
                                  widthFactor: 1,
                                  child: Text(
                                    _shortenNiveau(n),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        if (niveauNames.length > 3)
                          Container(
                            height: 20,
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF2F3F7),
                              borderRadius: BorderRadius.circular(9999),
                            ),
                            child: Center(
                              widthFactor: 1,
                              child: Text(
                                '+${niveauNames.length - 3}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
              const SizedBox(height: 10),
              // ── ENSEIGNANTS (using UserAvatar for consistency) ──
              Row(
                children: [
                  const Icon(
                    Icons.people_outline,
                    size: 12,
                    color: Color(0xFF9CA3AF),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'ENSEIGNANTS (${teachers.length})',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9CA3AF),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              if (teachers.isNotEmpty) ...[
                const SizedBox(height: 5),
                SizedBox(
                  height: 22,
                  child: Stack(
                    children: [
                      for (var ti = 0; ti < teachers.take(4).length; ti++)
                        Positioned(
                          left: ti * 14.0,
                          child: UserAvatar(
                            name: teachers[ti].fullName,
                            photoUrl: teachers[ti].photoUrl,
                            gender: teachers[ti].gender,
                            radius: 11,
                            borderColor: Colors.white,
                            borderWidth: 1.5,
                          ),
                        ),
                      if (teachers.length > 4)
                        Positioned(
                          left: 56,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFF2F3F7),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '+${teachers.length - 4}',
                                style: const TextStyle(
                                  fontSize: 7,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              // ── TYPES D'EXAMEN ──
              if (examTypes.isNotEmpty) ...[
                const Row(
                  children: [
                    Icon(
                      Icons.assignment_outlined,
                      size: 12,
                      color: Color(0xFF9CA3AF),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'TYPES D\'EXAMEN',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF9CA3AF),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    ...examTypes
                        .take(3)
                        .map(
                          (et) => Container(
                            height: 20,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF2F3F7),
                              borderRadius: BorderRadius.circular(9999),
                            ),
                            child: Center(
                              widthFactor: 1,
                              child: Text(
                                et.code,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF6B7280),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ),
                        ),
                    if (examTypes.length > 3)
                      Container(
                        height: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F3F7),
                          borderRadius: BorderRadius.circular(9999),
                        ),
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            '+${examTypes.length - 3}',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              const Spacer(),
              // ── Divider ──
              Container(height: 1, color: const Color(0xFFF1F2F6)),
              const SizedBox(height: 10),
              // ── Footer ──
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$classCount Classes affectées',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _showSubjectDialog(subject),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F3FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_outlined, size: 13, color: _brand),
                            SizedBox(width: 4),
                            Text(
                              'Modifier',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _brand,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddSubjectCard() {
    return InkWell(
      onTap: () => _showSubjectDialog(),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFE3E5EE),
            width: 2,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
          color: const Color(0xFFFAFAFB),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF3F4F6),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: const Icon(
                  Icons.add,
                  color: Color(0xFF9CA3AF),
                  size: 24,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Nouvelle Matière',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Ajouter une nouvelle matière\nau programme académique',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9CA3AF),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== ASSIGNMENTS TAB ====================
  Widget _buildAssignmentsTab(
    BuildContext context,
    SubjectsManagementState state,
  ) {
    final Map<String, List<SubjectAssignmentModel>> assignmentsByNiveau = {};
    for (final assignment in state.filteredAssignments) {
      final key = assignment.gradeLevelId;
      assignmentsByNiveau.putIfAbsent(key, () => []).add(assignment);
    }
    for (final list in assignmentsByNiveau.values) {
      switch (_sortKey) {
        case 'name_desc':
          list.sort((a, b) => (b.subjectName ?? '').toLowerCase().compareTo((a.subjectName ?? '').toLowerCase()));
          break;
        case 'coef_desc':
          list.sort((a, b) => b.coefficient.compareTo(a.coefficient));
          break;
        case 'coef_asc':
          list.sort((a, b) => a.coefficient.compareTo(b.coefficient));
          break;
        case 'code_asc':
          list.sort((a, b) => (a.subjectCode ?? '').compareTo(b.subjectCode ?? ''));
          break;
        case 'name_asc':
        default:
          list.sort((a, b) => (a.subjectName ?? '').toLowerCase().compareTo((b.subjectName ?? '').toLowerCase()));
          break;
      }
    }
    final hasSelection = _selectedAssignmentIds.isNotEmpty;
    final allExpanded = state.gradeLevels.every(
      (n) => _expandedNiveaux[n.id] == true,
    );

    return Container(
      color: const Color(0xFFF9FAFB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Minimal section header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 20),
            child: Row(
              children: [
                // Purple accent bar + title
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _brand,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Niveaux Académiques',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const Spacer(),
                // Selection actions (compact)
                if (hasSelection) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _brandLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_selectedAssignmentIds.length} sélectionné(s)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _brand,
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _showBulkEditDialog(state),
                          child: const Icon(
                            Icons.edit_outlined,
                            size: 15,
                            color: _brand,
                          ),
                        ),
                        const SizedBox(width: 5),
                        InkWell(
                          onTap: _confirmBulkDelete,
                          child: const Icon(
                            Icons.delete_outline,
                            size: 15,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                        const SizedBox(width: 5),
                        InkWell(
                          onTap: _clearSelection,
                          child: const Icon(
                            Icons.close,
                            size: 15,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                // Tout ouvrir / fermer
                InkWell(
                  onTap: () {
                    setState(() {
                      for (final n in state.gradeLevels) {
                        _expandedNiveaux[n.id] = !allExpanded;
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          allExpanded ? Icons.unfold_less : Icons.unfold_more,
                          size: 18,
                          color: _brand,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          allExpanded ? 'Tout fermer' : 'Tout ouvrir',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: _brand,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Accordion cards ──
          Expanded(
            child: state.filteredAssignments.isEmpty
                ? _buildEmptyState(
                    'Aucune affectation',
                    Icons.assignment_outlined,
                    () => _showAssignmentDialog(state),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                    itemCount: state.gradeLevels.length,
                    itemBuilder: (context, index) {
                      final niveau = state.gradeLevels[index];
                      final niveauAssignments =
                          assignmentsByNiveau[niveau.id] ?? [];
                      if (niveauAssignments.isEmpty &&
                          state.filterGradeId != null)
                        return const SizedBox.shrink();
                      return _buildNiveauCard(niveau, niveauAssignments, state);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── Accordion-style niveau card (matches reference design) ──
  Widget _buildNiveauCard(
    GradeLevelModel niveau,
    List<SubjectAssignmentModel> assignments,
    SubjectsManagementState state,
  ) {
    final isExpanded = _expandedNiveaux[niveau.id] ?? false;
    final niveauColor = _getNiveauColor(niveau.code);

    // Cycle label
    String cycleLabel = niveau.levelTypeLabel;
    final codeUp = niveau.code.toUpperCase();
    if (codeUp.contains('3')) {
      cycleLabel = "Cycle d'orientation";
    } else if (codeUp.contains('4') || codeUp.contains('5')) {
      cycleLabel = 'Cycle central';
    } else if (codeUp.contains('6')) {
      cycleLabel = "Cycle d'adaptation";
    }

    final hasSections = niveau.sections.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF3F4F6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ── Card header ──
          InkWell(
            onTap: () =>
                setState(() => _expandedNiveaux[niveau.id] = !isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  // Badge with count indicator
                  SizedBox(
                    width: 48,
                    height: 42,
                    child: Stack(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: niveauColor.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: niveauColor.withOpacity(0.12),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              niveau.code,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: niveauColor,
                              ),
                            ),
                          ),
                        ),
                        // Matières count bubble
                        if (assignments.isNotEmpty)
                          Positioned(
                            right: 0,
                            top: -2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              constraints: const BoxConstraints(minWidth: 18),
                              decoration: BoxDecoration(
                                color: niveauColor.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '${assignments.length}',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Niveau ${niveau.code}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          cycleLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Material(
                    color: _brand.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showAssignmentDialog(state),
                      hoverColor: _brand.withOpacity(0.14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add, size: 16, color: _brand),
                            const SizedBox(width: 6),
                            Text(
                              'Assigner une matière',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _brand,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      size: 22,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Expanded content ──
          if (isExpanded)
            hasSections
                // ── Niveau WITH sections: show section sub-accordions ──
                ? _buildSectionsList(niveau, assignments, state)
                // ── Niveau WITHOUT sections: show subjects table directly ──
                : _buildSubjectsTable(assignments, niveau, state),
        ],
      ),
    );
  }

  // ── Section sub-accordions inside a niveau ──
  Widget _buildSectionsList(
    GradeLevelModel niveau,
    List<SubjectAssignmentModel> allAssignments,
    SubjectsManagementState state,
  ) {
    // Group assignments by sectionId; null-section = shared/common
    final Map<String?, List<SubjectAssignmentModel>> bySectionId = {};
    for (final a in allAssignments) {
      bySectionId.putIfAbsent(a.sectionId, () => []).add(a);
    }

    // Common subjects (no section)
    final commonAssignments = bySectionId[null] ?? [];

    return Column(
      children: [
        // Show common subjects first (if any)
        if (commonAssignments.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
              color: Color(0xFFFAFAFB),
            ),
            child: Row(
              children: [
                Icon(Icons.public, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 8),
                Text(
                  'Tronc commun • ${commonAssignments.length} matières',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
          _buildSubjectsTable(commonAssignments, niveau, state),
        ],
        // Each section
        ...niveau.sections.map((section) {
          final sectionAssignments = bySectionId[section.id] ?? [];
          final sectionKey = '${niveau.id}_${section.id}';
          final isSectionExpanded = _expandedSections[sectionKey] ?? false;

          return Column(
            children: [
              // Section header
              InkWell(
                onTap: () => setState(
                  () => _expandedSections[sectionKey] = !isSectionExpanded,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _brand.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          section.code,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _brand,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: section.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF374151),
                                ),
                              ),
                              TextSpan(
                                text:
                                    ' • ${sectionAssignments.length} matières',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFFB0B7C3),
                                ),
                              ),
                            ],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      AnimatedRotation(
                        turns: isSectionExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.expand_more,
                          size: 20,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Section expanded table
              if (isSectionExpanded)
                sectionAssignments.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Aucune matière assignée à cette filière',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : _buildSubjectsTable(sectionAssignments, niveau, state),
            ],
          );
        }),
      ],
    );
  }

  // ── Reusable subjects table (header + rows) ──
  Widget _buildSubjectsTable(
    List<SubjectAssignmentModel> assignments,
    GradeLevelModel niveau,
    SubjectsManagementState state,
  ) {
    if (assignments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.inbox_outlined, size: 36, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Text(
                'Aucune affectation pour ce niveau',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        // Column headers
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Color(0xFFF3F4F6)),
              bottom: BorderSide(color: Color(0xFFF3F4F6)),
            ),
          ),
          child: const Row(
            children: [
              Expanded(
                flex: 4,
                child: Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Text(
                    'MATIÈRE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFBFC5D2),
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 90,
                child: Text(
                  'COEF.',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFBFC5D2),
                    letterSpacing: 0.6,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  'H/SEM',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFBFC5D2),
                    letterSpacing: 0.6,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'ENSEIGNANTS',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFBFC5D2),
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              SizedBox(width: 44, child: SizedBox()),
            ],
          ),
        ),
        // Rows
        ...assignments.map((a) => _buildModernAssignmentRow(a, niveau, state)),
      ],
    );
  }

  // ── Compact assignment row matching reference design ──
  Widget _buildModernAssignmentRow(
    SubjectAssignmentModel assignment,
    GradeLevelModel niveau,
    SubjectsManagementState state,
  ) {
    final color = _getSubjectColor(assignment.subjectCode);

    // Get teachers for this subject in this niveau
    // Strategy: match subject first, then check niveau via multiple paths
    final rowTeachers = state.teacherAssignments
        .where((t) {
          if (t.subjectId != assignment.subjectId) return false;
          // 1) Direct niveauId match
          if (t.niveauId != null && t.niveauId == assignment.gradeLevelId)
            return true;
          // 2) classId → lookup class → gradeLevelId match
          if (t.classId != null) {
            final cls = state.classes
                .where((c) => c.id == t.classId)
                .firstOrNull;
            if (cls != null && cls.gradeLevelId == assignment.gradeLevelId)
              return true;
          }
          // 3) If teacher has neither niveauId nor classId, they teach the subject globally
          if (t.niveauId == null && t.classId == null) return true;
          return false;
        })
        .map((t) => t.teacherName)
        .whereType<String>()
        .toSet()
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          // ── Subject badge + name ──
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      assignment.subjectCode ?? '?',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    assignment.subjectName ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF374151),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // ── Coefficient pill ──
          SizedBox(
            width: 90,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Coef. ${assignment.coefficient.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
            ),
          ),
          // ── Weekly hours ──
          SizedBox(
            width: 70,
            child: Center(
              child: Text(
                assignment.weeklyHours > 0
                    ? '${assignment.weeklyHours.toStringAsFixed(assignment.weeklyHours.truncateToDouble() == assignment.weeklyHours ? 0 : 1)}h'
                    : '—',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ),
          ),
          // ── Teachers avatars only ──
          Expanded(
            flex: 3,
            child: rowTeachers.isEmpty
                ? Text(
                    '—',
                    style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
                  )
                : SizedBox(
                    width: (rowTeachers.take(3).length - 1) * 18.0 + 28,
                    height: 28,
                    child: Stack(
                      children: [
                        for (var ti = 0; ti < rowTeachers.take(3).length; ti++)
                          Positioned(
                            left: ti * 18.0,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: [
                                  const Color(0xFFEDE9FE),
                                  const Color(0xFFDBEAFE),
                                  const Color(0xFFFEF3C7),
                                ][ti % 3],
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  _getInitials(rowTeachers[ti]),
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: [
                                      const Color(0xFF6D28D9),
                                      const Color(0xFF2563EB),
                                      const Color(0xFFB45309),
                                    ][ti % 3],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          // ── Actions (ellipsis menu) ──
          SizedBox(
            width: 44,
            child: Align(
              alignment: Alignment.centerRight,
              child: PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_horiz,
                  size: 18,
                  color: Colors.grey.shade300,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                onSelected: (value) {
                  if (value == 'edit') {
                    _showAssignmentDialog(state, assignment);
                  } else if (value == 'delete') {
                    _confirmDeleteAssignment(assignment);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: Color(0xFF6B7280),
                        ),
                        SizedBox(width: 8),
                        Text('Modifier', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: Color(0xFFDC2626),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Supprimer',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFFDC2626),
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
    );
  }

  Widget _buildEmptyState(String message, IconData icon, VoidCallback onAdd) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SUBJECT DETAIL FLOATING OVERLAY — pixel-match mockup
  // ═══════════════════════════════════════════════════════════════
  void _showSubjectDetailOverlay(
    SubjectModel subject,
    SubjectsManagementState state,
  ) {
    final color = _getSubjectColor(subject.code);

    // ── Gather data ──
    final assignments = state.assignments
        .where((a) => a.subjectId == subject.id)
        .toList();
    final teacherIds = state.teacherAssignments
        .where((a) => a.subjectId == subject.id)
        .map((a) => a.teacherId)
        .toSet()
        .toList();
    final teachers = teacherIds
        .map((id) => state.teachers.where((t) => t.id == id).firstOrNull)
        .whereType<UserModel>()
        .toList();
    final classCount = state.teacherAssignments
        .where((a) => a.subjectId == subject.id)
        .map((a) => a.className)
        .whereType<String>()
        .toSet()
        .length;
    final totalHours = assignments.fold<double>(
      0,
      (sum, a) => sum + a.weeklyHours,
    );
    final examTypes = state.examTypes;

    final filterController = TextEditingController();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 350),
      transitionBuilder: (ctx, a1, a2, child) {
        final curve = CurvedAnimation(parent: a1, curve: Curves.easeOutCubic);
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6 * a1.value, sigmaY: 6 * a1.value),
          child: FadeTransition(
            opacity: curve,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(curve),
              child: child,
            ),
          ),
        );
      },
      pageBuilder: (ctx, _, __) {
        final Set<String> selectedDetailIds = {};
        int detailCurrentPage = 1;
        int detailItemsPerPage = 10;
        final detailPerPageOptions = [5, 10, 20, 50, -1];
        return StatefulBuilder(
          builder: (ctx, setDetailState) {
            final _ft = filterController.text.toLowerCase();
            final filtered = _ft.isEmpty
                ? assignments
                : assignments
                      .where(
                        (a) =>
                            (a.gradeLevelName ?? '').toLowerCase().contains(
                              _ft,
                            ) ||
                            (a.sectionName ?? '').toLowerCase().contains(_ft),
                      )
                      .toList();
            final totalFilteredItems = filtered.length;
            final totalPages = detailItemsPerPage == -1
                ? 1
                : (totalFilteredItems / detailItemsPerPage).ceil().clamp(1, 99999);
            if (detailCurrentPage > totalPages) detailCurrentPage = totalPages;
            final pagedAssignments = detailItemsPerPage == -1
                ? filtered
                : filtered.skip((detailCurrentPage - 1) * detailItemsPerPage).take(detailItemsPerPage).toList();
            return Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(ctx).size.width * 0.82,
                  constraints: BoxConstraints(
                    maxWidth: 1060,
                    maxHeight: MediaQuery.of(ctx).size.height * 0.90,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF111827).withOpacity(0.12),
                        blurRadius: 48,
                        offset: const Offset(0, 16),
                      ),
                      BoxShadow(
                        color: color.withOpacity(0.06),
                        blurRadius: 80,
                        offset: const Offset(0, -8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      children: [
                        Column(
                          children: [
                        // ══════════════════════════════════════
                        // HEADER — matches pic 1 exactly
                        // ══════════════════════════════════════
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(28, 24, 24, 22),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              bottom: BorderSide(color: Color(0xFFF0F0F5)),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Subject code badge (big, like mockup)
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Center(
                                  child: Text(
                                    subject.code ??
                                        subject.name
                                            .substring(0, 2)
                                            .toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: color,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Title + description
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      subject.name,
                                      style: const TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF111827),
                                        height: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: subject.isActive
                                            ? const Color(0xFFDCFCE7)
                                            : const Color(0xFFFEE2E2),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        subject.isActive
                                            ? 'ACTIF'
                                            : 'INACTIF',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: subject.isActive
                                              ? const Color(0xFF166534)
                                              : const Color(0xFF991B1B),
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ),
                                    if (subject.description != null &&
                                        subject.description!.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        subject.description!,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          color: Color(0xFF9CA3AF),
                                          height: 1.4,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Actions: Modifier (primary) + X
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Modifier primary button
                                  InkWell(
                                    onTap: () {
                                      Navigator.of(ctx).pop();
                                      _showSubjectDialog(subject);
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 9,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _brand,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.edit_outlined,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            'Modifier',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  // X close
                                  InkWell(
                                    onTap: () => Navigator.of(ctx).pop(),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF3F4F6),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.close,
                                          size: 16,
                                          color: Color(0xFF6B7280),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // ══════════════════════════════════════
                        // BODY — two columns
                        // ══════════════════════════════════════
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ────────────────────────────────
                                // LEFT COLUMN (fixed 260)
                                // ────────────────────────────────
                                SizedBox(
                                  width: 260,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // ── APERÇU STATISTIQUE title ──
                                      _overlayLeftTitle(
                                        Icons.bar_chart_rounded,
                                        'APERÇU STATISTIQUE',
                                      ),
                                      const SizedBox(height: 14),

                                      // ── TOTAL CLASSES ──
                                      _overlayStatCard(
                                        label: 'TOTAL CLASSES',
                                        value: '$classCount',
                                        icon: Icons.class_outlined,
                                        iconColor: const Color(0xFF2563EB),
                                      ),
                                      const SizedBox(height: 10),

                                      // ── HEURES / SEMAINE ──
                                      _overlayStatCard(
                                        label: 'HEURES / SEMAINE',
                                        value: totalHours > 0
                                            ? '${totalHours.toStringAsFixed(0)}h'
                                            : '—',
                                        icon: Icons.schedule_outlined,
                                        iconColor: const Color(0xFF059669),
                                      ),
                                      const SizedBox(height: 10),

                                      // ── PROFESSEURS ──
                                      _overlayStatCard(
                                        label: 'PROFESSEURS',
                                        value: '${teachers.length}',
                                        icon: Icons.people_outline,
                                        iconColor: const Color(0xFFF97316),
                                      ),

                                      const SizedBox(height: 28),

                                      // ── TYPES D'EXAMENS ──
                                      _overlayLeftTitle(
                                        Icons.assignment_outlined,
                                        'TYPES D\'EXAMENS',
                                      ),
                                      const SizedBox(height: 12),
                                      if (examTypes.isEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 2,
                                          ),
                                          child: Text(
                                            'Aucun type configuré',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade400,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        )
                                      else
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: examTypes
                                              .map(
                                                (et) => Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFF0ECFE,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    '${et.name} (${et.code})',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Color(0xFF5B21B6),
                                                    ),
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                        ),

                                      const SizedBox(height: 28),

                                      // ── ENSEIGNANTS ──
                                      _overlayLeftTitle(
                                        Icons.people_outline,
                                        'ENSEIGNANTS',
                                      ),
                                      const SizedBox(height: 14),
                                      if (teachers.isEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 2,
                                          ),
                                          child: Text(
                                            'Aucun enseignant affecté',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade400,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        )
                                      else
                                        Wrap(
                                          spacing: 12,
                                          runSpacing: 14,
                                          children: teachers.map((t) {
                                            return SizedBox(
                                              width: 110,
                                              child: Row(
                                                children: [
                                                  UserAvatar(
                                                    name: t.fullName,
                                                    photoUrl: t.photoUrl,
                                                    gender: t.gender,
                                                    radius: 18,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          _shortName(
                                                            t.fullName,
                                                          ),
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: Color(
                                                                  0xFF111827,
                                                                ),
                                                              ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                        Text(
                                                          'Titulaire',
                                                          style: TextStyle(
                                                            fontSize: 9.5,
                                                            color: Colors
                                                                .grey
                                                                .shade400,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                    ],
                                  ),
                                ),

                                const SizedBox(width: 28),

                                // ────────────────────────────────
                                // RIGHT COLUMN (flex)
                                // ────────────────────────────────
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // "AFFECTATIONS DÉTAILLÉES" + Filter
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.grid_view_rounded,
                                            size: 15,
                                            color: Color(0xFF6B7280),
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'AFFECTATIONS DÉTAILLÉES',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF6B7280),
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          const Spacer(),
                                          // Filter input
                                          SizedBox(
                                            width: 200,
                                            height: 34,
                                            child: TextField(
                                              controller: filterController,
                                              onChanged: (_) =>
                                                  setDetailState(() {}),
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: 'Filtrer...',
                                                hintStyle: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFFD1D5DB),
                                                ),
                                                prefixIcon: const Icon(
                                                  Icons.search,
                                                  size: 14,
                                                  color: Color(0xFF9CA3AF),
                                                ),
                                                prefixIconConstraints:
                                                    const BoxConstraints(
                                                      minWidth: 32,
                                                      minHeight: 32,
                                                    ),
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 8,
                                                    ),
                                                filled: true,
                                                fillColor: const Color(
                                                  0xFFF9FAFB,
                                                ),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  borderSide: const BorderSide(
                                                    color: Color(0xFFE5E7EB),
                                                  ),
                                                ),
                                                enabledBorder:
                                                    OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      borderSide:
                                                          const BorderSide(
                                                            color: Color(
                                                              0xFFE5E7EB,
                                                            ),
                                                          ),
                                                    ),
                                                focusedBorder:
                                                    OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      borderSide:
                                                          const BorderSide(
                                                            color: Color(
                                                              0xFF6D4CF6,
                                                            ),
                                                            width: 1.5,
                                                          ),
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),

                                      // ── Table container ──
                                      if (filtered.isEmpty)
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 48,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF9FAFB),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFE5E7EB),
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Icon(
                                                Icons.assignment_outlined,
                                                size: 32,
                                                color: Colors.grey.shade300,
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Aucune affectation',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey.shade400,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      else
                                        Container(
                                          width: double.infinity,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(color: const Color(0xFFE5E7EB)),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: Column(
                                            children: [
                                              LayoutBuilder(
                                                builder: (context, constraints) {
                                                  final availableW = constraints.maxWidth;
                                                  final sectionW = (availableW - 394).clamp(180.0, 9999.0);
                                                  final totalW = 44.0 + 110.0 + sectionW + 110.0 + 130.0;
                                                  return SingleChildScrollView(
                                                    scrollDirection: Axis.horizontal,
                                                    child: SizedBox(
                                                      width: totalW,
                                                      child: DataTable(
                                                        columnSpacing: 0,
                                                        horizontalMargin: 0,
                                                        dataRowMinHeight: 52,
                                                        dataRowMaxHeight: 56,
                                                        headingRowHeight: 44,
                                                        headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
                                                        headingTextStyle: const TextStyle(
                                                          fontWeight: FontWeight.w600,
                                                          color: Color(0xFF94A3B8),
                                                          fontSize: 11,
                                                          letterSpacing: 0.5,
                                                        ),
                                                        showCheckboxColumn: false,
                                                        columns: [
                                                          DataColumn(
                                                            label: SizedBox(
                                                              width: 44,
                                                              child: Center(
                                                                child: SizedBox(
                                                                  width: 16,
                                                                  height: 16,
                                                                  child: Checkbox(
                                                                    value: pagedAssignments.isNotEmpty && pagedAssignments.every((a) => selectedDetailIds.contains(a.id)),
                                                                    activeColor: const Color(0xFF655DD5),
                                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                                                                    side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
                                                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                                    onChanged: (v) {
                                                                      setDetailState(() {
                                                                        final allSel = pagedAssignments.isNotEmpty && pagedAssignments.every((a) => selectedDetailIds.contains(a.id));
                                                                        if (allSel) {
                                                                          for (final a in pagedAssignments) selectedDetailIds.remove(a.id);
                                                                        } else {
                                                                          for (final a in pagedAssignments) selectedDetailIds.add(a.id);
                                                                        }
                                                                      });
                                                                    },
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          const DataColumn(label: SizedBox(width: 110, child: Text('NIVEAU', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF94A3B8), fontSize: 11, letterSpacing: 0.5)))),
                                                          DataColumn(label: SizedBox(width: sectionW, child: const Text('FILIÈRE / SECTION', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF94A3B8), fontSize: 11, letterSpacing: 0.5)))),
                                                          const DataColumn(label: SizedBox(width: 110, child: Text('COEFFICIENT', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF94A3B8), fontSize: 11, letterSpacing: 0.5)))),
                                                          const DataColumn(label: SizedBox(width: 130, child: Text('HEURES / SEMAINE', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF94A3B8), fontSize: 11, letterSpacing: 0.5)))),
                                                        ],
                                                        rows: pagedAssignments.map((a) {
                                                          final isSelected = selectedDetailIds.contains(a.id);
                                                          return DataRow(
                                                            color: WidgetStateProperty.resolveWith<Color?>((states) {
                                                              if (isSelected) return const Color(0xFFF5F3FF).withOpacity(0.5);
                                                              if (states.contains(WidgetState.hovered)) return const Color(0xFFF9FAFB);
                                                              return null;
                                                            }),
                                                            cells: [
                                                              DataCell(
                                                                SizedBox(
                                                                  width: 44,
                                                                  child: Center(
                                                                    child: SizedBox(
                                                                      width: 16,
                                                                      height: 16,
                                                                      child: Checkbox(
                                                                        value: isSelected,
                                                                        activeColor: const Color(0xFF655DD5),
                                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                                                                        side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
                                                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                                        onChanged: (v) {
                                                                          setDetailState(() {
                                                                            if (v == true) {
                                                                              selectedDetailIds.add(a.id);
                                                                            } else {
                                                                              selectedDetailIds.remove(a.id);
                                                                            }
                                                                          });
                                                                        },
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                              DataCell(
                                                                SizedBox(
                                                                  width: 110,
                                                                  child: Align(
                                                                    alignment: Alignment.centerLeft,
                                                                    child: Container(
                                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                                      decoration: BoxDecoration(
                                                                        color: const Color(0xFFF0F0F5),
                                                                        borderRadius: BorderRadius.circular(8),
                                                                      ),
                                                                      child: Text(
                                                                        _shortNiveau(a.gradeLevelName ?? '—'),
                                                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                              DataCell(
                                                                SizedBox(
                                                                  width: sectionW,
                                                                  child: Text(
                                                                    a.sectionName ?? 'Tronc Commun',
                                                                    style: TextStyle(
                                                                      fontSize: 12.5,
                                                                      fontWeight: FontWeight.w400,
                                                                      color: a.sectionName != null ? const Color(0xFF374151) : const Color(0xFF9CA3AF),
                                                                    ),
                                                                    overflow: TextOverflow.ellipsis,
                                                                  ),
                                                                ),
                                                              ),
                                                              DataCell(
                                                                SizedBox(
                                                                  width: 110,
                                                                  child: Row(
                                                                    children: [
                                                                      Container(
                                                                        width: 26,
                                                                        height: 26,
                                                                        decoration: BoxDecoration(
                                                                          shape: BoxShape.circle,
                                                                          color: _brand.withOpacity(0.10),
                                                                        ),
                                                                        child: Center(
                                                                          child: Text(
                                                                            a.coefficient.toStringAsFixed(0),
                                                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _brand),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ),
                                                              DataCell(
                                                                SizedBox(
                                                                  width: 130,
                                                                  child: Text(
                                                                    a.weeklyHours > 0 ? '${a.weeklyHours}h / sem' : '—',
                                                                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          );
                                                        }).toList(),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                              // ── Users table style bottom pagination footer ──
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFFFAFAFB),
                                                  border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Text('Afficher par ', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white,
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(color: const Color(0xFFE5E7EB)),
                                                      ),
                                                      child: DropdownButtonHideUnderline(
                                                        child: DropdownButton<int>(
                                                          value: detailItemsPerPage,
                                                          isDense: true,
                                                          borderRadius: BorderRadius.circular(10),
                                                          dropdownColor: Colors.white,
                                                          elevation: 4,
                                                          menuMaxHeight: 200,
                                                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: Color(0xFF6B7280)),
                                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                                                          items: detailPerPageOptions.map((v) => DropdownMenuItem(
                                                            value: v,
                                                            child: Text(v == -1 ? 'Tous' : '$v', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                                                          )).toList(),
                                                          onChanged: (v) => setDetailState(() {
                                                            detailItemsPerPage = v!;
                                                            detailCurrentPage = 1;
                                                         }),
                                                        ),
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    Text(
                                                      'Page $detailCurrentPage sur ${totalPages == 0 ? 1 : totalPages}',
                                                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Container(
                                                      decoration: BoxDecoration(
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: const Color(0xFFE5E7EB)),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          InkWell(
                                                            onTap: detailCurrentPage > 1 ? () => setDetailState(() => detailCurrentPage--) : null,
                                                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(5)),
                                                            child: Padding(
                                                              padding: const EdgeInsets.all(4),
                                                              child: Icon(Icons.chevron_left, size: 18, color: detailCurrentPage > 1 ? const Color(0xFF374151) : const Color(0xFF9CA3AF)),
                                                            ),
                                                          ),
                                                          Container(width: 1, height: 24, color: const Color(0xFFE5E7EB)),
                                                          InkWell(
                                                            onTap: detailCurrentPage < totalPages ? () => setDetailState(() => detailCurrentPage++) : null,
                                                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(5)),
                                                            child: Padding(
                                                              padding: const EdgeInsets.all(4),
                                                              child: Icon(Icons.chevron_right, size: 18, color: detailCurrentPage < totalPages ? const Color(0xFF374151) : const Color(0xFF9CA3AF)),
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
                    // Floating bottom black tool box for detail assignments
                    if (selectedDetailIds.isNotEmpty)
                      Positioned(
                        bottom: 24,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Material(
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
                                      border: Border(
                                        right: BorderSide(color: Colors.white.withOpacity(0.15)),
                                      ),
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
                                              '${selectedDetailIds.length}',
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
                                          'Sélectionnées',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Delete Action
                                  _buildSelectionAction(
                                    Icons.delete_outline,
                                    'Supprimer',
                                    const Color(0xFFFCA5A5),
                                    () async {
                                      final confirm = await showDialog<bool>(
                                        context: ctx,
                                        builder: (dCtx) => BackdropFilter(
                                          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                                          child: AlertDialog(
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            title: Row(
                                              children: [
                                                Container(
                                                  width: 36,
                                                  height: 36,
                                                  decoration: BoxDecoration(
                                                    color: AppColors.errorSoft,
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  'Supprimer ${selectedDetailIds.length} affectation${selectedDetailIds.length > 1 ? 's' : ''} ?',
                                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                                ),
                                              ],
                                            ),
                                            content: Text(
                                              'Cette action est irréversible. ${selectedDetailIds.length} affectation${selectedDetailIds.length > 1 ? 's seront supprimées' : ' sera supprimée'} définitivement.',
                                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                            ),
                                            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                                            actions: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.end,
                                                children: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(dCtx, false),
                                                    style: TextButton.styleFrom(
                                                      foregroundColor: const Color(0xFF6B7280),
                                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                                    ),
                                                    child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  ElevatedButton.icon(
                                                    onPressed: () => Navigator.pop(dCtx, true),
                                                    icon: const Icon(Icons.delete_outline, size: 16),
                                                    label: Text(
                                                      'Supprimer ${selectedDetailIds.length}',
                                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                                    ),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: AppColors.error,
                                                      foregroundColor: Colors.white,
                                                      elevation: 0,
                                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                      if (confirm == true) {
                                        for (final aid in selectedDetailIds.toList()) {
                                          await ref.read(subjectsManagementProvider.notifier).deleteAssignment(aid);
                                        }
                                        setDetailState(() => selectedDetailIds.clear());
                                      }
                                    },
                                  ),
                                  // Close button
                                  Container(
                                    margin: const EdgeInsets.only(left: 4),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        left: BorderSide(color: Colors.white.withOpacity(0.15)),
                                      ),
                                    ),
                                    child: IconButton(
                                      icon: const Icon(Icons.close, size: 16, color: Colors.white60),
                                      onPressed: () => setDetailState(() => selectedDetailIds.clear()),
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Overlay helper: section title in left column ──
  Widget _overlayLeftTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF9CA3AF)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF9CA3AF),
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }

  // ── Overlay helper: stat card (styled like dashboard header cards) ──
  Widget _overlayStatCard({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Icon(icon, size: 14, color: iconColor),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.arrow_outward_rounded,
                size: 12,
                color: Color(0xFFCBD5E1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
              letterSpacing: -0.4,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Overlay helper: short name (e.g. "M. Dubois") ──
  String _shortName(String fullName) {
    final parts = fullName.trim().split(' ');
    if (parts.length <= 1) return fullName;
    final first = parts.first;
    final last = parts.last;
    // If "M." or "Mme." prefix, keep it
    final prefixes = ['M.', 'Mme.', 'Mme', 'Mr', 'Dr', 'Pr'];
    if (prefixes.contains(first)) {
      return '$first $last';
    }
    return 'M. $last';
  }

  // ── Overlay helper: short niveau name for table pill ──
  String _shortNiveau(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('6') &&
        (lower.contains('ème') ||
            lower.contains('am') ||
            lower.contains('eme')))
      return '6ème';
    if (lower.contains('5') &&
        (lower.contains('ème') ||
            lower.contains('am') ||
            lower.contains('eme')))
      return '5ème';
    if (lower.contains('4') &&
        (lower.contains('ème') ||
            lower.contains('am') ||
            lower.contains('eme')))
      return '4ème';
    if (lower.contains('3') &&
        (lower.contains('ème') ||
            lower.contains('am') ||
            lower.contains('eme')))
      return '3ème';
    if (lower.contains('2') &&
        (lower.contains('ème') ||
            lower.contains('as') ||
            lower.contains('eme')))
      return '2ème';
    if (lower.contains('1') &&
        (lower.contains('ère') ||
            lower.contains('as') ||
            lower.contains('ere')))
      return '1ère';
    if (lower.contains('terminal')) return 'Term.';
    if (name.length > 6) return '${name.substring(0, 5)}.';
    return name;
  }

  void _showSubjectDialog([SubjectModel? subject]) {
    final nameCtrl = TextEditingController(text: subject?.name);
    final codeCtrl = TextEditingController(text: subject?.code);
    final descCtrl = TextEditingController(text: subject?.description);
    String selectedCategory = subject?.category ?? 'Fondamental';
    double coefficient = subject?.defaultCoefficient ?? 1.0;
    final Set<String> selectedNiveauIds = {};
    final Map<String, Set<String>> selectedSectionIdsByNiveau = {};
    final Set<String> selectedTeacherIds = {};
    final Set<String> selectedExamTypeIds = {};

    // Pre-select niveaux from existing assignments
    if (subject != null) {
      final stateAsync = ref.read(subjectsManagementProvider);
      stateAsync.whenData((state) {
        final subjectAssignments = state.assignments.where(
          (a) => a.subjectId == subject.id,
        );
        for (final a in subjectAssignments) {
          selectedNiveauIds.add(a.gradeLevelId);
          if (a.sectionId != null) {
            selectedSectionIdsByNiveau.putIfAbsent(a.gradeLevelId, () => {});
            selectedSectionIdsByNiveau[a.gradeLevelId]!.add(a.sectionId!);
          }
        }
        // Pre-select teachers
        final teacherAssignments = state.teacherAssignments.where(
          (ta) => ta.subjectId == subject.id,
        );
        for (final ta in teacherAssignments) {
          selectedTeacherIds.add(ta.teacherId);
        }
      });
    }

    final categories = [
      'Fondamental',
      'Scientifique',
      'Littéraire',
      'Artistique',
      'Sportif',
      'Technique',
      'sciences',
      'humanities',
      'arts',
      'languages',
      'technical',
      'sports',
    ];
    // Ensure the subject's existing category is in the list
    if (selectedCategory.isNotEmpty && !categories.contains(selectedCategory)) {
      categories.add(selectedCategory);
    }

    // Auto-generate code when name changes (only for new subjects)
    nameCtrl.addListener(() {
      if (subject == null && nameCtrl.text.isNotEmpty) {
        final generatedCode = ref
            .read(subjectsManagementProvider.notifier)
            .generateSubjectCode(nameCtrl.text);
        codeCtrl.text = generatedCode;
      }
    });

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: StatefulBuilder(
          builder: (ctx, setDialogState) {
            // Fetch data from provider
            final stateAsync = ref.read(subjectsManagementProvider);
            final gradeLevels = stateAsync.value?.gradeLevels ?? [];
            final allTeachersUnfiltered =
                stateAsync.value?.teachers
                    .where((t) => t.role == 'teacher' && t.isActive)
                    .toList() ??
                [];
            final teacherAssignments = stateAsync.value?.teacherAssignments ?? [];
            final allExamTypes = stateAsync.value?.examTypes ?? [];

            // Filter teachers by subject speciality
            final currentSubjectName = (subject?.name ?? nameCtrl.text).toLowerCase();
            final teacherIdsForSubject = teacherAssignments
                .where((ta) {
                  final taSubjectName = (ta.subjectName ?? '').toLowerCase();
                  return taSubjectName == currentSubjectName ||
                      currentSubjectName.contains(taSubjectName) ||
                      taSubjectName.contains(currentSubjectName);
                })
                .map((ta) => ta.teacherId)
                .toSet();

            // If no matching assignments found (new subject or no assignments yet), show all teachers
            final allTeachers = teacherIdsForSubject.isEmpty
                ? allTeachersUnfiltered
                : allTeachersUnfiltered.where((t) => teacherIdsForSubject.contains(t.id)).toList();

            return Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 680,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 40,
                        offset: const Offset(0, 20),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Header ──
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 24,
                            ),
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Color(0xFFF3F4F6)),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF5F3FF),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.menu_book_rounded,
                                    color: _brand,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        subject == null
                                            ? 'Nouvelle Matière'
                                            : 'Modifier Matière',
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF111827),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Configurez les paramètres académiques et pédagogiques de la matière.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                InkWell(
                                  onTap: () => Navigator.pop(ctx),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF3F4F6),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.close,
                                      size: 18,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // ── Scrollable Content ──
                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // ── Section: Informations Générales ──
                                  _buildSectionTitle('Informations Générales'),
                                  const SizedBox(height: 16),

                                  // Nom
                                  _buildFieldLabel('Nom de la matière'),
                                  const SizedBox(height: 8),
                                  _buildTextField(
                                    nameCtrl,
                                    'Ex: Mathématiques Avancées',
                                  ),
                                  const SizedBox(height: 20),

                                  // Code + Category side by side
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _buildFieldLabel(
                                              'Code matière (Abréviation)',
                                            ),
                                            const SizedBox(height: 8),
                                            _buildTextField(
                                              codeCtrl,
                                              'EX: MATH-AV',
                                              isUppercase: true,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 24),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _buildFieldLabel('Catégorie'),
                                            const SizedBox(height: 8),
                                            Container(
                                              height: 44,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF9FAFB),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: const Color(
                                                    0xFFE5E7EB,
                                                  ),
                                                ),
                                              ),
                                              child: DropdownButtonHideUnderline(
                                                child: DropdownButton<String>(
                                                  value: selectedCategory,
                                                  isExpanded: true,
                                                  borderRadius: BorderRadius.circular(12),
                                                  icon: Icon(
                                                    Icons
                                                        .keyboard_arrow_down_rounded,
                                                    color: Colors.grey.shade400,
                                                    size: 20,
                                                  ),
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    color: Color(0xFF111827),
                                                  ),
                                                  items: categories
                                                      .map(
                                                        (c) => DropdownMenuItem(
                                                          value: c,
                                                          child: Text(c),
                                                        ),
                                                      )
                                                      .toList(),
                                                  onChanged: (v) =>
                                                      setDialogState(
                                                        () => selectedCategory =
                                                            v!,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),

                                  // Description
                                  _buildFieldLabel('Description (Optionnel)'),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: descCtrl,
                                    maxLines: 2,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF111827),
                                    ),
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: const Color(0xFFF9FAFB),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: Color(0xFFE5E7EB),
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: Color(0xFFE5E7EB),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: _brand,
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 32),
                                  Container(
                                    height: 1,
                                    color: const Color(0xFFF3F4F6),
                                  ),
                                  const SizedBox(height: 32),

                                  // ── Section: Configuration Académique ──
                                  _buildSectionTitle(
                                    'Configuration Académique',
                                  ),
                                  const SizedBox(height: 20),

                                  // ── Coefficient par Niveau (full-width card) ──
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF9FAFB),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFE5E7EB),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: _brandLight,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.tune_rounded,
                                            size: 18,
                                            color: _brand,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Coefficient par Niveau',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF111827),
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Valeur appliquée par défaut aux niveaux sélectionnés.',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade400,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        // Stepper
                                        Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFE5E7EB),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              InkWell(
                                                onTap: () => setDialogState(() {
                                                  if (coefficient > 0.5)
                                                    coefficient =
                                                        (coefficient * 2 - 1)
                                                            .round() /
                                                        2;
                                                }),
                                                borderRadius:
                                                    const BorderRadius.horizontal(
                                                      left: Radius.circular(10),
                                                    ),
                                                child: Container(
                                                  width: 36,
                                                  height: 38,
                                                  alignment: Alignment.center,
                                                  decoration:
                                                      const BoxDecoration(
                                                        border: Border(
                                                          right: BorderSide(
                                                            color: Color(
                                                              0xFFE5E7EB,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                  child: Icon(
                                                    Icons.remove,
                                                    size: 16,
                                                    color: coefficient > 0.5
                                                        ? const Color(
                                                            0xFF374151,
                                                          )
                                                        : Colors.grey.shade300,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                width: 52,
                                                height: 38,
                                                alignment: Alignment.center,
                                                child: Text(
                                                  coefficient % 1 == 0
                                                      ? coefficient
                                                            .toInt()
                                                            .toString()
                                                      : coefficient
                                                            .toStringAsFixed(1),
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF111827),
                                                  ),
                                                ),
                                              ),
                                              InkWell(
                                                onTap: () => setDialogState(() {
                                                  if (coefficient < 6)
                                                    coefficient =
                                                        (coefficient * 2 + 1)
                                                            .round() /
                                                        2;
                                                }),
                                                borderRadius:
                                                    const BorderRadius.horizontal(
                                                      right: Radius.circular(
                                                        10,
                                                      ),
                                                    ),
                                                child: Container(
                                                  width: 36,
                                                  height: 38,
                                                  alignment: Alignment.center,
                                                  decoration:
                                                      const BoxDecoration(
                                                        border: Border(
                                                          left: BorderSide(
                                                            color: Color(
                                                              0xFFE5E7EB,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                  child: Icon(
                                                    Icons.add,
                                                    size: 16,
                                                    color: coefficient < 6
                                                        ? const Color(
                                                            0xFF374151,
                                                          )
                                                        : Colors.grey.shade300,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 24),

                                  // ── Niveaux & Sections label row ──
                                  Row(
                                    children: [
                                      const Text(
                                        'Niveaux & Sections',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF111827),
                                        ),
                                      ),
                                      const Spacer(),
                                      if (selectedNiveauIds.isNotEmpty)
                                        InkWell(
                                          onTap: () => setDialogState(() {
                                            selectedNiveauIds.clear();
                                            selectedSectionIdsByNiveau.clear();
                                          }),
                                          child: const Text(
                                            'Réinitialiser',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              color: _brand,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  // ── Niveaux grouped by cycle ──
                                  Builder(
                                    builder: (_) {
                                      final collegeNiveaux = gradeLevels
                                          .where(
                                            (l) => l.levelType == 'college',
                                          )
                                          .toList();
                                      final lyceeNiveaux = gradeLevels
                                          .where(
                                            (l) => l.levelType != 'college',
                                          )
                                          .toList();
                                      final allSections =
                                          stateAsync.value?.sections ?? [];

                                      // ── Build COLLÈGE box ──
                                      Widget buildCollegeBox() {
                                        if (collegeNiveaux.isEmpty)
                                          return const SizedBox.shrink();
                                        return Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF9FAFB),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFE5E7EB),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'COLLÈGE',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.grey.shade400,
                                                  letterSpacing: 0.8,
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: collegeNiveaux.map((
                                                  level,
                                                ) {
                                                  final isSel =
                                                      selectedNiveauIds
                                                          .contains(level.id);
                                                  return InkWell(
                                                    onTap: () => setDialogState(
                                                      () {
                                                        if (isSel) {
                                                          selectedNiveauIds
                                                              .remove(level.id);
                                                        } else {
                                                          selectedNiveauIds.add(
                                                            level.id,
                                                          );
                                                        }
                                                      },
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 14,
                                                            vertical: 7,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: isSel
                                                            ? _brand
                                                            : Colors.white,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        border: Border.all(
                                                          color: isSel
                                                              ? _brand
                                                              : const Color(
                                                                  0xFFD1D5DB,
                                                                ),
                                                        ),
                                                      ),
                                                      child: Text(
                                                        level.code.isNotEmpty
                                                            ? level.code
                                                            : level.name,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: isSel
                                                              ? Colors.white
                                                              : const Color(
                                                                  0xFF374151,
                                                                ),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                            ],
                                          ),
                                        );
                                      }

                                      // ── Build LYCÉE box ──
                                      Widget buildLyceeBox() {
                                        if (lyceeNiveaux.isEmpty)
                                          return const SizedBox.shrink();
                                        int getLyceeRank(GradeLevelModel l) {
                                          final s = '${l.code} ${l.name}'.toLowerCase();
                                          if (s.contains('1') || s.contains('1ère') || s.contains('1ere')) return 1;
                                          if (s.contains('2') || s.contains('2ème') || s.contains('2eme')) return 2;
                                          if (s.contains('3') || s.contains('3ème') || s.contains('3eme')) return 3;
                                          if (s.contains('4') || s.contains('4ème') || s.contains('4eme') || s.contains('bac')) return 4;
                                          return l.orderIndex > 0 ? l.orderIndex : 99;
                                        }
                                        // Separate: niveaux without sections vs with sections
                                        final noSectionNiveaux = lyceeNiveaux
                                            .where((l) => !l.hasSections)
                                            .toList()
                                          ..sort((a, b) => getLyceeRank(a).compareTo(getLyceeRank(b)));
                                        final withSectionNiveaux = lyceeNiveaux
                                            .where((l) => l.hasSections)
                                            .toList()
                                          ..sort((a, b) => getLyceeRank(a).compareTo(getLyceeRank(b)));

                                        return Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF9FAFB),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFE5E7EB),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'LYCÉE',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.grey.shade400,
                                                  letterSpacing: 0.8,
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              // Niveaux WITHOUT sections (chip row)
                                              if (noSectionNiveaux
                                                  .isNotEmpty) ...[
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: noSectionNiveaux.map((
                                                    level,
                                                  ) {
                                                    final isSel =
                                                        selectedNiveauIds
                                                            .contains(level.id);
                                                    return InkWell(
                                                      onTap: () =>
                                                          setDialogState(() {
                                                            if (isSel) {
                                                              selectedNiveauIds
                                                                  .remove(
                                                                    level.id,
                                                                  );
                                                            } else {
                                                              selectedNiveauIds
                                                                  .add(
                                                                    level.id,
                                                                  );
                                                            }
                                                          }),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 14,
                                                              vertical: 7,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: isSel
                                                              ? _brand
                                                              : Colors.white,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                          border: Border.all(
                                                            color: isSel
                                                                ? _brand
                                                                : const Color(
                                                                    0xFFD1D5DB,
                                                                  ),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          level.code.isNotEmpty
                                                              ? level.code
                                                              : level.name,
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: isSel
                                                                ? Colors.white
                                                                : const Color(
                                                                    0xFF374151,
                                                                  ),
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  }).toList(),
                                                ),
                                                if (withSectionNiveaux
                                                    .isNotEmpty)
                                                  const SizedBox(height: 10),
                                              ],
                                              // Each niveau WITH sections gets its own row
                                              ...withSectionNiveaux.map((
                                                level,
                                              ) {
                                                final isSel = selectedNiveauIds
                                                    .contains(level.id);
                                                final levelSections =
                                                    level.sections.isNotEmpty
                                                    ? level.sections
                                                    : allSections;
                                                final sectionIds =
                                                    selectedSectionIdsByNiveau[level
                                                        .id] ??
                                                    {};

                                                return Container(
                                                  width: double.infinity,
                                                  margin: EdgeInsets.only(
                                                    top:
                                                        withSectionNiveaux
                                                                    .indexOf(
                                                                      level,
                                                                    ) ==
                                                                0 &&
                                                            noSectionNiveaux
                                                                .isEmpty
                                                        ? 0
                                                        : 8,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 10,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                    border: Border.all(
                                                      color: isSel
                                                          ? _brand.withOpacity(
                                                              0.3,
                                                            )
                                                          : const Color(
                                                              0xFFE5E7EB,
                                                            ),
                                                    ),
                                                  ),
                                                  child: Wrap(
                                                    spacing: 6,
                                                    runSpacing: 6,
                                                    crossAxisAlignment:
                                                        WrapCrossAlignment
                                                            .center,
                                                    children: [
                                                      // Niveau chip — filled purple when selected
                                                      InkWell(
                                                        onTap: () => setDialogState(() {
                                                          if (isSel) {
                                                            selectedNiveauIds
                                                                .remove(
                                                                  level.id,
                                                                );
                                                            selectedSectionIdsByNiveau
                                                                .remove(
                                                                  level.id,
                                                                );
                                                          } else {
                                                            selectedNiveauIds
                                                                .add(level.id);
                                                            selectedSectionIdsByNiveau[level
                                                                    .id] =
                                                                {};
                                                          }
                                                        }),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 12,
                                                                vertical: 6,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: isSel
                                                                ? _brand
                                                                : Colors.white,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  8,
                                                                ),
                                                            border: Border.all(
                                                              color: isSel
                                                                  ? _brand
                                                                  : const Color(
                                                                      0xFFD1D5DB,
                                                                    ),
                                                              width: isSel
                                                                  ? 1.5
                                                                  : 1,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            level.name,
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color: isSel
                                                                  ? Colors.white
                                                                  : const Color(
                                                                      0xFF374151,
                                                                    ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      // Section chips — outlined when selected (not filled)
                                                      ...levelSections.map((
                                                        section,
                                                      ) {
                                                        final isSecSel =
                                                            isSel &&
                                                            sectionIds.contains(
                                                              section.id,
                                                            );
                                                        final isDisabled =
                                                            !isSel;
                                                        return InkWell(
                                                          onTap: isDisabled
                                                              ? null
                                                              : () => setDialogState(() {
                                                                  selectedSectionIdsByNiveau
                                                                      .putIfAbsent(
                                                                        level
                                                                            .id,
                                                                        () =>
                                                                            {},
                                                                      );
                                                                  if (isSecSel) {
                                                                    selectedSectionIdsByNiveau[level
                                                                            .id]!
                                                                        .remove(
                                                                          section
                                                                              .id,
                                                                        );
                                                                  } else {
                                                                    selectedSectionIdsByNiveau[level
                                                                            .id]!
                                                                        .add(
                                                                          section
                                                                              .id,
                                                                        );
                                                                  }
                                                                }),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                16,
                                                              ),
                                                          child: Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      10,
                                                                  vertical: 5,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color: isSecSel
                                                                  ? Colors.white
                                                                  : Colors
                                                                        .white,
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    16,
                                                                  ),
                                                              border: Border.all(
                                                                color: isSecSel
                                                                    ? _brand
                                                                    : (isDisabled
                                                                          ? const Color(
                                                                              0xFFE5E7EB,
                                                                            )
                                                                          : const Color(
                                                                              0xFFD1D5DB,
                                                                            )),
                                                                width: isSecSel
                                                                    ? 2
                                                                    : 1,
                                                              ),
                                                            ),
                                                            child: Text(
                                                              section.name,
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    isSecSel
                                                                    ? FontWeight
                                                                          .w600
                                                                    : FontWeight
                                                                          .w500,
                                                                color: isSecSel
                                                                    ? _brand
                                                                    : (isDisabled
                                                                          ? Colors.grey.shade300
                                                                          : Colors.grey.shade500),
                                                              ),
                                                            ),
                                                          ),
                                                        );
                                                      }),
                                                    ],
                                                  ),
                                                );
                                              }),
                                            ],
                                          ),
                                        );
                                      }

                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          buildCollegeBox(),
                                          if (collegeNiveaux.isNotEmpty &&
                                              lyceeNiveaux.isNotEmpty)
                                            const SizedBox(height: 12),
                                          buildLyceeBox(),
                                        ],
                                      );
                                    },
                                  ),

                                  const SizedBox(height: 32),
                                  Container(
                                    height: 1,
                                    color: const Color(0xFFF3F4F6),
                                  ),
                                  const SizedBox(height: 32),

                                  // ── Section: Types d'Examen ──
                                  _buildSectionTitle('Types d\'Examen'),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Sélectionnez les types d\'évaluation applicables à cette matière.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  if (allExamTypes.isEmpty)
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 20,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF9FAFB),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: const Color(0xFFE5E7EB),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.assignment_outlined,
                                            size: 18,
                                            color: Colors.grey.shade400,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Aucun type d\'examen configuré. Créez-les dans Niveaux.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade400,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: allExamTypes.map((et) {
                                        final isSelected = selectedExamTypeIds
                                            .contains(et.id);
                                        return InkWell(
                                          onTap: () => setDialogState(() {
                                            if (isSelected) {
                                              selectedExamTypeIds.remove(et.id);
                                            } else {
                                              selectedExamTypeIds.add(et.id);
                                            }
                                          }),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? _brand
                                                  : Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: isSelected
                                                    ? _brand
                                                    : const Color(0xFFD1D5DB),
                                                width: isSelected ? 1.5 : 1,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  et.code,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: isSelected
                                                        ? Colors.white
                                                        : const Color(
                                                            0xFF374151,
                                                          ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  et.name,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w400,
                                                    color: isSelected
                                                        ? Colors.white
                                                              .withOpacity(0.8)
                                                        : Colors.grey.shade500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),

                                  const SizedBox(height: 32),
                                  Container(
                                    height: 1,
                                    color: const Color(0xFFF3F4F6),
                                  ),
                                  const SizedBox(height: 32),

                                  // ── Section: Professeurs Autorisés ──
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      _buildSectionTitle(
                                        'Professeurs Autorisés',
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          // Show teacher picker
                                          _showTeacherPickerDialog(
                                            ctx,
                                            allTeachers,
                                            selectedTeacherIds,
                                            (ids) {
                                              setDialogState(() {
                                                selectedTeacherIds.clear();
                                                selectedTeacherIds.addAll(ids);
                                              });
                                            },
                                          );
                                        },
                                        child: const Text(
                                          '+ Ajouter',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: _brand,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (selectedTeacherIds.isEmpty)
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 28,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF9FAFB),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: const Color(0xFFE5E7EB),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.person_add_outlined,
                                            size: 18,
                                            color: Colors.grey.shade400,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Aucun professeur sélectionné pour le moment',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey.shade400,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF9FAFB),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: const Color(0xFFE5E7EB),
                                        ),
                                      ),
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: selectedTeacherIds.map((tId) {
                                          final teacher = allTeachersUnfiltered
                                              .where((t) => t.id == tId)
                                              .firstOrNull;
                                          return Container(
                                            padding: const EdgeInsets.fromLTRB(
                                              4,
                                              4,
                                              10,
                                              4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: const Color(0xFFE5E7EB),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                UserAvatar(
                                                  name:
                                                      teacher?.fullName ?? '?',
                                                  photoUrl: teacher?.photoUrl,
                                                  radius: 12,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  teacher?.fullName ?? tId,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                    color: Color(0xFF111827),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                InkWell(
                                                  onTap: () => setDialogState(
                                                    () => selectedTeacherIds
                                                        .remove(tId),
                                                  ),
                                                  child: Icon(
                                                    Icons.close_rounded,
                                                    size: 14,
                                                    color: Colors.grey.shade400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),

                          // ── Footer ──
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 20,
                            ),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              border: Border(
                                top: BorderSide(color: Color(0xFFF3F4F6)),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                SizedBox(
                                  height: 40,
                                  child: TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF6B7280),
                                      padding: const EdgeInsets.symmetric(horizontal: 20),
                                    ),
                                    child: const Text(
                                      'Annuler',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  height: 40,
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.check_rounded, size: 18),
                                  label: Text(
                                    subject == null
                                        ? 'Enregistrer la matière'
                                        : 'Enregistrer',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  onPressed: () async {
                                    if (nameCtrl.text.trim().isEmpty ||
                                        codeCtrl.text.trim().isEmpty) {
                                      _showError(
                                        'Le nom et le code sont obligatoires',
                                      );
                                      return;
                                    }
                                    final newSubject = SubjectModel(
                                      id: subject?.id ?? '',
                                      schoolId: subject?.schoolId ?? '',
                                      name: nameCtrl.text.trim(),
                                      code: codeCtrl.text.trim().toUpperCase(),
                                      description: descCtrl.text.trim().isEmpty
                                          ? null
                                          : descCtrl.text.trim(),
                                      category: selectedCategory,
                                      defaultCoefficient: coefficient,
                                    );
                                    try {
                                      if (subject == null) {
                                        await ref
                                            .read(
                                              subjectsManagementProvider
                                                  .notifier,
                                            )
                                            .addSubject(newSubject);
                                      } else {
                                        await ref
                                            .read(
                                              subjectsManagementProvider
                                                  .notifier,
                                            )
                                            .updateSubject(
                                              subject.id,
                                              newSubject,
                                            );
                                      }
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      _showSuccess(
                                        subject == null
                                            ? 'Matière ajoutée'
                                            : 'Matière modifiée',
                                      );
                                    } catch (e) {
                                      _showError(UserFriendlyError.format(e));
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _brand,
                                    foregroundColor: Colors.white,
                                    elevation: 2,
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
          },
        ),
        );
      },
    );
  }

  void _showTeacherPickerDialog(
    BuildContext parentCtx,
    List<UserModel> allTeachers,
    Set<String> alreadySelected,
    void Function(Set<String>) onConfirm,
  ) {
    final searchCtrl = TextEditingController();
    final tempSelected = Set<String>.from(alreadySelected);

    showDialog(
      context: parentCtx,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setPickerState) {
          final query = searchCtrl.text.toLowerCase();
          final filtered = allTeachers.where((t) {
            if (query.isEmpty) return true;
            return t.fullName.toLowerCase().contains(query) ||
                t.email.toLowerCase().contains(query);
          }).toList();

          return Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 440,
                constraints: const BoxConstraints(
                  maxHeight: 560,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Sélectionner des professeurs',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: () => Navigator.pop(ctx),
                                child: Icon(
                                  Icons.close,
                                  size: 20,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 40,
                            child: TextField(
                              controller: searchCtrl,
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Rechercher un professeur...',
                                hintStyle: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade400,
                                ),
                                prefixIcon: Icon(
                                  Icons.search,
                                  size: 18,
                                  color: Colors.grey.shade400,
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF9FAFB),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 0,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: _brand),
                                ),
                              ),
                              onChanged: (_) => setPickerState(() {}),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: Colors.grey.shade100),
                    // List showing 6 items at the same time
                    SizedBox(
                      height: filtered.isEmpty
                          ? 80
                          : (filtered.length < 6
                              ? filtered.length * 54.0
                              : 324.0),
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                'Aucun professeur trouvé',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemExtent: 54.0,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final t = filtered[i];
                                final isSel = tempSelected.contains(t.id);
                                return InkWell(
                                  onTap: () {
                                    setPickerState(() {
                                      if (isSel) {
                                        tempSelected.remove(t.id);
                                      } else {
                                        tempSelected.add(t.id);
                                      }
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      children: [
                                        UserAvatar(
                                          name: t.fullName,
                                          photoUrl: t.photoUrl,
                                          radius: 16,
                                          backgroundColor: isSel
                                              ? _brand
                                              : const Color(0xFFF3F4F6),
                                          textColor: isSel
                                              ? Colors.white
                                              : Colors.grey.shade600,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                t.fullName,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: isSel
                                                      ? FontWeight.w600
                                                      : FontWeight.w500,
                                                  color: const Color(
                                                    0xFF111827,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                t.email,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade400,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isSel)
                                          const Icon(
                                            Icons.check_circle_rounded,
                                            size: 20,
                                            color: _brand,
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    // Footer
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Colors.grey.shade100),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '${tempSelected.length} sélectionné(s)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(
                              'Annuler',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              onConfirm(tempSelected);
                              Navigator.pop(ctx);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _brand,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              'Confirmer',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Dialog helper widgets ──
  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: _brand,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: Colors.grey.shade700,
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String placeholder, {
    bool isUppercase = false,
  }) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: ctrl,
        style: TextStyle(
          fontSize: 13,
          color: const Color(0xFF111827),
          letterSpacing: isUppercase ? 1.0 : 0,
        ),
        textCapitalization: isUppercase
            ? TextCapitalization.characters
            : TextCapitalization.none,
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          filled: true,
          fillColor: const Color(0xFFF9FAFB),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 0,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _brand),
          ),
        ),
      ),
    );
  }

  void _showAssignmentDialog(
    SubjectsManagementState state, [
    SubjectAssignmentModel? assignment,
  ]) {
    String? subjectId = assignment?.subjectId;
    String? gradeId = assignment?.gradeLevelId;
    String? sectionId = assignment?.sectionId;
    double coefficient = assignment?.coefficient ?? 1.0;
    final coefCtrl = TextEditingController(text: coefficient.toInt().toString());
    double weeklyHours = assignment?.weeklyHours ?? 0;
    bool isMainSubject = assignment?.isMainSubject ?? false;

    final isEditing = assignment != null;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Container(color: Colors.black.withOpacity(0.28)),
              ),
            ),
            Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 560,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.85,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 48, offset: const Offset(0, 16)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ═══ HEADER ═══
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 28, 24, 20),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: _brandLight,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  isEditing ? Icons.edit_rounded : Icons.add_circle_outline_rounded,
                                  color: _brand,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isEditing ? 'Modifier Affectation' : 'Nouvelle Affectation',
                                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      isEditing
                                          ? 'Modifiez les paramètres de cette affectation.'
                                          : 'Configurez l\'affectation d\'une matière à un niveau.',
                                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                                    ),
                                  ],
                                ),
                              ),
                              InkWell(
                                onTap: () => Navigator.pop(ctx),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 32, height: 32,
                                  decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8)),
                                  child: Icon(Icons.close_rounded, size: 16, color: Colors.grey.shade500),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),

                        // ═══ SCROLLABLE CONTENT ═══
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── Section: Informations ──
                                _buildSectionTitle('Informations'),
                                const SizedBox(height: 14),

                                // Matière dropdown
                                _buildFieldLabel('Matière *'),
                                const SizedBox(height: 6),
                                SizedBox(
                                  height: 44,
                                  child: DropdownButtonFormField<String>(
                                    value: subjectId,
                                    isDense: true,
                                    borderRadius: BorderRadius.circular(12),
                                    menuMaxHeight: 300,
                                    dropdownColor: Colors.white,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF111827)),
                                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade400, size: 20),
                                    decoration: InputDecoration(
                                      hintText: 'Sélectionner une matière',
                                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                                      filled: true,
                                      fillColor: const Color(0xFFF9FAFB),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _brand)),
                                      prefixIcon: const Icon(Icons.book_outlined, size: 18, color: Color(0xFF9CA3AF)),
                                    ),
                                    items: state.subjects
                                        .map((s) => DropdownMenuItem(value: s.id, child: Text('${s.name} (${s.code})', style: const TextStyle(fontSize: 13, color: Color(0xFF111827)))))
                                        .toList(),
                                    onChanged: (v) => setState(() => subjectId = v),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Niveau dropdown
                                _buildFieldLabel('Niveau *'),
                                const SizedBox(height: 6),
                                SizedBox(
                                  height: 44,
                                  child: DropdownButtonFormField<String>(
                                    value: gradeId,
                                    isDense: true,
                                    borderRadius: BorderRadius.circular(12),
                                    dropdownColor: Colors.white,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF111827)),
                                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade400, size: 20),
                                    decoration: InputDecoration(
                                      hintText: 'Sélectionner un niveau',
                                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                                      filled: true,
                                      fillColor: const Color(0xFFF9FAFB),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _brand)),
                                      prefixIcon: const Icon(Icons.school_outlined, size: 18, color: Color(0xFF9CA3AF)),
                                    ),
                                    items: state.gradeLevels
                                        .map((g) => DropdownMenuItem(value: g.id, child: Text(g.name, style: const TextStyle(fontSize: 13, color: Color(0xFF111827)))))
                                        .toList(),
                                    onChanged: (v) => setState(() { gradeId = v; sectionId = null; }),
                                  ),
                                ),

                                // Section dropdown (conditional)
                                if (gradeId != null &&
                                    state.gradeLevels
                                        .firstWhere((g) => g.id == gradeId, orElse: () => state.gradeLevels.first)
                                        .hasSections) ...[
                                  const SizedBox(height: 16),
                                  Builder(
                                    builder: (_) {
                                      final selectedGrade = state.gradeLevels.firstWhere((g) => g.id == gradeId, orElse: () => state.gradeLevels.first);
                                      final gradeSections = selectedGrade.sections.isNotEmpty ? selectedGrade.sections : state.sections;
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          _buildFieldLabel('Filière'),
                                          const SizedBox(height: 6),
                                          SizedBox(
                                            height: 44,
                                            child: DropdownButtonFormField<String?>(
                                              value: sectionId,
                                              isDense: true,
                                              borderRadius: BorderRadius.circular(12),
                                              dropdownColor: Colors.white,
                                              elevation: 8,
                                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF111827)),
                                              icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade400, size: 20),
                                              decoration: InputDecoration(
                                                hintText: 'Sélectionner une filière',
                                                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                                                filled: true,
                                                fillColor: const Color(0xFFF9FAFB),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _brand)),
                                                prefixIcon: const Icon(Icons.category_outlined, size: 18, color: Color(0xFF9CA3AF)),
                                              ),
                                              items: gradeSections
                                                  .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name, style: const TextStyle(fontSize: 13, color: Color(0xFF111827)))))
                                                  .toList(),
                                              onChanged: (v) => setState(() => sectionId = v),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],

                                const SizedBox(height: 20),
                                // ── Divider ──
                                Divider(height: 1, color: Colors.grey.shade200),
                                const SizedBox(height: 20),

                                // ── Section: Configuration Académique ──
                                _buildSectionTitle('Configuration Académique'),
                                const SizedBox(height: 14),

                                // Coefficient + Heures/Semaine row
                                Row(
                                  children: [
                                    // Coefficient
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          _buildFieldLabel('Coefficient'),
                                          const SizedBox(height: 6),
                                          SizedBox(
                                            height: 44,
                                            child: TextField(
                                              controller: coefCtrl,
                                              keyboardType: TextInputType.number,
                                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                              onChanged: (v) {
                                                final parsed = int.tryParse(v);
                                                if (parsed != null && parsed > 0) {
                                                  coefficient = parsed.toDouble();
                                                }
                                              },
                                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                                              decoration: InputDecoration(
                                                hintText: '1',
                                                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                                                prefixIcon: const Icon(Icons.trending_up, size: 18, color: Color(0xFF9CA3AF)),
                                                filled: true,
                                                fillColor: const Color(0xFFF9FAFB),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _brand)),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // Heures/Semaine
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          _buildFieldLabel('Heures/Semaine'),
                                          const SizedBox(height: 6),
                                          SizedBox(
                                            height: 44,
                                            child: InkWell(
                                              borderRadius: BorderRadius.circular(12),
                                              onTap: () async {
                                                final hours = weeklyHours.floor();
                                                final mins = ((weeklyHours - hours) * 60).round();
                                                final hoursCtrl = TextEditingController(text: hours > 0 ? hours.toString() : '');
                                                final minsCtrl = TextEditingController(text: mins > 0 ? mins.toString() : '');

                                                final result = await showDialog<double>(
                                                  context: context,
                                                  builder: (dCtx) => StatefulBuilder(
                                                    builder: (dCtx, setPickerState) => AlertDialog(
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                      title: Row(
                                                        children: [
                                                          Container(
                                                            width: 40,
                                                            height: 40,
                                                            decoration: BoxDecoration(color: _brandLight, borderRadius: BorderRadius.circular(10)),
                                                            child: const Icon(Icons.schedule, color: _brand, size: 20),
                                                          ),
                                                          const SizedBox(width: 12),
                                                          const Text('Durée hebdomadaire', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                                        ],
                                                      ),
                                                      content: SizedBox(
                                                        width: 320,
                                                        child: Column(
                                                          mainAxisSize: MainAxisSize.min,
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            const Text(
                                                              'Saisissez les heures et minutes de cours par semaine',
                                                              style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
                                                            ),
                                                            const SizedBox(height: 20),
                                                            Row(
                                                              children: [
                                                                // Hours input
                                                                Expanded(
                                                                  child: Column(
                                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                                    children: [
                                                                      const Text('Heures', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                                                                      const SizedBox(height: 6),
                                                                      SizedBox(
                                                                        height: 46,
                                                                        child: TextField(
                                                                          controller: hoursCtrl,
                                                                          keyboardType: TextInputType.number,
                                                                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                                                          textAlign: TextAlign.center,
                                                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                                                                          decoration: InputDecoration(
                                                                            hintText: '0',
                                                                            hintStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFCBD5E1)),
                                                                            suffixText: 'h',
                                                                            suffixStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _brand),
                                                                            filled: true,
                                                                            fillColor: const Color(0xFFF9FAFB),
                                                                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                                                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                                                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _brand, width: 1.5)),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                                const Padding(
                                                                  padding: EdgeInsets.fromLTRB(10, 22, 10, 0),
                                                                  child: Text(':', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF9CA3AF))),
                                                                ),
                                                                // Minutes input
                                                                Expanded(
                                                                  child: Column(
                                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                                    children: [
                                                                      const Text('Minutes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                                                                      const SizedBox(height: 6),
                                                                      SizedBox(
                                                                        height: 46,
                                                                        child: TextField(
                                                                          controller: minsCtrl,
                                                                          keyboardType: TextInputType.number,
                                                                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                                                          textAlign: TextAlign.center,
                                                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                                                                          decoration: InputDecoration(
                                                                            hintText: '0',
                                                                            hintStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFCBD5E1)),
                                                                            suffixText: 'min',
                                                                            suffixStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _brand),
                                                                            filled: true,
                                                                            fillColor: const Color(0xFFF9FAFB),
                                                                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                                                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                                                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _brand, width: 1.5)),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                            const SizedBox(height: 16),
                                                            // Quick preset pills
                                                            const Text('Raccourcis rapides', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF9CA3AF))),
                                                            const SizedBox(height: 8),
                                                            Wrap(
                                                              spacing: 8,
                                                              runSpacing: 6,
                                                              children: [
                                                                {'label': '1h', 'h': 1, 'm': 0},
                                                                {'label': '1h 30', 'h': 1, 'm': 30},
                                                                {'label': '2h', 'h': 2, 'm': 0},
                                                                {'label': '3h', 'h': 3, 'm': 0},
                                                                {'label': '4h', 'h': 4, 'm': 0},
                                                              ].map((p) => InkWell(
                                                                onTap: () {
                                                                  hoursCtrl.text = p['h'].toString();
                                                                  minsCtrl.text = p['m'].toString();
                                                                },
                                                                borderRadius: BorderRadius.circular(8),
                                                                child: Container(
                                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                                                  decoration: BoxDecoration(
                                                                    color: const Color(0xFFF3F4F6),
                                                                    borderRadius: BorderRadius.circular(8),
                                                                  ),
                                                                  child: Text(
                                                                    p['label'] as String,
                                                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                                                                  ),
                                                                ),
                                                              )).toList(),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      actions: [
                                                        TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Annuler')),
                                                        ElevatedButton(
                                                          onPressed: () {
                                                            final h = int.tryParse(hoursCtrl.text) ?? 0;
                                                            final m = (int.tryParse(minsCtrl.text) ?? 0).clamp(0, 59);
                                                            Navigator.pop(dCtx, h + m / 60.0);
                                                          },
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor: _brand,
                                                            foregroundColor: Colors.white,
                                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                          ),
                                                          child: const Text('Confirmer'),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                                if (result != null) setState(() => weeklyHours = result);
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF9FAFB),
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(color: const Color(0xFFE5E7EB)),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.schedule, size: 18, color: _brand),
                                                    const SizedBox(width: 10),
                                                    Text(
                                                      '${weeklyHours.floor()}h ${((weeklyHours - weeklyHours.floor()) * 60).round().toString().padLeft(2, '0')}min',
                                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F2937)),
                                                    ),
                                                    const Spacer(),
                                                    Icon(Icons.edit_outlined, size: 16, color: Colors.grey.shade400),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 20),
                                // ── Divider ──
                                Divider(height: 1, color: Colors.grey.shade200),
                                const SizedBox(height: 20),

                                // ── Section: Options ──
                                _buildSectionTitle('Options'),
                                const SizedBox(height: 14),

                                // Main subject toggle (borderless)
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: isMainSubject ? _brandLight : const Color(0xFFF9FAFB),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36, height: 36,
                                        decoration: BoxDecoration(
                                          color: isMainSubject ? _brand : Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(Icons.star_rounded, color: isMainSubject ? Colors.white : Colors.grey.shade400, size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Matière principale', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                                            Text(
                                              'Cette matière est la principale pour cette filière',
                                              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                                            ),
                                          ],
                                        ),
                                      ),
                                      ModernAnimatedSwitch(
                                        value: isMainSubject,
                                        onChanged: (v) => setState(() => isMainSubject = v),
                                        activeColor: _brand,
                                      ),
                                    ],
                                  ),
                                ),

                                // Suggested subjects button
                                if (gradeId != null && assignment == null) ...[
                                  const SizedBox(height: 14),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () => _showSuggestedSubjectsForAssignment(state, gradeId!, sectionId),
                                      icon: const Icon(Icons.lightbulb_outline, size: 18),
                                      label: const Text('Voir matières suggérées', style: TextStyle(fontWeight: FontWeight.w600)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _brand,
                                        side: const BorderSide(color: _brand, width: 1),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ),

                        // ═══ FOOTER ═══
                        Container(
                          padding: const EdgeInsets.fromLTRB(28, 16, 24, 20),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            border: Border(top: BorderSide(color: Color(0xFFF0F0F5))),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(
                                height: 40,
                                child: TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF6B7280),
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                  ),
                                  child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                height: 40,
                                child: ElevatedButton(
                                  onPressed: () async {
                                    if (subjectId == null || gradeId == null) {
                                      _showError('Veuillez sélectionner une matière et un niveau');
                                      return;
                                    }
                                    final newAssignment = SubjectAssignmentModel(
                                      id: assignment?.id ?? '',
                                      subjectId: subjectId!,
                                      gradeLevelId: gradeId!,
                                      sectionId: sectionId,
                                      coefficient: coefficient,
                                      weeklyHours: weeklyHours,
                                      isMainSubject: isMainSubject,
                                    );
                                    try {
                                      if (assignment == null) {
                                        await ref.read(subjectsManagementProvider.notifier).addAssignment(newAssignment);
                                      } else {
                                        await ref.read(subjectsManagementProvider.notifier).updateAssignment(assignment.id, newAssignment);
                                      }
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      _showSuccess(assignment == null ? 'Affectation ajoutée' : 'Affectation modifiée');
                                    } catch (e) {
                                      _showError(UserFriendlyError.format(e));
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _brand,
                                    foregroundColor: Colors.white,
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                  ),
                                  child: Text(
                                    assignment == null ? 'Ajouter' : 'Enregistrer',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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

  // ignore: unused_element
  void _confirmDeleteSubject(SubjectModel subject) {
    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
              ),
              const SizedBox(width: 12),
              const Text('Supprimer la matière ?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          content: Text(
            'Voulez-vous vraiment supprimer "${subject.name}" ? Cette action est irréversible.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      await ref
                          .read(subjectsManagementProvider.notifier)
                          .deleteSubject(subject.id);
                      if (ctx.mounted) Navigator.pop(ctx);
                      _showSuccess('Matière supprimée');
                    } catch (e) {
                      _showError(UserFriendlyError.format(e));
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Supprimer', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteAssignment(SubjectAssignmentModel assignment) {
    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
              ),
              const SizedBox(width: 12),
              const Text('Supprimer l\'affectation ?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          content: Text(
            'Voulez-vous vraiment supprimer l\'affectation de "${assignment.subjectName}" ? Cette action est irréversible.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      await ref
                          .read(subjectsManagementProvider.notifier)
                          .deleteAssignment(assignment.id);
                      if (ctx.mounted) Navigator.pop(ctx);
                      _showSuccess('Affectation supprimée');
                    } catch (e) {
                      _showError(UserFriendlyError.format(e));
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Supprimer', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmBulkDelete() {
    final count = _selectedAssignmentIds.length;
    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                'Supprimer $count affectation${count > 1 ? 's' : ''} ?',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ),
          content: Text(
            'Cette action est irréversible. $count affectation${count > 1 ? 's seront supprimées' : ' sera supprimée'} définitivement.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      final notifier = ref.read(subjectsManagementProvider.notifier);
                      for (final id in _selectedAssignmentIds) {
                        await notifier.deleteAssignment(id);
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      _clearSelection();
                      _showSuccess(
                        '$count affectation${count > 1 ? 's' : ''} supprimée${count > 1 ? 's' : ''}',
                      );
                    } catch (e) {
                      _showError(UserFriendlyError.format(e));
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text(
                    'Supprimer $count',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showBulkEditDialog(SubjectsManagementState state) {
    double? newCoefficient;
    double? newWeeklyHours;
    bool updateCoefficient = false;
    bool updateWeeklyHours = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(
            'Modification groupée (${_selectedAssignmentIds.length})',
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Modifier ${_selectedAssignmentIds.length} affectation(s) sélectionnée(s)',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                // Coefficient
                CheckboxListTile(
                  title: const Text('Modifier le coefficient'),
                  value: updateCoefficient,
                  onChanged: (v) =>
                      setState(() => updateCoefficient = v ?? false),
                ),
                if (updateCoefficient)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Nouveau coefficient',
                        prefixIcon: Icon(Icons.trending_up),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (v) =>
                          newCoefficient = double.tryParse(v) ?? 1.0,
                    ),
                  ),
                const SizedBox(height: 16),
                // Weekly Hours
                CheckboxListTile(
                  title: const Text('Modifier les heures/semaine'),
                  value: updateWeeklyHours,
                  onChanged: (v) =>
                      setState(() => updateWeeklyHours = v ?? false),
                ),
                if (updateWeeklyHours)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final nwh = newWeeklyHours ?? 0;
                        final h = nwh.floor();
                        final m = ((nwh - h) * 60).round();
                        int pH = h; int pM = m;
                        final result = await showDialog<double>(
                          context: ctx,
                          builder: (dCtx) => StatefulBuilder(
                            builder: (dCtx, sps) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              title: Row(children: [
                                Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(10)),
                                  child: const Icon(Icons.schedule, color: Color(0xFF6366F1), size: 20)),
                                const SizedBox(width: 12),
                                const Text('Durée hebdomadaire', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                              ]),
                              content: Column(mainAxisSize: MainAxisSize.min, children: [
                                const Text('Choisissez les heures et minutes', style: TextStyle(fontSize: 12.5, color: Color(0xFF9CA3AF))),
                                const SizedBox(height: 20),
                                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Column(children: [
                                    const Text('Heures', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6366F1))),
                                    const SizedBox(height: 6),
                                    SizedBox(width: 80, height: 120, child: ListWheelScrollView.useDelegate(
                                      itemExtent: 40, diameterRatio: 1.2, physics: const FixedExtentScrollPhysics(),
                                      controller: FixedExtentScrollController(initialItem: pH),
                                      onSelectedItemChanged: (i) => sps(() => pH = i),
                                      childDelegate: ListWheelChildBuilderDelegate(childCount: 13, builder: (ctx, i) =>
                                        Container(alignment: Alignment.center, decoration: BoxDecoration(color: i == pH ? const Color(0xFFEEF2FF) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                                          child: Text('$i h', style: TextStyle(fontSize: 18, fontWeight: i == pH ? FontWeight.w700 : FontWeight.w400, color: i == pH ? const Color(0xFF6366F1) : const Color(0xFF9CA3AF))))),
                                    )),
                                  ]),
                                  const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text(':', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF6366F1)))),
                                  Column(children: [
                                    const Text('Minutes', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6366F1))),
                                    const SizedBox(height: 6),
                                    SizedBox(width: 80, height: 120, child: ListWheelScrollView.useDelegate(
                                      itemExtent: 40, diameterRatio: 1.2, physics: const FixedExtentScrollPhysics(),
                                      controller: FixedExtentScrollController(initialItem: pM ~/ 15),
                                      onSelectedItemChanged: (i) => sps(() => pM = i * 15),
                                      childDelegate: ListWheelChildBuilderDelegate(childCount: 4, builder: (ctx, i) {
                                        final mn = i * 15; final sel = mn == pM;
                                        return Container(alignment: Alignment.center, decoration: BoxDecoration(color: sel ? const Color(0xFFEEF2FF) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                                          child: Text('${mn.toString().padLeft(2, '0')} min', style: TextStyle(fontSize: 18, fontWeight: sel ? FontWeight.w700 : FontWeight.w400, color: sel ? const Color(0xFF6366F1) : const Color(0xFF9CA3AF))));
                                      }),
                                    )),
                                  ]),
                                ]),
                                const SizedBox(height: 16),
                                Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFBBF7D0))),
                                  child: Text('${pH}h ${pM.toString().padLeft(2, '0')}min = ${(pH + pM / 60.0).toStringAsFixed(2)} heures', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF16A34A)))),
                              ]),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Annuler')),
                                ElevatedButton(onPressed: () => Navigator.pop(dCtx, pH + pM / 60.0),
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                  child: const Text('Confirmer')),
                              ],
                            ),
                          ),
                        );
                        if (result != null) setState(() => newWeeklyHours = result);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE8EAF0))),
                        child: Row(children: [
                          const Icon(Icons.schedule, size: 18, color: Color(0xFF6366F1)),
                          const SizedBox(width: 10),
                          Text('${(newWeeklyHours ?? 0).floor()}h ${(((newWeeklyHours ?? 0) - (newWeeklyHours ?? 0).floor()) * 60).round().toString().padLeft(2, '0')}min',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
                          const Spacer(),
                          const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF9CA3AF)),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!updateCoefficient && !updateWeeklyHours) {
                  _showError(
                    'Veuillez sélectionner au moins un champ à modifier',
                  );
                  return;
                }

                try {
                  final notifier = ref.read(
                    subjectsManagementProvider.notifier,
                  );
                  final stateValue = ref.read(subjectsManagementProvider);

                  await stateValue.whenData((currentState) async {
                    for (final id in _selectedAssignmentIds) {
                      final assignment = currentState.assignments.firstWhere(
                        (a) => a.id == id,
                      );

                      final updated = SubjectAssignmentModel(
                        id: assignment.id,
                        subjectId: assignment.subjectId,
                        gradeLevelId: assignment.gradeLevelId,
                        sectionId: assignment.sectionId,
                        semesterId: assignment.semesterId,
                        coefficient: updateCoefficient
                            ? (newCoefficient ?? assignment.coefficient)
                            : assignment.coefficient,
                        weeklyHours: updateWeeklyHours
                            ? (newWeeklyHours ?? assignment.weeklyHours)
                            : assignment.weeklyHours,
                        isMainSubject: assignment.isMainSubject,
                        isActive: assignment.isActive,
                        createdAt: assignment.createdAt,
                        subjectName: assignment.subjectName,
                        subjectCode: assignment.subjectCode,
                        gradeLevelName: assignment.gradeLevelName,
                        sectionName: assignment.sectionName,
                        semesterName: assignment.semesterName,
                        examConfigs: assignment.examConfigs,
                      );

                      await notifier.updateAssignment(id, updated);
                    }
                  });

                  if (ctx.mounted) Navigator.pop(ctx);
                  _clearSelection();
                  _showSuccess('Affectations modifiées avec succès');
                } catch (e) {
                  _showError(UserFriendlyError.format(e));
                }
              },
              child: const Text('Appliquer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuggestedSubjectsForAssignment(
    SubjectsManagementState state,
    String gradeId,
    String? sectionId,
  ) {
    // Get grade and section info
    final grade = state.gradeLevels.firstWhere(
      (g) => g.id == gradeId,
      orElse: () => GradeLevelModel(
        id: '',
        schoolId: '',
        name: '',
        code: '',
        levelType: 'college',
      ),
    );
    final section = sectionId != null
        ? state.sections.firstWhere(
            (s) => s.id == sectionId,
            orElse: () =>
                SectionModel(id: '', schoolId: '', name: '', code: ''),
          )
        : null;

    // Get suggested subjects
    final suggested = ref
        .read(subjectsManagementProvider.notifier)
        .getSuggestedSubjects(grade.code, section?.code);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.lightbulb, color: AppColors.accent),
            const SizedBox(width: 8),
            Text('Matières suggérées pour ${grade.name}'),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 400,
          child: suggested.isEmpty
              ? const Center(child: Text('Aucune suggestion disponible'))
              : ListView.builder(
                  itemCount: suggested.length,
                  itemBuilder: (ctx, i) {
                    final s = suggested[i];
                    return Card(
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _getSubjectColor(s.subjectCode),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              s.subjectCode,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                        title: Text(s.subjectName),
                        subtitle: Text(
                          'Coef: ${s.coefficient}${s.hasPractical ? ' • TP' : ''}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _getCoefColor(s.coefficient),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'x${s.coefficient}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0].substring(0, parts[0].length > 1 ? 2 : 1).toUpperCase();
    }
    return '?';
  }

  // ==================== TEACHER ASSIGNMENT DIALOG ====================
  void _showTeacherAssignmentDialog(
    SubjectsManagementState state, {
    String? editTeacherId,
  }) {
    String? selectedTeacherId = editTeacherId;
    String? selectedSubjectId;
    final Set<String> selectedNiveauIds = {};
    final Set<String> selectedSectionIds = {};
    final Set<String> selectedClassIds = {};

    // If editing, pre-populate selections
    if (editTeacherId != null) {
      final existingAssignments = state.teacherAssignments
          .where((a) => a.teacherId == editTeacherId)
          .toList();
      if (existingAssignments.isNotEmpty) {
        selectedSubjectId = existingAssignments.first.subjectId;
      }
      for (final a in existingAssignments) {
        if (a.niveauId != null) selectedNiveauIds.add(a.niveauId!);
        if (a.classId != null) selectedClassIds.add(a.classId!);
      }
      // Derive section selections from the pre-populated classes
      for (final classId in List<String>.from(selectedClassIds)) {
        final cls = state.classes.where((c) => c.id == classId).firstOrNull;
        if (cls?.sectionId != null) selectedSectionIds.add(cls!.sectionId!);
      }
    }

    // Shared input decoration matching ClassFormDialog
    InputDecoration dialogInputDeco({String? hintText}) => InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF8F9FA),
      hintText: hintText,
      hintStyle: const TextStyle(color: Color(0xFFB0B3BE), fontSize: 14, fontWeight: FontWeight.w400),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: StatefulBuilder(
          builder: (ctx, setDialogState) {
            // Niveaux that require section selection
            final niveauxWithSectionsIds = state.gradeLevels
                .where((g) => selectedNiveauIds.contains(g.id) && g.hasSections)
                .map((g) => g.id)
                .toSet();

            // Sections to show (collected from all selected niveaux that have sections)
            final selectedNiveauxWithSections = state.gradeLevels
                .where((g) => selectedNiveauIds.contains(g.id) && g.hasSections && g.sections.isNotEmpty)
                .toList();

            // Whether the classes step should be visible
            final hasNiveauxWithoutSections = state.gradeLevels
                .any((g) => selectedNiveauIds.contains(g.id) && !g.hasSections);
            final showClassesSection = selectedNiveauIds.isNotEmpty &&
                (hasNiveauxWithoutSections || selectedSectionIds.isNotEmpty);

            // Filter classes by selected niveaux (+ sections for niveaux that require them)
            final filteredClasses = !showClassesSection
                ? <dynamic>[]
                : state.classes.where((c) {
                    if (!selectedNiveauIds.contains(c.gradeLevelId)) return false;
                    if (niveauxWithSectionsIds.contains(c.gradeLevelId)) {
                      return c.sectionId != null && selectedSectionIds.contains(c.sectionId);
                    }
                    return true;
                  }).toList();

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              child: Container(
                width: 520,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ──
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                editTeacherId != null
                                    ? 'Modifier les affectations'
                                    : 'Affecter un Professeur',
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                editTeacherId != null
                                    ? 'Modifiez la matière, les niveaux et les classes.'
                                    : 'Associer un enseignant à une matière et des classes.',
                                style: const TextStyle(fontSize: 13, color: Color(0xFF9B9DAB)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade300, width: 1),
                          ),
                          child: InkWell(
                            onTap: () => Navigator.pop(ctx),
                            customBorder: const CircleBorder(),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.close, size: 18, color: Color(0xFF7B7D8B)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // ── Scrollable content ──
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Professeur
                            _dialogFieldLabel('Professeur', required: true),
                            DropdownButtonFormField<String>(
                              value: selectedTeacherId,
                              decoration: dialogInputDeco(hintText: 'Sélectionner un professeur'),
                              borderRadius: BorderRadius.circular(12),
                              dropdownColor: Colors.white,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Color(0xFF1A1A2E)),
                              items: state.teachers
                                  .where((t) => t.isActive || t.id == editTeacherId)
                                  .map(
                                    (t) => DropdownMenuItem(
                                      value: t.id,
                                      child: Text(t.fullName),
                                    ),
                                  )
                                  .toList(),
                              onChanged: editTeacherId != null
                                  ? null
                                  : (v) {
                                      setDialogState(() => selectedTeacherId = v);
                                    },
                            ),
                            if (editTeacherId == null) ...[
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _showCreateTeacherDialog(state);
                                },
                                icon: const Icon(Icons.person_add_alt_1, size: 16),
                                label: const Text('Créer un nouveau professeur'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),

                            // 2. Matière
                            _dialogFieldLabel('Matière', required: true),
                            DropdownButtonFormField<String>(
                              value: selectedSubjectId,
                              decoration: dialogInputDeco(hintText: 'Sélectionner une matière'),
                              borderRadius: BorderRadius.circular(12),
                              dropdownColor: Colors.white,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Color(0xFF1A1A2E)),
                              items: state.subjects
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s.id,
                                      child: Text(s.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                setDialogState(() {
                                  selectedSubjectId = v;
                                  selectedNiveauIds.clear();
                                  selectedSectionIds.clear();
                                  selectedClassIds.clear();
                                });
                              },
                            ),
                            const SizedBox(height: 20),

                            // 3. Niveaux (chips)
                            if (selectedSubjectId != null) ...[
                              _dialogFieldLabel('Niveaux'),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: state.gradeLevels.map((niveau) {
                                  final isSelected = selectedNiveauIds.contains(niveau.id);
                                  return FilterChip(
                                    label: Text(niveau.name),
                                    selected: isSelected,
                                    onSelected: (v) {
                                      setDialogState(() {
                                        if (v) {
                                          selectedNiveauIds.add(niveau.id);
                                        } else {
                                          selectedNiveauIds.remove(niveau.id);
                                          // Remove sections belonging to this niveau
                                          final sectionIdsForNiveau = niveau.sections.map((s) => s.id).toSet();
                                          selectedSectionIds.removeAll(sectionIdsForNiveau);
                                          // Remove classes belonging to this niveau
                                          final classesToRemove = state.classes
                                              .where((c) => c.gradeLevelId == niveau.id)
                                              .map((c) => c.id)
                                              .toSet();
                                          selectedClassIds.removeAll(classesToRemove);
                                        }
                                      });
                                    },
                                    backgroundColor: const Color(0xFFF8F9FA),
                                    selectedColor: AppColors.primary.withOpacity(0.1),
                                    checkmarkColor: AppColors.primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: isSelected ? Colors.transparent : const Color(0xFFE5E7EB),
                                      ),
                                    ),
                                    labelStyle: TextStyle(
                                      fontSize: 13,
                                      color: isSelected ? AppColors.primary : const Color(0xFF374151),
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                    ),
                                  );
                                }).toList(),
                              ),

                              // 4. Sections (only for niveaux that have hasSections = true)
                              if (selectedNiveauxWithSections.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                _dialogFieldLabel('Filières'),
                                ...selectedNiveauxWithSections.map((niveau) => Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (selectedNiveauxWithSections.length > 1) ...[
                                      Text(
                                        niveau.name,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF9B9DAB),
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                    ],
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: niveau.sections.map((section) {
                                        final isSelected = selectedSectionIds.contains(section.id);
                                        return FilterChip(
                                          label: Text(section.name),
                                          selected: isSelected,
                                          onSelected: (v) {
                                            setDialogState(() {
                                              if (v) {
                                                selectedSectionIds.add(section.id);
                                              } else {
                                                selectedSectionIds.remove(section.id);
                                                // Remove classes of this section
                                                final classesToRemove = state.classes
                                                    .where((c) => c.sectionId == section.id)
                                                    .map((c) => c.id)
                                                    .toSet();
                                                selectedClassIds.removeAll(classesToRemove);
                                              }
                                            });
                                          },
                                          backgroundColor: const Color(0xFFF8F9FA),
                                          selectedColor: const Color(0xFF7C3AED).withOpacity(0.1),
                                          checkmarkColor: const Color(0xFF7C3AED),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            side: BorderSide(
                                              color: isSelected ? Colors.transparent : const Color(0xFFE5E7EB),
                                            ),
                                          ),
                                          labelStyle: TextStyle(
                                            fontSize: 13,
                                            color: isSelected ? const Color(0xFF7C3AED) : const Color(0xFF374151),
                                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                )),
                              ],

                              const SizedBox(height: 20),

                              // 5. Classes
                              if (showClassesSection) ...[
                                _dialogFieldLabel('Classes'),
                                filteredClasses.isEmpty
                                    ? Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF8F9FA),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.info_outline, size: 16, color: Colors.grey.shade400),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'Aucune classe pour les niveaux sélectionnés',
                                              style: TextStyle(color: Color(0xFF9B9DAB), fontSize: 13),
                                            ),
                                          ],
                                        ),
                                      )
                                    : Container(
                                        constraints: const BoxConstraints(maxHeight: 200),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF8F9FA),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: ListView.builder(
                                          shrinkWrap: true,
                                          itemCount: filteredClasses.length,
                                          itemBuilder: (_, i) {
                                            final cls = filteredClasses[i];
                                            final isSelected = selectedClassIds.contains(cls.id);
                                            return CheckboxListTile(
                                              value: isSelected,
                                              onChanged: (v) {
                                                setDialogState(() {
                                                  if (v == true) {
                                                    selectedClassIds.add(cls.id);
                                                  } else {
                                                    selectedClassIds.remove(cls.id);
                                                  }
                                                });
                                              },
                                              title: Text(
                                                cls.name,
                                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Color(0xFF1A1A2E)),
                                              ),
                                              subtitle: Text(
                                                [cls.gradeLevelName, cls.sectionName].where((s) => s != null).join(' • '),
                                                style: const TextStyle(fontSize: 12, color: Color(0xFF9B9DAB)),
                                              ),
                                              dense: true,
                                              controlAffinity: ListTileControlAffinity.leading,
                                              activeColor: AppColors.primary,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            );
                                          },
                                        ),
                                      ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Actions ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          height: 40,
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF6B7280),
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                            ),
                            child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 40,
                          child: ElevatedButton(
                          onPressed: () async {
                            if (selectedTeacherId == null) {
                              _showError('Veuillez sélectionner un professeur');
                              return;
                            }
                            if (selectedSubjectId == null) {
                              _showError('Veuillez sélectionner une matière');
                              return;
                            }
                            try {
                              final notifier = ref.read(subjectsManagementProvider.notifier);
                              if (editTeacherId != null) {
                                await notifier.deleteAllTeacherAssignments(editTeacherId);
                              }
                              await notifier.addTeacherAssignmentsBulk(
                                teacherId: selectedTeacherId!,
                                subjectId: selectedSubjectId!,
                                niveauIds: selectedNiveauIds.toList(),
                                classIds: selectedClassIds.toList(),
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              _showSuccess(
                                editTeacherId != null
                                    ? 'Affectations mises à jour'
                                    : 'Professeur affecté avec succès',
                              );
                            } catch (e) {
                              _showError(UserFriendlyError.format(e));
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _brand,
                            foregroundColor: Colors.white,
                            elevation: 2,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          child: Text(editTeacherId != null ? 'Mettre à jour' : 'Affecter'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Dialog to create a new teacher (prof)
  void _showCreateTeacherDialog(SubjectsManagementState state) {
    final fullNameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController(text: '+216 ');
    bool isCreating = false;

    // ── Compact field helpers (class_detail style) ──
    Widget cLabel(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            text,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textTertiary, letterSpacing: 1),
          ),
        );

    InputDecoration cInput({String? hint, IconData? icon}) => InputDecoration(
          filled: false,
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
          prefixIcon: icon != null ? Icon(icon, size: 16, color: AppColors.textTertiary) : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E4EA))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E4EA))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _brand, width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.error)),
        );

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 440,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 24)],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Header ──
                      Row(children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(color: _brandLight, borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.person_add_rounded, color: _brand, size: 18),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Nouveau professeur', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                          Text('Créer et assigner à une classe', style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                        ])),
                        IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close_rounded, size: 20)),
                      ]),
                      const SizedBox(height: 20),
                      const Divider(height: 1, color: Color(0xFFF1F1F5)),
                      const SizedBox(height: 20),

                      // ── Full name ──
                      cLabel('NOM COMPLET *'),
                      TextField(
                        controller: fullNameController,
                        style: const TextStyle(fontSize: 13),
                        decoration: cInput(hint: 'Ex: Ahmed Ben Salah', icon: Icons.person_outline_rounded),
                      ),
                      const SizedBox(height: 14),

                      // ── Email ──
                      cLabel('EMAIL'),
                      TextField(
                        controller: emailController,
                        style: const TextStyle(fontSize: 13),
                        keyboardType: TextInputType.emailAddress,
                        decoration: cInput(hint: 'prof@ecole.tn', icon: Icons.email_outlined),
                      ),
                      const SizedBox(height: 14),

                      // ── Phone ──
                      cLabel('TÉLÉPHONE (OPTIONNEL)'),
                      TextField(
                        controller: phoneController,
                        style: const TextStyle(fontSize: 13),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[+\d ]')),
                          _PhoneFormatter216(),
                        ],
                        decoration: cInput(hint: '+216 XX XXX XXX', icon: Icons.phone_outlined),
                      ),
                      const SizedBox(height: 24),

                      // ── Create button ──
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          onPressed: isCreating
                              ? null
                              : () async {
                                  final fullName = fullNameController.text.trim();
                                  final email = emailController.text.trim();
                                  final phone = phoneController.text.trim();
                                  final phoneToStore = (phone.isEmpty || phone == '+216') ? null : phone;

                                  if (fullName.isEmpty) {
                                    _showError('Le nom est obligatoire');
                                    return;
                                  }
                                  if (email.isNotEmpty && !email.contains('@')) {
                                    _showError('Email invalide');
                                    return;
                                  }
                                  // Phone validation: +216 + 8 digits
                                  if (phoneToStore != null) {
                                    final digits = phoneToStore.replaceAll(RegExp(r'[^\d]'), '');
                                    if (!phoneToStore.startsWith('+216') || (digits.length - 3) != 8) {
                                      _showError('Numéro tunisien = +216 suivi de 8 chiffres');
                                      return;
                                    }
                                  }

                                  setDialogState(() => isCreating = true);
                                  try {
                                    await ref
                                        .read(subjectsManagementProvider.notifier)
                                        .createTeacher(
                                          fullName: fullName,
                                          email: email.isEmpty ? null : email,
                                          phone: phoneToStore,
                                        );

                                    if (ctx.mounted) Navigator.pop(ctx);
                                    _showSuccess('Professeur "$fullName" créé avec succès');

                                    Future.delayed(const Duration(milliseconds: 500), () {
                                      final newState = ref.read(subjectsManagementProvider).value;
                                      if (newState != null) {
                                        _showTeacherAssignmentDialog(newState);
                                      }
                                    });
                                  } catch (e) {
                                    setDialogState(() => isCreating = false);
                                    _showError(UserFriendlyError.format(e));
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _brand,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          child: isCreating
                              ? const IosLoader.small(color: Colors.white)
                              : const Text('Créer le professeur'),
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
    );
  }

  // ignore: unused_element
  Widget _buildDialogSection(
    String title,
    IconData icon, {
    String? subtitle,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AppColors.secondary),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(width: 8),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  /// Reusable label widget matching ClassFormDialog style
  Widget _dialogFieldLabel(String label, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          text: label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF374151)),
          children: [
            if (required)
              const TextSpan(text: ' *', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Color _getSubjectColor(String? code) {
    if (code == null || code.isEmpty) {
      // Auto-generate a pastel color from the hashCode — NEVER return grey
      return HSLColor.fromAHSL(
        1.0,
        (code.hashCode % 360).toDouble(),
        0.65,
        0.55,
      ).toColor();
    }
    switch (code.toUpperCase()) {
      case 'MATH':
      case 'MATHS':
        return const Color(0xFF2563EB); // blue
      case 'PHYS':
        return const Color(0xFFDC2626); // red
      case 'SVT':
        return const Color(0xFF059669); // emerald
      case 'AR':
        return const Color(0xFF0891B2); // cyan
      case 'FR':
        return const Color(0xFF7C3AED); // violet
      case 'EN':
        return const Color(0xFFDB2777); // pink
      case 'HG':
      case 'HIST':
        return const Color(0xFFCA8A04); // yellow-700
      case 'PHILO':
        return const Color(0xFF4F46E5); // indigo
      case 'INFO':
        return const Color(0xFF0284C7); // sky
      case 'EPS':
        return const Color(0xFF059669); // green
      case 'ESP':
        return const Color(0xFFE11D48); // rose
      case 'TECH':
        return const Color(0xFF6D28D9); // purple
      case 'SYS':
        return const Color(0xFF0369A1); // blue
      case 'RESEAUX':
        return const Color(0xFF0E7490); // teal
      case 'PROG':
        return const Color(0xFF7C3AED); // violet
      case 'PHY':
        return const Color(0xFF2563EB); // blue
      case 'MUS':
        return const Color(0xFFBE185D); // pink
      case 'LV3':
        return const Color(0xFF059669); // emerald
      case 'PENS_IS':
        return const Color(0xFF7E22CE); // purple
      default:
        // Auto-generate a pastel hue — NEVER grey
        final hue = (code.hashCode % 360).abs().toDouble();
        return HSLColor.fromAHSL(1.0, hue, 0.60, 0.50).toColor();
    }
  }

  Color _getNiveauColor(String code) {
    switch (code.toUpperCase()) {
      case '1AM':
      case '1AS':
        return const Color(0xFF7C3AED);
      case '2AM':
      case '2AS':
        return const Color(0xFF2563EB);
      case '3AM':
      case '3AS':
        return const Color(0xFF059669);
      case '4AM':
        return const Color(0xFFF97316);
      default:
        return const Color(0xFF6B7280);
    }
  }

  Color _getCoefColor(double coef) {
    if (coef >= 5) return AppColors.errorSoft;
    if (coef >= 3) return AppColors.accentSoft;
    if (coef >= 2) return AppColors.warningSoft;
    return AppColors.borderLight;
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.success),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }
}

// ignore: unused_element
class _DashedRectPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;

  _DashedRectPainter({
    required this.color,
    required this.strokeWidth,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path();
    final width = size.width;
    final height = size.height;
    final r = 12.0;

    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width, height),
      Radius.circular(r),
    ));

    final dashPath = Path();
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      bool draw = true;
      while (distance < metric.length) {
        final length = gap * 1.5;
        if (draw) {
          dashPath.addPath(
            metric.extractPath(distance, distance + length),
            Offset.zero,
          );
        }
        distance += length;
        draw = !draw;
      }
    }
    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PhoneFormatter216 extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.text.startsWith('+216')) {
      return oldValue;
    }
    return newValue;
  }
}

