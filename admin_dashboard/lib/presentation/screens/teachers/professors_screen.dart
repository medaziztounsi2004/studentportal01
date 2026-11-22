import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../../data/services/user_management_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/admin_sidebar.dart';
import '../../widgets/ios_loader.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/admin_sort_dropdown.dart';


// ── Speciality Color Helper ───────────────────────────────────────────────

Color _specialityColor(String? name) {
  if (name == null || name.trim().isEmpty) return const Color(0xFF655DD5);
  final s = name.trim().toLowerCase();

  if (s.contains('math')) return const Color(0xFF2563EB); // Blue
  if (s.contains('phys') || s.contains('chim')) return const Color(0xFFDC2626); // Red
  if (s.contains('svt') || s.contains('biol') || s.contains('vie') || s.contains('sc. nat')) return const Color(0xFF059669); // Emerald
  if (s.contains('arab') || s == 'ar') return const Color(0xFF0891B2); // Cyan
  if (s.contains('fran') || s == 'fr') return const Color(0xFF7C3AED); // Purple
  if (s.contains('angl') || s.contains('eng') || s == 'en' || s == 'ang') return const Color(0xFFDB2777); // Pink
  if (s.contains('hist') || s.contains('géo') || s.contains('geo') || s == 'hg') return const Color(0xFFD97706); // Amber
  if (s.contains('philo')) return const Color(0xFF4F46E5); // Indigo
  if (s.contains('info') || s.contains('tic') || s.contains('prog') || s.contains('syst') || s.contains('réseau')) return const Color(0xFF0284C7); // Sky
  if (s.contains('sport') || s.contains('eps')) return const Color(0xFF10B981); // Green
  if (s.contains('esp') || s.contains('span')) return const Color(0xFFE11D48); // Crimson
  if (s.contains('all') || s.contains('germ')) return const Color(0xFFB45309); // Dark Amber
  if (s.contains('ita')) return const Color(0xFF047857); // Forest Green
  if (s.contains('tech') || s.contains('méc') || s.contains('élec')) return const Color(0xFF6D28D9); // Violet
  if (s.contains('éco') || s.contains('eco') || s.contains('gest') || s.contains('compt')) return const Color(0xFFEA580C); // Orange
  if (s.contains('mus') || s.contains('art') || s.contains('dess')) return const Color(0xFFBE185D); // Berry
  if (s.contains('islam') || s.contains('pens') || s.contains('relig') || s.contains('pens_is')) return const Color(0xFF9333EA); // Purple-violet

  final hue = (s.hashCode % 360).abs().toDouble();
  return HSLColor.fromAHSL(1.0, hue, 0.65, 0.45).toColor();
}

// ── Provider ───────────────────────────────────────────────────────────────

class ProfessorsNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async => _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final response = await Supabase.instance.client
        .from('users')
        .select('id, full_name, email, phone, photo_url, role, is_active, created_at, gender')
        .eq('role', 'teacher')
        .order('full_name', ascending: true);

    final professors = List<Map<String, dynamic>>.from(response as List);

    // Fetch teacher assignments with subjects, classes, and niveaux
    final teacherIds = professors.map((p) => p['id'] as String).toList();
    if (teacherIds.isNotEmpty) {
      try {
        final assignmentsResp = await Supabase.instance.client
            .from('teacher_assignments')
            .select('teacher_id, subject_id, niveau_id, class_id, subjects(name), classes(name, niveaux(code)), niveaux(code)')
            .inFilter('teacher_id', teacherIds)
            .eq('is_active', true);

        // Group subjects, classes, niveaux by teacher_id
        final Map<String, Set<String>> teacherSubjects = {};
        final Map<String, List<String>> teacherClasses = {};
        final Map<String, Set<String>> teacherNiveaux = {};
        for (final a in assignmentsResp as List) {
          final teacherId = a['teacher_id'] as String?;
          final subjectName = (a['subjects'] as Map?)?['name'] as String?;
          final className = (a['classes'] as Map?)?['name'] as String?;
          // Try direct niveau_id first, fallback to class→niveaux, use code
          final niveauCode = (a['niveaux'] as Map?)?['code'] as String? ??
              ((a['classes'] as Map?)?['niveaux'] as Map?)?['code'] as String?;
          if (teacherId != null) {
            if (subjectName != null) teacherSubjects.putIfAbsent(teacherId, () => {}).add(subjectName);
            if (className != null) teacherClasses.putIfAbsent(teacherId, () => []).add(className);
            if (niveauCode != null) teacherNiveaux.putIfAbsent(teacherId, () => {}).add(niveauCode);
          }
        }

        for (final prof in professors) {
          final id = prof['id'] as String;
          final subjects = teacherSubjects[id];
          prof['speciality'] = subjects != null && subjects.isNotEmpty ? subjects.first : null;
          prof['all_subjects'] = subjects?.toList() ?? [];
          prof['classes'] = teacherClasses[id] ?? [];
          prof['niveaux'] = teacherNiveaux[id]?.toList() ?? [];
        }
      } catch (_) {
        for (final prof in professors) {
          prof['speciality'] = null;
          prof['all_subjects'] = <String>[];
          prof['classes'] = <String>[];
          prof['niveaux'] = <String>[];
        }
      }
    }

    return professors;
  }

  Future<void> refresh({bool showLoading = false}) async {
    if (showLoading) state = const AsyncValue.loading();
    state = AsyncValue.data(await _load());
  }

  Future<bool> toggleArchive(List<String> userIds, bool isActive) async {
    final previous = state.value;
    final idSet = userIds.toSet();
    if (state.value != null) {
      state = AsyncValue.data(
        state.value!.map((p) {
          if (idSet.contains(p['id'])) {
            final copy = Map<String, dynamic>.from(p);
            copy['is_active'] = isActive;
            return copy;
          }
          return p;
        }).toList(),
      );
    }
    try {
      final success = await UserManagementService.toggleArchive(userIds: userIds, isActive: isActive);
      await refresh(showLoading: false);
      return success;
    } catch (e) {
      if (previous != null) state = AsyncValue.data(previous);
      return false;
    }
  }

  Future<bool> delete(String id) async {
    final previous = state.value;
    if (state.value != null) {
      state = AsyncValue.data(state.value!.where((p) => p['id'] != id).toList());
    }
    try {
      final success = await UserManagementService.deleteUser(id);
      await refresh(showLoading: false);
      return success;
    } catch (e) {
      if (previous != null) state = AsyncValue.data(previous);
      return false;
    }
  }

  Future<bool> bulkDelete(List<String> ids) async {
    final previous = state.value;
    final idSet = ids.toSet();
    if (state.value != null) {
      state = AsyncValue.data(state.value!.where((p) => !idSet.contains(p['id'])).toList());
    }
    try {
      await UserManagementService.bulkDeleteUsers(ids);
      await refresh(showLoading: false);
      return true;
    } catch (e) {
      if (previous != null) state = AsyncValue.data(previous);
      return false;
    }
  }
}

final professorsProvider = AsyncNotifierProvider<ProfessorsNotifier, List<Map<String, dynamic>>>(
  ProfessorsNotifier.new,
);

final _subjectsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  // Get school_id from authenticated user
  String? schoolId = ref.watch(authProvider).user?.schoolId;
  if (schoolId == null) {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId != null) {
        final profile = await Supabase.instance.client
            .from('users')
            .select('school_id')
            .eq('id', currentUserId)
            .maybeSingle();
        schoolId = profile?['school_id'] as String?;
      }
    } catch (_) {}
  }

  var query = Supabase.instance.client
      .from('subjects')
      .select('id, name, code')
      .eq('is_active', true);
  if (schoolId != null) {
    query = query.eq('school_id', schoolId);
  }
  final response = await query.order('name', ascending: true);
  return List<Map<String, dynamic>>.from(response as List);
});

// ── Screen ─────────────────────────────────────────────────────────────────

class ProfessorsScreen extends ConsumerStatefulWidget {
  const ProfessorsScreen({super.key});

  @override
  ConsumerState<ProfessorsScreen> createState() => _ProfessorsScreenState();
}

class _ProfessorsScreenState extends ConsumerState<ProfessorsScreen> {
  String _searchQuery = '';
  String? _statusFilter; // null = tous, 'active', 'archived'
  String _genderFilter = 'all';
  String _specialityFilter = 'all';
  String _sortKey = 'name_asc';
  final _searchController = TextEditingController();
  bool _showFilterDrawer = false;

  // Bulk selection
  final Set<String> _selectedProfIds = {};

  // Pagination
  int _currentPage = 1;
  int _itemsPerPage = 20;

  bool get _hasActiveFilters => _statusFilter != null || _genderFilter != 'all' || _specialityFilter != 'all';

  void _toggleFilters() => setState(() => _showFilterDrawer = !_showFilterDrawer);

  void _resetFilters() => setState(() {
    _statusFilter = null;
    _genderFilter = 'all';
    _specialityFilter = 'all';
    _sortKey = 'name_asc';
    _currentPage = 1;
  });

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> professors) {
    final filtered = professors.where((p) {
      final name = (p['full_name'] as String? ?? '').toLowerCase();
      final email = (p['email'] as String? ?? '').toLowerCase();
      final query = _searchQuery.toLowerCase();
      final matchesSearch = query.isEmpty || name.contains(query) || email.contains(query);

      final isActive = p['is_active'] == true;
      final matchesStatus = _statusFilter == null ||
          (_statusFilter == 'active' && isActive) ||
          (_statusFilter == 'archived' && !isActive);

      final gender = (p['gender'] as String? ?? '').toLowerCase();
      final matchesGender = _genderFilter == 'all' ||
          (_genderFilter == 'male' && gender == 'male') ||
          (_genderFilter == 'female' && gender == 'female');

      final speciality = (p['speciality'] as String? ?? '').toLowerCase();
      final allSubjects = (p['all_subjects'] as List<String>? ?? []).map((s) => s.toLowerCase()).toList();
      final matchesSpeciality = _specialityFilter == 'all' ||
          speciality == _specialityFilter.toLowerCase() ||
          allSubjects.contains(_specialityFilter.toLowerCase());

      return matchesSearch && matchesStatus && matchesGender && matchesSpeciality;
    }).toList();

    filtered.sort((a, b) {
      switch (_sortKey) {
        case 'date_desc':
          final da = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(1970);
          final db = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(1970);
          return db.compareTo(da);
        case 'date_asc':
          final da = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(1970);
          final db = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(1970);
          return da.compareTo(db);
        case 'name_desc':
          final na = (a['full_name'] as String? ?? '').toLowerCase();
          final nb = (b['full_name'] as String? ?? '').toLowerCase();
          return nb.compareTo(na);
        case 'speciality_asc':
          final sa = (a['speciality'] as String? ?? '').toLowerCase();
          final sb = (b['speciality'] as String? ?? '').toLowerCase();
          if (sa.isEmpty && sb.isNotEmpty) return 1;
          if (sa.isNotEmpty && sb.isEmpty) return -1;
          return sa.compareTo(sb);
        case 'status_active':
          final aa = a['is_active'] == true ? 0 : 1;
          final ab = b['is_active'] == true ? 0 : 1;
          if (aa != ab) return aa.compareTo(ab);
          final na = (a['full_name'] as String? ?? '').toLowerCase();
          final nb = (b['full_name'] as String? ?? '').toLowerCase();
          return na.compareTo(nb);
        case 'name_asc':
        default:
          final na = (a['full_name'] as String? ?? '').toLowerCase();
          final nb = (b['full_name'] as String? ?? '').toLowerCase();
          return na.compareTo(nb);
      }
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final professorsAsync = ref.watch(professorsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Row(
            children: [
              const AdminSidebar(currentRoute: '/professors'),
              Expanded(
                child: Column(
                  children: [
                    _buildHeader(context, professorsAsync),
                    _buildStatusFilterBar(context, professorsAsync),
                    Expanded(
                      child: professorsAsync.when(
                        loading: () => const ProfessorsSkeletonLoader(),
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
                                const Icon(Icons.error_outline_rounded, size: 36, color: AppColors.error),
                                const SizedBox(height: 12),
                                Text(
                                  UserFriendlyError.format(
                                    e,
                                    fallback: 'Unable to load professors right now. Please try again.',
                                  ),
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () => ref.invalidate(professorsProvider),
                                  icon: const Icon(Icons.refresh_rounded, size: 18),
                                  label: const Text('Réessayer'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        data: (professors) {
                          final filtered = _applyFilters(professors);
                          final start = (_currentPage - 1) * _itemsPerPage;
                          final end = _itemsPerPage == -1 ? filtered.length : (start + _itemsPerPage).clamp(0, filtered.length);
                          final pageItems = filtered.sublist(start, end);
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
                                    Expanded(child: _buildTable(context, pageItems)),
                                    _buildPagination(filtered.length),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Floating selection bar
          if (_selectedProfIds.isNotEmpty)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(child: _buildFloatingSelectionBar(context)),
            ),
          // ── Filter drawer overlay ──
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
              child: _buildFilterDrawer(context, professorsAsync),
            ),
          ],
        ],
      ),
    );
  }

  // ── Header (matching users page layout) ─────────────────────────────────

  Widget _buildHeader(BuildContext context, AsyncValue<List<Map<String, dynamic>>> professorsAsync) {
    final total = professorsAsync.whenOrNull(data: (p) => p.length) ?? 0;
    final activeCount = professorsAsync.whenOrNull(data: (p) => p.where((u) => u['is_active'] == true).length) ?? 0;

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
                'Professeurs',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$total professeurs • $activeCount actifs',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
          const Spacer(),
          // Search bar — width 320, height 40 (same as users)
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
                          setState(() {
                            _searchQuery = '';
                            _currentPage = 1;
                          });
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
                  borderSide: BorderSide(color: AppColors.primary.withOpacity(0.4), width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AdminSortDropdown<String>(
            selectedValue: _sortKey,
            options: const [
              SortOption(value: 'name_asc', label: 'Nom: A → Z', icon: Icons.sort_by_alpha_rounded),
              SortOption(value: 'name_desc', label: 'Nom: Z → A', icon: Icons.sort_by_alpha_rounded),
              SortOption(value: 'date_desc', label: 'Date: Plus récent', icon: Icons.schedule_rounded),
              SortOption(value: 'date_asc', label: 'Date: Plus ancien', icon: Icons.history_rounded),
              SortOption(value: 'speciality_asc', label: 'Spécialité: A → Z', icon: Icons.school_outlined),
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
          // Filter button — same as users
          IconButton(
            icon: const Icon(Icons.filter_list_rounded, size: 20),
            tooltip: 'Filtres',
            onPressed: _toggleFilters,
            color: (_showFilterDrawer || _hasActiveFilters) ? AppColors.primary : AppColors.textTertiary,
            style: IconButton.styleFrom(
              backgroundColor: (_showFilterDrawer || _hasActiveFilters) ? AppColors.primarySoft : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: (_showFilterDrawer || _hasActiveFilters) ? AppColors.primary.withOpacity(0.2) : Colors.transparent),
              ),
            ),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          const SizedBox(width: 16),
          // Ajouter button — same as users
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: () => _showAddProfessorDialog(context),
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

  // ── Status Filter Bar (Tous / Actifs / Archivés) ────────────────────────
  Widget _buildStatusFilterBar(BuildContext context, AsyncValue<List<Map<String, dynamic>>> professorsAsync) {
    final allProfs = professorsAsync.whenOrNull(data: (p) => p) ?? [];
    final isLoading = professorsAsync.isLoading;
    final totalCount = allProfs.length;
    final activeCount = allProfs.where((p) => p['is_active'] == true).length;
    final inactiveCount = allProfs.where((p) => p['is_active'] != true).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.5))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.slate100.withOpacity(0.8),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                _buildStatusChip('Tous', totalCount, _statusFilter == null, () => setState(() { _statusFilter = null; _currentPage = 1; }), isLoading: isLoading),
                _buildStatusChip('Actifs', activeCount, _statusFilter == 'active', () => setState(() { _statusFilter = 'active'; _currentPage = 1; }), isLoading: isLoading),
                _buildStatusChip('Inactifs', inactiveCount, _statusFilter == 'archived', () => setState(() { _statusFilter = 'archived'; _currentPage = 1; }), isLoading: isLoading),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, int count, bool isActive, VoidCallback onTap, {bool isLoading = false}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
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
              if (isLoading)
                const SkeletonBox(width: 14, height: 12, borderRadius: 3)
              else
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

  // ── Filter Drawer (sidebar, matching users page) ──────────────────────────

  Widget _buildFilterDrawer(BuildContext context, AsyncValue<List<Map<String, dynamic>>> professorsAsync) {
    return Material(
      elevation: 16,
      color: Colors.white,
      child: SizedBox(
        width: 370,
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
                    // Status
                    _buildDrawerFilterLabel('STATUT'),
                    const SizedBox(height: 8),
                    _buildDrawerDropdown<String>(
                      value: _statusFilter,
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Tous')),
                        DropdownMenuItem(value: 'active', child: Text('Actifs')),
                        DropdownMenuItem(value: 'archived', child: Text('Inactifs')),
                      ],
                      onChanged: (v) => setState(() {
                        _statusFilter = v;
                        _currentPage = 1;
                      }),
                    ),
                    const SizedBox(height: 20),
                    // Genre
                    _buildDrawerFilterLabel('GENRE'),
                    const SizedBox(height: 8),
                    _buildDrawerDropdown<String>(
                      value: _genderFilter,
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('Tous')),
                        DropdownMenuItem(value: 'male', child: Text('Hommes')),
                        DropdownMenuItem(value: 'female', child: Text('Femmes')),
                      ],
                      onChanged: (v) => setState(() {
                        _genderFilter = v ?? 'all';
                        _currentPage = 1;
                      }),
                    ),
                    const SizedBox(height: 20),
                    // Specialité
                    _buildDrawerFilterLabel('SPÉCIALITÉ'),
                    const SizedBox(height: 8),
                    _buildSpecialityDropdown(professorsAsync),
                  ],
                ),
              ),
            ),
            // Footer — exact users page style
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
                          onTap: () => setState(() => _showFilterDrawer = false),
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

  Widget _buildSpecialityDropdown(AsyncValue<List<Map<String, dynamic>>> professorsAsync) {
    // Extract unique specialities from all professors
    final allSpecialities = <String>{};
    professorsAsync.whenOrNull(data: (professors) {
      for (final prof in professors) {
        final subjects = prof['all_subjects'] as List<String>? ?? [];
        allSpecialities.addAll(subjects);
      }
    });
    final sortedSpecialities = allSpecialities.toList()..sort();

    return _buildDrawerDropdown<String>(
      value: _specialityFilter == 'all' ? 'all' : (_specialityFilter),
      items: [
        const DropdownMenuItem(value: 'all', child: Text('Toutes')),
        ...sortedSpecialities.map((s) => DropdownMenuItem(value: s, child: Text(s))),
      ],
      onChanged: (v) => setState(() {
        _specialityFilter = v ?? 'all';
        _currentPage = 1;
      }),
    );
  }

  PopupMenuItem<String> _buildProfPopupItem(String value, IconData icon, String label, Color color) {
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

  void _handleProfessorAction(String action, Map<String, dynamic> prof) {
    final id = prof['id'] as String? ?? '';
    switch (action) {
      case 'view':
        if (id.isNotEmpty) context.push('/teachers/$id');
        break;
      case 'archive':
        _confirmArchiveProfessor(context, prof);
        break;
      case 'unarchive':
        _confirmUnarchiveProfessor(context, prof);
        break;
      case 'delete':
        _confirmDeleteProfessor(context, prof);
        break;
    }
  }

  void _confirmArchiveProfessor(BuildContext context, Map<String, dynamic> prof) {
    final name = prof['full_name'] as String? ?? 'N/A';
    final id = prof['id'] as String? ?? '';
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
              const Text('Archiver ce professeur ?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                ),
                child: Row(
                  children: [
                    UserAvatar(
                      name: name,
                      photoUrl: prof['photo_url'] as String?,
                      radius: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            (prof['speciality'] as String?) ?? 'Enseignant',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.slate500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Ce professeur sera archivé et désactivé.',
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
                    child: const Text('Annuler', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      ref.read(professorsProvider.notifier).toggleArchive([id], false);
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Professeur "$name" archivé'), backgroundColor: AppColors.warning));
                    },
                    icon: const Icon(Icons.archive_outlined, size: 16),
                    label: const Text('Archiver', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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

  void _confirmUnarchiveProfessor(BuildContext context, Map<String, dynamic> prof) {
    final name = prof['full_name'] as String? ?? 'N/A';
    final id = prof['id'] as String? ?? '';
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
                decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.unarchive_outlined, color: Color(0xFF6D4CF6), size: 18),
              ),
              const SizedBox(width: 12),
              const Text('Désarchiver ce professeur ?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          content: Text('Le professeur "$name" sera réactivé.'),
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
                    child: const Text('Annuler', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      ref.read(professorsProvider.notifier).toggleArchive([id], true);
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Professeur "$name" désarchivé'), backgroundColor: AppColors.success));
                    },
                    icon: const Icon(Icons.unarchive_outlined, size: 16),
                    label: const Text('Désarchiver', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6D4CF6),
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

  void _confirmDeleteProfessor(BuildContext context, Map<String, dynamic> prof) {
    final name = prof['full_name'] as String? ?? 'N/A';
    final id = prof['id'] as String? ?? '';
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
              const Text('Supprimer professeur ?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Voulez-vous vraiment supprimer "$name" ?'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.slate50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: AppColors.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('ID: $id', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary, fontFamily: 'monospace')),
                    ),
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
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF6B7280), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                  child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    ref.read(professorsProvider.notifier).delete(id);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Professeur "$name" supprimé'), backgroundColor: AppColors.error));
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Supprimer', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerFilterLabel(String text) {
    return Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: AppColors.textTertiary),
    );
  }

  Widget _buildDrawerDropdown<T>({
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(8),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ── Floating Selection Bar ───────────────────────────────────────────────

  Widget _buildFloatingSelectionBar(BuildContext context) {
    final count = _selectedProfIds.length;
    final profsAsync = ref.read(professorsProvider);
    final allProfs = profsAsync.value ?? [];
    final selectedProfs = allProfs.where((p) => _selectedProfIds.contains(p['id'])).toList();
    final allInactive = selectedProfs.isNotEmpty && selectedProfs.every((p) => p['is_active'] != true);

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
                      color: AppColors.primary,
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
            if (allInactive)
              _buildSelectionAction(Icons.unarchive_outlined, 'Désarchiver', Colors.white, () => _bulkUnarchive(context))
            else
              _buildSelectionAction(Icons.archive_outlined, 'Archiver', Colors.white70, () => _bulkArchive(context)),
            _buildSelectionAction(Icons.delete_outline, 'Supprimer', const Color(0xFFFCA5A5), () => _bulkDelete(context)),
            // Close button
            Container(
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: Colors.white.withOpacity(0.15))),
              ),
              child: IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.white60),
                onPressed: () => setState(() => _selectedProfIds.clear()),
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

  void _bulkArchive(BuildContext context) {
    final count = _selectedProfIds.length;
    final profsAsync = ref.read(professorsProvider);
    final allProfs = profsAsync.value ?? [];
    final selectedProfs = allProfs.where((p) => _selectedProfIds.contains(p['id'])).toList();
    final singleProf = selectedProfs.length == 1 ? selectedProfs.first : null;

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
              Text(
                count == 1 && singleProf != null
                    ? 'Archiver ce professeur ?'
                    : 'Archiver $count professeur${count > 1 ? 's' : ''} ?',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ),
          content: count == 1 && singleProf != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                      ),
                      child: Row(
                        children: [
                          UserAvatar(
                            name: singleProf['full_name'] as String? ?? 'Professeur',
                            photoUrl: singleProf['photo_url'] as String?,
                            radius: 18,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  singleProf['full_name'] as String? ?? 'Professeur',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  (singleProf['speciality'] as String?) ?? 'Enseignant',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.slate500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Ce professeur sera archivé et désactivé.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                )
              : Text('$count professeur${count > 1 ? 's seront archivés' : ' sera archivé'} et désactivé${count > 1 ? 's' : ''}.'),
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
                    child: const Text('Annuler', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final ids = _selectedProfIds.toList();
                      setState(() => _selectedProfIds.clear());
                      Navigator.pop(ctx);
                      ref.read(professorsProvider.notifier).toggleArchive(ids, false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$count professeur${count > 1 ? 's archivés' : ' archivé'}'), backgroundColor: AppColors.warning),
                        );
                      }
                    },
                    icon: const Icon(Icons.archive_outlined, size: 16),
                    label: const Text('Archiver', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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

  void _bulkUnarchive(BuildContext context) {
    final count = _selectedProfIds.length;
    final profsAsync = ref.read(professorsProvider);
    final allProfs = profsAsync.value ?? [];
    final selectedProfs = allProfs.where((p) => _selectedProfIds.contains(p['id'])).toList();
    final singleProf = selectedProfs.length == 1 ? selectedProfs.first : null;

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
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.unarchive_outlined, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                count == 1 && singleProf != null
                    ? 'Désarchiver ce professeur ?'
                    : 'Désarchiver $count professeur${count > 1 ? 's' : ''} ?',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ),
          content: count == 1 && singleProf != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                      ),
                      child: Row(
                        children: [
                          UserAvatar(
                            name: singleProf['full_name'] as String? ?? 'Professeur',
                            photoUrl: singleProf['photo_url'] as String?,
                            radius: 18,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  singleProf['full_name'] as String? ?? 'Professeur',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  (singleProf['speciality'] as String?) ?? 'Enseignant',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.slate500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Ce professeur sera désarchivé et réactivé.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                )
              : Text('$count professeur${count > 1 ? 's seront désarchivés' : ' sera désarchivé'} et réactivé${count > 1 ? 's' : ''}.'),
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
                    child: const Text('Annuler', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final ids = _selectedProfIds.toList();
                      setState(() => _selectedProfIds.clear());
                      Navigator.pop(ctx);
                      ref.read(professorsProvider.notifier).toggleArchive(ids, true);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$count professeur${count > 1 ? 's désarchivés' : ' désarchivé'}'), backgroundColor: AppColors.success),
                        );
                      }
                    },
                    icon: const Icon(Icons.unarchive_outlined, size: 16),
                    label: const Text('Désarchiver', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6D4CF6),
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

  void _bulkDelete(BuildContext context) {
    final count = _selectedProfIds.length;
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
              Text('Supprimer $count professeur${count > 1 ? 's' : ''} ?', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          content: Text('Cette action est irréversible. $count professeur${count > 1 ? 's seront supprimés' : ' sera supprimé'} définitivement.'),
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
                  onPressed: () {
                    final ids = _selectedProfIds.toList();
                    setState(() => _selectedProfIds.clear());
                    Navigator.pop(ctx);
                    ref.read(professorsProvider.notifier).bulkDelete(ids);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$count professeur${count > 1 ? 's supprimés' : ' supprimé'}'), backgroundColor: AppColors.error),
                      );
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text('Supprimer $count', style: const TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error, foregroundColor: Colors.white,
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


  Widget _headerLabel(String text, {Alignment alignment = Alignment.centerLeft, TextAlign textAlign = TextAlign.left}) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text,
        textAlign: textAlign,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textTertiary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ── Table ─────────────────────────────────────────────────────────────────

  Widget _buildTable(BuildContext context, List<Map<String, dynamic>> professors) {
    if (professors.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.school_outlined, size: 36, color: Color(0xFF6366F1)),
            ),
            const SizedBox(height: 16),
            const Text('Aucun professeur trouvé', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
            const SizedBox(height: 6),
            const Text('Essayez de modifier la recherche ou les filtres', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
          ],
        ),
      );
    }

    final allPageSelected = professors.isNotEmpty && professors.every((p) => _selectedProfIds.contains(p['id']));

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        const checkboxW = 40.0;
        const actionsW = 40.0;
        const phoneW = 140.0;
        const specialityW = 140.0;
        const niveauxW = 100.0;
        const classesW = 110.0;
        const dateJoinedW = 90.0;
        final nameW = (availableWidth - checkboxW - phoneW - specialityW - niveauxW - classesW - dateJoinedW - actionsW).clamp(220.0, 360.0);

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: availableWidth),
            child: DataTable(
                  columnSpacing: 12,
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
                              value: allPageSelected && professors.isNotEmpty,
                              tristate: false,
                              onChanged: (v) {
                                setState(() {
                                  if (allPageSelected) {
                                    for (final p in professors) _selectedProfIds.remove(p['id']);
                                  } else {
                                    for (final p in professors) _selectedProfIds.add(p['id'] as String);
                                  }
                                });
                              },
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                              side: BorderSide(color: AppColors.slate300, width: 1.5),
                              activeColor: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    DataColumn(label: SizedBox(width: nameW, child: _headerLabel('NOM COMPLET / EMAIL'))),
                    DataColumn(label: SizedBox(width: specialityW, child: _headerLabel('SPÉCIALITÉ', alignment: Alignment.center, textAlign: TextAlign.center))),
                    DataColumn(label: SizedBox(width: niveauxW, child: _headerLabel('NIVEAUX', alignment: Alignment.center, textAlign: TextAlign.center))),
                    DataColumn(label: SizedBox(width: classesW, child: _headerLabel('CLASSES', alignment: Alignment.center, textAlign: TextAlign.center))),
                    DataColumn(label: SizedBox(width: phoneW, child: _headerLabel('TÉLÉPHONE', alignment: Alignment.center, textAlign: TextAlign.center))),
                    DataColumn(label: SizedBox(width: dateJoinedW, child: _headerLabel('CRÉÉ LE', alignment: Alignment.center, textAlign: TextAlign.center))),
                    DataColumn(label: SizedBox(width: actionsW, child: Container())),
                  ],
                  rows: professors.map((prof) {
                    final id = prof['id'] as String? ?? '';
                    final name = prof['full_name'] as String? ?? 'N/A';
                    final email = prof['email'] as String? ?? '';
                    final phone = prof['phone'] as String? ?? '';
                    final isActiveProf = prof['is_active'] == true;
                    final gender = prof['gender'] as String? ?? '';
                    final photoUrl = prof['photo_url'] as String?;
                    final speciality = prof['speciality'] as String?;
                    final profClasses = (prof['classes'] as List?)?.cast<String>() ?? [];
                    final profNiveaux = (prof['niveaux'] as List?)?.cast<String>() ?? [];
                    final createdAt = prof['created_at'] != null ? DateTime.tryParse(prof['created_at']) : null;
                    final isSelected = _selectedProfIds.contains(id);

                    return DataRow(
                      color: WidgetStateProperty.resolveWith<Color?>((states) {
                        if (isSelected) return const Color(0xFFF5F3FF).withOpacity(0.4);
                        if (states.contains(WidgetState.hovered)) return const Color(0xFFF9FAFB);
                        return null;
                      }),
                      cells: [
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
                                        _selectedProfIds.add(id);
                                      } else {
                                        _selectedProfIds.remove(id);
                                      }
                                    });
                                  },
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                                  side: BorderSide(color: AppColors.slate300, width: 1.5),
                                  activeColor: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Name + Email + Avatar
                        DataCell(
                          SizedBox(
                            width: nameW,
                            child: Row(
                              children: [
                                UserAvatar(
                                  name: name,
                                  photoUrl: photoUrl,
                                  gender: gender,
                                  radius: 17,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              name,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                                color: isActiveProf ? AppColors.textPrimary : AppColors.textTertiary,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (!isActiveProf) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFEF2F2),
                                                borderRadius: BorderRadius.circular(100),
                                              ),
                                              child: const Text(
                                                'Inactif',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFFDC2626),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        email,
                                        style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          onTap: id.isNotEmpty ? () => context.push('/teachers/$id') : null,
                        ),
                        // Speciality (normal black text)
                        DataCell(
                          SizedBox(
                            width: specialityW,
                            child: speciality != null
                                ? Center(
                                    child: Text(
                                      speciality,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF1E293B),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                                : const Center(child: Text('—', style: TextStyle(fontSize: 12, color: AppColors.textTertiary))),
                          ),
                        ),
                        // Niveaux
                        DataCell(
                          SizedBox(
                            width: niveauxW,
                            child: profNiveaux.isNotEmpty
                                ? Center(
                                    child: Wrap(
                                      spacing: 4,
                                      runSpacing: 2,
                                      children: profNiveaux.take(2).map((n) {
                                        final nColor = _specialityColor(n);
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: nColor.withOpacity(0.10),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(n, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: nColor), overflow: TextOverflow.ellipsis),
                                        );
                                      }).toList(),
                                    ),
                                  )
                                : const Center(child: Text('—', style: TextStyle(fontSize: 12, color: AppColors.textTertiary))),
                          ),
                        ),
                        // Classes
                        DataCell(
                          SizedBox(
                            width: classesW,
                            child: profClasses.isNotEmpty
                                ? Center(
                                    child: Wrap(
                                      spacing: 4,
                                      runSpacing: 2,
                                       children: profClasses.take(2).map((c) => Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.successSoft,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(c, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis),
                                      )).toList(),
                                    ),
                                  )
                                : const Center(child: Text('—', style: TextStyle(fontSize: 12, color: AppColors.textTertiary))),
                          ),
                        ),
                        // Phone (centered)
                        DataCell(
                          SizedBox(
                            width: phoneW,
                            child: Center(
                              child: Text(phone.isNotEmpty ? phone : '—', style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563))),
                            ),
                          ),
                        ),
                        // Date joined
                        DataCell(
                          SizedBox(
                            width: dateJoinedW,
                            child: Text(
                              createdAt != null ? DateFormat('d MMM yyyy', 'fr_FR').format(createdAt) : '—',
                              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                            ),
                          ),
                        ),
                        // Three-dots actions menu
                        DataCell(
                          SizedBox(
                            width: actionsW,
                            child: PopupMenuButton<String>(
                              icon: Icon(Icons.more_horiz, size: 18, color: AppColors.textTertiary),
                              tooltip: 'Actions',
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 8,
                              offset: const Offset(-160, 40),
                              onSelected: (action) => _handleProfessorAction(action, prof),
                              itemBuilder: (ctx) => [
                                _buildProfPopupItem('view', Icons.visibility_outlined, 'Voir profil', AppColors.success),
                                if (isActiveProf)
                                  _buildProfPopupItem('archive', Icons.archive_outlined, 'Archiver', AppColors.textSecondary)
                                else
                                  _buildProfPopupItem('unarchive', Icons.unarchive_outlined, 'Désarchiver', AppColors.primary),
                                const PopupMenuDivider(),
                                _buildProfPopupItem('delete', Icons.delete_outline_rounded, 'Supprimer', AppColors.error),
                              ],
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
    );
  }

  // ── Pagination ────────────────────────────────────────────────────────────

  Widget _buildPagination(int totalItems) {
    if (totalItems == 0) return const SizedBox.shrink();
    final totalPages = _itemsPerPage == -1 ? 1 : (totalItems / _itemsPerPage).ceil();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFB),
        border: Border(top: BorderSide(color: const Color(0xFFE5E7EB).withOpacity(0.5))),
      ),
      child: Row(
        children: [
          // Items per page
          const Text('Afficher par ', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
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
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF4B5563)),
                items: [10, 20, 50, 100].map((v) => DropdownMenuItem(
                  value: v,
                  child: Text('$v', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                )).toList(),
                onChanged: (v) => setState(() {
                  if (v != null) {
                    _itemsPerPage = v;
                    _currentPage = 1;
                  }
                }),
              ),
            ),
          ),
          const Spacer(),
          // Page info
          Text(
            'Page $_currentPage sur ${totalPages == 0 ? 1 : totalPages}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
          ),
          const SizedBox(width: 12),
          // Prev/Next
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(5)),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.chevron_left, size: 18, color: _currentPage > 1 ? const Color(0xFF4B5563) : const Color(0xFF9CA3AF)),
                  ),
                ),
                Container(width: 1, height: 24, color: const Color(0xFFE5E7EB)),
                InkWell(
                  onTap: _currentPage < totalPages ? () => setState(() => _currentPage++) : null,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(5)),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.chevron_right, size: 18, color: _currentPage < totalPages ? const Color(0xFF4B5563) : const Color(0xFF9CA3AF)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Add Professor Dialog ──────────────────────────────────────────────────

  void _showAddProfessorDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String? selectedSubjectId;
    final formKey = GlobalKey<FormState>();
    bool isCreating = false;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
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
        return Center(
          child: Material(
            color: Colors.transparent,
            child: StatefulBuilder(builder: (ctx, setDialogState) {
              return Container(
                width: 440,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 24)],
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Dialog header
                      Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.person_add_rounded, color: Color(0xFF6366F1), size: 18),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Nouveau professeur', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                                Text('Créer un nouveau professeur', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: const Icon(Icons.close_rounded, size: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Divider(height: 1, color: Color(0xFFF1F1F5)),
                      const SizedBox(height: 20),

                      // ── INFORMATIONS PERSONNELLES ──
                      Row(
                        children: [
                          Container(width: 3, height: 15, decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 8),
                          const Text('INFORMATIONS PERSONNELLES', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF4B5563), letterSpacing: 0.8)),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Full name
                      _dialogFieldLabel('NOM COMPLET'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: nameCtrl,
                        style: const TextStyle(fontSize: 13),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
                        decoration: _dialogInputDeco(hint: 'Ex: Ahmed Ben Salah', icon: Icons.person_outline_rounded),
                      ),
                      const SizedBox(height: 14),

                      // Email
                      _dialogFieldLabel('EMAIL'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: emailCtrl,
                        style: const TextStyle(fontSize: 13),
                        keyboardType: TextInputType.emailAddress,
                        inputFormatters: [
                          FilteringTextInputFormatter.deny(RegExp(r'\s')),
                        ],
                        validator: (v) {
                          final trimmed = v?.trim() ?? '';
                          if (trimmed.isEmpty) return 'Champ requis';
                          final emailRegex = RegExp(r'^[\w\.-]+@([\w-]+\.)+[\w-]{2,4}$');
                          if (!emailRegex.hasMatch(trimmed)) return 'Format email invalide';
                          return null;
                        },
                        decoration: _dialogInputDeco(hint: 'prof@ecole.tn', icon: Icons.email_outlined),
                      ),
                      const SizedBox(height: 14),

                      // Phone — Chiffres uniquement
                      _dialogFieldLabel('TÉLÉPHONE'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: phoneCtrl,
                        style: const TextStyle(fontSize: 13),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(12),
                        ],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null; // optional
                          final trimmed = v.trim();
                          if (trimmed.length < 8) return 'Numéro trop court (min 8 chiffres)';
                          return null;
                        },
                        decoration: _dialogInputDeco(hint: 'XX XXX XXX', icon: Icons.phone_outlined),
                      ),
                      const SizedBox(height: 14),
                      const SizedBox(height: 12),

                      // ── MATIÈRE ──
                      Row(
                        children: [
                          Container(width: 3, height: 15, decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 8),
                          const Text('MATIÈRE', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF4B5563), letterSpacing: 0.8)),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Subject
                      _dialogFieldLabel('MATIÈRE À ENSEIGNER'),
                      const SizedBox(height: 6),
                      Consumer(builder: (context, dialogRef, _) {
                        final subjectsAsync = dialogRef.watch(_subjectsProvider);
                        return DropdownButtonFormField<String>(
                          value: selectedSubjectId,
                          isExpanded: true,
                          hint: const Text('Sélectionner une matière', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
                          style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
                          borderRadius: BorderRadius.circular(12),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.menu_book_outlined, size: 16, color: Color(0xFF9CA3AF)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E4EA))),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
                            isDense: true,
                          ),
                          items: subjectsAsync.when(
                            loading: () => [],
                            error: (_, __) => [],
                            data: (subjects) => subjects.map((s) => DropdownMenuItem(
                              value: s['id'] as String,
                              child: Text(s['name'] ?? '', style: const TextStyle(fontSize: 13)),
                            )).toList(),
                          ),
                          onChanged: (v) => setDialogState(() => selectedSubjectId = v),
                        );
                      }),
                      const SizedBox(height: 24),

                      // Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          SizedBox(
                            height: 40,
                            child: TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
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
                            child: ElevatedButton(
                            onPressed: isCreating ? null : () async {
                            if (!formKey.currentState!.validate()) return;
                            setDialogState(() => isCreating = true);
                            try {
                              String? schoolId;
                              try {
                                final currentUserId = Supabase.instance.client.auth.currentUser?.id;
                                if (currentUserId != null) {
                                  final profile = await Supabase.instance.client
                                      .from('users')
                                      .select('school_id')
                                      .eq('id', currentUserId)
                                      .maybeSingle();
                                  schoolId = profile?['school_id'] as String?;
                                }
                              } catch (_) {}

                              final autoEmail = emailCtrl.text.trim();
                              final autoPass = 'Teacher@${DateTime.now().millisecondsSinceEpoch}';
                              final phoneVal = phoneCtrl.text.trim();
                              final phoneToStore = phoneVal.isEmpty ? null : phoneVal;

                              // Create teacher securely through Edge Function
                              final createResult = await UserManagementService.createUser(
                                email: autoEmail,
                                password: autoPass,
                                fullName: nameCtrl.text.trim(),
                                role: 'teacher',
                                phone: phoneToStore,
                                schoolId: schoolId,
                              );
                              final newTeacherId = (createResult['user'] as Map)['id'] as String;

                              if (selectedSubjectId != null && schoolId != null) {
                                await SupabaseConfig.adminClient.from('teacher_assignments').insert({
                                  'school_id': schoolId,
                                  'teacher_id': newTeacherId,
                                  'subject_id': selectedSubjectId,
                                  'is_active': true,
                                });
                              }

                              if (ctx.mounted) Navigator.of(ctx).pop();
                              ref.invalidate(professorsProvider);
                            } catch (e) {
                              debugPrint('Create professor error: $e');
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text(UserFriendlyError.format(e)), backgroundColor: AppColors.error),
                                );
                              }
                            }
                            if (ctx.mounted) setDialogState(() => isCreating = false);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6D4CF6),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFF6D4CF6).withOpacity(0.3),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 2,
                          ),
                          child: isCreating
                              ? const IosLoader.small(color: Colors.white)
                              : const Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.check_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text('Créer le professeur', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                ]),
                              ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  static Widget _dialogFieldLabel(String text) => Text(
    text,
    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9CA3AF), letterSpacing: 1),
  );

  static InputDecoration _dialogInputDeco({required String hint, required IconData icon}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
    prefixIcon: Icon(icon, size: 16, color: const Color(0xFF9CA3AF)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E4EA))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.error.withOpacity(0.6))),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.error)),
    isDense: true,
  );
}

// ── Phone Formatter ─────────────────────────────────────────────────────────

class _PhoneFormatter extends TextInputFormatter {
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
