import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border, TextSpan, BorderStyle;
import '../../../core/theme/app_theme.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/utils/error_messages.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/class_model.dart';
import '../../providers/users_provider.dart';
import '../../providers/curriculum_provider.dart';
import '../../../models/curriculum_models.dart';
import '../../widgets/admin_sidebar.dart';
import '../../widgets/user_avatar.dart';
import 'user_form_dialog.dart';
import 'bulk_photo_upload_screen.dart';
import 'simple_bulk_import_screen.dart';
import '../../widgets/ios_loader.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/admin_sort_dropdown.dart';


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
  String _sortKey = 'date_desc';
  String? _classFilter;
  String? _levelFilter;
  String? _sectionFilter;
  String? _genderFilter;
  DateTime? _dateFromFilter;
  DateTime? _dateToFilter;
  String? _statusFilter; // null = tous, 'active', 'archived'

  // Bulk selection state
  final Set<String> _selectedUserIds = {};
  bool _isImporting = false;
  bool _isSelectionMode = false;

  // Pagination state
  int _currentPage = 1;
  int _itemsPerPage = 20;
  static const List<int> _perPageOptions = [10, 20, 50, 100, -1];

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(usersProvider);
    });
  }

  void _resetFilters() {
    setState(() {
      _sortBy = 'name';
      _sortAscending = true;
      _sortKey = 'date_desc';
      _classFilter = null;
      _levelFilter = null;
      _sectionFilter = null;
      _genderFilter = null;
      _dateFromFilter = null;
      _dateToFilter = null;
      _statusFilter = null;
      _currentPage = 1;
    });
  }

  void _toggleFilters() {
    setState(() {
      _showFilterDrawer = !_showFilterDrawer;
    });
  }

  bool get _hasActiveFilters =>
      _levelFilter != null ||
      _sectionFilter != null ||
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
                        _buildStatusFilterBar(context, usersAsync),
                        Expanded(
                          child: usersAsync.when(
                            loading: () => const TableSkeletonLoader(),










                        error: (e, _) => Center(
                          child: Container(
                            padding: const EdgeInsets.all(36),
                            margin: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: AppColors.errorSoft,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.error.withOpacity(0.2)),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 56, height: 56,
                                  decoration: BoxDecoration(
                                    color: AppColors.error.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
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
                                ElevatedButton.icon(
                                  onPressed: () => ref.invalidate(usersProvider),
                                  icon: const Icon(Icons.refresh_rounded, size: 18),
                                  label: const Text('Réessayer'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF655DD5),
                                    foregroundColor: Colors.white,
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
                        child: Center(child: _buildFloatingSelectionBar(context, usersAsync)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // Filter drawer overlay — full-app blur
          if (_showFilterDrawer) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: _toggleFilters,
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
              child: _buildFilterDrawer(context),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════
  Widget _buildHeader(BuildContext context, AsyncValue<UsersState> usersAsync) {
    final userCount = usersAsync.whenOrNull(data: (s) => s.users.where((u) => u.role != 'teacher').length) ?? 0;
    final studentCount = usersAsync.whenOrNull(data: (s) => s.users.where((u) => u.role == 'student').length) ?? 0;
    final staffCount = usersAsync.whenOrNull(data: (s) => s.users.where((u) => u.role != 'student' && u.role != 'teacher').length) ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE9EAF2))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Title — no icon
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Gestion des Utilisateurs',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$userCount utilisateurs • $studentCount étudiants • $staffCount staff',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
          const Spacer(),
          // ── Toolbar: pinned far right ──
          SizedBox(
            width: 320,
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
                hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textTertiary),
                suffixIcon: _searchQuery.isEmpty
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
                          setState(() => _searchQuery = '');
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
          const SizedBox(width: 8),
          AdminSortDropdown<String>(
            selectedValue: _sortKey,
            options: const [
              SortOption(value: 'date_desc', label: 'Date: Plus récent', icon: Icons.schedule_rounded),
              SortOption(value: 'date_asc', label: 'Date: Plus ancien', icon: Icons.history_rounded),
              SortOption(value: 'name_asc', label: 'Nom: A → Z', icon: Icons.sort_by_alpha_rounded),
              SortOption(value: 'name_desc', label: 'Nom: Z → A', icon: Icons.sort_by_alpha_rounded),
              SortOption(value: 'email_asc', label: 'Email: A → Z', icon: Icons.email_outlined),
              SortOption(value: 'status_active', label: 'Statut: Actifs d\'abord', icon: Icons.verified_user_outlined),
            ],
            onSelected: (val) {
              setState(() {
                _sortKey = val;
                _currentPage = 1;
              });
            },
          ),
          const SizedBox(width: 8),
          _buildHeaderIconButton(
            icon: Icons.filter_list_rounded,
            tooltip: 'Filtres',
            isActive: _showFilterDrawer || _hasActiveFilters,
            onPressed: _toggleFilters,
          ),
          const SizedBox(width: 8),
          _buildHeaderIconButton(
            icon: Icons.file_download_outlined,
            tooltip: 'Import en masse',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SimpleBulkImportScreen())),
          ),
          const SizedBox(width: 8),
          _buildHeaderIconButton(
            icon: Icons.photo_library_outlined,
            tooltip: 'Photos en masse',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BulkPhotoUploadScreen())),
          ),
          const SizedBox(width: 16),
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: () => _showUserDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Ajouter', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
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

  // ═══════════════════════════════════════════════════
  // TAB BAR
  // ═══════════════════════════════════════════════════
  Widget _buildTabBar(BuildContext context, AsyncValue<UsersState> usersAsync) {
    final studentCount = usersAsync.whenOrNull(data: (s) => s.users.where((u) => u.role == 'student').length) ?? 0;
    final staffCount = usersAsync.whenOrNull(data: (s) => s.users.where((u) => u.role != 'student' && u.role != 'teacher').length) ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.5))),
      ),
      padding: const EdgeInsets.only(left: 24, top: 4),
      child: Row(
        children: [
          _buildTab(
            icon: Icons.school_rounded,
            label: 'Étudiants',
            count: studentCount,
            isActive: _tabController.index == 0,
            onTap: () => setState(() => _tabController.animateTo(0)),
            activeColor: const Color(0xFF655DD5),
          ),
          const SizedBox(width: 24),
          _buildTab(
            icon: Icons.engineering_rounded,
            label: 'Staff & Managers',
            count: staffCount,
            isActive: _tabController.index == 1,
            onTap: () => setState(() => _tabController.animateTo(1)),
            activeColor: const Color(0xFF655DD5),
          ),
        ],
      ),
    );
  }

  Widget _buildTab({
    required IconData icon,
    required String label,
    required int count,
    required bool isActive,
    required VoidCallback onTap,
    required Color activeColor,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(bottom: 12, top: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? activeColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? activeColor : AppColors.textTertiary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? activeColor : AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFFE0E7FF) : AppColors.slate100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isActive ? const Color(0xFF4338CA) : AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // STATUS FILTER BAR (Tous / Actifs / Archivés)
  // ═══════════════════════════════════════════════════
  Widget _buildStatusFilterBar(BuildContext context, AsyncValue<UsersState> usersAsync) {
    final allUsers = usersAsync.whenOrNull(data: (s) => s.users) ?? [];
    final currentTabUsers = _tabController.index == 0
        ? allUsers.where((u) => u.role == 'student').toList()
        : allUsers.where((u) => u.role != 'student' && u.role != 'teacher').toList();

    final totalCount = currentTabUsers.length;
    final activeCount = currentTabUsers.where((u) => u.isActive).length;
    final archivedCount = currentTabUsers.where((u) => !u.isActive).length;

    // Show active filter chips
    final activeFilterChips = <Widget>[];
    if (_levelFilter != null) {
      final currState = ref.read(curriculumProvider);
      final niveauName = currState.whenOrNull(data: (s) {
        try { return s.niveaux.firstWhere((n) => n.code == _levelFilter).shortName; } catch (_) { return _levelFilter; }
      }) ?? _levelFilter;
      activeFilterChips.add(_buildActiveFilterChip(
        label: 'Niveau: $niveauName',
        onRemove: () => setState(() { _levelFilter = null; _classFilter = null; }),
      ));
    }
    if (_sectionFilter != null) {
      final currState = ref.read(curriculumProvider);
      final sectionName = currState.whenOrNull(data: (s) {
        try { return s.sections.firstWhere((sec) => sec.id == _sectionFilter).name; } catch (_) { return _sectionFilter; }
      }) ?? _sectionFilter;
      activeFilterChips.add(_buildActiveFilterChip(
        label: 'Filière: $sectionName',
        onRemove: () => setState(() { _sectionFilter = null; _classFilter = null; }),
      ));
    }
    if (_classFilter != null) {
      activeFilterChips.add(_buildActiveFilterChip(
        label: 'Classe: $_classFilter',
        onRemove: () => setState(() => _classFilter = null),
      ));
    }
    if (_genderFilter != null) {
      activeFilterChips.add(_buildActiveFilterChip(
        label: 'Genre: ${_genderFilter == 'M' ? 'Masculin' : 'Féminin'}',
        onRemove: () => setState(() => _genderFilter = null),
        color: _genderFilter == 'M' ? const Color(0xFF655DD5) : AppColors.chart4,
      ));
    }
    if (_dateFromFilter != null) {
      activeFilterChips.add(_buildActiveFilterChip(
        label: 'Du ${DateFormat('d MMM', 'fr_FR').format(_dateFromFilter!)}',
        onRemove: () => setState(() => _dateFromFilter = null),
        color: AppColors.warning,
      ));
    }
    if (_dateToFilter != null) {
      activeFilterChips.add(_buildActiveFilterChip(
        label: 'Au ${DateFormat('d MMM', 'fr_FR').format(_dateToFilter!)}',
        onRemove: () => setState(() => _dateToFilter = null),
        color: AppColors.warning,
      ));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.5))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Segmented status buttons
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.slate100.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    _buildStatusChip('Tous', totalCount, _statusFilter == null, () => setState(() { _statusFilter = null; _currentPage = 1; })),
                    _buildStatusChip('Actifs', activeCount, _statusFilter == 'active', () => setState(() { _statusFilter = 'active'; _currentPage = 1; })),
                    _buildStatusChip('Archivés', archivedCount, _statusFilter == 'archived', () => setState(() { _statusFilter = 'archived'; _currentPage = 1; })),
                  ],
                ),
              ),
              if (activeFilterChips.isNotEmpty) ...[
                const SizedBox(width: 16),
                Container(width: 1, height: 24, color: AppColors.border),
                const SizedBox(width: 12),
                Text('Filtres actifs:', style: TextStyle(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w500)),
                const SizedBox(width: 8),
                ...activeFilterChips,
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, int count, bool isActive, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            boxShadow: isActive ? [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1))] : null,
          ),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive ? AppColors.textPrimary : AppColors.textTertiary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: isActive ? AppColors.textSecondary : AppColors.textTertiary.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveFilterChip({required String label, required VoidCallback onRemove, Color? color}) {
    final chipColor = color ?? const Color(0xFF655DD5);
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: chipColor.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: chipColor, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          InkWell(
            onTap: onRemove,
            child: Icon(Icons.close, size: 14, color: chipColor),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // STUDENTS LIST
  // ═══════════════════════════════════════════════════
  Widget _buildStudentsList(BuildContext context, UsersState state) {
    var users = state.users.where((u) => u.role == 'student').toList();
    users = _filterAndSort(users);

    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border.withOpacity(0.5)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              Expanded(
                child: users.isEmpty
                    ? _buildEmptyState('Aucun étudiant trouvé')
                    : _buildDataTable(users, isStudent: true),
              ),
              _buildPagination(users.length),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStaffList(BuildContext context, UsersState state) {
    var users = state.users.where((u) => u.role != 'student' && u.role != 'teacher').toList();
    users = _filterAndSort(users);

    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border.withOpacity(0.5)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              Expanded(
                child: users.isEmpty
                    ? _buildEmptyState('Aucun staff trouvé')
                    : _buildDataTable(users, isStudent: false),
              ),
              _buildPagination(users.length),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // DATA TABLE
  // ═══════════════════════════════════════════════════
  Widget _buildDataTable(List<UserModel> users, {required bool isStudent}) {
    // Pagination
    final totalPages = _itemsPerPage == -1 ? 1 : (users.length / _itemsPerPage).ceil();
    if (_currentPage > totalPages && totalPages > 0) _currentPage = totalPages;
    final startIndex = _itemsPerPage == -1 ? 0 : (_currentPage - 1) * _itemsPerPage;
    final endIndex = _itemsPerPage == -1 ? users.length : (startIndex + _itemsPerPage).clamp(0, users.length);
    final pageUsers = users.sublist(startIndex, endIndex);
    final allPageSelected = pageUsers.isNotEmpty && pageUsers.every((u) => _selectedUserIds.contains(u.id));

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        // Fixed column widths
        const checkboxW = 44.0;
        const actionsW = 44.0;
        // Student columns
        const genreW = 80.0;
        const dobW = 95.0;
        const natW = 90.0;
        const niveauW = 80.0;
        const classeW = 85.0;
        const codeW = 120.0;
        // Shared columns
        const phoneW = 120.0;
        const createdW = 80.0;
        // Staff only
        const roleW = 100.0;

        final fixedStudentW = checkboxW + genreW + dobW + natW + niveauW + classeW + codeW + phoneW + createdW + actionsW;
        final fixedStaffW = checkboxW + roleW + phoneW + createdW + actionsW;
        final nameW = isStudent
            ? (availableWidth - fixedStudentW).clamp(160.0, 300.0)
            : (availableWidth - fixedStaffW).clamp(200.0, 400.0);

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
            // Checkbox header
            DataColumn(
              label: SizedBox(
                width: checkboxW,
                child: Center(
                  child: SizedBox(
                    width: 16, height: 16,
                    child: Checkbox(
                      value: allPageSelected && pageUsers.isNotEmpty,
                      tristate: false,
                      onChanged: (v) {
                        setState(() {
                          if (allPageSelected) {
                            for (final u in pageUsers) _selectedUserIds.remove(u.id);
                          } else {
                            for (final u in pageUsers) _selectedUserIds.add(u.id);
                          }
                        });
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
            DataColumn(label: SizedBox(width: nameW, child: _headerLabel('NOM COMPLET / EMAIL'))),
            if (isStudent) DataColumn(label: SizedBox(width: genreW, child: _headerLabel('GENRE'))),
            if (isStudent) DataColumn(label: SizedBox(width: dobW, child: _headerLabel('DATE NAISS.'))),
            if (isStudent) DataColumn(label: SizedBox(width: natW, child: _headerLabel('NATIONALITÉ'))),
            if (isStudent) DataColumn(label: SizedBox(width: niveauW, child: _headerLabel('NIVEAU'))),
            if (isStudent) DataColumn(label: SizedBox(width: classeW, child: _headerLabel('CLASSE'))),
            if (isStudent) DataColumn(label: SizedBox(width: codeW, child: _headerLabel('CODE ÉTUD.'))),
            if (!isStudent) DataColumn(label: SizedBox(width: roleW, child: _headerLabel('RÔLE'))),
            DataColumn(label: SizedBox(width: phoneW, child: _headerLabel('TÉLÉPHONE'))),
            DataColumn(label: SizedBox(width: createdW, child: _headerLabel('CRÉÉ LE'))),
            DataColumn(label: SizedBox(width: actionsW, child: Container())),
          ],
          rows: pageUsers.map((u) {
            final isSelected = _selectedUserIds.contains(u.id);
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
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedUserIds.add(u.id);
                              } else {
                                _selectedUserIds.remove(u.id);
                              }
                            });
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
                // Name + Email
                DataCell(
                  SizedBox(
                    width: nameW,
                    child: Row(
                      children: [
                        _buildAvatar(u),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                u.fullName,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                u.email,
                                style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  onTap: () => _navigateToProfile(context, u),
                ),
                // Student-specific columns
                if (isStudent) ...[
                  // Genre
                  DataCell(SizedBox(
                    width: genreW,
                    child: Row(
                      children: [
                        Icon(
                          u.gender == 'M' ? Icons.male : u.gender == 'F' ? Icons.female : Icons.remove,
                          size: 16,
                          color: u.gender == 'M' ? const Color(0xFF655DD5) : u.gender == 'F' ? const Color(0xFFEC4899) : AppColors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(child: Text(u.genderDisplay, style: TextStyle(fontSize: 12, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  )),
                  // Date de naissance
                  DataCell(SizedBox(
                    width: dobW,
                    child: Text(
                      u.dateOfBirth != null ? DateFormat('d MMM yyyy', 'fr_FR').format(u.dateOfBirth!) : '-',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  )),
                  // Nationality
                  DataCell(SizedBox(
                    width: natW,
                    child: Text(
                      u.nationality ?? '-',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
                  // Niveau
                   DataCell(SizedBox(
                    width: niveauW,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F3FF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _formatNiveauDisplay(u),
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF7C3AED)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  )),
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
                          u.className ?? '-',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF059669)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  )),
                  // Student Code
                  DataCell(SizedBox(
                    width: codeW,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: InkWell(
                        onTap: u.studentCode != null
                            ? () {
                                Clipboard.setData(ClipboardData(text: u.studentCode!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Code étudiant copié!'), duration: Duration(seconds: 1)),
                                );
                              }
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.slate50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            u.studentCode ?? '-',
                            style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  )),
                ],
                // Role (staff only)
                if (!isStudent) DataCell(SizedBox(width: roleW, child: _RoleChip(role: u.role))),
                // Phone
                DataCell(SizedBox(
                  width: phoneW,
                  child: Text(
                    u.phone ?? '-',
                    style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
                // Created
                DataCell(SizedBox(
                  width: createdW,
                  child: Text(
                    DateFormat('d MMM yyyy', 'fr_FR').format(u.createdAt),
                    style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                  ),
                )),
                // Actions (three dots)
                DataCell(SizedBox(
                  width: actionsW,
                  child: PopupMenuButton<String>(
                    icon: Icon(Icons.more_horiz, size: 18, color: AppColors.textTertiary),
                    tooltip: 'Actions',
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 8,
                    offset: const Offset(-160, 40),
                    onSelected: (action) => _handleRowAction(action, u),
                    itemBuilder: (ctx) => [
                      _buildPopupItem('view', Icons.visibility_outlined, 'Voir profil', AppColors.success),
                      _buildPopupItem('edit', Icons.edit_outlined, 'Modifier', const Color(0xFF655DD5)),
                      _buildPopupItem('reset_password', Icons.lock_reset_outlined, 'Réinitialiser mot de passe', AppColors.textSecondary),
                      _buildPopupItem('archive', Icons.archive_outlined, 'Archiver', AppColors.textSecondary),
                      const PopupMenuDivider(),
                      _buildPopupItem('delete', Icons.delete_outline_rounded, 'Supprimer', AppColors.error),
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

  PopupMenuItem<String> _buildPopupItem(String value, IconData icon, String label, Color color) {
    return PopupMenuItem(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 13, color: value == 'delete' ? AppColors.error : AppColors.textPrimary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _handleRowAction(String action, UserModel user) {
    switch (action) {
      case 'view':
        _navigateToProfile(context, user);
        break;
      case 'edit':
        _showUserDialog(context, user: user);
        break;
      case 'reset_password':
        _showResetPasswordDialog(context, user);
        break;
      case 'archive':
        _confirmArchive(context, user);
        break;
      case 'delete':
        _confirmDelete(context, user);
        break;
    }
  }

  Widget _buildAvatar(UserModel user) {
    return UserAvatar(
      name: user.fullName,
      photoUrl: user.photoUrl,
      gender: user.gender,
      radius: 17,
    );
  }

  // ═══════════════════════════════════════════════════
  // PAGINATION
  // ═══════════════════════════════════════════════════
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

  // ═══════════════════════════════════════════════════
  // FLOATING SELECTION BAR
  // ═══════════════════════════════════════════════════
  Widget _buildFloatingSelectionBar(BuildContext context, AsyncValue<UsersState> usersAsync) {
    final count = _selectedUserIds.length;
    final allUsers = usersAsync.whenOrNull(data: (s) => s.users) ?? [];
    final selectedUsers = allUsers.where((u) => _selectedUserIds.contains(u.id)).toList();
    final allArchived = selectedUsers.isNotEmpty && selectedUsers.every((u) => !u.isActive);
    final hasStudents = selectedUsers.any((u) => u.role == 'student');

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
              allArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
              allArchived ? 'Désarchiver' : 'Archiver',
              Colors.white70,
              () => _bulkToggleArchive(allArchived),
            ),
            if (hasStudents)
              _buildSelectionAction(
                Icons.school_rounded,
                'Changer classe',
                Colors.white70,
                () => _showChangeClassDialog(context, selectedUsers.where((u) => u.role == 'student').toList()),
              ),
            _buildSelectionAction(
              Icons.delete_outline,
              'Supprimer',
              const Color(0xFFFCA5A5),
              () => _bulkDelete(context),
            ),
            // Close button
            Container(
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: Colors.white.withOpacity(0.15))),
              ),
              child: IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.white60),
                onPressed: () => setState(() => _selectedUserIds.clear()),
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

  // ═══════════════════════════════════════════════════
  // FILTER DRAWER (right side)
  // ═══════════════════════════════════════════════════
  Widget _buildFilterDrawer(BuildContext context) {
    final usersState = ref.watch(usersProvider);
    final allClasses = usersState.whenOrNull(data: (s) => s.classes) ?? [];

    // Get niveaux from curriculum provider (all school niveaux)
    final curriculumState = ref.watch(curriculumProvider);
    final allNiveaux = curriculumState.whenOrNull(data: (s) => s.niveaux) ?? [];

    // Filter classes based on selected niveau code
    final niveauMatch = allNiveaux.where((n) => n.code == _levelFilter);
    final selectedNiveau = niveauMatch.isNotEmpty ? niveauMatch.first : null;

    // Sections (filières) for selected niveau
    final allSections = curriculumState.whenOrNull(data: (s) => s.sections) ?? [];
    final Map<String, String> sectionsForNiveau = {};
    if (selectedNiveau != null) {
      for (final c in allClasses) {
        final matchesNiveau = (selectedNiveau.id.isNotEmpty && c.gradeLevelId == selectedNiveau.id) ||
            c.gradeLevelName?.toLowerCase() == selectedNiveau.name.toLowerCase() ||
            c.gradeLevelName?.toLowerCase() == selectedNiveau.shortName.toLowerCase();
        if (matchesNiveau && c.sectionId != null && c.sectionName != null) {
          sectionsForNiveau[c.sectionId!] = c.sectionName!;
        }
      }
      if (selectedNiveau.hasSections) {
        for (final sec in allSections) {
          sectionsForNiveau[sec.id] = sec.name;
        }
      }
    }
    final hasSections = selectedNiveau != null && (selectedNiveau.hasSections || sectionsForNiveau.isNotEmpty);

    // Filter classes based on selected niveau and section
    final filteredClasses = allClasses.where((c) {
      if (selectedNiveau != null) {
        final matchesNiveau = (selectedNiveau.id.isNotEmpty && c.gradeLevelId == selectedNiveau.id) ||
            c.gradeLevelName?.toLowerCase() == selectedNiveau.name.toLowerCase() ||
            c.gradeLevelName?.toLowerCase() == selectedNiveau.shortName.toLowerCase();
        if (!matchesNiveau) return false;
      }
      if (hasSections && _sectionFilter != null) {
        if (c.sectionId != _sectionFilter && c.sectionName != sectionsForNiveau[_sectionFilter]) {
          return false;
        }
      }
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
                    onPressed: _toggleFilters,
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
                      value: _levelFilter,
                      hint: 'Tous les niveaux',
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Tous les niveaux')),
                        ...allNiveaux.map((n) => DropdownMenuItem(value: n.code, child: Text(n.shortName))),
                      ],
                      onChanged: (v) => setState(() {
                        _levelFilter = v;
                        _sectionFilter = null;
                        _classFilter = null;
                        _currentPage = 1;
                      }),
                    ),
                    const SizedBox(height: 20),

                    // Filière (if exists)
                    if (hasSections) ...[
                      _buildFilterLabel('FILIÈRE'),
                      const SizedBox(height: 8),
                      _buildFilterDropdown<String?>(
                        value: _sectionFilter,
                        hint: 'Toutes les filières',
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Toutes les filières')),
                          ...sectionsForNiveau.entries.map((s) => DropdownMenuItem(value: s.key, child: Text(s.value))),
                        ],
                        onChanged: (v) => setState(() {
                          _sectionFilter = v;
                          _classFilter = null;
                          _currentPage = 1;
                        }),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Classe
                    _buildFilterLabel('CLASSE'),
                    const SizedBox(height: 8),
                    _buildFilterDropdown<String?>(
                      value: _classFilter,
                      hint: _levelFilter != null ? 'Classes (${filteredClasses.length})' : 'Toutes les classes',
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(_levelFilter != null ? 'Toutes (${filteredClasses.length})' : 'Toutes les classes'),
                        ),
                        ...filteredClasses.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))),
                      ],
                      onChanged: (v) => setState(() {
                        _classFilter = v;
                        _currentPage = 1;
                      }),
                    ),
                    const SizedBox(height: 20),
                    // Genre
                    _buildFilterLabel('GENRE'),
                    const SizedBox(height: 8),
                    _buildFilterDropdown<String?>(
                      value: _genderFilter,
                      hint: 'Tous',
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Tous')),
                        DropdownMenuItem(value: 'M', child: Text('Masculin')),
                        DropdownMenuItem(value: 'F', child: Text('Féminin')),
                      ],
                      onChanged: (v) => setState(() {
                        _genderFilter = v;
                        _currentPage = 1;
                      }),
                    ),
                    const SizedBox(height: 20),
                    // Date de création
                    _buildFilterLabel('DATE DE CRÉATION'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDatePickerField(
                            value: _dateFromFilter,
                            hint: 'Date début',
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: _dateFromFilter ?? DateTime.now().subtract(const Duration(days: 365)),
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                              );
                              if (date != null) setState(() => _dateFromFilter = date);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDatePickerField(
                            value: _dateToFilter,
                            hint: 'Date fin',
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: _dateToFilter ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                              );
                              if (date != null) setState(() => _dateToFilter = date);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Statut
                    _buildFilterLabel('STATUT'),
                    const SizedBox(height: 8),
                    _buildFilterDropdown<String?>(
                      value: _statusFilter,
                      hint: 'Tous',
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Tous')),
                        DropdownMenuItem(value: 'active', child: Text('Actifs')),
                        DropdownMenuItem(value: 'archived', child: Text('Archivés')),
                      ],
                      onChanged: (v) => setState(() {
                        _statusFilter = v;
                        _currentPage = 1;
                      }),
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
                          _resetFilters();
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
                          onTap: () {
                            setState(() => _showFilterDrawer = false);
                          },
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

  // ═══════════════════════════════════════════════════
  // EMPTY STATE
  // ═══════════════════════════════════════════════════
  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(color: AppColors.slate100, shape: BoxShape.circle),
            child: Icon(Icons.people_outline, size: 36, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: AppColors.textSecondary, fontSize: 16, fontWeight: FontWeight.w600)),
          if (_searchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Essayez une autre recherche', style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // FILTER & SORT LOGIC
  // ═══════════════════════════════════════════════════
  List<UserModel> _filterAndSort(List<UserModel> users) {
    // Apply status filter
    if (_statusFilter == 'active') {
      users = users.where((u) => u.isActive).toList();
    } else if (_statusFilter == 'archived') {
      users = users.where((u) => !u.isActive).toList();
    }

    // Apply smart search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase().trim();
      final ageMatch = RegExp(r'^(\d+)\s*(ans?)?$').firstMatch(query);
      final ageQueryMatch = RegExp(r'^age[:\s]*(\d+)$').firstMatch(query);
      int? searchAge;
      if (ageMatch != null) {
        searchAge = int.tryParse(ageMatch.group(1)!);
      } else if (ageQueryMatch != null) {
        searchAge = int.tryParse(ageQueryMatch.group(1)!);
      }

      users = users.where((u) {
        if (searchAge != null && u.dateOfBirth != null) {
          final age = DateTime.now().difference(u.dateOfBirth!).inDays ~/ 365;
          if (age == searchAge) return true;
        }
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
            (u.dateOfBirth != null && '${DateTime.now().difference(u.dateOfBirth!).inDays ~/ 365} ans'.contains(query));
      }).toList();
    }

    // Apply class filter
    if (_classFilter != null) {
      users = users.where((u) => u.className == _classFilter).toList();
    }

    // Apply section filter
    if (_sectionFilter != null) {
      final usersState = ref.read(usersProvider);
      final allClasses = usersState.whenOrNull(data: (s) => s.classes) ?? [];
      final curriculumState = ref.read(curriculumProvider);
      final allSections = curriculumState.whenOrNull(data: (s) => s.sections) ?? [];
      final secModel = allSections.cast<SectionModel?>().firstWhere(
        (s) => s?.id == _sectionFilter || s?.code == _sectionFilter,
        orElse: () => null,
      );
      final targetSecName = secModel?.name.toLowerCase();
      final targetSecCode = secModel?.code.toLowerCase();

      users = users.where((u) {
        if (u.sectionCode != null) {
          final uSec = u.sectionCode!.toLowerCase();
          if (uSec == _sectionFilter?.toLowerCase() || (targetSecCode != null && uSec == targetSecCode)) {
            return true;
          }
        }
        if (u.className != null) {
          final c = allClasses.where((cl) => cl.name == u.className);
          if (c.isNotEmpty) {
            final classSecId = c.first.sectionId;
            final classSecName = c.first.sectionName?.toLowerCase();
            if (classSecId == _sectionFilter) return true;
            if (targetSecName != null && classSecName == targetSecName) return true;
            if (targetSecCode != null && classSecName == targetSecCode) return true;
          }
        }
        return false;
      }).toList();
    }

    // Apply niveau filter (by niveauCode e.g. '7B', '8B', '1S' etc.)
    if (_levelFilter != null) {
      users = users.where((u) {
        return u.niveauCode == _levelFilter;
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
      users = users.where((u) => u.createdAt.isBefore(_dateToFilter!.add(const Duration(days: 1)))).toList();
    }

    // Apply sorting
    users.sort((a, b) {
      switch (_sortKey) {
        case 'date_desc':
          return b.createdAt.compareTo(a.createdAt);
        case 'date_asc':
          return a.createdAt.compareTo(b.createdAt);
        case 'name_desc':
          return b.fullName.toLowerCase().compareTo(a.fullName.toLowerCase());
        case 'email_asc':
          return a.email.toLowerCase().compareTo(b.email.toLowerCase());
        case 'status_active':
          if (a.isActive != b.isActive) {
            return a.isActive ? -1 : 1;
          }
          return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
        case 'name_asc':
          return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
        default:
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
      }
    });

    return users;
  }

  // ═══════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════
  String _formatNiveauDisplay(UserModel user) {
    if (user.className != null && user.className!.isNotEmpty) {
      final className = user.className!;
      if (className.contains('7')) return '7ème';
      if (className.contains('8')) return '8ème';
      if (className.contains('9')) return '9ème';
      if (className.startsWith('1')) return '1ère';
      if (className.startsWith('2')) return '2ème';
      if (className.startsWith('3')) return '3ème';
      if (className.startsWith('4') || className.toLowerCase().contains('bac')) return 'Bac';
    }

    final niveauShort = getNiveauShortName(user.niveauCode);
    if (niveauShort.isNotEmpty && niveauShort != user.niveauCode) {
      if (user.sectionCode != null) {
        final sectionShort = getSectionShortName(user.sectionCode);
        return '$niveauShort $sectionShort';
      }
      return niveauShort;
    }

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

  void _navigateToProfile(BuildContext context, UserModel u) {
    context.go('/users/${u.id}');
  }

  void _showUserDialog(BuildContext context, {UserModel? user}) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (ctx) => UserFormDialog(user: user),
    );
  }

  void _showResetPasswordDialog(BuildContext context, UserModel user) {
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
              decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.lock_reset, color: AppColors.warning, size: 18),
            ),
            const SizedBox(width: 12),
            const Text('Réinitialiser le mot de passe ?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
        content: Text('Un nouveau mot de passe sera généré pour "${user.fullName}".'),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Mot de passe réinitialisé'), backgroundColor: AppColors.success),
                    );
                  },
                  icon: const Icon(Icons.lock_reset, size: 16),
                  label: const Text('Réinitialiser', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warning,
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
  }

  void _confirmArchive(BuildContext context, UserModel user) {
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
              decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.archive_outlined, color: AppColors.warning, size: 18),
            ),
            const SizedBox(width: 12),
            const Text('Archiver cet utilisateur ?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
        content: Text('L\'utilisateur "${user.fullName}" sera archiv\u00e9.'),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final willArchive = user.isActive;
                    try {
                      await SupabaseConfig.adminClient.from('users').update({'is_active': !willArchive}).eq('id', user.id);
                      ref.invalidate(usersProvider);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(willArchive ? 'Utilisateur archivé' : 'Utilisateur désarchivé'),
                            backgroundColor: willArchive ? AppColors.warning : AppColors.success,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(UserFriendlyError.format(e)), backgroundColor: AppColors.error));
                      }
                    }
                  },
                  icon: const Icon(Icons.archive_outlined, size: 16),
                  label: const Text('Archiver', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warning,
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
  }

  void _confirmDelete(BuildContext context, UserModel u) {
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
            const Text('Supprimer utilisateur ?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Voulez-vous vraiment supprimer "${u.fullName}" ?'),
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
                  onPressed: () => Navigator.pop(ctx),
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
                  onPressed: () {
                    ref.read(usersProvider.notifier).deleteUser(u.id);
                    Navigator.pop(ctx);
                  },
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
  }

  // ═══════════════════════════════════════════════════
  // BULK ACTIONS
  // ═══════════════════════════════════════════════════
  Future<void> _bulkToggleArchive(bool currentlyArchived) async {
    final newActive = currentlyArchived;
    try {
      await SupabaseConfig.adminClient
          .from('users')
          .update({'is_active': newActive})
          .inFilter('id', _selectedUserIds.toList());
      ref.invalidate(usersProvider);
      final count = _selectedUserIds.length;
      setState(() => _selectedUserIds.clear());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newActive ? '$count utilisateur(s) désarchivé(s)' : '$count utilisateur(s) archivé(s)'),
            backgroundColor: newActive ? AppColors.success : AppColors.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFriendlyError.format(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _showChangeClassDialog(BuildContext ctx, List<UserModel> students) async {
    if (students.isEmpty) return;

    final usersState = ref.read(usersProvider);
    List<ClassModel> allClasses = usersState.whenOrNull(data: (s) => s.classes) ?? [];
    if (allClasses.isEmpty) {
      try {
        final freshClasses = await SupabaseConfig.adminClient
            .from('classes')
            .select('*, niveaux:niveaux(name, code), sections:sections(name, code)')
            .order('name');
        if (freshClasses.isNotEmpty) {
          allClasses = freshClasses.map((e) => ClassModel.fromJson(e)).toList();
        }
      } catch (_) {}
    }

    if (allClasses.isEmpty) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Aucune classe disponible')),
        );
      }
      return;
    }

    final firstStudent = students.first;
    String? currentClassName = firstStudent.className;
    String? currentClassId;
    String? currentNiveauId;
    String? currentSectionId;

    // Look for student's current class in allClasses
    ClassModel? currentClass;
    final initialClassName = currentClassName;
    if (initialClassName != null && initialClassName.isNotEmpty) {
      currentClass = allClasses.where((c) => c.name.toLowerCase() == initialClassName.toLowerCase()).firstOrNull;
    }

    // If not found or missing niveau_id, fetch from enrollments
    if (currentClass == null || currentClass.gradeLevelId == null) {
      try {
        final enr = await SupabaseConfig.adminClient
            .from('enrollments')
            .select('class_id, classes:classes(id, name, niveau_id, section_id, niveaux:niveaux(name, code), sections:sections(name, code))')
            .eq('student_id', firstStudent.id)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (enr != null && enr['classes'] != null) {
          final cMap = enr['classes'] as Map<String, dynamic>;
          currentClassId = cMap['id']?.toString();
          currentClassName = cMap['name']?.toString() ?? currentClassName;
          currentNiveauId = cMap['niveau_id']?.toString();
          currentSectionId = cMap['section_id']?.toString();
          currentClass = allClasses.where((c) => c.id == currentClassId).firstOrNull;
        }
      } catch (e) {
        debugPrint('Error finding student current class: $e');
      }
    }

    if (currentClass != null) {
      currentClassId ??= currentClass.id;
      currentClassName ??= currentClass.name;
      currentNiveauId ??= currentClass.gradeLevelId;
      currentSectionId ??= currentClass.sectionId;
    }

    // Extract prefix from class name (e.g. "9B-1" -> "9B", "4S-ST-2" -> "4S-ST")
    String? classPrefix;
    if (currentClassName != null && currentClassName.contains('-')) {
      classPrefix = currentClassName.substring(0, currentClassName.lastIndexOf('-')).trim().toUpperCase();
    }

    // Freeze variables for filtering closure
    final fixedCurrentClassId = currentClassId;
    final fixedCurrentClassName = currentClassName?.toLowerCase();
    final fixedNiveauId = currentNiveauId;
    final fixedSectionId = currentSectionId;
    final fixedPrefix = classPrefix;

    // Filter available classes to ONLY classes of that student's niveau (and section/filière if exists)
    final availableClasses = allClasses.where((c) {
      // Exclude current class if single student
      if (students.length == 1) {
        if (fixedCurrentClassId != null && c.id == fixedCurrentClassId) return false;
        if (fixedCurrentClassName != null && c.name.toLowerCase() == fixedCurrentClassName) return false;
      }

      // 1. Match by niveau ID and section ID if available
      if (fixedNiveauId != null && c.gradeLevelId != null) {
        if (c.gradeLevelId != fixedNiveauId) return false;
        if (fixedSectionId != null && c.sectionId != null) {
          if (c.sectionId != fixedSectionId) return false;
        }
        return true;
      }

      // 2. Fallback: match by prefix (e.g. "9B" or "4S-ST")
      if (fixedPrefix != null && fixedPrefix.isNotEmpty) {
        final cPrefix = c.name.contains('-')
            ? c.name.substring(0, c.name.lastIndexOf('-')).trim().toUpperCase()
            : c.name.toUpperCase();
        return cPrefix == fixedPrefix;
      }

      // 3. Fallback: match by student.niveauCode
      if (firstStudent.niveauCode != null && firstStudent.niveauCode!.isNotEmpty) {
        final nCode = firstStudent.niveauCode!.toUpperCase();
        if (c.name.toUpperCase().startsWith(nCode)) return true;
        if (c.gradeLevelName != null && c.gradeLevelName!.toUpperCase().contains(nCode)) return true;
      }

      return true;
    }).toList();

    String? selectedClassId;
    String search = '';

    if (!ctx.mounted) return;

    await showDialog(
      context: ctx,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (dCtx) {
        return StatefulBuilder(builder: (dCtx, setInner) {
          final filtered = availableClasses.where((c) {
            if (search.isEmpty) return true;
            final q = search.toLowerCase();
            return c.name.toLowerCase().contains(q) || (c.gradeLevelName?.toLowerCase().contains(q) ?? false);
          }).toList();

          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 480,
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(dCtx).size.height * 0.8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 30,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Color(0xFFF1F1F5))),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEECFB),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.school_rounded, color: Color(0xFF6D4CF6), size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  students.length == 1 ? 'Changer la classe' : 'Changer la classe (${students.length} étudiants)',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  students.length == 1 ? students.first.fullName : '${students.length} étudiants sélectionnés',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(dCtx),
                            icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF9CA3AF)),
                          ),
                        ],
                      ),
                    ),
                    // From -> To Pill
                    if (currentClassName != null && currentClassName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Classe actuelle: $currentClassName',
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFFD97706)),
                                ),
                              ),
                              if (selectedClassId != null) ...[
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 6),
                                  child: Icon(Icons.arrow_forward_rounded, size: 14, color: Color(0xFF94A3B8)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD1FAE5),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Vers: ${availableClasses.where((c) => c.id == selectedClassId).firstOrNull?.name ?? ''}',
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF059669)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      // Search
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: TextField(
                          onChanged: (v) => setInner(() => search = v),
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Rechercher une classe...',
                            hintStyle: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
                            prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textTertiary),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E4EA))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E4EA))),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6D4CF6))),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            isDense: true,
                          ),
                        ),
                      ),
                      // Classes list without grey rectangle background
                      Flexible(
                        child: filtered.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.info_outline_rounded, size: 36, color: AppColors.textTertiary),
                                    const SizedBox(height: 10),
                                    Text(
                                      search.isEmpty
                                          ? 'Aucune autre classe disponible pour ce niveau'
                                          : 'Aucune classe trouvée pour "$search"',
                                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                shrinkWrap: true,
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final c = filtered[i];
                                  final isSelected = selectedClassId == c.id;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: InkWell(
                                      onTap: () => setInner(() => selectedClassId = c.id),
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                        decoration: BoxDecoration(
                                          color: isSelected ? const Color(0xFFEEECFB) : Colors.transparent,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: isSelected ? const Color(0xFF6D4CF6) : const Color(0xFFE2E8F0),
                                            width: isSelected ? 1.5 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.school_outlined,
                                              size: 18,
                                              color: isSelected ? const Color(0xFF6D4CF6) : const Color(0xFF64748B),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                c.name,
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                                  color: isSelected ? const Color(0xFF6D4CF6) : AppColors.textPrimary,
                                                ),
                                              ),
                                            ),
                                            Icon(
                                              isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                                              size: 18,
                                              color: isSelected ? const Color(0xFF6D4CF6) : const Color(0xFFCBD5E1),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      // Footer
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                          border: Border(top: BorderSide(color: Color(0xFFF1F1F5))),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx),
                              child: const Text('Annuler', style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: selectedClassId == null
                                  ? null
                                  : () async {
                                      Navigator.pop(dCtx);
                                      try {
                                        final studentIds = students.map((s) => s.id).toList();
                                        await SupabaseConfig.adminClient
                                            .from('enrollments')
                                            .update({'class_id': selectedClassId})
                                            .inFilter('student_id', studentIds);
                                        ref.invalidate(usersProvider);
                                        setState(() => _selectedUserIds.clear());
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Classe mise à jour avec succès'), backgroundColor: AppColors.success),
                                          );
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(UserFriendlyError.format(e)), backgroundColor: AppColors.error),
                                          );
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6D4CF6),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Valider', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        });
      },
    );
  }

  void _bulkDelete(BuildContext context) {
    final count = _selectedUserIds.length;
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
            const Text('Supprimer en masse ?', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Voulez-vous vraiment supprimer $count utilisateur(s) ?'),
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
                  onPressed: () => Navigator.pop(ctx),
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
                  onPressed: () async {
                    Navigator.pop(ctx);
                    if (!mounted) return;
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
                        backgroundColor: const Color(0xFF655DD5),
                      ),
                    );
                    final notifier = ref.read(usersProvider.notifier);
                    final result = await notifier.bulkDeleteUsers(_selectedUserIds.toList());
                    final deleted = result['deleted'] ?? 0;
                    final failed = result['failed'] ?? 0;
                    setState(() {
                      _selectedUserIds.clear();
                      _isSelectionMode = false;
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$deleted supprimé(s), $failed échec(s)'),
                          backgroundColor: failed == 0 ? AppColors.success : AppColors.warning,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      );
                    }
                  },
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
  }



  // ═══════════════════════════════════════════════════
  // IMPORT METHODS
  // ═══════════════════════════════════════════════════
  void _showImportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.upload_file, color: const Color(0xFF655DD5)),
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
              const Text('Importez des utilisateurs à partir d\'un fichier Excel (.xlsx) ou CSV (.csv)'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF655DD5).withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Format requis:', style: TextStyle(fontWeight: FontWeight.bold, color: const Color(0xFF655DD5))),
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
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFE8EAF0)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
          ),
          OutlinedButton.icon(
            onPressed: () { Navigator.pop(ctx); _downloadTemplate(); },
            icon: const Icon(Icons.download),
            label: const Text('Télécharger modèle'),
          ),
          ElevatedButton.icon(
            onPressed: () { Navigator.pop(ctx); _pickAndImportExcel(); },
            icon: const Icon(Icons.file_upload),
            label: const Text('Choisir fichier'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF655DD5), foregroundColor: Colors.white),
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
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
            child: Text(column, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
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

    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Nom complet *');
    sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue('Email *');
    sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('Téléphone');
    sheet.cell(CellIndex.indexByString('D1')).value = TextCellValue('Rôle');
    sheet.cell(CellIndex.indexByString('E1')).value = TextCellValue('Date naissance');
    sheet.cell(CellIndex.indexByString('F1')).value = TextCellValue('Adresse');

    sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue('Ahmed Ben Ali');
    sheet.cell(CellIndex.indexByString('B2')).value = TextCellValue('ahmed.benali@example.com');
    sheet.cell(CellIndex.indexByString('C2')).value = TextCellValue('+216 55 123 456');
    sheet.cell(CellIndex.indexByString('D2')).value = TextCellValue('student');
    sheet.cell(CellIndex.indexByString('E2')).value = TextCellValue('15/03/2008');
    sheet.cell(CellIndex.indexByString('F2')).value = TextCellValue('Tunis, Tunisie');

    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

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
          const SnackBar(content: Text('Modèle prêt à télécharger'), backgroundColor: AppColors.success),
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
          final content = String.fromCharCodes(bytes);
          final lines = content.split('\n');
          for (var i = 1; i < lines.length; i++) {
            final line = lines[i].trim();
            if (line.isEmpty) continue;
            final parts = line.split(',');
            if (parts.length < 2) continue;
            final fullName = parts[0].trim();
            final email = parts[1].trim();
            if (fullName.isNotEmpty && email.isNotEmpty) {
              users.add({
                'fullName': fullName,
                'email': email,
                'phone': parts.length > 2 ? parts[2].trim() : '',
                'role': parts.length > 3 ? (parts[3].trim().isEmpty ? 'student' : parts[3].trim().toLowerCase()) : 'student',
                'dateOfBirth': parts.length > 4 ? parts[4].trim() : '',
                'address': parts.length > 5 ? parts[5].trim() : '',
              });
            }
          }
        } else {
          final excel = Excel.decodeBytes(bytes);
          for (final table in excel.tables.keys) {
            final sheet = excel.tables[table]!;
            for (var i = 1; i < sheet.maxRows; i++) {
              final row = sheet.rows[i];
              if (row.isEmpty || row[0]?.value == null) continue;
              final fullName = row[0]?.value?.toString() ?? '';
              final email = row[1]?.value?.toString() ?? '';
              if (fullName.isNotEmpty && email.isNotEmpty) {
                users.add({
                  'fullName': fullName,
                  'email': email,
                  'phone': row.length > 2 ? row[2]?.value?.toString() ?? '' : '',
                  'role': row.length > 3 ? (row[3]?.value?.toString() ?? 'student').toLowerCase() : 'student',
                  'dateOfBirth': row.length > 4 ? row[4]?.value?.toString() ?? '' : '',
                  'address': row.length > 5 ? row[5]?.value?.toString() ?? '' : '',
                });
              }
            }
            break;
          }
        }

        if (users.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Aucun utilisateur valide trouvé'), backgroundColor: AppColors.warning),
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
                      itemBuilder: (ctx, i) => Text('• ${users[i]['fullName']} (${users[i]['email']})', style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                  if (users.length > 5)
                    Text('... et ${users.length - 5} autres', style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                ],
              ),
              actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFE8EAF0)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(ctx, true),
                          icon: const Icon(Icons.upload, size: 16),
                          label: const Text('Importer', style: TextStyle(fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF655DD5),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );

          if (confirm == true) await _importUsers(users);
        }
        setState(() => _isImporting = false);
      }
    } catch (e) {
      setState(() => _isImporting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFriendlyError.format(e, fallback: 'Unable to import users from this file. Please verify the file and try again.')), backgroundColor: AppColors.error),
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
          createdUsers.add({'email': user['email']!, 'fullName': user['fullName']!, 'password': password});
        } else {
          failed++;
          errors.add(user['email']!);
        }
      } catch (e) {
        failed++;
        errors.add('${user['email']}: ${UserFriendlyError.format(e, fallback: 'Unable to create this account.')}');
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
      if (createdUsers.isNotEmpty) _showGeneratedCredentials(createdUsers);
      if (errors.isNotEmpty) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.warning_amber, color: AppColors.warning),
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
                        child: Text('• ${errors[i]}', style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            actions: [
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE8EAF0)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
                ),
              ),
            ],
          ),
        );
      }
    }
  }

  void _showGeneratedCredentials(List<Map<String, String>> createdUsers) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.success),
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
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF655DD5).withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: const Color(0xFF655DD5)),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Veuillez télécharger ou copier ces identifiants. Les mots de passe ne seront plus accessibles après fermeture.',
                        style: TextStyle(color: const Color(0xFF655DD5), fontSize: 13),
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
                    rows: createdUsers.map((u) => DataRow(cells: [
                      DataCell(Text(u['fullName'] ?? '', style: const TextStyle(fontSize: 12))),
                      DataCell(Text(u['email'] ?? '', style: const TextStyle(fontSize: 12))),
                      DataCell(SelectableText(u['password'] ?? '', style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.success))),
                    ])).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: () => _exportCredentials(createdUsers),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE8EAF0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Télécharger Excel', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE8EAF0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Fermer', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

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

    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

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

// ═══════════════════════════════════════════════════
// ROLE CHIP WIDGET
// ═══════════════════════════════════════════════════
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
        bg = const Color(0xFFF5F3FF);
        fg = const Color(0xFF655DD5);
        label = 'Manager';
        icon = Icons.badge_outlined;
        break;
      default:
        bg = AppColors.accentSoft;
        fg = AppColors.accent;
        label = role;
        icon = Icons.person_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }
}
