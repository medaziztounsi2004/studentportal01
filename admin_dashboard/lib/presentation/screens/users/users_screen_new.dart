import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border, TextSpan, BorderStyle;
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../../data/models/user_model.dart';
import '../../providers/users_provider.dart';
import '../../providers/curriculum_provider.dart';
import '../../widgets/admin_sidebar.dart';
import 'user_form_dialog.dart';
import 'user_profile_screen.dart';
import 'bulk_photo_upload_screen.dart';
import 'simple_bulk_import_screen.dart';
import '../../widgets/ios_loader.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});
  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  bool _showFilterDrawer = false;
  String _sortBy = 'name';
  bool _sortAscending = true;
  String? _classFilter;
  String? _levelFilter;
  String? _genderFilter;
  DateTime? _dateFromFilter;
  DateTime? _dateToFilter;
  String? _statusFilter; // null = tous, 'active', 'archived'

  // Bulk selection state
  final Set<String> _selectedUserIds = {};
  bool _isImporting = false;

  // Pagination state
  int _currentPage = 1;
  int _itemsPerPage = 20; // default
  static const List<int> _perPageOptions = [10, 20, 50, 100, -1]; // -1 = All

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _selectedUserIds.clear();
          _currentPage = 1;
        });
      }
    });
  }

  void _resetFilters() {
    setState(() {
      _sortBy = 'name';
      _sortAscending = true;
      _classFilter = null;
      _levelFilter = null;
      _genderFilter = null;
      _dateFromFilter = null;
      _dateToFilter = null;
      _statusFilter = null;
      _currentPage = 1;
    });
  }

  bool get _hasActiveFilters =>
      _levelFilter != null ||
      _classFilter != null ||
      _genderFilter != null ||
      _dateFromFilter != null ||
      _dateToFilter != null;

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Row(
            children: [
              const AdminSidebar(currentRoute: '/users'),
              Expanded(
                child: Stack(
                  children: [
                    Column(
                      children: [
                        _buildHeader(context, usersAsync),
                        _buildTabBar(context, usersAsync),
                        _buildStatusSubTabs(context, usersAsync),
                        if (_hasActiveFilters) _buildActiveFilterChips(context),
                        Expanded(
                      child: usersAsync.when(
                        loading: () => Center(
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              boxShadow: AppShadows.card,
                              border: Border.all(color: AppColors.border.withOpacity(0.5)),
                            ),
                            child: const IosLoader(size: 36, color: AppColors.primary),
                          ),
                        ),
                        error: (e, _) => Center(
                          child: Container(
                            padding: const EdgeInsets.all(36),
                            margin: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: AppColors.errorSoft,
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              border: Border.all(color: AppColors.error.withOpacity(0.2)),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: AppColors.error.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(AppRadius.md),
                                  ),
                                  child: const Icon(Icons.error_outline_rounded, size: 28, color: AppColors.error),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  UserFriendlyError.format(
                                    e,
                                    fallback: 'Unable to load users right now. Please try again.',
                                  ),
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                ),
                                const SizedBox(height: 20),
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: AppColors.primaryGradient,
                                    borderRadius: BorderRadius.circular(AppRadius.sm),
                                    boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 4))],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => ref.invalidate(usersProvider),
                                      borderRadius: BorderRadius.circular(AppRadius.sm),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                                            SizedBox(width: 8),
                                            Text('Réessayer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
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
                        data: (state) => TabBarView(
                          controller: _tabController,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _buildStudentsList(context, state),
                            _buildStaffList(context, state),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // Floating selection bar
                if (_selectedUserIds.isNotEmpty)
                  Positioned(
                    bottom: 24,
                    left: 0,
                    right: 0,
                    child: _buildFloatingSelectionBar(context, usersAsync),
                  ),
              ],
            ),
          ),
        ],
      ),
      // Filter drawer overlay — full-app blur
      if (_showFilterDrawer) _buildFilterDrawerOverlay(context),
    ],
    ),
    );
  }

  // ====================== HEADER ======================
  Widget _buildHeader(BuildContext context, AsyncValue<UsersState> usersAsync) {
    final userCount = usersAsync.whenOrNull(data: (s) => s.users.length) ?? 0;
    final studentCount = usersAsync.whenOrNull(data: (s) => s.users.where((u) => u.role == 'student').length) ?? 0;
    final staffCount = usersAsync.whenOrNull(data: (s) => s.users.where((u) => u.role != 'student').length) ?? 0;

    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.5))),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF), // indigo-50
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: const Color(0xFFE0E7FF)), // indigo-100 border
            ),
            child: const Icon(Icons.groups_rounded, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          // Title + subtitle
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Gestion des Utilisateurs',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$userCount utilisateurs • $studentCount étudiants • $staffCount staff',
                style: const TextStyle(color: AppColors.textTertiary, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const Spacer(),
          // Search field
          SizedBox(
            width: 280,
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() {
                _searchQuery = v;
                _currentPage = 1;
              }),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Rechercher...',
                hintStyle: const TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.w400, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textTertiary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _currentPage = 1;
                          });
                        },
                      )
                    : Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.slate100,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.slate200),
                              ),
                              child: const Text('⌘K', style: TextStyle(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                filled: true,
                fillColor: AppColors.slate50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: AppColors.border.withOpacity(0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Filter toggle
          _HeaderIconButton(
            icon: _showFilterDrawer ? Icons.filter_alt : Icons.filter_alt_outlined,
            tooltip: 'Filtres',
            isActive: _showFilterDrawer || _hasActiveFilters,
            badgeCount: _activeFilterCount,
            onPressed: () => setState(() => _showFilterDrawer = !_showFilterDrawer),
          ),
          // Vertical divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(width: 1, height: 28, color: AppColors.divider),
          ),
          // Download / Export
          _HeaderIconButton(
            icon: Icons.download_rounded,
            tooltip: 'Import en masse (Excel/CSV)',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SimpleBulkImportScreen()),
            ),
          ),
          const SizedBox(width: 4),
          // Print / Photo
          _HeaderIconButton(
            icon: Icons.photo_library_outlined,
            tooltip: 'Photos en masse',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BulkPhotoUploadScreen()),
            ),
          ),
          const SizedBox(width: 12),
          // Add button
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showUserDialog(context),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text('Ajouter', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int get _activeFilterCount {
    int count = 0;
    if (_levelFilter != null) count++;
    if (_classFilter != null) count++;
    if (_genderFilter != null) count++;
    if (_dateFromFilter != null) count++;
    if (_dateToFilter != null) count++;
    return count;
  }

  // ====================== TABS ======================
  Widget _buildTabBar(BuildContext context, AsyncValue<UsersState> usersAsync) {
    final studentCount = usersAsync.whenOrNull(data: (s) => s.users.where((u) => u.role == 'student').length) ?? 0;
    final staffCount = usersAsync.whenOrNull(data: (s) => s.users.where((u) => u.role != 'student').length) ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.5))),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textTertiary,
        indicatorColor: AppColors.primary,
        indicatorWeight: 2.5,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        labelPadding: const EdgeInsets.symmetric(horizontal: 24),
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.school_rounded, size: 18),
                const SizedBox(width: 8),
                const Text('Étudiants'),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E7FF), // indigo-100
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$studentCount',
                    style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.engineering_rounded, size: 18),
                const SizedBox(width: 8),
                const Text('Staff & Managers'),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.slate100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$staffCount',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ====================== STATUS SUB-TABS ======================
  Widget _buildStatusSubTabs(BuildContext context, AsyncValue<UsersState> usersAsync) {
    final allUsers = usersAsync.whenOrNull(data: (s) => s.users) ?? [];
    final isStudentTab = _tabController.index == 0;
    final tabUsers = isStudentTab
        ? allUsers.where((u) => u.role == 'student').toList()
        : allUsers.where((u) => u.role != 'student').toList();
    final allCount = tabUsers.length;
    final activeCount = tabUsers.where((u) => u.isActive).length;
    final archivedCount = tabUsers.where((u) => !u.isActive).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.3))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.slate100,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusPill(
                  label: 'Tous',
                  count: allCount,
                  isActive: _statusFilter == null,
                  onTap: () => setState(() {
                    _statusFilter = null;
                    _currentPage = 1;
                  }),
                ),
                const SizedBox(width: 2),
                _StatusPill(
                  label: 'Actifs',
                  count: activeCount,
                  isActive: _statusFilter == 'active',
                  onTap: () => setState(() {
                    _statusFilter = 'active';
                    _currentPage = 1;
                  }),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Sort controls
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.slate50,
              borderRadius: BorderRadius.circular(AppRadius.xs),
              border: Border.all(color: AppColors.border.withOpacity(0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sort_rounded, size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 4),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _sortBy,
                    isDense: true,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                    items: const [
                      DropdownMenuItem(value: 'name', child: Text('Nom')),
                      DropdownMenuItem(value: 'email', child: Text('Email')),
                      DropdownMenuItem(value: 'id', child: Text('ID')),
                      DropdownMenuItem(value: 'date', child: Text('Date création')),
                    ],
                    onChanged: (v) => setState(() => _sortBy = v!),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => setState(() => _sortAscending = !_sortAscending),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      _sortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      size: 14,
                      color: AppColors.textTertiary,
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

  // ====================== ACTIVE FILTER CHIPS ======================
  Widget _buildActiveFilterChips(BuildContext context) {
    final usersState = ref.watch(usersProvider);
    final allClasses = usersState.whenOrNull(data: (s) => s.classes) ?? [];
    final niveauxFromClasses = <String, String>{};
    for (final c in allClasses) {
      if (c.gradeLevelId != null && c.gradeLevelName != null) {
        niveauxFromClasses[c.gradeLevelId!] = c.gradeLevelName!;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.2))),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_list_rounded, size: 14, color: AppColors.textTertiary),
          const SizedBox(width: 8),
          const Text('Filtres actifs:', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (_levelFilter != null)
                  _FilterChipTag(
                    label: 'Niveau: ${niveauxFromClasses[_levelFilter] ?? _levelFilter!}',
                    color: AppColors.primary,
                    onRemove: () => setState(() {
                      _levelFilter = null;
                      _classFilter = null;
                      _currentPage = 1;
                    }),
                  ),
                if (_classFilter != null)
                  _FilterChipTag(
                    label: 'Classe: $_classFilter',
                    color: AppColors.success,
                    onRemove: () => setState(() {
                      _classFilter = null;
                      _currentPage = 1;
                    }),
                  ),
                if (_genderFilter != null)
                  _FilterChipTag(
                    label: _genderFilter == 'M' ? 'Genre: Garçons' : 'Genre: Filles',
                    color: _genderFilter == 'M' ? AppColors.primary : AppColors.chart4,
                    onRemove: () => setState(() {
                      _genderFilter = null;
                      _currentPage = 1;
                    }),
                  ),
                if (_dateFromFilter != null)
                  _FilterChipTag(
                    label: 'Du ${DateFormat('d MMM yyyy', 'fr_FR').format(_dateFromFilter!)}',
                    color: AppColors.warning,
                    onRemove: () => setState(() {
                      _dateFromFilter = null;
                      _currentPage = 1;
                    }),
                  ),
                if (_dateToFilter != null)
                  _FilterChipTag(
                    label: 'Au ${DateFormat('d MMM yyyy', 'fr_FR').format(_dateToFilter!)}',
                    color: AppColors.warning,
                    onRemove: () => setState(() {
                      _dateToFilter = null;
                      _currentPage = 1;
                    }),
                  ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _resetFilters,
            icon: const Icon(Icons.clear_all_rounded, size: 14),
            label: const Text('Tout effacer', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textTertiary,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  // ====================== FILTER DRAWER ======================
  Widget _buildFilterDrawerOverlay(BuildContext context) {
    return Stack(
      children: [
        // Full-app blur scrim
        Positioned.fill(
          child: GestureDetector(
            onTap: () => setState(() => _showFilterDrawer = false),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(color: Colors.black.withOpacity(0.28)),
            ),
          ),
        ),
        // Drawer
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: 370,
          child: _FilterDrawerContent(
            levelFilter: _levelFilter,
            classFilter: _classFilter,
            genderFilter: _genderFilter,
            dateFromFilter: _dateFromFilter,
            dateToFilter: _dateToFilter,
            usersState: ref.watch(usersProvider),
            onClose: () => setState(() => _showFilterDrawer = false),
            onApply: ({
              String? levelFilter,
              String? classFilter,
              String? genderFilter,
              DateTime? dateFromFilter,
              DateTime? dateToFilter,
            }) {
              setState(() {
                _levelFilter = levelFilter;
                _classFilter = classFilter;
                _genderFilter = genderFilter;
                _dateFromFilter = dateFromFilter;
                _dateToFilter = dateToFilter;
                _currentPage = 1;
                _showFilterDrawer = false;
              });
            },
            onReset: () {
              _resetFilters();
              setState(() => _showFilterDrawer = false);
            },
          ),
        ),
      ],
    );
  }

  // ====================== FLOATING SELECTION BAR ======================
  Widget _buildFloatingSelectionBar(BuildContext context, AsyncValue<UsersState> usersAsync) {
    final count = _selectedUserIds.length;
    final allUsers = usersAsync.value?.users ?? [];
    final selectedUsers = allUsers.where((u) => _selectedUserIds.contains(u.id)).toList();
    final allInactive = selectedUsers.isNotEmpty && selectedUsers.every((u) => !u.isActive);

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.slate900,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 8)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Count badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            const SizedBox(width: 10),
            const Text('Sélectionnés', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(width: 20),
            Container(width: 1, height: 24, color: AppColors.slate700),
            const SizedBox(width: 16),
            // Export
            _FloatingBarButton(
              icon: Icons.download_rounded,
              label: 'Exporter',
              onTap: () => _bulkExport(),
            ),
            const SizedBox(width: 8),
            // Activer / Suspendre
            if (allInactive)
              _FloatingBarButton(
                icon: Icons.check_circle_outline_rounded,
                label: 'Activer',
                color: AppColors.success,
                onTap: () {
                  final ids = _selectedUserIds.toList();
                  ref.read(usersProvider.notifier).bulkToggleArchive(ids, true);
                  setState(() => _selectedUserIds.clear());
                },
              )
            else
              _FloatingBarButton(
                icon: Icons.pause_circle_outline_rounded,
                label: 'Suspendre',
                color: AppColors.warning,
                onTap: () {
                  final ids = _selectedUserIds.toList();
                  ref.read(usersProvider.notifier).bulkToggleArchive(ids, false);
                  setState(() => _selectedUserIds.clear());
                },
              ),
            const SizedBox(width: 8),
            // Change class
            _FloatingBarButton(
              icon: Icons.swap_horiz_rounded,
              label: 'Changer classe',
              onTap: () {
                // Placeholder for class change
              },
            ),
            const SizedBox(width: 8),
            // Delete
            _FloatingBarButton(
              icon: Icons.delete_outline_rounded,
              label: 'Supprimer',
              color: AppColors.error,
              onTap: () => _bulkDelete(context),
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 24, color: AppColors.slate700),
            const SizedBox(width: 8),
            // Close
            InkWell(
              onTap: () => setState(() => _selectedUserIds.clear()),
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.slate800,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ====================== STUDENTS LIST ======================
  Widget _buildStudentsList(BuildContext context, UsersState state) {
    var users = state.users.where((u) => u.role == 'student').toList();
    users = _filterAndSort(users);

    // Pagination
    final totalItems = users.length;
    final totalPages = _itemsPerPage == -1 ? 1 : (totalItems / _itemsPerPage).ceil().clamp(1, double.infinity).toInt();
    if (_currentPage > totalPages) _currentPage = totalPages;
    final paginatedUsers = _itemsPerPage == -1
        ? users
        : users.skip((_currentPage - 1) * _itemsPerPage).take(_itemsPerPage).toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.border.withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: users.isEmpty
                        ? _buildEmptyState('Aucun étudiant trouvé')
                        : _buildStudentTable(paginatedUsers, users),
                  ),
                  // Pagination
                  _buildPagination(totalItems, totalPages),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ====================== STAFF LIST ======================
  Widget _buildStaffList(BuildContext context, UsersState state) {
    var users = state.users.where((u) => u.role != 'student').toList();
    users = _filterAndSort(users);

    final totalItems = users.length;
    final totalPages = _itemsPerPage == -1 ? 1 : (totalItems / _itemsPerPage).ceil().clamp(1, double.infinity).toInt();
    if (_currentPage > totalPages) _currentPage = totalPages;
    final paginatedUsers = _itemsPerPage == -1
        ? users
        : users.skip((_currentPage - 1) * _itemsPerPage).take(_itemsPerPage).toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.border.withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: users.isEmpty
                        ? _buildEmptyState('Aucun staff trouvé')
                        : _buildStaffTable(paginatedUsers, users),
                  ),
                  _buildPagination(totalItems, totalPages),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ====================== PAGINATION ======================
  Widget _buildPagination(int totalItems, int totalPages) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border.withOpacity(0.5))),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(AppRadius.md),
          bottomRight: Radius.circular(AppRadius.md),
        ),
      ),
      child: Row(
        children: [
          const Text('Afficher par', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            decoration: BoxDecoration(
              color: AppColors.slate50,
              borderRadius: BorderRadius.circular(AppRadius.xs),
              border: Border.all(color: AppColors.border.withOpacity(0.5)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _itemsPerPage,
                isDense: true,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                items: _perPageOptions.map((opt) {
                  return DropdownMenuItem(
                    value: opt,
                    child: Text(opt == -1 ? 'Tout' : '$opt'),
                  );
                }).toList(),
                onChanged: (v) => setState(() {
                  _itemsPerPage = v!;
                  _currentPage = 1;
                }),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$totalItems résultat${totalItems != 1 ? 's' : ''}',
            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          const Spacer(),
          Text(
            'Page $_currentPage sur $totalPages',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.xs),
              border: Border.all(color: AppColors.border.withOpacity(0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppRadius.xs),
                    bottomLeft: Radius.circular(AppRadius.xs),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _currentPage > 1 ? AppColors.surface : AppColors.slate50,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(AppRadius.xs),
                        bottomLeft: Radius.circular(AppRadius.xs),
                      ),
                    ),
                    child: Icon(
                      Icons.chevron_left_rounded,
                      size: 18,
                      color: _currentPage > 1 ? AppColors.textSecondary : AppColors.textTertiary,
                    ),
                  ),
                ),
                Container(width: 1, height: 30, color: AppColors.border.withOpacity(0.5)),
                InkWell(
                  onTap: _currentPage < totalPages ? () => setState(() => _currentPage++) : null,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(AppRadius.xs),
                    bottomRight: Radius.circular(AppRadius.xs),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _currentPage < totalPages ? AppColors.surface : AppColors.slate50,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(AppRadius.xs),
                        bottomRight: Radius.circular(AppRadius.xs),
                      ),
                    ),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: _currentPage < totalPages ? AppColors.textSecondary : AppColors.textTertiary,
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

  // ====================== FILTER + SORT LOGIC ======================
  List<UserModel> _filterAndSort(List<UserModel> users) {
    // Apply status filter
    if (_statusFilter == 'active') {
      users = users.where((u) => u.isActive).toList();
    } else if (_statusFilter == 'archived') {
      users = users.where((u) => !u.isActive).toList();
    }

    // Apply smart search filter - search across all user fields including age
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase().trim();

      // Check if searching for age (e.g., "15 ans", "age:15", "15")
      final ageMatch = RegExp(r'^(\d+)\s*(ans?)?$').firstMatch(query);
      final ageQueryMatch = RegExp(r'^age[:\s]*(\d+)$').firstMatch(query);
      int? searchAge;
      if (ageMatch != null) {
        searchAge = int.tryParse(ageMatch.group(1)!);
      } else if (ageQueryMatch != null) {
        searchAge = int.tryParse(ageQueryMatch.group(1)!);
      }

      users = users.where((u) {
        // If searching by age
        if (searchAge != null && u.dateOfBirth != null) {
          final age = DateTime.now().difference(u.dateOfBirth!).inDays ~/ 365;
          if (age == searchAge) return true;
        }

        // Text search across all fields
        return u.fullName.toLowerCase().contains(query) ||
            u.email.toLowerCase().contains(query) ||
            u.id.toLowerCase().contains(query) ||
            (u.studentCode?.toLowerCase().contains(query) ?? false) ||
            (u.phone?.toLowerCase().contains(query) ?? false) ||
            (u.niveau?.toLowerCase().contains(query) ?? false) ||
            (u.niveauCode?.toLowerCase().contains(query) ?? false) ||
            (u.className?.toLowerCase().contains(query) ?? false) ||
            (u.nationality?.toLowerCase().contains(query) ?? false) ||
            (u.address?.toLowerCase().contains(query) ?? false) ||
            (u.sectionCode?.toLowerCase().contains(query) ?? false) ||
            (u.gender?.toLowerCase().contains(query) ?? false) ||
            // Search by age text like "14 ans"
            (u.dateOfBirth != null &&
                '${DateTime.now().difference(u.dateOfBirth!).inDays ~/ 365} ans'
                    .contains(query));
      }).toList();
    }

    // Apply class filter
    if (_classFilter != null) {
      users = users.where((u) => u.className == _classFilter).toList();
    }

    // Apply niveau filter (now uses gradeLevelId)
    if (_levelFilter != null) {
      users = users.where((u) {
        // Match by niveau ID, name or code
        return u.niveau == _levelFilter ||
            u.niveauCode == _levelFilter ||
            // Also check if user's class belongs to this niveau
            true; // Will be handled by class filter cascade
      }).toList();
    }

    // Apply gender filter
    if (_genderFilter != null) {
      users = users.where((u) => u.gender == _genderFilter).toList();
    }

    // Apply date from filter
    if (_dateFromFilter != null) {
      users = users.where((u) => u.createdAt.isAfter(_dateFromFilter!)).toList();
    }

    // Apply date to filter
    if (_dateToFilter != null) {
      users = users
          .where((u) => u.createdAt.isBefore(_dateToFilter!.add(const Duration(days: 1))))
          .toList();
    }

    // Apply sorting
    users.sort((a, b) {
      int result;
      switch (_sortBy) {
        case 'email':
          result = a.email.compareTo(b.email);
          break;
        case 'id':
          result = a.id.compareTo(b.id);
          break;
        case 'date':
          result = a.createdAt.compareTo(b.createdAt);
          break;
        default:
          result = a.fullName.compareTo(b.fullName);
      }
      return _sortAscending ? result : -result;
    });

    return users;
  }

  // ====================== STUDENT DATA TABLE ======================
  Widget _buildStudentTable(List<UserModel> paginatedUsers, List<UserModel> allFilteredUsers) {
    final allSelected = allFilteredUsers.isNotEmpty &&
        allFilteredUsers.every((u) => _selectedUserIds.contains(u.id));
    final someSelected = _selectedUserIds.isNotEmpty && !allSelected;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 12,
          horizontalMargin: 16,
          headingRowHeight: 44,
          dataRowMinHeight: 52,
          dataRowMaxHeight: 56,
          headingRowColor: WidgetStateProperty.all(AppColors.slate50),
          headingTextStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
          dataTextStyle: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          showCheckboxColumn: false,
          columns: [
            // Checkbox
            DataColumn(
              label: Checkbox(
                value: allSelected ? true : (someSelected ? null : false),
                tristate: true,
                onChanged: (v) {
                  setState(() {
                    if (allSelected) {
                      for (final u in allFilteredUsers) {
                        _selectedUserIds.remove(u.id);
                      }
                    } else {
                      for (final u in allFilteredUsers) {
                        _selectedUserIds.add(u.id);
                      }
                    }
                  });
                },
                activeColor: AppColors.primary,
              ),
            ),
            const DataColumn(label: Text('NOM COMPLET / EMAIL')),
            const DataColumn(label: Text('GENRE')),
            const DataColumn(label: Text('ÂGE')),
            const DataColumn(label: Text('NATIONALITÉ')),
            const DataColumn(label: Text('NIVEAU')),
            const DataColumn(label: Text('CLASSE')),
            const DataColumn(label: Text('CODE ÉTUDIANT')),
            const DataColumn(label: Text('TÉLÉPHONE')),
            const DataColumn(label: Text('STATUT')),
            const DataColumn(label: Text('CRÉÉ LE')),
            const DataColumn(label: Text('')),
          ],
          rows: paginatedUsers.map((u) {
            final isSelected = _selectedUserIds.contains(u.id);
            return DataRow(
              selected: isSelected,
              color: WidgetStateProperty.resolveWith<Color?>((states) {
                if (isSelected) {
                  return const Color(0xFFEEF2FF).withOpacity(0.4);
                }
                if (states.contains(WidgetState.hovered)) {
                  return AppColors.slate50;
                }
                return null;
              }),
              onSelectChanged: (_) => _navigateToProfile(context, u),
              cells: [
                // Checkbox
                DataCell(
                  Checkbox(
                    value: isSelected,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedUserIds.add(u.id);
                        } else {
                          _selectedUserIds.remove(u.id);
                        }
                      });
                    },
                    activeColor: AppColors.primary,
                  ),
                ),
                // Name + Email combined
                DataCell(
                  Row(
                    children: [
                      _buildAvatar(u),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            u.fullName,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 1),
                          _CopyableText(
                            text: u.email,
                            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                            toastMessage: 'Email copié!',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Genre
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        u.gender == 'M' ? Icons.male_rounded : u.gender == 'F' ? Icons.female_rounded : Icons.remove,
                        size: 16,
                        color: u.gender == 'M'
                            ? AppColors.primary
                            : u.gender == 'F'
                                ? AppColors.chart4
                                : AppColors.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        u.genderDisplay,
                        style: TextStyle(
                          fontSize: 12,
                          color: u.gender == 'M'
                              ? AppColors.primary
                              : u.gender == 'F'
                                  ? AppColors.chart4
                                  : AppColors.textTertiary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Âge
                DataCell(
                  Text(
                    u.age != null ? '${u.age} ans' : '-',
                    style: TextStyle(
                      color: u.age != null ? AppColors.textPrimary : AppColors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ),
                // Nationalité
                DataCell(
                  Text(
                    u.nationality ?? '-',
                    style: TextStyle(
                      color: u.nationality != null ? AppColors.textPrimary : AppColors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ),
                // Niveau badge
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                      border: Border.all(color: const Color(0xFFE0E7FF)),
                    ),
                    child: Text(
                      _formatNiveauDisplay(u),
                      style: const TextStyle(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                // Classe badge
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.successSoft,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                      border: Border.all(color: AppColors.success.withOpacity(0.2)),
                    ),
                    child: Text(
                      u.className ?? '-',
                      style: TextStyle(
                        color: u.className != null ? AppColors.success : AppColors.textTertiary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                // Code étudiant (monospace in gray bg)
                DataCell(
                  _CopyableText(
                    text: u.studentCode ?? '-',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: u.studentCode != null ? AppColors.textSecondary : AppColors.textTertiary,
                      backgroundColor: AppColors.slate100,
                    ),
                    toastMessage: 'Code étudiant copié!',
                    showBackground: u.studentCode != null,
                  ),
                ),
                // Téléphone (mono)
                DataCell(
                  _CopyableText(
                    text: u.phone ?? '-',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: u.phone != null ? AppColors.textSecondary : AppColors.textTertiary,
                    ),
                    toastMessage: 'Téléphone copié!',
                  ),
                ),
                // Statut (borderless pill)
                DataCell(
                  Builder(
                    builder: (context) {
                      final isAct = u.isActive;
                      final isPaused = u.accountStatus == 'paused_unpaid';
                      final label = !isAct ? 'Inactif' : (isPaused ? 'Suspendu' : 'Actif');
                      final bg = !isAct
                          ? const Color(0xFFFEF2F2)
                          : (isPaused ? const Color(0xFFFFFBEB) : const Color(0xFFECFDF5));
                      final fg = !isAct
                          ? const Color(0xFFDC2626)
                          : (isPaused ? const Color(0xFFD97706) : const Color(0xFF059669));

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: fg,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Créé le
                DataCell(
                  Text(
                    DateFormat('d MMM yyyy', 'fr_FR').format(u.createdAt),
                    style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                  ),
                ),
                // Actions (PopupMenuButton)
                DataCell(_buildActionsMenu(context, u)),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ====================== STAFF DATA TABLE ======================
  Widget _buildStaffTable(List<UserModel> paginatedUsers, List<UserModel> allFilteredUsers) {
    final allSelected = allFilteredUsers.isNotEmpty &&
        allFilteredUsers.every((u) => _selectedUserIds.contains(u.id));
    final someSelected = _selectedUserIds.isNotEmpty && !allSelected;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 12,
          horizontalMargin: 16,
          headingRowHeight: 44,
          dataRowMinHeight: 52,
          dataRowMaxHeight: 56,
          headingRowColor: WidgetStateProperty.all(AppColors.slate50),
          headingTextStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
          dataTextStyle: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          showCheckboxColumn: false,
          columns: [
            // Checkbox
            DataColumn(
              label: Checkbox(
                value: allSelected ? true : (someSelected ? null : false),
                tristate: true,
                onChanged: (v) {
                  setState(() {
                    if (allSelected) {
                      for (final u in allFilteredUsers) {
                        _selectedUserIds.remove(u.id);
                      }
                    } else {
                      for (final u in allFilteredUsers) {
                        _selectedUserIds.add(u.id);
                      }
                    }
                  });
                },
                activeColor: AppColors.primary,
              ),
            ),
            const DataColumn(label: Text('NOM COMPLET / EMAIL')),
            const DataColumn(label: Text('RÔLE')),
            const DataColumn(label: Text('TÉLÉPHONE')),
            const DataColumn(label: Text('STATUT')),
            const DataColumn(label: Text('CRÉÉ LE')),
            const DataColumn(label: Text('')),
          ],
          rows: paginatedUsers.map((u) {
            final isSelected = _selectedUserIds.contains(u.id);
            return DataRow(
              selected: isSelected,
              color: WidgetStateProperty.resolveWith<Color?>((states) {
                if (isSelected) {
                  return const Color(0xFFEEF2FF).withOpacity(0.4);
                }
                if (states.contains(WidgetState.hovered)) {
                  return AppColors.slate50;
                }
                return null;
              }),
              onSelectChanged: (_) => _navigateToProfile(context, u),
              cells: [
                // Checkbox
                DataCell(
                  Checkbox(
                    value: isSelected,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedUserIds.add(u.id);
                        } else {
                          _selectedUserIds.remove(u.id);
                        }
                      });
                    },
                    activeColor: AppColors.primary,
                  ),
                ),
                // Name + Email combined
                DataCell(
                  Row(
                    children: [
                      _buildAvatar(u),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            u.fullName,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 1),
                          _CopyableText(
                            text: u.email,
                            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                            toastMessage: 'Email copié!',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Role
                DataCell(_RoleChip(role: u.role)),
                // Téléphone
                DataCell(
                  _CopyableText(
                    text: u.phone ?? '-',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: u.phone != null ? AppColors.textSecondary : AppColors.textTertiary,
                    ),
                    toastMessage: 'Téléphone copié!',
                  ),
                ),
                // Statut (borderless pill)
                DataCell(
                  Builder(
                    builder: (context) {
                      final isAct = u.isActive;
                      final label = isAct ? 'Actif' : 'Inactif';
                      final bg = !isAct ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5);
                      final fg = !isAct ? const Color(0xFFDC2626) : const Color(0xFF059669);

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: fg,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Créé le
                DataCell(
                  Text(
                    DateFormat('d MMM yyyy', 'fr_FR').format(u.createdAt),
                    style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                  ),
                ),
                // Actions
                DataCell(_buildActionsMenu(context, u)),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ====================== AVATAR ======================
  Widget _buildAvatar(UserModel u) {
    Color bgColor;
    if (u.gender == 'F') {
      bgColor = AppColors.chart4.withOpacity(0.15);
    } else if (u.fullName.isNotEmpty && u.fullName[0].toUpperCase() == 'A') {
      bgColor = AppColors.accent.withOpacity(0.15);
    } else if (u.fullName.isNotEmpty && u.fullName[0].toUpperCase() == 'M') {
      bgColor = AppColors.primary.withOpacity(0.15);
    } else {
      bgColor = AppColors.slate200;
    }

    Color textColor;
    if (u.gender == 'F') {
      textColor = AppColors.chart4;
    } else if (u.fullName.isNotEmpty && u.fullName[0].toUpperCase() == 'A') {
      textColor = AppColors.accent;
    } else if (u.fullName.isNotEmpty && u.fullName[0].toUpperCase() == 'M') {
      textColor = AppColors.primary;
    } else {
      textColor = AppColors.textSecondary;
    }

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: u.photoUrl != null
          ? ClipOval(
              child: Image.network(
                u.photoUrl!,
                width: 34,
                height: 34,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    u.fullName.isNotEmpty ? u.fullName[0].toUpperCase() : '?',
                    style: TextStyle(fontWeight: FontWeight.w700, color: textColor, fontSize: 14),
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                u.fullName.isNotEmpty ? u.fullName[0].toUpperCase() : '?',
                style: TextStyle(fontWeight: FontWeight.w700, color: textColor, fontSize: 14),
              ),
            ),
    );
  }

  // ====================== ACTIONS POPUP MENU ======================
  Widget _buildActionsMenu(BuildContext context, UserModel u) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz_rounded, size: 20, color: AppColors.textTertiary),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.15),
      offset: const Offset(0, 36),
      onSelected: (value) {
        switch (value) {
          case 'view':
            _navigateToProfile(context, u);
            break;
          case 'edit':
            _showUserDialog(context, user: u);
            break;
          case 'reset_password':
            // Password reset placeholder
            break;
          case 'toggle_status':
            final newActive = !u.isActive;
            ref.read(usersProvider.notifier).toggleUserArchive(u.id, newActive);
            break;
          case 'delete':
            _confirmDelete(context, u);
            break;
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'view',
          child: Row(
            children: [
              Icon(Icons.visibility_outlined, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              const Text('Voir profil', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              const Text('Modifier', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'reset_password',
          child: Row(
            children: [
              Icon(Icons.lock_reset_rounded, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              const Text('Réinitialiser mot de passe', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        if (u.isActive)
          PopupMenuItem(
            value: 'toggle_status',
            child: Row(
              children: [
                const Icon(Icons.pause_circle_outline_rounded, size: 18, color: AppColors.warning),
                const SizedBox(width: 10),
                Text(
                  u.role == 'student' ? 'Suspendre' : 'Désactiver',
                  style: const TextStyle(fontSize: 13, color: AppColors.warning),
                ),
              ],
            ),
          )
        else
          PopupMenuItem(
            value: 'toggle_status',
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded, size: 18, color: AppColors.success),
                const SizedBox(width: 10),
                const Text('Activer', style: TextStyle(fontSize: 13, color: AppColors.success)),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
              const SizedBox(width: 10),
              const Text('Supprimer', style: TextStyle(fontSize: 13, color: AppColors.error)),
            ],
          ),
        ),
      ],
    );
  }

  // ====================== EMPTY STATE ======================
  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppColors.slate100,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.people_outline, size: 36, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          if (_searchQuery.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Essayez une autre recherche',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  // ====================== NIVEAU FORMATTING ======================
  String _formatNiveauDisplay(UserModel user) {
    // First, try to derive niveau from class name if available
    if (user.className != null && user.className!.isNotEmpty) {
      final className = user.className!;
      if (className.contains('1ère')) return '1ère';
      if (className.contains('2ème')) return '2ème';
      if (className.contains('3ème')) return '3ème';
      if (className.contains('4ème') || className.toLowerCase().contains('bac')) {
        return 'Bac';
      }
    }

    // Try niveau_code
    final niveauShort = getNiveauShortName(user.niveauCode);
    if (niveauShort.isNotEmpty && niveauShort != user.niveauCode) {
      if (user.sectionCode != null) {
        final sectionShort = getSectionShortName(user.sectionCode);
        return '$niveauShort $sectionShort';
      }
      return niveauShort;
    }

    // Fallback to legacy niveau
    if (user.niveau != null) {
      return _shortenNiveau(user.niveau!);
    }

    return '-';
  }

  String _shortenNiveau(String niveau) {
    if (niveau.contains('7ème')) return '7ème';
    if (niveau.contains('8ème')) return '8ème';
    if (niveau.contains('9ème')) return '9ème';
    if (niveau.contains('1ère')) return '1ère S';
    if (niveau.contains('2ème')) return '2ème S';
    if (niveau.contains('3ème')) return '3ème S';
    if (niveau.contains('4ème') || niveau.contains('Bac')) return 'Bac';
    return niveau.length > 5 ? niveau.substring(0, 5) : niveau;
  }

  // ====================== NAVIGATION ======================
  void _navigateToProfile(BuildContext context, UserModel u) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(userId: u.id, userName: u.fullName),
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'admin':
        return AppColors.secondary;
      case 'staff':
        return AppColors.primary;
      default:
        return AppColors.warning;
    }
  }

  void _showUserDialog(BuildContext context, {UserModel? user}) {
    showDialog(
      context: context,
      builder: (ctx) => UserFormDialog(user: user),
    );
  }

  // ====================== CONFIRM DELETE ======================
  void _confirmDelete(BuildContext context, UserModel u) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: AppColors.errorSoft, borderRadius: BorderRadius.circular(AppRadius.xs)),
              child: const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
            ),
            const SizedBox(width: 12),
            const Text('Supprimer utilisateur ?', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Voulez-vous vraiment supprimer "${u.fullName}" ?'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.slate50,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.textTertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ID: ${u.id}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.errorGradient,
              borderRadius: BorderRadius.circular(AppRadius.xs),
              boxShadow: [BoxShadow(color: AppColors.error.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  ref.read(usersProvider.notifier).deleteUser(u.id);
                  Navigator.pop(ctx);
                },
                borderRadius: BorderRadius.circular(AppRadius.xs),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Text('Supprimer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== BULK ACTIONS ====================

  void _bulkDelete(BuildContext context) {
    final count = _selectedUserIds.length;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: AppColors.errorSoft, borderRadius: BorderRadius.circular(AppRadius.xs)),
              child: const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
            ),
            const SizedBox(width: 12),
            const Text('Supprimer en masse ?', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Voulez-vous vraiment supprimer $count utilisateur(s) ?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.errorSoft,
                borderRadius: BorderRadius.circular(AppRadius.xs),
                border: Border.all(color: AppColors.error.withOpacity(0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_rounded, color: AppColors.error, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cette action est irréversible !',
                      style: TextStyle(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);

              // Show loading indicator
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const IosLoader.small(color: Colors.white),
                      const SizedBox(width: 12),
                      Text('Suppression de $count utilisateurs en cours...'),
                    ],
                  ),
                  duration: const Duration(seconds: 60),
                  backgroundColor: AppColors.primary,
                ),
              );

              // Use bulk delete method - much faster!
              final notifier = ref.read(usersProvider.notifier);
              final result = await notifier.bulkDeleteUsers(
                _selectedUserIds.toList(),
              );
              final deleted = result['deleted'] ?? 0;
              final failed = result['failed'] ?? 0;

              setState(() {
                _selectedUserIds.clear();
              });

              if (mounted) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$deleted supprimé(s), $failed échec(s)'),
                    backgroundColor: failed == 0 ? AppColors.success : AppColors.warning,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xs)),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(
              'Supprimer $count',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _bulkExport() async {
    final usersState = ref.read(usersProvider);
    final allUsers = usersState.whenOrNull(data: (s) => s.users) ?? [];
    final selectedUsers = allUsers.where((u) => _selectedUserIds.contains(u.id)).toList();

    if (selectedUsers.isEmpty) return;

    final excel = Excel.createExcel();
    final sheet = excel['Utilisateurs'];

    // Headers
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('ID');
    sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue('Nom complet');
    sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('Email');
    sheet.cell(CellIndex.indexByString('D1')).value = TextCellValue('Téléphone');
    sheet.cell(CellIndex.indexByString('E1')).value = TextCellValue('Rôle');
    sheet.cell(CellIndex.indexByString('F1')).value = TextCellValue('Code étudiant');

    // Data rows
    for (var i = 0; i < selectedUsers.length; i++) {
      final u = selectedUsers[i];
      final row = i + 2;
      sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(u.id);
      sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(u.fullName);
      sheet.cell(CellIndex.indexByString('C$row')).value = TextCellValue(u.email);
      sheet.cell(CellIndex.indexByString('D$row')).value = TextCellValue(u.phone ?? '');
      sheet.cell(CellIndex.indexByString('E$row')).value = TextCellValue(u.role);
      sheet.cell(CellIndex.indexByString('F$row')).value = TextCellValue(u.studentCode ?? '');
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final bytes = excel.encode();
    if (bytes != null && mounted) {
      await FilePicker.platform.saveFile(
        dialogTitle: 'Exporter les utilisateurs',
        fileName: 'utilisateurs_export_${DateTime.now().millisecondsSinceEpoch}.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        bytes: Uint8List.fromList(bytes),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${selectedUsers.length} utilisateur(s) exporté(s)'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  // ==================== EXCEL IMPORT METHODS ====================

  void _showImportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.upload_file, color: AppColors.primary),
            const SizedBox(width: 12),
            const Text('Importer des Utilisateurs'),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Importez des utilisateurs à partir d\'un fichier Excel (.xlsx) ou CSV (.csv)',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Format requis:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildFormatRow('Colonne A', 'Nom complet *'),
                    _buildFormatRow('Colonne B', 'Email *'),
                    _buildFormatRow('Colonne C', 'Téléphone'),
                    _buildFormatRow('Colonne D', 'Rôle (student/staff/admin)'),
                    _buildFormatRow('Colonne E', 'Date de naissance (JJ/MM/AAAA)'),
                    _buildFormatRow('Colonne F', 'Adresse'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.successSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.success.withOpacity(0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.auto_fix_high, color: AppColors.success, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Le mot de passe et le code étudiant sont générés automatiquement !',
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.textTertiary, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'La première ligne doit contenir les en-têtes et sera ignorée.',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadTemplate();
            },
            icon: const Icon(Icons.download),
            label: const Text('Télécharger modèle'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _pickAndImportExcel();
            },
            icon: const Icon(Icons.file_upload),
            label: const Text('Choisir fichier'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatRow(String column, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              column,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Text('→ $description', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _downloadTemplate() async {
    final excel = Excel.createExcel();
    final sheet = excel['Utilisateurs'];

    // Headers - NO PASSWORD COLUMN (auto-generated)
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Nom complet *');
    sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue('Email *');
    sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('Téléphone');
    sheet.cell(CellIndex.indexByString('D1')).value = TextCellValue('Rôle');
    sheet.cell(CellIndex.indexByString('E1')).value = TextCellValue('Date naissance');
    sheet.cell(CellIndex.indexByString('F1')).value = TextCellValue('Adresse');

    // Example rows
    sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue('Ahmed Ben Ali');
    sheet.cell(CellIndex.indexByString('B2')).value = TextCellValue('ahmed.benali@example.com');
    sheet.cell(CellIndex.indexByString('C2')).value = TextCellValue('+216 55 123 456');
    sheet.cell(CellIndex.indexByString('D2')).value = TextCellValue('student');
    sheet.cell(CellIndex.indexByString('E2')).value = TextCellValue('15/03/2008');
    sheet.cell(CellIndex.indexByString('F2')).value = TextCellValue('Tunis, Tunisie');

    sheet.cell(CellIndex.indexByString('A3')).value = TextCellValue('Fatma Trabelsi');
    sheet.cell(CellIndex.indexByString('B3')).value = TextCellValue('fatma.trabelsi@example.com');
    sheet.cell(CellIndex.indexByString('C3')).value = TextCellValue('+216 22 987 654');
    sheet.cell(CellIndex.indexByString('D3')).value = TextCellValue('student');
    sheet.cell(CellIndex.indexByString('E3')).value = TextCellValue('22/07/2009');
    sheet.cell(CellIndex.indexByString('F3')).value = TextCellValue('Sfax, Tunisie');

    sheet.cell(CellIndex.indexByString('A4')).value = TextCellValue('Mohamed Karim');
    sheet.cell(CellIndex.indexByString('B4')).value = TextCellValue('mohamed.karim@example.com');
    sheet.cell(CellIndex.indexByString('C4')).value = TextCellValue('');
    sheet.cell(CellIndex.indexByString('D4')).value = TextCellValue('staff');
    sheet.cell(CellIndex.indexByString('E4')).value = TextCellValue('');
    sheet.cell(CellIndex.indexByString('F4')).value = TextCellValue('');

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final bytes = excel.encode();
    if (bytes != null && mounted) {
      await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer le modèle',
        fileName: 'modele_import_utilisateurs.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        bytes: Uint8List.fromList(bytes),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Modèle prêt à télécharger'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _pickAndImportExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        setState(() => _isImporting = true);

        final bytes = result.files.single.bytes!;
        final fileName = result.files.single.name.toLowerCase();
        final users = <Map<String, String>>[];

        if (fileName.endsWith('.csv')) {
          // Parse CSV - NEW FORMAT (no password)
          final content = String.fromCharCodes(bytes);
          final lines = content.split('\n');

          for (var i = 1; i < lines.length; i++) {
            final line = lines[i].trim();
            if (line.isEmpty) continue;

            final parts = line.split(',');
            if (parts.length < 2) continue;

            final fullName = parts[0].trim();
            final email = parts[1].trim();
            final phone = parts.length > 2 ? parts[2].trim() : '';
            final role = parts.length > 3 ? parts[3].trim().toLowerCase() : 'student';
            final dateOfBirth = parts.length > 4 ? parts[4].trim() : '';
            final address = parts.length > 5 ? parts[5].trim() : '';

            if (fullName.isNotEmpty && email.isNotEmpty) {
              users.add({
                'fullName': fullName,
                'email': email,
                'phone': phone,
                'role': role.isEmpty ? 'student' : role,
                'dateOfBirth': dateOfBirth,
                'address': address,
              });
            }
          }
        } else {
          // Parse Excel - NEW FORMAT (no password)
          final excel = Excel.decodeBytes(bytes);

          for (final table in excel.tables.keys) {
            final sheet = excel.tables[table]!;

            for (var i = 1; i < sheet.maxRows; i++) {
              final row = sheet.rows[i];
              if (row.isEmpty || row[0]?.value == null) continue;

              final fullName = row[0]?.value?.toString() ?? '';
              final email = row[1]?.value?.toString() ?? '';
              final phone = row.length > 2 ? row[2]?.value?.toString() : null;
              final role = row.length > 3 ? row[3]?.value?.toString() ?? 'student' : 'student';
              final dateOfBirth = row.length > 4 ? row[4]?.value?.toString() : null;
              final address = row.length > 5 ? row[5]?.value?.toString() : null;

              if (fullName.isNotEmpty && email.isNotEmpty) {
                users.add({
                  'fullName': fullName,
                  'email': email,
                  'phone': phone ?? '',
                  'role': role.toLowerCase().isEmpty ? 'student' : role.toLowerCase(),
                  'dateOfBirth': dateOfBirth ?? '',
                  'address': address ?? '',
                });
              }
            }
            break;
          }
        }

        if (users.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Aucun utilisateur valide trouvé'),
                backgroundColor: AppColors.warning,
              ),
            );
          }
          setState(() => _isImporting = false);
          return;
        }

        if (mounted) {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Confirmer l\'import'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${users.length} utilisateur(s) trouvé(s):'),
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: users.length > 5 ? 5 : users.length,
                      itemBuilder: (ctx, i) => Text(
                        '• ${users[i]['fullName']} (${users[i]['email']})',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  if (users.length > 5)
                    Text(
                      '... et ${users.length - 5} autres',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Annuler'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  child: const Text(
                    'Importer',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          );

          if (confirm == true) {
            await _importUsers(users);
          }
        }

        setState(() => _isImporting = false);
      }
    } catch (e) {
      setState(() => _isImporting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFriendlyError.format(
                e,
                fallback: 'Unable to import users from this file. Please check the file format and try again.',
              ),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _importUsers(List<Map<String, String>> users) async {
    int success = 0;
    int failed = 0;
    final errors = <String>[];
    final createdUsers = <Map<String, String>>[];

    for (final user in users) {
      try {
        // Auto-generate password for each user
        final password = ref.read(usersProvider.notifier).generatePassword();

        final result = await ref.read(usersProvider.notifier).createUser(
          email: user['email']!,
          password: password,
          fullName: user['fullName']!,
          role: user['role'] ?? 'student',
          phone: user['phone']?.isNotEmpty == true ? user['phone'] : null,
          dateOfBirth: user['dateOfBirth']?.isNotEmpty == true ? user['dateOfBirth'] : null,
          address: user['address']?.isNotEmpty == true ? user['address'] : null,
        );

        if (result) {
          success++;
          createdUsers.add({
            'email': user['email']!,
            'fullName': user['fullName']!,
            'password': password,
          });
        } else {
          failed++;
          errors.add(user['email']!);
        }
      } catch (e) {
        failed++;
        errors.add(
          '${user['email']}: ${UserFriendlyError.format(e, fallback: 'Unable to create this account.')}',
        );
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import terminé: $success réussi(s), $failed échec(s)'),
          backgroundColor: failed == 0 ? AppColors.success : AppColors.warning,
          duration: const Duration(seconds: 5),
        ),
      );

      // Show generated credentials dialog if users were created successfully
      if (createdUsers.isNotEmpty) {
        _showGeneratedCredentials(createdUsers);
      }

      if (errors.isNotEmpty) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.warning_amber, color: AppColors.warning),
                const SizedBox(width: 8),
                const Text('Erreurs d\'import'),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${errors.length} utilisateur(s) n\'ont pas pu être importés:'),
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: errors.length,
                      itemBuilder: (ctx, i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '• ${errors[i]}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  /// Show dialog with generated credentials after bulk import
  void _showGeneratedCredentials(List<Map<String, String>> createdUsers) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success),
            const SizedBox(width: 8),
            const Text('Identifiants générés'),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.primary),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Veuillez télécharger ou copier ces identifiants. Les mots de passe ne seront plus accessibles après fermeture.',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.slate200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: DataTable(
                    columnSpacing: 20,
                    headingRowColor: WidgetStateProperty.all(AppColors.slate100),
                    columns: const [
                      DataColumn(label: Text('Nom', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Email', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Mot de passe', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: createdUsers
                        .map(
                          (u) => DataRow(
                            cells: [
                              DataCell(Text(u['fullName'] ?? '', style: const TextStyle(fontSize: 12))),
                              DataCell(Text(u['email'] ?? '', style: const TextStyle(fontSize: 12))),
                              DataCell(
                                SelectableText(
                                  u['password'] ?? '',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: AppColors.success,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () => _exportCredentials(createdUsers),
            icon: const Icon(Icons.download),
            label: const Text('Télécharger Excel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  /// Export generated credentials to Excel file
  Future<void> _exportCredentials(List<Map<String, String>> users) async {
    final excel = Excel.createExcel();
    final sheet = excel['Identifiants'];

    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Nom complet');
    sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue('Email');
    sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('Mot de passe');
    sheet.cell(CellIndex.indexByString('D1')).value = TextCellValue('Code étudiant');

    for (var i = 0; i < users.length; i++) {
      final row = i + 2;
      sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(users[i]['fullName'] ?? '');
      sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(users[i]['email'] ?? '');
      sheet.cell(CellIndex.indexByString('C$row')).value = TextCellValue(users[i]['password'] ?? '');
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final bytes = excel.encode();
    if (bytes != null && mounted) {
      final timestamp = DateTime.now().toString().split('.').first.replaceAll(':', '-');
      await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer les identifiants',
        fileName: 'identifiants_generes_$timestamp.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        bytes: Uint8List.fromList(bytes),
      );
    }
  }
}

// ====================== HELPER WIDGETS ======================

/// Header icon button with optional badge
class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isActive;
  final int badgeCount;

  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isActive = false,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isActive ? AppColors.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.xs),
              border: Border.all(
                color: isActive ? AppColors.primary.withOpacity(0.3) : AppColors.border.withOpacity(0.5),
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: 18, color: isActive ? AppColors.primary : AppColors.textSecondary),
                if (badgeCount > 0)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppColors.warning,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          '$badgeCount',
                          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700),
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
  }
}

/// Status pill for sub-tabs
class _StatusPill extends StatelessWidget {
  final String label;
  final int count;
  final bool isActive;
  final VoidCallback onTap;

  const _StatusPill({
    required this.label,
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? AppColors.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      elevation: isActive ? 1 : 0,
      shadowColor: Colors.black.withOpacity(0.08),
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          child: Text(
            '$label $count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              color: isActive ? AppColors.textPrimary : AppColors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Active filter chip tag
class _FilterChipTag extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onRemove;

  const _FilterChipTag({
    required this.label,
    required this.color,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close_rounded, size: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating bar button
class _FloatingBarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _FloatingBarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: c == Colors.white ? AppColors.slate800 : c.withOpacity(0.15),
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: c),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Copyable text with hover copy icon
class _CopyableText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final String toastMessage;
  final bool showBackground;

  const _CopyableText({
    required this.text,
    required this.style,
    required this.toastMessage,
    this.showBackground = false,
  });

  @override
  State<_CopyableText> createState() => _CopyableTextState();
}

class _CopyableTextState extends State<_CopyableText> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (widget.text == '-') {
      return Text(widget.text, style: widget.style);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          Clipboard.setData(ClipboardData(text: widget.text));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.toastMessage),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xs)),
            ),
          );
        },
        child: widget.showBackground
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.slate100,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.text, style: widget.style),
                    if (_hovered) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.copy_rounded, size: 12, color: widget.style.color?.withOpacity(0.5) ?? AppColors.textTertiary),
                    ],
                  ],
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.text, style: widget.style),
                  if (_hovered) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.copy_rounded, size: 12, color: widget.style.color?.withOpacity(0.5) ?? AppColors.textTertiary),
                  ],
                ],
              ),
      ),
    );
  }
}

/// Filter drawer content
class _FilterDrawerContent extends StatefulWidget {
  final String? levelFilter;
  final String? classFilter;
  final String? genderFilter;
  final DateTime? dateFromFilter;
  final DateTime? dateToFilter;
  final AsyncValue<UsersState> usersState;
  final VoidCallback onClose;
  final void Function({
    String? levelFilter,
    String? classFilter,
    String? genderFilter,
    DateTime? dateFromFilter,
    DateTime? dateToFilter,
  }) onApply;
  final VoidCallback onReset;

  const _FilterDrawerContent({
    required this.levelFilter,
    required this.classFilter,
    required this.genderFilter,
    required this.dateFromFilter,
    required this.dateToFilter,
    required this.usersState,
    required this.onClose,
    required this.onApply,
    required this.onReset,
  });

  @override
  State<_FilterDrawerContent> createState() => _FilterDrawerContentState();
}

class _FilterDrawerContentState extends State<_FilterDrawerContent> {
  late String? _level;
  String? _section;
  late String? _class;
  late String? _gender;
  late DateTime? _dateFrom;
  late DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    _level = widget.levelFilter;
    _class = widget.classFilter;
    _gender = widget.genderFilter;
    _dateFrom = widget.dateFromFilter;
    _dateTo = widget.dateToFilter;
  }

  @override
  Widget build(BuildContext context) {
    final allClasses = widget.usersState.whenOrNull(data: (s) => s.classes) ?? [];
    final niveauxFromClasses = <String, String>{};
    for (final c in allClasses) {
      if (c.gradeLevelId != null && c.gradeLevelName != null) {
        niveauxFromClasses[c.gradeLevelId!] = c.gradeLevelName!;
      }
    }
    final sectionsForLevel = <String, String>{};
    if (_level != null) {
      for (final c in allClasses) {
        if (c.gradeLevelId == _level && c.sectionId != null && c.sectionName != null) {
          sectionsForLevel[c.sectionId!] = c.sectionName!;
        }
      }
    }
    final hasSections = sectionsForLevel.isNotEmpty;
    final filteredClasses = allClasses.where((c) {
      if (_level != null && c.gradeLevelId != _level) return false;
      if (hasSections && _section != null && c.sectionId != _section) return false;
      return true;
    }).toList();

    return Material(
      elevation: 16,
      shadowColor: Colors.black.withOpacity(0.2),
      child: Container(
        color: AppColors.surface,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.5))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded, size: 20, color: AppColors.textPrimary),
                  const SizedBox(width: 10),
                  const Text('Filtres', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const Spacer(),
                  InkWell(
                    onTap: widget.onClose,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.slate100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            // Filter fields
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // NIVEAU
                    _buildDrawerLabel('NIVEAU'),
                    const SizedBox(height: 6),
                    _buildDrawerDropdown<String?>(
                      value: _level,
                      hint: 'Tous les niveaux',
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Tous les niveaux')),
                        ...niveauxFromClasses.entries.map(
                          (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        _level = v;
                        _section = null;
                        _class = null;
                      }),
                    ),
                    const SizedBox(height: 20),
                    // FILIÈRE (if exists)
                    if (hasSections) ...[
                      _buildDrawerLabel('FILIÈRE'),
                      const SizedBox(height: 6),
                      _buildDrawerDropdown<String?>(
                        value: _section,
                        hint: 'Toutes les filières',
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Toutes les filières')),
                          ...sectionsForLevel.entries.map(
                            (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                          ),
                        ],
                        onChanged: (v) => setState(() {
                          _section = v;
                          _class = null;
                        }),
                      ),
                      const SizedBox(height: 20),
                    ],
                    // CLASSE
                    _buildDrawerLabel('CLASSE'),
                    const SizedBox(height: 6),
                    _buildDrawerDropdown<String?>(
                      value: _class,
                      hint: _level != null ? 'Classes (${filteredClasses.length})' : 'Toutes les classes',
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(_level != null ? 'Toutes (${filteredClasses.length})' : 'Toutes les classes'),
                        ),
                        ...filteredClasses.map(
                          (c) => DropdownMenuItem(value: c.name, child: Text(c.name)),
                        ),
                      ],
                      onChanged: filteredClasses.isEmpty && _level != null
                          ? null
                          : (v) => setState(() => _class = v),
                    ),
                    const SizedBox(height: 20),
                    // GENRE
                    _buildDrawerLabel('GENRE'),
                    const SizedBox(height: 6),
                    _buildDrawerDropdown<String?>(
                      value: _gender,
                      hint: 'Tous',
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Tous')),
                        DropdownMenuItem(
                          value: 'M',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.male_rounded, size: 16, color: AppColors.primary),
                              SizedBox(width: 6),
                              Text('Garçons'),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'F',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.female_rounded, size: 16, color: AppColors.chart4),
                              SizedBox(width: 6),
                              Text('Filles'),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _gender = v),
                    ),
                    const SizedBox(height: 20),
                    // DATE DE CRÉATION
                    _buildDrawerLabel('DATE DE CRÉATION'),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDatePickerField(
                            label: 'Du',
                            value: _dateFrom,
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: _dateFrom ?? DateTime.now().subtract(const Duration(days: 365)),
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                              );
                              if (date != null) setState(() => _dateFrom = date);
                            },
                            onClear: () => setState(() => _dateFrom = null),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDatePickerField(
                            label: 'Au',
                            value: _dateTo,
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: _dateTo ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                              );
                              if (date != null) setState(() => _dateTo = date);
                            },
                            onClear: () => setState(() => _dateTo = null),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Action buttons
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
                            _level = null;
                            _class = null;
                            _gender = null;
                            _dateFrom = null;
                            _dateTo = null;
                          });
                          widget.onReset();
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
                          onTap: () => widget.onApply(
                            levelFilter: _level,
                            classFilter: _class,
                            genderFilter: _gender,
                            dateFromFilter: _dateFrom,
                            dateToFilter: _dateTo,
                          ),
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

  Widget _buildDrawerLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textTertiary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildDrawerDropdown<T>({
    required T value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?)? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: false,
          hint: Text(hint, style: const TextStyle(fontSize: 13, color: AppColors.textTertiary)),
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDatePickerField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.slate50,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.border.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.textTertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value != null ? DateFormat('d MMM yyyy', 'fr_FR').format(value) : label,
                style: TextStyle(
                  fontSize: 13,
                  color: value != null ? AppColors.textPrimary : AppColors.textTertiary,
                ),
              ),
            ),
            if (value != null)
              InkWell(
                onTap: onClear,
                child: const Icon(Icons.close_rounded, size: 14, color: AppColors.textTertiary),
              ),
          ],
        ),
      ),
    );
  }
}

/// Role chip widget
class _RoleChip extends StatelessWidget {
  final String role;
  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (role) {
      case 'admin':
        bg = const Color(0xFFF5F3FF);
        fg = AppColors.secondary;
        label = 'Admin';
        icon = Icons.admin_panel_settings_outlined;
        break;
      case 'staff':
        bg = AppColors.primarySoft;
        fg = AppColors.primary;
        label = 'Manager';
        icon = Icons.badge_outlined;
        break;
      default:
        bg = AppColors.accentSoft;
        fg = AppColors.accent;
        label = 'Étudiant';
        icon = Icons.person_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
