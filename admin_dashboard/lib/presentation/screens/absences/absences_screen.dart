import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../providers/absences_provider.dart';
import '../../widgets/admin_sidebar.dart';
import '../../widgets/admin_sort_dropdown.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/ios_loader.dart';
import '../../widgets/skeleton_loader.dart';
import '../../../data/models/class_model.dart';
import '../../widgets/modern_animated_switch.dart';

class AbsencesScreen extends ConsumerStatefulWidget {
  const AbsencesScreen({super.key});

  @override
  ConsumerState<AbsencesScreen> createState() => _AbsencesScreenState();
}

class _AbsencesScreenState extends ConsumerState<AbsencesScreen> {
  final _searchController = TextEditingController();
  bool _showFilters = false;
  bool _isSelectionMode = false;
  String _sortKey = 'date_desc';

  // Filter drawer cascade state
  String? _filterNiveauId;
  String? _filterSectionId;

  // Pagination state
  int _currentPage = 1;
  int _itemsPerPage = 20;
  static const List<int> _perPageOptions = [10, 20, 50, 100, -1];


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(absencesProvider.notifier).clearFilters();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildGradientActionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required LinearGradient gradient,
    required Color shadowColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.textOnPrimary),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: AppColors.textOnPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final absencesAsync = ref.watch(absencesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Row(
            children: [
              const AdminSidebar(currentRoute: '/absences'),
              Expanded(
                child: Column(
                  children: [
                    _buildHeader(context, absencesAsync),
                    if (_isSelectionMode)
                      _buildSelectionBar(context, absencesAsync),
                    Expanded(
                      child: absencesAsync.when(
                        loading: () => const TableSkeletonLoader(),
                        error: (e, _) => _buildErrorState(e),
                        data: (state) => _buildContent(context, state),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Filter drawer overlay — full-app blur
          if (_showFilters) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showFilters = false),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(color: Colors.black.withOpacity(0.28)),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 370,
              child: _buildFilterDrawer(context, absencesAsync),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AsyncValue<AbsencesState> absencesAsync,
  ) {
    final state = absencesAsync.asData?.value;
    final filteredCount = state?.filtered.length ?? 0;
    final totalHours = state?.totalHours ?? 0;
    final isSearching = _searchController.text.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE9EAF2))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Gestion des Absences',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$filteredCount absence(s) • ${totalHours.toStringAsFixed(1)}h total',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
          const Spacer(),
          // Toolbar: pinned far right
          SizedBox(
            width: 320,
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: (v) => ref.read(absencesProvider.notifier).setSearchQuery(v),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Rechercher étudiant, classe, matière...',
                hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textTertiary),
                suffixIcon: !isSearching
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
                          ref.read(absencesProvider.notifier).setSearchQuery('');
                        },
                      ),
                filled: true,
                fillColor: AppColors.slate50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
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
                  borderSide: BorderSide(color: const Color(0xFF655DD5).withOpacity(0.4), width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          AdminSortDropdown<String>(
            value: _sortKey,
            tooltip: 'Trier les absences',
            onChanged: (v) => setState(() {
              _sortKey = v;
              _currentPage = 1;
            }),
            options: const [
              SortOption(value: 'date_desc', label: 'Date (Plus récent)', icon: Icons.calendar_today_outlined),
              SortOption(value: 'date_asc', label: 'Date (Plus ancien)', icon: Icons.calendar_today_outlined),
              SortOption(value: 'student_asc', label: 'Étudiant (A → Z)', icon: Icons.sort_by_alpha),
              SortOption(value: 'student_desc', label: 'Étudiant (Z → A)', icon: Icons.sort_by_alpha),
              SortOption(value: 'class_asc', label: 'Classe (A → Z)', icon: Icons.class_outlined),
              SortOption(value: 'unjustified_first', label: 'Non justifiées d’abord', icon: Icons.warning_amber_rounded),
              SortOption(value: 'justified_first', label: 'Justifiées d’abord', icon: Icons.check_circle_outline),
              SortOption(value: 'hours_desc', label: 'Heures (Décroissant)', icon: Icons.access_time),
            ],
          ),
          const SizedBox(width: 8),
          _buildHeaderIconButton(
            icon: Icons.filter_list_rounded,
            tooltip: 'Filtres',
            isActive: _showFilters || _hasActiveFilters(state),
            onPressed: () => setState(() => _showFilters = !_showFilters),
          ),
          const SizedBox(width: 8),
          _buildHeaderIconButton(
            icon: Icons.file_download_outlined,
            tooltip: 'Exporter CSV',
            onPressed: () {
              // TODO: Implement CSV download
            },
          ),
          const SizedBox(width: 8),
          const SizedBox(width: 16),
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: () => _showAddAbsenceDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Ajouter', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6D4CF6),
                disabledBackgroundColor: AppColors.slate300,
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
    );
  }

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
          side: BorderSide(color: isActive ? const Color(0xFF655DD5).withOpacity(0.2) : Colors.transparent),
        ),
      ),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }

  bool _hasActiveFilters(AbsencesState? state) {
    if (state == null) return false;
    return state.classFilter != null ||
        state.materialFilter != null ||
        state.subjectFilter != null ||
        state.justifiedFilter != null ||
        state.dateFromFilter != null ||
        state.dateToFilter != null;
  }

  Widget _buildSelectionBar(
    BuildContext context,
    AsyncValue<AbsencesState> absencesAsync,
  ) {
    final state = absencesAsync.asData?.value;
    final selectedCount = state?.selectedIds.length ?? 0;
    final filteredCount = state?.filtered.length ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withOpacity(0.1), AppColors.primary.withOpacity(0.05)],
        ),
        border: Border(bottom: BorderSide(color: AppColors.primary.withOpacity(0.2))),
      ),
      child: Row(
        children: [
          Checkbox(
            value: selectedCount > 0 && selectedCount == filteredCount,
            tristate: true,
            activeColor: AppColors.primary,
            onChanged: (v) {
              if (v == true || selectedCount == 0) {
                ref.read(absencesProvider.notifier).selectAll();
              } else {
                ref.read(absencesProvider.notifier).clearSelection();
              }
            },
          ),
          Text(
            '$selectedCount sélectionné(s)',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 24),
          if (selectedCount > 0) ...[
            _buildGradientActionButton(
              onPressed: () async {
                try {
                  final count = await ref
                      .read(absencesProvider.notifier)
                      .bulkToggleJustified(true);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '$count absence(s) marquée(s) justifiée(s)',
                        ),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                } catch (_) {}
              },
              icon: Icons.check_circle_rounded,
              label: 'Justifier',
              gradient: AppColors.successGradient,
              shadowColor: AppColors.success,
            ),
            const SizedBox(width: 8),
            _buildGradientActionButton(
              onPressed: () async {
                try {
                  final count = await ref
                      .read(absencesProvider.notifier)
                      .bulkToggleJustified(false);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '$count absence(s) marquée(s) non justifiée(s)',
                        ),
                        backgroundColor: AppColors.warning,
                      ),
                    );
                  }
                } catch (_) {}
              },
              icon: Icons.cancel_rounded,
              label: 'Non justifier',
              gradient: AppColors.warningGradient,
              shadowColor: AppColors.warning,
            ),
            const SizedBox(width: 8),
            _buildGradientActionButton(
              onPressed: () => _confirmBulkDelete(context, selectedCount),
              icon: Icons.delete_rounded,
              label: 'Supprimer',
              gradient: AppColors.errorGradient,
              shadowColor: AppColors.error,
            ),
          ],
          const Spacer(),
          TextButton(
            onPressed: () {
              setState(() => _isSelectionMode = false);
              ref.read(absencesProvider.notifier).clearSelection();
            },
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDrawer(
    BuildContext context,
    AsyncValue<AbsencesState> absencesAsync,
  ) {
    final state = absencesAsync.asData?.value;
    if (state == null) return const SizedBox.shrink();

    final allClasses = state.classes;
    // Map of unique gradeLevelId -> gradeLevelName
    final Map<String, String> niveaux = {};
    for (final c in allClasses) {
      if (c.gradeLevelId != null && c.gradeLevelName != null) {
        niveaux[c.gradeLevelId!] = c.gradeLevelName!;
      }
    }

    // Sections (filières) for selected niveau
    final Map<String, String> sectionsForNiveau = {};
    if (_filterNiveauId != null) {
      for (final c in allClasses) {
        if (c.gradeLevelId == _filterNiveauId && c.sectionId != null && c.sectionName != null) {
          sectionsForNiveau[c.sectionId!] = c.sectionName!;
        }
      }
    }
    final hasSections = sectionsForNiveau.isNotEmpty;

    // Filtered classes according to niveau and section
    final availableClasses = allClasses.where((c) {
      if (_filterNiveauId != null && c.gradeLevelId != _filterNiveauId) return false;
      if (hasSections && _filterSectionId != null && c.sectionId != _filterSectionId) return false;
      return true;
    }).toList();

    return Material(
      elevation: 16,
      color: Colors.white,
      child: Container(
        width: 340,
        height: double.infinity,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.5))),
              ),
              child: Row(
                children: [
                  const Text('Filtres', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => setState(() => _showFilters = false),
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Niveau
                    _buildFilterLabel('NIVEAU'),
                    const SizedBox(height: 8),
                    _buildFilterDropdown<String?>(
                      value: _filterNiveauId,
                      hint: 'Tous les niveaux',
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Tous les niveaux')),
                        ...niveaux.entries.map(
                          (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        _filterNiveauId = v;
                        _filterSectionId = null;
                        ref.read(absencesProvider.notifier).setClassFilter(null);
                      }),
                    ),
                    const SizedBox(height: 20),

                    // Filière (if exists)
                    if (hasSections) ...[
                      _buildFilterLabel('FILIÈRE'),
                      const SizedBox(height: 8),
                      _buildFilterDropdown<String?>(
                        value: _filterSectionId,
                        hint: 'Toutes les filières',
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Toutes les filières')),
                          ...sectionsForNiveau.entries.map(
                            (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                          ),
                        ],
                        onChanged: (v) => setState(() {
                          _filterSectionId = v;
                          ref.read(absencesProvider.notifier).setClassFilter(null);
                        }),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Classe
                    _buildFilterLabel('CLASSE'),
                    const SizedBox(height: 8),
                    _buildFilterDropdown<String?>(
                      value: state.classFilter,
                      hint: _filterNiveauId != null ? 'Classes (${availableClasses.length})' : 'Toutes les classes',
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(_filterNiveauId != null ? 'Toutes (${availableClasses.length})' : 'Toutes les classes'),
                        ),
                        ...availableClasses.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                      ],
                      onChanged: (v) => ref.read(absencesProvider.notifier).setClassFilter(v),
                    ),
                    const SizedBox(height: 20),

                    // Matière
                    _buildFilterLabel('MATIÈRE'),
                    const SizedBox(height: 8),
                    _buildFilterDropdown<String?>(
                      value: state.materialFilter,
                      hint: 'Toutes les matières',
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Toutes les matières')),
                        ...state.uniqueSubjectNames.map(
                          (name) => DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis)),
                        ),
                      ],
                      onChanged: (v) => ref.read(absencesProvider.notifier).setMaterialFilter(v),
                    ),
                    const SizedBox(height: 20),

                    if (state.materialFilter != null && state.classesForSelectedMaterial.isNotEmpty) ...[
                      _buildFilterLabel('CLASSE (${state.materialFilter})'),
                      const SizedBox(height: 8),
                      _buildFilterDropdown<String?>(
                        value: state.subjectFilter,
                        hint: 'Toutes',
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Toutes')),
                          ...state.classesForSelectedMaterial.map(
                            (o) => DropdownMenuItem(value: o.id, child: Text(o.className ?? '?', overflow: TextOverflow.ellipsis)),
                          ),
                        ],
                        onChanged: (v) => ref.read(absencesProvider.notifier).setSubjectFilter(v),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Justification
                    _buildFilterLabel('JUSTIFICATION'),
                    const SizedBox(height: 8),
                    _buildFilterDropdown<String?>(
                      value: state.justifiedFilter,
                      hint: 'Tous',
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Tous')),
                        DropdownMenuItem(value: 'justified', child: Text('Justifiées')),
                        DropdownMenuItem(value: 'not_justified', child: Text('Non justifiées')),
                      ],
                      onChanged: (v) => ref.read(absencesProvider.notifier).setJustifiedFilter(v),
                    ),
                    const SizedBox(height: 20),

                    // Période
                    _buildFilterLabel('PÉRIODE'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDatePickerField(
                            value: state.dateFromFilter,
                            hint: 'Date début',
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: state.dateFromFilter ?? DateTime.now().subtract(const Duration(days: 30)),
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (date != null) {
                                ref.read(absencesProvider.notifier).setDateRange(date, state.dateToFilter);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDatePickerField(
                            value: state.dateToFilter,
                            hint: 'Date fin',
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: state.dateToFilter ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (date != null) {
                                ref.read(absencesProvider.notifier).setDateRange(state.dateFromFilter, date);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Bottom buttons
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
                        onPressed: () {
                          setState(() {
                            _filterNiveauId = null;
                            _filterSectionId = null;
                          });
                          ref.read(absencesProvider.notifier).clearFilters();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF374151),
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFFD1D5DB)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: const Text('Réinitialiser', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6D4CF6),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6D4CF6).withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => setState(() => _showFilters = false),
                          borderRadius: BorderRadius.circular(12),
                          child: const Center(
                            child: Text(
                              'Appliquer',
                              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
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

  Widget _buildFilterLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textTertiary,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildFilterDropdown<T>({
    required T value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint, style: const TextStyle(fontSize: 13, color: AppColors.textTertiary)),
          isExpanded: true,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          items: items,
          onChanged: onChanged,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          borderRadius: BorderRadius.circular(8),
          dropdownColor: Colors.white,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textTertiary),
        ),
      ),
    );
  }

  Widget _buildDatePickerField({DateTime? value, required String hint, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.slate50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value != null ? DateFormat('d MMM yyyy', 'fr_FR').format(value) : hint,
                style: TextStyle(
                  fontSize: 13,
                  color: value != null ? AppColors.textPrimary : AppColors.textTertiary,
                ),
              ),
            ),
            const Icon(Icons.calendar_month, size: 16, color: AppColors.textTertiary),
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
          Icon(Icons.error_outline, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          Text(
            UserFriendlyError.format(
              error,
              fallback: 'Unable to load absences right now. Please try again.',
            ),
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => ref.invalidate(absencesProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, AbsencesState state) {
    final list = state.filtered;

    return Stack(
      children: [
        Container(
          color: const Color(0xFFF8FAFC),
          padding: const EdgeInsets.all(24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border.withOpacity(0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  Expanded(
                    child: list.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.event_available, size: 64, color: AppColors.slate300),
                                const SizedBox(height: 16),
                                const Text('Aucune absence trouvée', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                const Text('Modifiez vos filtres ou ajoutez une nouvelle absence', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                              ],
                            ),
                          )
                        : _buildAbsenceDataTable(context, state),
                  ),
                  _buildPagination(list.length),
                ],
              ),
            ),
          ),
        ),
        if (state.selectedIds.isNotEmpty)
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(child: _buildFloatingSelectionBar(context, state)),
          ),
      ],
    );
  }

  Widget _buildFloatingSelectionBar(BuildContext context, AbsencesState state) {
    final count = state.selectedIds.length;

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
                      child: Text('$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('Sélectionnés', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white)),
                ],
              ),
            ),
            // Actions
            _buildSelectionAction(
              icon: Icons.check_circle_outlined,
              label: 'Justifier',
              color: Colors.white70,
              onPressed: () async {
                try {
                  final counted = await ref.read(absencesProvider.notifier).bulkToggleJustified(true);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$counted absence(s) marquée(s) justifiée(s)', style: const TextStyle(color: Colors.white)), backgroundColor: AppColors.success));
                  }
                } catch (_) {}
              },
            ),
            _buildSelectionAction(
              icon: Icons.cancel_outlined,
              label: 'Non justifier',
              color: Colors.white70,
              onPressed: () async {
                try {
                  final counted = await ref.read(absencesProvider.notifier).bulkToggleJustified(false);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$counted absence(s) marquée(s) non justifiée(s)', style: const TextStyle(color: Colors.white)), backgroundColor: AppColors.warning));
                  }
                } catch (_) {}
              },
            ),
            _buildSelectionAction(
              icon: Icons.delete_outline,
              label: 'Supprimer',
              color: const Color(0xFFFCA5A5),
              onPressed: () {
                _confirmBulkDelete(context, count);
              },
            ),
            // Close button
            Container(
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: Colors.white.withOpacity(0.15))),
              ),
              child: IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.white60),
                onPressed: () => ref.read(absencesProvider.notifier).clearSelection(),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
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

  Widget _buildAbsenceDataTable(BuildContext context, AbsencesState state) {
    final rawAbsences = state.filtered;
    final absences = List<AbsenceModel>.from(rawAbsences);
    switch (_sortKey) {
      case 'date_asc':
        absences.sort((a, b) {
          final cmp = a.date.compareTo(b.date);
          if (cmp != 0) return cmp;
          final cCmp = a.createdAt.compareTo(b.createdAt);
          if (cCmp != 0) return cCmp;
          return a.id.compareTo(b.id);
        });
        break;
      case 'student_asc':
        absences.sort((a, b) {
          final cmp = a.studentName.toLowerCase().compareTo(b.studentName.toLowerCase());
          if (cmp != 0) return cmp;
          final dCmp = b.date.compareTo(a.date);
          if (dCmp != 0) return dCmp;
          return a.id.compareTo(b.id);
        });
        break;
      case 'student_desc':
        absences.sort((a, b) {
          final cmp = b.studentName.toLowerCase().compareTo(a.studentName.toLowerCase());
          if (cmp != 0) return cmp;
          final dCmp = b.date.compareTo(a.date);
          if (dCmp != 0) return dCmp;
          return a.id.compareTo(b.id);
        });
        break;
      case 'class_asc':
        absences.sort((a, b) {
          final cmp = (a.className ?? '').toLowerCase().compareTo((b.className ?? '').toLowerCase());
          if (cmp != 0) return cmp;
          final dCmp = b.date.compareTo(a.date);
          if (dCmp != 0) return dCmp;
          return a.id.compareTo(b.id);
        });
        break;
      case 'unjustified_first':
        absences.sort((a, b) {
          if (a.justified != b.justified) return a.justified ? 1 : -1;
          final dCmp = b.date.compareTo(a.date);
          if (dCmp != 0) return dCmp;
          final cCmp = b.createdAt.compareTo(a.createdAt);
          if (cCmp != 0) return cCmp;
          return a.id.compareTo(b.id);
        });
        break;
      case 'justified_first':
        absences.sort((a, b) {
          if (a.justified != b.justified) return a.justified ? -1 : 1;
          final dCmp = b.date.compareTo(a.date);
          if (dCmp != 0) return dCmp;
          final cCmp = b.createdAt.compareTo(a.createdAt);
          if (cCmp != 0) return cCmp;
          return a.id.compareTo(b.id);
        });
        break;
      case 'hours_desc':
        absences.sort((a, b) {
          final cmp = b.hoursAbsent.compareTo(a.hoursAbsent);
          if (cmp != 0) return cmp;
          final dCmp = b.date.compareTo(a.date);
          if (dCmp != 0) return dCmp;
          return a.id.compareTo(b.id);
        });
        break;
      case 'date_desc':
      default:
        absences.sort((a, b) {
          final cmp = b.date.compareTo(a.date);
          if (cmp != 0) return cmp;
          final cCmp = b.createdAt.compareTo(a.createdAt);
          if (cCmp != 0) return cCmp;
          return a.id.compareTo(b.id);
        });
        break;
    }
    final dateFormat = DateFormat('d MMM yyyy', 'fr_FR');

    final totalPages = _itemsPerPage == -1 ? 1 : (absences.length / _itemsPerPage).ceil();
    if (_currentPage > totalPages && totalPages > 0) _currentPage = totalPages;
    final startIndex = _itemsPerPage == -1 ? 0 : (_currentPage - 1) * _itemsPerPage;
    final endIndex = _itemsPerPage == -1 ? absences.length : (startIndex + _itemsPerPage).clamp(0, absences.length);
    final pageAbsences = absences.sublist(startIndex, endIndex);
    final allPageSelected = pageAbsences.isNotEmpty && pageAbsences.every((a) => state.selectedIds.contains(a.id));

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        const checkboxW = 44.0;
        const actionsW = 44.0;
        const classeW = 85.0;
        const subjectW = 140.0;
        const dateW = 100.0;
        const hoursW = 80.0;
        const justifW = 110.0;

        final fixedW = checkboxW + classeW + subjectW + dateW + hoursW + justifW + actionsW;
        final nameW = (availableWidth - fixedW).clamp(180.0, 320.0);

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: availableWidth),
            child: DataTable(
              columnSpacing: 0,
              horizontalMargin: 0,
              dataRowMinHeight: 60,
              dataRowMaxHeight: 64,
              headingRowHeight: 44,
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
              headingTextStyle: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
              showCheckboxColumn: false,
              columns: [
                DataColumn(
                  label: SizedBox(
                    width: checkboxW,
                    child: Center(
                      child: SizedBox(
                        width: 16, height: 16,
                        child: Checkbox(
                          value: allPageSelected && pageAbsences.isNotEmpty,
                          tristate: false,
                          onChanged: (v) {
                            if (allPageSelected) {
                              for (final a in pageAbsences) ref.read(absencesProvider.notifier).toggleSelection(a.id);
                            } else {
                              for (final a in pageAbsences) {
                                if (!state.selectedIds.contains(a.id)) {
                                  ref.read(absencesProvider.notifier).toggleSelection(a.id);
                                }
                              }
                            }
                          },
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                          side: BorderSide(color: AppColors.slate300, width: 1.5),
                          activeColor: const Color(0xFF655DD5),
                        ),
                      ),
                    ),
                  ),
                ),
                DataColumn(label: SizedBox(width: nameW, child: _headerLabel('NOM COMPLET / ÉTUDIANT'))),
                DataColumn(label: SizedBox(width: classeW, child: _headerLabel('CLASSE'))),
                DataColumn(label: SizedBox(width: subjectW, child: _headerLabel('MATIÈRE'))),
                DataColumn(label: SizedBox(width: dateW, child: _headerLabel('DATE'))),
                DataColumn(label: SizedBox(width: hoursW, child: _headerLabel('HEURES'))),
                DataColumn(label: SizedBox(width: justifW, child: _headerLabel('JUSTIFIÉ'))),
                DataColumn(label: SizedBox(width: actionsW, child: Container())),
              ],
              rows: pageAbsences.map((a) {
                final isSelected = state.selectedIds.contains(a.id);
                return DataRow(
                  color: WidgetStateProperty.resolveWith<Color?>((states) {
                    if (isSelected) return const Color(0xFFF5F3FF).withOpacity(0.4);
                    if (states.contains(WidgetState.hovered)) return const Color(0xFFF9FAFB);
                    return null;
                  }),
                  cells: [
                    // Checkbox
                    DataCell(
                      SizedBox(
                        width: checkboxW,
                        child: Center(
                          child: SizedBox(
                            width: 16, height: 16,
                            child: Checkbox(
                              value: isSelected,
                              onChanged: (v) => ref.read(absencesProvider.notifier).toggleSelection(a.id),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                              side: BorderSide(color: AppColors.slate300, width: 1.5),
                              activeColor: const Color(0xFF655DD5),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Name + Subtitle
                    DataCell(
                      SizedBox(
                        width: nameW,
                        child: Row(
                          children: [
                            UserAvatar(
                              name: a.studentName,
                              photoUrl: a.studentPhotoUrl,
                              radius: 17,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    a.studentName,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    a.className ?? 'Étudiant',
                                    style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      onTap: () {
                        if (a.studentId.isNotEmpty) context.push('/student-absences/${a.studentId}');
                      },
                    ),
                    // Classe
                    DataCell(SizedBox(
                      width: classeW,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            a.className ?? '—',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF059669)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    )),
                    // Matière
                    DataCell(SizedBox(
                      width: subjectW,
                      child: Text(
                        a.subjectName ?? '—',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
                    // Date
                    DataCell(SizedBox(
                      width: dateW,
                      child: Text(
                        dateFormat.format(a.date),
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    )),
                    // Heures
                    DataCell(SizedBox(
                      width: hoursW,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.slate50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${a.hoursAbsent.toStringAsFixed(0)}h',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, fontFamily: 'monospace', color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                    )),
                    // Justifié
                    DataCell(SizedBox(
                      width: justifW,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _JustifiedBadge(
                          justified: a.justified,
                          onTap: () async {
                            try {
                              await ref.read(absencesProvider.notifier).toggleJustified(a.id, a.justified);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(UserFriendlyError.format(e)),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ),
                    )),
                    // Actions
                    DataCell(SizedBox(
                      width: actionsW,
                      child: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz, size: 18, color: AppColors.textTertiary),
                        tooltip: 'Actions',
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 8,
                        offset: const Offset(-160, 40),
                        onSelected: (value) {
                          if (value == 'edit') {
                            _showEditDialog(context, a);
                          } else if (value == 'delete') {
                            _confirmDelete(context, a);
                          } else if (value == 'view_profile') {
                            if (a.studentId.isNotEmpty) context.push('/users/${a.studentId}');
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'view_profile',
                            height: 40,
                            child: Row(
                              children: [
                                Icon(Icons.person_outline, size: 18, color: const Color(0xFF8B5CF6)),
                                const SizedBox(width: 12),
                                const Text('Voir le profil', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'edit',
                            height: 40,
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 18, color: const Color(0xFF655DD5)),
                                const SizedBox(width: 12),
                                const Text('Modifier', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'delete',
                            height: 40,
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                                const SizedBox(width: 12),
                                const Text('Supprimer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.error)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _headerLabel(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
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

  Widget _buildPagination(int totalItems) {
    final totalPages = _itemsPerPage == -1 ? 1 : (totalItems / _itemsPerPage).ceil();

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
          // Items per page
          Text('Afficher par ', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _itemsPerPage,
                isDense: true,
                borderRadius: BorderRadius.circular(10),
                dropdownColor: Colors.white,
                elevation: 4,
                menuMaxHeight: 200,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: AppColors.textTertiary),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                items: _perPageOptions.map((v) => DropdownMenuItem(
                  value: v,
                  child: Text(v == -1 ? 'All' : '$v', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                )).toList(),
                onChanged: (v) => setState(() {
                  _itemsPerPage = v!;
                  _currentPage = 1;
                }),
              ),
            ),
          ),
          const Spacer(),
          // Page info
          Text(
            'Page $_currentPage sur ${totalPages == 0 ? 1 : totalPages}',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          const SizedBox(width: 12),
          // Prev/Next
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(5)),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.chevron_left, size: 18, color: _currentPage > 1 ? AppColors.textSecondary : AppColors.textTertiary),
                  ),
                ),
                Container(width: 1, height: 24, color: AppColors.border),
                InkWell(
                  onTap: _currentPage < totalPages ? () => setState(() => _currentPage++) : null,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(5)),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.chevron_right, size: 18, color: _currentPage < totalPages ? AppColors.textSecondary : AppColors.textTertiary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddAbsenceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _AddAbsenceDialog(ref: ref),
    );
  }

  void _showEditDialog(BuildContext context, AbsenceModel absence) {
    final reasonController = TextEditingController(text: absence.reason);
    double hoursAbsent = absence.hoursAbsent;
    String? sessionType = absence.sessionType;
    bool justified = absence.justified;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(20),
            child: Container(
              width: 520,
              constraints: const BoxConstraints(maxHeight: 600),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 50, offset: const Offset(0, 20))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Header ──
                  Container(
                    padding: const EdgeInsets.fromLTRB(28, 20, 20, 20),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      border: Border(bottom: BorderSide(color: AppColors.slate100)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(color: const Color(0xFF6D4CF6).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.edit_outlined, color: Color(0xFF6D4CF6), size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Modifier l\'absence', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                              const SizedBox(height: 2),
                              Text('${absence.studentName} · ${absence.className ?? ""}', style: const TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: () => Navigator.pop(ctx),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.slate50),
                            child: const Icon(Icons.close, size: 18, color: AppColors.textTertiary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ── Body ──
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Date info badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: AppColors.slate50, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.borderLight)),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textTertiary),
                                const SizedBox(width: 8),
                                Text('${DateFormat('d MMM yyyy', 'fr_FR').format(absence.date)} · ${absence.subjectName ?? "—"}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          // Heures + Type row
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Heures', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate700)),
                                    const SizedBox(height: 8),
                                    Container(
                                      decoration: BoxDecoration(color: AppColors.slate50, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.borderLight)),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButtonFormField<double>(
                                          value: hoursAbsent,
                                          items: [1, 2, 3, 4, 5, 6].map((h) => DropdownMenuItem(value: h.toDouble(), child: Text('${h}h'))).toList(),
                                          onChanged: (v) => setDialogState(() => hoursAbsent = v ?? 2),
                                          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                                          decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none),
                                          dropdownColor: Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate700)),
                                    const SizedBox(height: 8),
                                    Container(
                                      decoration: BoxDecoration(color: AppColors.slate50, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.borderLight)),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButtonFormField<String>(
                                          value: sessionType,
                                          items: const [
                                            DropdownMenuItem(value: null, child: Text('—')),
                                            DropdownMenuItem(value: 'CI', child: Text('CI')),
                                            DropdownMenuItem(value: 'TD', child: Text('TD')),
                                            DropdownMenuItem(value: 'TP', child: Text('TP')),
                                          ],
                                          onChanged: (v) => setDialogState(() => sessionType = v),
                                          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                                          decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none),
                                          dropdownColor: Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Motif
                          const Text('Motif', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate700)),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(color: AppColors.slate50, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.borderLight)),
                            child: TextField(
                              controller: reasonController,
                              maxLines: 2,
                              style: const TextStyle(fontSize: 14),
                              decoration: const InputDecoration(
                                hintText: 'Ex: Maladie, RDV médical...',
                                hintStyle: TextStyle(color: AppColors.textTertiary),
                                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Justifiée toggle
                          Row(
                            children: [
                              const Expanded(child: Text('Justifiée', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
                              ModernAnimatedSwitch(
                                value: justified,
                                onChanged: (v) => setDialogState(() => justified = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // ── Footer ──
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                      border: Border(top: BorderSide(color: AppColors.slate100)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          height: 40,
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: TextButton.styleFrom(foregroundColor: const Color(0xFF6B7280), padding: const EdgeInsets.symmetric(horizontal: 20)),
                            child: const Text('Annuler', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 40,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await ref.read(absencesProvider.notifier).updateAbsence(
                                id: absence.id, hoursAbsent: hoursAbsent, sessionType: sessionType,
                                reason: reasonController.text.isNotEmpty ? reasonController.text : null, justified: justified,
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: const Text('Enregistrer', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6D4CF6),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 2,
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
    );
  }

  void _confirmDelete(BuildContext context, AbsenceModel absence) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Container(
                width: 36, height: 36,
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
              Text(
                'Voulez-vous vraiment supprimer l\'absence de "${absence.studentName}" ? Cette action est irréversible.',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: AppColors.slate50, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Date: ${DateFormat('d MMM yyyy', 'fr_FR').format(absence.date)}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500))),
                  ],
                ),
              ),
            ],
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
                    if (ctx.mounted) Navigator.pop(ctx);
                    try {
                      await ref.read(absencesProvider.notifier).delete(absence.id);
                    } catch (_) {}
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

  void _confirmBulkDelete(BuildContext context, int count) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => BackdropFilter(
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
              Text('Supprimer $count absence${count > 1 ? 's' : ''} ?', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          content: Text(
            'Cette action est irréversible. $count absence${count > 1 ? 's seront supprimées' : ' sera supprimée'} définitivement.',
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
                    if (ctx.mounted) Navigator.pop(ctx);
                    try {
                      final deleted = await ref.read(absencesProvider.notifier).deleteSelected();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$deleted absence(s) supprimée(s)'), backgroundColor: AppColors.error));
                      }
                    } catch (_) {}
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text('Supprimer $count', style: const TextStyle(fontWeight: FontWeight.w700)),
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
}

/// Period selection for bulk absences
enum AbsencePeriod { day, week, month, custom }

/// Dialog for adding new absences - SMART TIMETABLE-DRIVEN
class _AddAbsenceDialog extends StatefulWidget {
  final WidgetRef ref;
  const _AddAbsenceDialog({required this.ref});

  @override
  State<_AddAbsenceDialog> createState() => _AddAbsenceDialogState();
}

class _AddAbsenceDialogState extends State<_AddAbsenceDialog> {
  bool _isBulkMode = false;
  String? _selectedClassId;
  DateTime _selectedDate = DateTime.now();
  DateTime? _endDate; // For custom period
  AbsencePeriod _period = AbsencePeriod.day;
  String _reason = '';
  bool _justified = false;

  // Hierarchical selection
  String? _selectedNiveauId;
  String? _selectedSectionId;
  String _studentSearchQuery = '';
  final TextEditingController _studentSearchController =
      TextEditingController();

  // For single student mode
  String? _selectedStudentEnrollmentId;

  // For bulk/timetable mode
  List<StudentInfo> _classStudents = [];
  Set<String> _selectedStudentEnrollmentIds = {};

  // Timetable slots selection
  List<TimetableSlotInfo> _classTimetableSlots = [];
  Set<String> _selectedTimetableSlotIds = {};

  bool _isLoading = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _studentSearchController.dispose();
    super.dispose();
  }

  /// Get unique niveaux from classes
  List<Map<String, String>> _getUniqueNiveaux(List<ClassModel> classes) {
    final Map<String, String> niveauxMap = {};
    for (final c in classes) {
      if (c.gradeLevelId != null && c.gradeLevelName != null) {
        niveauxMap[c.gradeLevelId!] = c.gradeLevelName!;
      }
    }
    return niveauxMap.entries
        .map((e) => {'id': e.key, 'name': e.value})
        .toList()
      ..sort((a, b) => a['name']!.compareTo(b['name']!));
  }

  /// Get unique sections for selected niveau
  List<Map<String, String>> _getSectionsForNiveau(List<ClassModel> classes) {
    if (_selectedNiveauId == null) return [];

    final Map<String, String> sectionsMap = {};
    for (final c in classes) {
      if (c.gradeLevelId == _selectedNiveauId &&
          c.sectionId != null &&
          c.sectionName != null) {
        sectionsMap[c.sectionId!] = c.sectionName!;
      }
    }
    return sectionsMap.entries
        .map((e) => {'id': e.key, 'name': e.value})
        .toList()
      ..sort((a, b) => a['name']!.compareTo(b['name']!));
  }

  /// Get classes filtered by niveau and section
  List<ClassModel> _getFilteredClasses(List<ClassModel> classes) {
    if (_selectedNiveauId == null) return [];

    return classes.where((c) {
      if (c.gradeLevelId != _selectedNiveauId) return false;
      if (_selectedSectionId != null && c.sectionId != _selectedSectionId)
        return false;
      return true;
    }).toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Check if selected niveau has sections
  bool _niveauHasSections(List<ClassModel> classes) {
    if (_selectedNiveauId == null) return false;
    return classes.any(
      (c) =>
          c.gradeLevelId == _selectedNiveauId &&
          c.sectionId != null &&
          c.sectionName != null,
    );
  }

  /// Get filtered students for search
  List<StudentInfo> _getFilteredStudents(List<StudentInfo> allStudents) {
    if (_studentSearchQuery.trim().isEmpty) return const [];

    final query = _studentSearchQuery.toLowerCase().trim();
    return allStudents.where((s) {
      return s.fullName.toLowerCase().contains(query) ||
          (s.studentCode?.toLowerCase().contains(query) ?? false) ||
          (s.phone?.toLowerCase().contains(query) ?? false) ||
          (s.className?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.ref.watch(absencesProvider).asData?.value;
    if (state == null) return const SizedBox.shrink();

    final niveaux = _getUniqueNiveaux(state.classes);
    final sections = _getSectionsForNiveau(state.classes);
    final hasSections = _niveauHasSections(state.classes);
    final filteredClasses = _getFilteredClasses(state.classes);
    final filteredStudents = _getFilteredStudents(state.students);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          width: 720,
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 50, offset: const Offset(0, 20))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──
              Container(
                padding: const EdgeInsets.fromLTRB(28, 20, 20, 20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border(bottom: BorderSide(color: AppColors.slate100)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(color: const Color(0xFF6D4CF6).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.event_busy, color: Color(0xFF6D4CF6), size: 20),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text('Marquer absence', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ),
                    // Mode toggle
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _modePill(false, Icons.person, 'Individuelle'),
                          _modePill(true, Icons.groups, 'Classe'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.slate50),
                        child: const Icon(Icons.close, size: 18, color: AppColors.textTertiary),
                      ),
                    ),
                  ],
                ),
              ),
              // ── Body ──
              Flexible(
                child: _isSubmitting
                  ? const Padding(
                      padding: EdgeInsets.all(48),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IosLoader(),
                          SizedBox(height: 16),
                          Text('Création des absences en cours...'),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Student search bar (for individual mode)
                          if (!_isBulkMode) ...[
                            _fieldLabel('Rechercher un étudiant'),
                            const SizedBox(height: 8),

                            // Selected student card (if chosen)
                            if (_selectedStudentEnrollmentId != null) ...[
                              Builder(
                                builder: (context) {
                                  final sel = state.students
                                          .where((s) => s.enrollmentId == _selectedStudentEnrollmentId)
                                          .firstOrNull ??
                                      _classStudents
                                          .where((s) => s.enrollmentId == _selectedStudentEnrollmentId)
                                          .firstOrNull;
                                  if (sel == null) return const SizedBox.shrink();

                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6D4CF6).withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        UserAvatar(
                                          name: sel.fullName,
                                          photoUrl: sel.photoUrl,
                                          radius: 18,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                sel.fullName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14,
                                                  color: AppColors.textPrimary,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  if (sel.className != null) ...[
                                                    Text(
                                                      sel.className!,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Color(0xFF6D4CF6),
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                  ],
                                                  if (sel.studentCode != null)
                                                    Text(
                                                      sel.studentCode!,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color: AppColors.textTertiary,
                                                        fontFamily: 'monospace',
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.close, size: 18, color: AppColors.textTertiary),
                                          onPressed: () {
                                            setState(() {
                                              _selectedStudentEnrollmentId = null;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],

                            // Search textfield
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.slate50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.borderLight),
                              ),
                              child: TextField(
                                controller: _studentSearchController,
                                style: const TextStyle(fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: 'Rechercher par nom, téléphone, code...',
                                  hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                                  prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textTertiary),
                                  suffixIcon: _studentSearchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 16),
                                          onPressed: () => setState(() {
                                            _studentSearchController.clear();
                                            _studentSearchQuery = '';
                                          }),
                                        )
                                      : null,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                                onChanged: (v) => setState(() => _studentSearchQuery = v),
                              ),
                            ),

                            // Result count & interactive student list
                            if (_studentSearchQuery.trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: filteredStudents.isNotEmpty
                                          ? const Color(0xFF6D4CF6).withOpacity(0.1)
                                          : AppColors.slate100,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      filteredStudents.isEmpty
                                          ? 'Aucun résultat'
                                          : '${filteredStudents.length} résultat(s)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: filteredStudents.isNotEmpty
                                            ? const Color(0xFF6D4CF6)
                                            : AppColors.slate500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                constraints: const BoxConstraints(maxHeight: 240),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.borderLight),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.06),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: filteredStudents.isEmpty
                                    ? Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.search_off, size: 32, color: AppColors.slate300),
                                            const SizedBox(height: 6),
                                            Text(
                                              'Aucun élève trouvé pour "$_studentSearchQuery"',
                                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      )
                                    : ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: ListView.separated(
                                          shrinkWrap: true,
                                          itemCount: filteredStudents.length,
                                          separatorBuilder: (_, __) =>
                                              const Divider(height: 1, color: AppColors.slate100),
                                          itemBuilder: (context, index) {
                                            final student = filteredStudents[index];
                                            final isSelected =
                                                _selectedStudentEnrollmentId == student.enrollmentId;

                                            return Material(
                                              color: isSelected
                                                  ? const Color(0xFF6D4CF6).withOpacity(0.08)
                                                  : Colors.transparent,
                                              child: InkWell(
                                                onTap: () => _selectStudentFromSearch(
                                                  student,
                                                  state.classes,
                                                ),
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 10,
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      UserAvatar(
                                                        name: student.fullName,
                                                        photoUrl: student.photoUrl,
                                                        radius: 16,
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Text(
                                                              student.fullName,
                                                              style: const TextStyle(
                                                                fontSize: 13,
                                                                fontWeight: FontWeight.w600,
                                                                color: AppColors.textPrimary,
                                                              ),
                                                            ),
                                                            const SizedBox(height: 2),
                                                            Row(
                                                              children: [
                                                                if (student.className != null) ...[
                                                                  Container(
                                                                    padding: const EdgeInsets.symmetric(
                                                                      horizontal: 6,
                                                                      vertical: 2,
                                                                    ),
                                                                    decoration: BoxDecoration(
                                                                      color: AppColors.slate100,
                                                                      borderRadius:
                                                                          BorderRadius.circular(4),
                                                                    ),
                                                                    child: Text(
                                                                      student.className!,
                                                                      style: const TextStyle(
                                                                        fontSize: 11,
                                                                        color: AppColors.textSecondary,
                                                                        fontWeight: FontWeight.w500,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  const SizedBox(width: 6),
                                                                ],
                                                                if (student.studentCode != null)
                                                                  Text(
                                                                    student.studentCode!,
                                                                    style: const TextStyle(
                                                                      fontSize: 11,
                                                                      color: AppColors.textTertiary,
                                                                      fontFamily: 'monospace',
                                                                    ),
                                                                  ),
                                                              ],
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      if (isSelected)
                                                        const Icon(
                                                          Icons.check_circle,
                                                          size: 18,
                                                          color: Color(0xFF6D4CF6),
                                                        )
                                                      else
                                                        const Icon(
                                                          Icons.arrow_forward_ios,
                                                          size: 12,
                                                          color: AppColors.slate300,
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                              ),
                            ],
                            const SizedBox(height: 16),
                          ],

                          // Niveau, Filière (if applicable), and Classe on the same row
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Niveau
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _fieldLabel('Niveau *'),
                                    const SizedBox(height: 8),
                                    _premiumDropdown<String>(
                                      value: _selectedNiveauId,
                                      hint: 'Sélectionner un niveau',
                                      prefixIcon: Icons.school_outlined,
                                      items: niveaux
                                          .map(
                                            (n) => DropdownMenuItem(
                                              value: n['id'],
                                              child: Text(n['name']!, overflow: TextOverflow.ellipsis),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) {
                                        setState(() {
                                          _selectedNiveauId = v;
                                          _selectedSectionId = null;
                                          _selectedClassId = null;
                                          _classStudents.clear();
                                          _selectedStudentEnrollmentIds.clear();
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              if (_selectedNiveauId != null && hasSections) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _fieldLabel('Filière'),
                                      const SizedBox(height: 8),
                                      _premiumDropdown<String>(
                                        value: _selectedSectionId,
                                        hint: 'Sélectionner filière',
                                        prefixIcon: Icons.category_outlined,
                                        items: sections
                                            .map((s) => DropdownMenuItem(value: s['id'], child: Text(s['name']!, overflow: TextOverflow.ellipsis)))
                                            .toList(),
                                        onChanged: (v) => setState(() {
                                          _selectedSectionId = v;
                                          _selectedClassId = null;
                                          _classStudents.clear();
                                          _selectedStudentEnrollmentIds.clear();
                                        }),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(width: 12),
                              // Classe
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _fieldLabel('Classe *'),
                                    const SizedBox(height: 8),
                                    _premiumDropdown<String>(
                                      value: _selectedClassId,
                                      hint: _selectedNiveauId == null ? 'Choisir un niveau' : 'Sélectionner classe',
                                      prefixIcon: Icons.class_outlined,
                                      items: filteredClasses
                                          .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)))
                                          .toList(),
                                      onChanged: _selectedNiveauId == null ? null : _onClassChanged,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                    // Period selection (for bulk mode)
                    if (_isBulkMode) ...[
                      Text(
                        'Période d\'absence',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.slate700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          _periodChip(
                            AbsencePeriod.day,
                            Icons.today,
                            'Journée',
                          ),
                          _periodChip(
                            AbsencePeriod.week,
                            Icons.view_week,
                            'Semaine',
                          ),
                          _periodChip(
                            AbsencePeriod.month,
                            Icons.calendar_month,
                            'Mois',
                          ),
                          _periodChip(
                            AbsencePeriod.custom,
                            Icons.date_range,
                            'Personnalisé',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                          // Date selection
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _fieldLabel(_period == AbsencePeriod.custom ? 'Date début *' : 'Date *'),
                                    const SizedBox(height: 8),
                                    InkWell(
                                      onTap: () => _pickDate(isStart: true),
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                        decoration: BoxDecoration(
                                          color: AppColors.slate50,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: AppColors.borderLight),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.calendar_month, size: 18, color: AppColors.textTertiary),
                                            const SizedBox(width: 10),
                                            Text(DateFormat('EEE d MMM yyyy', 'fr_FR').format(_selectedDate), style: const TextStyle(fontSize: 14)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_isBulkMode && _period == AbsencePeriod.custom) ...[
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _fieldLabel('Date fin *'),
                                      const SizedBox(height: 8),
                                      InkWell(
                                        onTap: () => _pickDate(isStart: false),
                                        borderRadius: BorderRadius.circular(10),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                          decoration: BoxDecoration(
                                            color: AppColors.slate50,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: AppColors.borderLight),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.calendar_month, size: 18, color: AppColors.textTertiary),
                                              const SizedBox(width: 10),
                                              Text(
                                              _endDate != null
                                                ? DateFormat('EEE d MMM yyyy', 'fr_FR').format(_endDate!)
                                                : 'Sélectionner...',
                                              style: const TextStyle(fontSize: 14),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),


                          // Student selector row (for bulk mode) - placed BEFORE timetable
                          if (_isBulkMode && _selectedClassId != null && !_isLoading) ...[
                            _buildClassStudentsSelectorRow(context),
                            const SizedBox(height: 16),
                          ],

                          // Timetable slots for the selected day - SMART VIEW
                          if (_selectedClassId != null && !_isLoading) ...[
                            _buildTimetableSection(),
                            const SizedBox(height: 16),
                          ],

                          // Reason
                          _fieldLabel('Motif (optionnel)'),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.slate50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.borderLight),
                            ),
                            child: TextField(
                              maxLines: 2,
                              onChanged: (v) => _reason = v,
                              style: const TextStyle(fontSize: 14),
                              decoration: const InputDecoration(
                                hintText: 'Ex: Maladie, RDV médical...',
                                hintStyle: TextStyle(color: AppColors.textTertiary),
                                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Justified toggle
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Absence justifiée',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              ModernAnimatedSwitch(
                                value: _justified,
                                onChanged: (v) => setState(() => _justified = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
              ),
              // ── Footer ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                  border: Border(top: BorderSide(color: AppColors.slate100)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: 40,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF6B7280),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                        ),
                        child: const Text('Annuler', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: _canSubmit() && !_isSubmitting ? _submit : null,
                        icon: const Icon(Icons.check_rounded, size: 16),
                        label: Text(_getSaveButtonText(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6D4CF6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 2,
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
  }

  Widget _fieldLabel(String label) =>
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate700));

  Widget _premiumDropdown<T>({
    required T? value,
    required String hint,
    required IconData prefixIcon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          hint: Row(children: [Icon(prefixIcon, size: 18, color: AppColors.textTertiary), const SizedBox(width: 10), Text(hint, style: const TextStyle(color: AppColors.textTertiary, fontSize: 14))]),
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
          ),
          dropdownColor: Colors.white,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _modePill(bool value, IconData icon, String label) {
    final isActive = _isBulkMode == value;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() {
          _isBulkMode = value;
          _selectedStudentEnrollmentId = null;
          _selectedStudentEnrollmentIds.clear();
          if (_isBulkMode && _classStudents.isNotEmpty) {
            _selectedStudentEnrollmentIds = _classStudents
                .where((s) => s.enrollmentId != null)
                .map((s) => s.enrollmentId!)
                .toSet();
          }
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isActive ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 1))] : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: isActive ? const Color(0xFF6D4CF6) : AppColors.textTertiary),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isActive ? const Color(0xFF6D4CF6) : AppColors.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _periodChip(AbsencePeriod period, IconData icon, String label) {
    final isSelected = _period == period;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _period = period;
            _endDate = null;
            _updateTimetableSlotsForPeriod();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1E293B) : AppColors.slate100,
            borderRadius: BorderRadius.circular(20),
            boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 3, offset: const Offset(0, 1))] : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: isSelected ? Colors.white : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : AppColors.slate700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClassStudentsSelectorRow(BuildContext context) {
    final total = _classStudents.length;
    final selected = _selectedStudentEnrollmentIds.length;
    final allSelected = selected == total && total > 0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: () => _showStudentSelectionDialog(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.slate50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF6D4CF6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.people_alt_outlined, color: Color(0xFF6D4CF6), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Étudiants concernés',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      total == 0
                          ? 'Aucun étudiant dans cette classe'
                          : allSelected
                              ? 'Tous les étudiants ($total) sélectionnés'
                              : '$selected sur $total étudiant(s) sélectionné(s)',
                      style: TextStyle(
                        fontSize: 12,
                        color: selected > 0 ? const Color(0xFF6D4CF6) : AppColors.textTertiary,
                        fontWeight: selected > 0 ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text('Modifier', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6D4CF6))),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios, size: 11, color: Color(0xFF6D4CF6)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStudentSelectionDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (ctx) => _StudentSelectionModal(
        students: _classStudents,
        initialSelectedIds: _selectedStudentEnrollmentIds,
        onConfirmed: (newIds) {
          setState(() {
            _selectedStudentEnrollmentIds = newIds;
          });
        },
      ),
    );
  }

  Widget _buildTimetableSection() {
    final dayIndex = _selectedDate.weekday; // 1=Mon, 7=Sun
    final slotsForDay = _classTimetableSlots
        .where((s) => s.dayIndex == dayIndex)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    // For multi-day periods, show all slots sorted by day and time
    final List<TimetableSlotInfo> displaySlots;
    if (_isBulkMode && _period != AbsencePeriod.day) {
      displaySlots = List<TimetableSlotInfo>.from(_classTimetableSlots)
        ..sort((a, b) {
          final dayCmp = a.dayIndex.compareTo(b.dayIndex);
          if (dayCmp != 0) return dayCmp;
          return a.startTime.compareTo(b.startTime);
        });
    } else {
      displaySlots = slotsForDay;
    }

    if (displaySlots.isEmpty && _classTimetableSlots.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.slate50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: const [
            Icon(Icons.info_outline, color: AppColors.slate600, size: 18),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Aucun emploi du temps trouvé pour cette classe.',
                style: TextStyle(color: AppColors.slate700, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    if (displaySlots.isEmpty && _classTimetableSlots.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.slate50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.slate600, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Pas de cours le ${DateFormat('EEEE', 'fr_FR').format(_selectedDate)}.',
                style: const TextStyle(color: AppColors.slate700, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    // Group by day for multi-day periods
    if (_isBulkMode && _period != AbsencePeriod.day) {
      return _buildMultiDayTimetable(displaySlots);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.schedule, color: AppColors.slate600, size: 18),
            const SizedBox(width: 8),
            Text(
              'Emploi du temps - ${DateFormat('EEEE d MMMM', 'fr_FR').format(_selectedDate)}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.slate800),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  if (_selectedTimetableSlotIds.length == displaySlots.length) {
                    _selectedTimetableSlotIds.clear();
                  } else {
                    _selectedTimetableSlotIds = displaySlots
                        .map((s) => s.id)
                        .toSet();
                  }
                });
              },
              icon: Icon(
                _selectedTimetableSlotIds.length == displaySlots.length
                    ? Icons.deselect
                    : Icons.select_all,
                size: 16,
              ),
              label: Text(
                _selectedTimetableSlotIds.length == displaySlots.length
                    ? 'Aucun'
                    : 'Tous',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...displaySlots.map((slot) => _buildSlotTile(slot)),
      ],
    );
  }

  Widget _buildMultiDayTimetable(List<TimetableSlotInfo> slots) {
    // Group by day
    final byDay = <int, List<TimetableSlotInfo>>{};
    for (final slot in slots) {
      byDay.putIfAbsent(slot.dayIndex, () => []).add(slot);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.schedule, color: AppColors.slate600, size: 18),
            const SizedBox(width: 8),
            const Text(
              'Séances à marquer absentes',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.slate800),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  if (_selectedTimetableSlotIds.length == slots.length) {
                    _selectedTimetableSlotIds.clear();
                  } else {
                    _selectedTimetableSlotIds = slots.map((s) => s.id).toSet();
                  }
                });
              },
              icon: Icon(
                _selectedTimetableSlotIds.length == slots.length
                    ? Icons.deselect
                    : Icons.select_all,
                size: 16,
              ),
              label: Text(
                _selectedTimetableSlotIds.length == slots.length
                    ? 'Aucun'
                    : 'Tous',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: ListView(
            children: [
              for (final day in [1, 2, 3, 4, 5, 6]) // Mon-Sat
                if (byDay.containsKey(day)) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      _dayName(day),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.slate700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  ...(byDay[day]!..sort((a, b) => a.startTime.compareTo(b.startTime)))
                      .map((slot) => _buildSlotTile(slot)),
                ],
            ],
          ),
        ),
      ],
    );
  }

  String _dayName(int dayIndex) {
    const days = [
      '',
      'Lundi',
      'Mardi',
      'Mercredi',
      'Jeudi',
      'Vendredi',
      'Samedi',
      'Dimanche',
    ];
    return days[dayIndex];
  }

  Widget _buildSlotTile(TimetableSlotInfo slot) {
    final isSelected = _selectedTimetableSlotIds.contains(slot.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF8FAFC) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? const Color(0xFFCBD5E1) : AppColors.borderLight,
        ),
      ),
      child: CheckboxListTile(
        value: isSelected,
        activeColor: const Color(0xFF6D4CF6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        onChanged: (v) {
          setState(() {
            if (v == true) {
              _selectedTimetableSlotIds.add(slot.id);
            } else {
              _selectedTimetableSlotIds.remove(slot.id);
            }
          });
        },
        title: Row(
          children: [
            Text(
              slot.subjectName,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 8),
            _SessionTypeChip(type: slot.sessionType),
          ],
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                '${slot.startTime.substring(0, 5)} - ${slot.endTime.substring(0, 5)} • ${slot.hours}h${slot.room != null ? ' • ${slot.room}' : ''}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            if (slot.teacherName != null) ...[
              UserAvatar(
                name: slot.teacherName!,
                photoUrl: slot.teacherPhotoUrl,
                radius: 10,
              ),
              const SizedBox(width: 5),
              Text(
                slot.teacherName!,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }


  Future<void> _selectStudentFromSearch(StudentInfo student, List<ClassModel> classes) async {
    final classModel = classes.where((c) => c.id == student.classId).firstOrNull;
    setState(() {
      if (classModel != null) {
        _selectedNiveauId = classModel.gradeLevelId;
        _selectedSectionId = classModel.sectionId;
        _selectedClassId = student.classId;
      }
      _selectedStudentEnrollmentId = student.enrollmentId;
      _studentSearchController.clear();
      _studentSearchQuery = '';
    });
    if (student.classId != null) {
      setState(() => _isLoading = true);
      final students = await widget.ref
          .read(absencesProvider.notifier)
          .getStudentsForClass(student.classId!);
      final slots = widget.ref
          .read(absencesProvider.notifier)
          .getTimetableSlotsForClass(student.classId!);
      setState(() {
        _classStudents = students;
        _classTimetableSlots = slots;
        _updateTimetableSlotsForPeriod();
        _isLoading = false;
      });
    }
  }

  Future<void> _onClassChanged(String? classId) async {
    setState(() {
      _selectedClassId = classId;
      _selectedStudentEnrollmentId = null;
      _classStudents = [];
      _selectedStudentEnrollmentIds.clear();
      _classTimetableSlots = [];
      _selectedTimetableSlotIds.clear();
    });
    if (classId != null) {
      setState(() => _isLoading = true);
      final students = await widget.ref
          .read(absencesProvider.notifier)
          .getStudentsForClass(classId);
      final slots = widget.ref
          .read(absencesProvider.notifier)
          .getTimetableSlotsForClass(classId);
      setState(() {
        _classStudents = students;
        _classTimetableSlots = slots;
        if (_isBulkMode) {
          _selectedStudentEnrollmentIds = students
              .where((s) => s.enrollmentId != null)
              .map((s) => s.enrollmentId!)
              .toSet();
        }
        // Keep slots unchecked by default (student is present by default)
        _selectedTimetableSlotIds.clear();
        _isLoading = false;
      });
    }
  }

  void _updateTimetableSlotsForPeriod() {
    // Keep timetable slots unchecked by default - user checks if absent
    _selectedTimetableSlotIds.clear();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _selectedDate : (_endDate ?? _selectedDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('fr', 'FR'),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _selectedDate = picked;
          _updateTimetableSlotsForPeriod();
        } else {
          _endDate = picked;
        }
      });
    }
  }

  String _getSaveButtonText() {
    if (_isBulkMode) {
      final count =
          _selectedStudentEnrollmentIds.length *
          _selectedTimetableSlotIds.length;
      return 'Créer ($count)';
    }
    return 'Créer (${_selectedTimetableSlotIds.length})';
  }

  bool _canSubmit() {
    if (_selectedClassId == null) return false;
    if (_selectedTimetableSlotIds.isEmpty) return false;
    if (_isBulkMode) {
      if (_selectedStudentEnrollmentIds.isEmpty) return false;
      if (_period == AbsencePeriod.custom && _endDate == null) return false;
    } else {
      if (_selectedStudentEnrollmentId == null) return false;
    }
    return true;
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      final notifier = widget.ref.read(absencesProvider.notifier);
      int totalCreated = 0;

      if (_isBulkMode) {
        // Determine date range based on period
        DateTime startDate = _selectedDate;
        DateTime endDate = _selectedDate;

        switch (_period) {
          case AbsencePeriod.day:
            endDate = _selectedDate;
            break;
          case AbsencePeriod.week:
            // Start from Monday of the selected week
            startDate = _selectedDate.subtract(
              Duration(days: _selectedDate.weekday - 1),
            );
            endDate = startDate.add(const Duration(days: 5)); // Mon-Sat
            break;
          case AbsencePeriod.month:
            startDate = DateTime(_selectedDate.year, _selectedDate.month, 1);
            endDate = DateTime(_selectedDate.year, _selectedDate.month + 1, 0);
            break;
          case AbsencePeriod.custom:
            endDate = _endDate!;
            break;
        }

        if (_period == AbsencePeriod.day) {
          totalCreated = await notifier.createAbsencesFromTimetable(
            classId: _selectedClassId!,
            date: _selectedDate,
            enrollmentIds: _selectedStudentEnrollmentIds.toList(),
            timetableSlotIds: _selectedTimetableSlotIds.toList(),
            reason: _reason.isNotEmpty ? _reason : null,
            justified: _justified,
          );
        } else {
          totalCreated = await notifier.createAbsencesForDateRange(
            classId: _selectedClassId!,
            startDate: startDate,
            endDate: endDate,
            enrollmentIds: _selectedStudentEnrollmentIds.toList(),
            timetableSlotIds: _selectedTimetableSlotIds.toList(),
            reason: _reason.isNotEmpty ? _reason : null,
            justified: _justified,
          );
        }
      } else {
        // Single student
        totalCreated = await notifier.createAbsencesFromTimetable(
          classId: _selectedClassId!,
          date: _selectedDate,
          enrollmentIds: [_selectedStudentEnrollmentId!],
          timetableSlotIds: _selectedTimetableSlotIds.toList(),
          reason: _reason.isNotEmpty ? _reason : null,
          justified: _justified,
        );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$totalCreated absence(s) créée(s)'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFriendlyError.format(
                e,
                fallback: 'Unable to record absences right now. Please try again.',
              ),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

/// Chip for session type (CI, TD, TP)
class _SessionTypeChip extends StatelessWidget {
  final String? type;
  const _SessionTypeChip({this.type});

  @override
  Widget build(BuildContext context) {
    if (type == null) return const Text('—');

    Color bg;
    switch (type) {
      case 'CI':
        bg = AppColors.border;
        break;
      case 'TD':
        bg = AppColors.successSoft;
        break;
      case 'TP':
        bg = AppColors.secondary;
        break;
      default:
        bg = AppColors.slate100;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        type!,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

/// Badge for justified/not justified status
class _JustifiedBadge extends StatelessWidget {
  final bool justified;
  final VoidCallback onTap;
  const _JustifiedBadge({required this.justified, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: justified ? AppColors.successSoft : AppColors.errorSoft,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              justified ? Icons.check_circle : Icons.cancel,
              size: 14,
              color: justified ? AppColors.success : AppColors.error,
            ),
            const SizedBox(width: 4),
            Text(
              justified ? 'Oui' : 'Non',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: justified ? AppColors.success : AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating student selection dialog matching users screen table style
class _StudentSelectionModal extends StatefulWidget {
  final List<StudentInfo> students;
  final Set<String> initialSelectedIds;
  final ValueChanged<Set<String>> onConfirmed;

  const _StudentSelectionModal({
    required this.students,
    required this.initialSelectedIds,
    required this.onConfirmed,
  });

  @override
  State<_StudentSelectionModal> createState() => _StudentSelectionModalState();
}

class _StudentSelectionModalState extends State<_StudentSelectionModal> {
  late Set<String> _selectedIds;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.initialSelectedIds);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<StudentInfo> get _filteredStudents {
    if (_searchQuery.trim().isEmpty) return widget.students;
    final q = _searchQuery.toLowerCase().trim();
    return widget.students.where((s) {
      return s.fullName.toLowerCase().contains(q) ||
          (s.studentCode?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredStudents;
    final allFilteredSelected = filtered.isNotEmpty &&
        filtered.every((s) => s.enrollmentId != null && _selectedIds.contains(s.enrollmentId));

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          width: 580,
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.slate100)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6D4CF6).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.groups, color: Color(0xFF6D4CF6), size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Sélectionner les étudiants',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_selectedIds.length} sur ${widget.students.length} sélectionné(s)',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: AppColors.textTertiary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Search & Select All Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Column(
                  children: [
                    // Search bar
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.slate50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Rechercher un élève par nom ou code...',
                          hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                          prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textTertiary),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () => setState(() {
                                    _searchController.clear();
                                    _searchQuery = '';
                                  }),
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Table Header / Select All bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: Row(
                        children: [
                          Checkbox(
                            value: allFilteredSelected,
                            tristate: !allFilteredSelected && filtered.any((s) => s.enrollmentId != null && _selectedIds.contains(s.enrollmentId)),
                            activeColor: const Color(0xFF6D4CF6),
                            onChanged: (v) {
                              setState(() {
                                if (allFilteredSelected) {
                                  for (final s in filtered) {
                                    if (s.enrollmentId != null) {
                                      _selectedIds.remove(s.enrollmentId!);
                                    }
                                  }
                                } else {
                                  for (final s in filtered) {
                                    if (s.enrollmentId != null) {
                                      _selectedIds.add(s.enrollmentId!);
                                    }
                                  }
                                }
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          Text(
                            allFilteredSelected ? 'Tout désélectionner' : 'Tout sélectionner (${filtered.length})',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.slate700),
                          ),
                          const Spacer(),
                          Text(
                            '${_selectedIds.length} sélectionné(s)',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6D4CF6)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Student List
              Flexible(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person_search_outlined, size: 40, color: AppColors.slate300),
                            const SizedBox(height: 8),
                            Text(
                              widget.students.isEmpty
                                  ? 'Aucun étudiant dans cette classe'
                                  : 'Aucun élève trouvé pour "$_searchQuery"',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.slate100),
                        itemBuilder: (ctx, i) {
                          final student = filtered[i];
                          final isSelected = student.enrollmentId != null &&
                              _selectedIds.contains(student.enrollmentId);

                          return InkWell(
                            onTap: student.enrollmentId == null
                                ? null
                                : () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedIds.remove(student.enrollmentId!);
                                      } else {
                                        _selectedIds.add(student.enrollmentId!);
                                      }
                                    });
                                  },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: isSelected,
                                    activeColor: const Color(0xFF6D4CF6),
                                    onChanged: student.enrollmentId == null
                                        ? null
                                        : (v) {
                                            setState(() {
                                              if (v == true) {
                                                _selectedIds.add(student.enrollmentId!);
                                              } else {
                                                _selectedIds.remove(student.enrollmentId!);
                                              }
                                            });
                                          },
                                  ),
                                  const SizedBox(width: 8),
                                  UserAvatar(
                                    name: student.fullName,
                                    photoUrl: student.photoUrl,
                                    radius: 16,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          student.fullName,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        if (student.studentCode != null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            student.studentCode!,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textTertiary,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.slate100)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: 38,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF6B7280),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: const Text('Annuler', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 38,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          widget.onConfirmed(_selectedIds);
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.check_rounded, size: 16),
                        label: Text('Confirmer (${_selectedIds.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6D4CF6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 1,
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
  }
}
