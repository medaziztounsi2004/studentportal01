// ignore_for_file: avoid_web_libraries_in_flutter, unused_element, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:ui';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart' show AppColors;
import '../../../core/utils/error_messages.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/user_management_service.dart';
import '../../providers/users_provider.dart';
import '../../widgets/admin_sidebar.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/user_avatar.dart';
import '../users/user_profile_screen.dart';

/// Helper to get current admin's school_id
Future<String?> _getAdminSchoolId(SupabaseClient supabase) async {
  try {
    final user = supabase.auth.currentUser;
    if (user == null) return null;
    final profile = await supabase
        .from('users')
        .select('school_id')
        .eq('id', user.id)
        .maybeSingle();
    return profile?['school_id'] as String?;
  } catch (e) {
    debugPrint('Error getting admin school_id: $e');
    return null;
  }
}

/// Provider for pending password reset count (for notification badges)
final pendingPasswordResetCountProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final supabase = Supabase.instance.client;

  try {
    final schoolId = await _getAdminSchoolId(supabase);
    if (schoolId == null) return 0;

    // First try querying directly by school_id column
    try {
      final response = await supabase
          .from('password_reset_requests')
          .select('id')
          .eq('status', 'pending')
          .eq('school_id', schoolId);
      final list = response as List;
      debugPrint('Pending password reset count (by school_id): ${list.length}');
      return list.length;
    } catch (_) {
      // Fallback: match via user_id -> users.school_id
      final schoolUsers = await supabase
          .from('users')
          .select('id')
          .eq('school_id', schoolId);
      final userIds = (schoolUsers as List)
          .map((u) => u['id'] as String?)
          .whereType<String>()
          .toList();
      if (userIds.isEmpty) return 0;

      final response = await supabase
          .from('password_reset_requests')
          .select('id')
          .eq('status', 'pending')
          .inFilter('user_id', userIds);
      debugPrint('Pending password reset count (by user_id): ${(response as List).length}');
      return (response as List).length;
    }
  } catch (e) {
    debugPrint('Error fetching pending count: $e');
    return 0;
  }
});

/// Provider for password reset requests - strictly tenant-isolated
final passwordResetRequestsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final supabase = Supabase.instance.client;

      try {
        final schoolId = await _getAdminSchoolId(supabase);
        if (schoolId == null) return [];

        debugPrint('Fetching password reset requests for school $schoolId...');

        // First try querying directly by school_id column
        try {
          final response = await supabase
              .from('password_reset_requests')
              .select('*')
              .eq('school_id', schoolId)
              .order('requested_at', ascending: false);
          return (response as List).cast<Map<String, dynamic>>();
        } catch (_) {
          // Fallback: match via user_id -> users.school_id
          final schoolUsers = await supabase
              .from('users')
              .select('id')
              .eq('school_id', schoolId);
          final userIds = (schoolUsers as List)
              .map((u) => u['id'] as String?)
              .whereType<String>()
              .toList();
          if (userIds.isEmpty) return [];

          final response = await supabase
              .from('password_reset_requests')
              .select('*')
              .inFilter('user_id', userIds)
              .order('requested_at', ascending: false);
          return (response as List).cast<Map<String, dynamic>>();
        }
      } catch (e) {
        debugPrint('Error fetching password reset requests: $e');
        return [];
      }
    });

class PasswordResetRequestsScreen extends ConsumerStatefulWidget {
  const PasswordResetRequestsScreen({super.key});

  @override
  ConsumerState<PasswordResetRequestsScreen> createState() =>
      _PasswordResetRequestsScreenState();
}

class _PasswordResetRequestsScreenState
    extends ConsumerState<PasswordResetRequestsScreen> {
  int _selectedTabIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  // Pagination state (matching DocumentsScreen)
  int _currentPage = 1;
  int _rowsPerPage = 10;

  // Filter Drawer State
  bool _showFilterDrawer = false;
  String? _filterAccountLinked; // 'linked', 'unlinked'
  DateTime? _filterDateFrom;
  DateTime? _filterDateTo;

  // Multi-selection state
  final Set<String> _selectedIds = <String>{};

  // Tabs: 0: En attente, 1: Approuvées, 2: Rejetées, 3: Toutes
  final List<String> _filterKeys = ['pending', 'approved', 'rejected', 'all'];

  bool get _hasActiveFilters =>
      _filterAccountLinked != null ||
      _filterDateFrom != null ||
      _filterDateTo != null;

  void _resetFilters() {
    setState(() {
      _selectedTabIndex = 0;
      _filterAccountLinked = null;
      _filterDateFrom = null;
      _filterDateTo = null;
      _currentPage = 1;
    });
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 250), () {
        if (mounted) {
          setState(() {
            _searchQuery = _searchController.text.trim().toLowerCase();
            _currentPage = 1;
          });
        }
      });
    });

    // Force refresh on page load
    Future.microtask(() {
      ref.invalidate(passwordResetRequestsProvider);
      ref.invalidate(pendingPasswordResetCountProvider);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> _filterRequests(
    List<Map<String, dynamic>> requests,
    int tabIndex,
  ) {
    final statusFilter = _filterKeys[tabIndex];
    return requests.where((r) {
      final status = (r['status'] as String? ?? 'pending').toLowerCase();
      final fullName = (r['full_name'] as String? ?? '').toLowerCase();
      final email = (r['email'] as String? ?? '').toLowerCase();
      final userId = r['user_id'] as String?;

      // Tab status condition
      if (statusFilter != 'all' && status != statusFilter) {
        return false;
      }

      // Account linkage filter
      if (_filterAccountLinked == 'linked' && userId == null) {
        return false;
      }
      if (_filterAccountLinked == 'unlinked' && userId != null) {
        return false;
      }

      // Date range filter (requested_at)
      if (_filterDateFrom != null || _filterDateTo != null) {
        DateTime? requestedAt;
        try {
          if (r['requested_at'] != null) {
            requestedAt = DateTime.parse(r['requested_at']).toLocal();
          }
        } catch (_) {}
        if (requestedAt == null) return false;
        if (_filterDateFrom != null) {
          final startOfDay = DateTime(
            _filterDateFrom!.year,
            _filterDateFrom!.month,
            _filterDateFrom!.day,
          );
          if (requestedAt.isBefore(startOfDay)) return false;
        }
        if (_filterDateTo != null) {
          final endOfDay = DateTime(
            _filterDateTo!.year,
            _filterDateTo!.month,
            _filterDateTo!.day,
            23,
            59,
            59,
          );
          if (requestedAt.isAfter(endOfDay)) return false;
        }
      }

      // Search query condition
      if (_searchQuery.isNotEmpty) {
        final matchesName = fullName.contains(_searchQuery);
        final matchesEmail = email.contains(_searchQuery);
        if (!matchesName && !matchesEmail) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  void _exportCsv(List<Map<String, dynamic>> requests) {
    if (requests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune demande à exporter')),
      );
      return;
    }

    final rows = <List<dynamic>>[];
    rows.add([
      'ID',
      'Nom complet',
      'Email',
      'User ID',
      'Statut',
      'Date de demande',
      'Traité le',
      'Traité par',
    ]);

    final df = DateFormat("d MMM yyyy 'à' HH:mm", 'fr_FR');
    for (final r in requests) {
      DateTime? reqDate;
      DateTime? procDate;
      try {
        if (r['requested_at'] != null) reqDate = DateTime.parse(r['requested_at']);
        if (r['processed_at'] != null) procDate = DateTime.parse(r['processed_at']);
      } catch (_) {}

      rows.add([
        r['id'] ?? '',
        r['full_name'] ?? 'Inconnu',
        r['email'] ?? '',
        r['user_id'] ?? 'Non lié',
        _getStatusLabel(r['status'] as String? ?? ''),
        reqDate != null ? df.format(reqDate) : '',
        procDate != null ? df.format(procDate) : '',
        r['processed_by'] ?? '',
      ]);
    }

    final csvData = const ListToCsvConverter().convert(rows);
    final bytes = html.Blob([csvData], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(bytes);
    html.AnchorElement(href: url)
      ..setAttribute(
        'download',
        'demandes_mot_de_passe_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv',
      )
      ..click();
    html.Url.revokeObjectUrl(url);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${requests.length} demandes exportées en CSV'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(passwordResetRequestsProvider);
    final allRequests = requestsAsync.value ?? <Map<String, dynamic>>[];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          Row(
            children: [
              const AdminSidebar(currentRoute: '/password-resets'),
              Expanded(
                child: Column(
                  children: [
                    _buildHeader(requestsAsync),
                    _buildTabsBar(requestsAsync),
                    Expanded(
                      child: requestsAsync.when(
                        loading: () => const PasswordResetsSkeletonLoader(),
                        error: (e, stack) => Center(
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
                                  fallback:
                                      'Unable to load password reset requests right now. Please try again.',
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: () {
                                  ref.invalidate(passwordResetRequestsProvider);
                                  ref.invalidate(
                                      pendingPasswordResetCountProvider);
                                },
                                icon: const Icon(Icons.refresh_rounded, size: 16),
                                label: const Text('Réessayer'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6D4CF6),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        data: (requests) => _buildContent(requests),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Floating Selection Bar Overlay (Bottom Center, matching DocumentsScreen)
          if (_selectedIds.isNotEmpty)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: _buildFloatingSelectionBar(allRequests),
              ),
            ),

          // Right-side Filter Drawer Overlay
          if (_showFilterDrawer) _buildRightFilterDrawer(),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // HEADER BAR
  // ─────────────────────────────────────────────────────────────
  Widget _buildHeader(AsyncValue<List<Map<String, dynamic>>> requestsAsync) {
    final allRequests = requestsAsync.value ?? [];
    final total = allRequests.length;
    final pending = allRequests.where((r) => r['status'] == 'pending').length;
    final approved = allRequests.where((r) => r['status'] == 'approved').length;
    final rejected = allRequests.where((r) => r['status'] == 'rejected').length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE9EAF2))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Title + Subtitle
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Mot de passe',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$total demandes • $pending en attente • $approved approuvées • $rejected rejetées',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
          const Spacer(),

          // Exact Documents page Search Bar (no blue Web focus highlight)
          SizedBox(
            width: 320,
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Rechercher...',
                hintStyle: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 13,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
                suffixIcon: _searchController.text.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.slate50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Text(
                            '⌘K',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textTertiary,
                              fontFamily: 'monospace',
                            ),
                          ),
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: const Color(0xFF655DD5).withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Filter Button
          _buildHeaderIconButton(
            icon: Icons.filter_list_rounded,
            tooltip: 'Filtres',
            isActive: _showFilterDrawer || _hasActiveFilters,
            onPressed: () {
              setState(() => _showFilterDrawer = !_showFilterDrawer);
            },
          ),
          const SizedBox(width: 16),

          // Primary Direct Reset Button
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: () => _showDirectResetDialog(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text(
                'Réinitialiser un mot de passe',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6D4CF6),
                foregroundColor: Colors.white,
                elevation: 2,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
        backgroundColor:
            isActive ? const Color(0xFFF5F3FF) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isActive
                ? const Color(0xFF655DD5).withOpacity(0.2)
                : Colors.transparent,
          ),
        ),
      ),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SUBPAGE TABS (EXACT CLONE OF DOCUMENTS PAGE)
  // ─────────────────────────────────────────────────────────────
  Widget _buildTabsBar(AsyncValue<List<Map<String, dynamic>>> requestsAsync) {
    final tabs = [
      (
        icon: Icons.hourglass_empty_rounded,
        label: 'En attente',
      ),
      (
        icon: Icons.check_circle_outline_rounded,
        label: 'Approuvées',
      ),
      (
        icon: Icons.cancel_outlined,
        label: 'Rejetées',
      ),
      (
        icon: Icons.format_list_bulleted_rounded,
        label: 'Toutes',
      ),
    ];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.border.withOpacity(0.5)),
        ),
      ),
      padding: const EdgeInsets.only(left: 24, top: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(tabs.length, (index) {
            final t = tabs[index];
            return Padding(
              padding: const EdgeInsets.only(right: 24),
              child: _buildTab(
                icon: t.icon,
                label: t.label,
                isActive: _selectedTabIndex == index,
                onTap: () {
                  setState(() {
                    _selectedTabIndex = index;
                    _selectedIds.clear();
                    _currentPage = 1;
                  });
                },
                activeColor: const Color(0xFF655DD5),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildTab({
    required IconData icon,
    required String label,
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
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // FLOATING SELECTION BAR (EXACT CLONE OF DOCUMENTS PAGE)
  // ─────────────────────────────────────────────────────────────
  Widget _buildFloatingSelectionBar(List<Map<String, dynamic>> allRequests) {
    final count = _selectedIds.length;

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
                  Text(
                    count > 1 ? 'Sélectionnés' : 'Sélectionné',
                    style: const TextStyle(
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
              Icons.check_circle_outline_rounded,
              'Approuver',
              const Color(0xFF6EE7B7),
              _confirmBatchApprove,
            ),
            _buildSelectionAction(
              Icons.highlight_off_rounded,
              'Rejeter',
              const Color(0xFFFCD34D),
              _confirmBatchReject,
            ),
            _buildSelectionAction(
              Icons.delete_outline,
              'Supprimer',
              const Color(0xFFFCA5A5),
              _confirmBatchDelete,
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
                onPressed: () => setState(() => _selectedIds.clear()),
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

  // ─────────────────────────────────────────────────────────────
  // CONTENT & DATA TABLE
  // ─────────────────────────────────────────────────────────────
  Widget _buildContent(List<Map<String, dynamic>> requests) {
    final currentTabFiltered = _filterRequests(requests, _selectedTabIndex);

    // Pagination slice supporting _rowsPerPage == -1 ("All")
    final totalFiltered = currentTabFiltered.length;
    final totalPages =
        _rowsPerPage == -1 ? 1 : (totalFiltered / _rowsPerPage).ceil();
    if (_currentPage > totalPages && totalPages > 0) {
      _currentPage = totalPages;
    }
    final startIndex =
        _rowsPerPage == -1 ? 0 : (_currentPage - 1) * _rowsPerPage;
    final endIndex = _rowsPerPage == -1
        ? totalFiltered
        : (startIndex + _rowsPerPage).clamp(0, totalFiltered);
    final paginatedRequests = (startIndex < totalFiltered)
        ? currentTabFiltered.sublist(startIndex, endIndex)
        : <Map<String, dynamic>>[];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Active Filter Chips Bar (matching DocumentsScreen)
          if (_hasActiveFilters)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (_filterAccountLinked != null)
                      _buildActiveFilterChip(
                        label: _filterAccountLinked == 'linked'
                            ? 'Compte : Lié'
                            : 'Compte : Non lié',
                        onRemove: () => setState(() {
                          _filterAccountLinked = null;
                          _currentPage = 1;
                        }),
                      ),
                    if (_filterDateFrom != null || _filterDateTo != null)
                      _buildActiveFilterChip(
                        label:
                            'Date : ${_filterDateFrom != null ? DateFormat('d MMM yyyy', 'fr_FR').format(_filterDateFrom!) : '...'} → ${_filterDateTo != null ? DateFormat('d MMM yyyy', 'fr_FR').format(_filterDateTo!) : '...'}',
                        onRemove: () => setState(() {
                          _filterDateFrom = null;
                          _filterDateTo = null;
                          _currentPage = 1;
                        }),
                      ),
                    TextButton(
                      onPressed: _resetFilters,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textTertiary,
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: const Text('Effacer tout'),
                    ),
                  ],
                ),
              ),
            ),

          // Main Table Card
          Expanded(
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
                    _buildTableHeader(paginatedRequests),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    Expanded(
                      child: paginatedRequests.isEmpty
                          ? _buildEmptyState()
                          : ListView.separated(
                              itemCount: paginatedRequests.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(
                                      height: 1, color: Color(0xFFF1F5F9)),
                              itemBuilder: (context, index) {
                                final req = paginatedRequests[index];
                                final reqId = req['id'] as String;
                                final isSelected = _selectedIds.contains(reqId);
                                return _buildTableRow(req, isSelected);
                              },
                            ),
                    ),
                    _buildPaginationFooter(totalFiltered),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilterChip({
    required String label,
    required VoidCallback onRemove,
  }) {
    const chipColor = Color(0xFF655DD5);
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
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: chipColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 14, color: chipColor),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationFooter(int totalItems) {
    final totalPages =
        _rowsPerPage == -1 ? 1 : (totalItems / _rowsPerPage).ceil();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFB),
        border: Border(
          top: BorderSide(color: AppColors.border.withOpacity(0.3)),
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: Row(
        children: [
          // Items per page
          const Text(
            'Afficher par ',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _rowsPerPage,
                isDense: true,
                borderRadius: BorderRadius.circular(10),
                dropdownColor: Colors.white,
                elevation: 4,
                menuMaxHeight: 200,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 14,
                  color: AppColors.textTertiary,
                ),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
                items: const [10, 20, 50, -1]
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(
                          v == -1 ? 'All' : '$v',
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
                      _rowsPerPage = v;
                      _currentPage = 1;
                    });
                  }
                },
              ),
            ),
          ),
          const Spacer(),
          // Page info
          Text(
            'Page $_currentPage sur ${totalPages == 0 ? 1 : totalPages}',
            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
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
                  onTap: _currentPage > 1
                      ? () => setState(() => _currentPage--)
                      : null,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.chevron_left,
                      size: 18,
                      color: _currentPage > 1
                          ? AppColors.textSecondary
                          : AppColors.textTertiary,
                    ),
                  ),
                ),
                Container(width: 1, height: 24, color: AppColors.border),
                InkWell(
                  onTap: _currentPage < totalPages
                      ? () => setState(() => _currentPage++)
                      : null,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: _currentPage < totalPages
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
    );
  }

  // ─────────────────────────────────────────────────────────────
  // RIGHT FILTER DRAWER (EXACT CLONE OF DOCUMENTS PAGE)
  // ─────────────────────────────────────────────────────────────
  Widget _buildRightFilterDrawer() {
    return Positioned.fill(
      child: Stack(
        children: [
          // Blurred Backdrop
          GestureDetector(
            onTap: () => setState(() => _showFilterDrawer = false),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(color: Colors.black.withOpacity(0.2)),
            ),
          ),

          // Slide-over Drawer Panel
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 380,
              height: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 24,
                    offset: Offset(-4, 0),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: AppColors.border.withOpacity(0.5),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'Filtres',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () =>
                              setState(() => _showFilterDrawer = false),
                          color: AppColors.textTertiary,
                        ),
                      ],
                    ),
                  ),

                  // Filter Fields
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Statut (synced with subtabs)
                          _buildFilterLabel('STATUT'),
                          const SizedBox(height: 8),
                          _buildFilterDropdown<int>(
                            value: _selectedTabIndex,
                            hint: 'Tous les statuts',
                            items: const [
                              DropdownMenuItem(
                                value: 3,
                                child: Text('Tous les statuts'),
                              ),
                              DropdownMenuItem(
                                value: 0,
                                child: Text('En attente'),
                              ),
                              DropdownMenuItem(
                                value: 1,
                                child: Text('Approuvées'),
                              ),
                              DropdownMenuItem(
                                value: 2,
                                child: Text('Rejetées'),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setState(() {
                                  _selectedTabIndex = v;
                                  _selectedIds.clear();
                                  _currentPage = 1;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 20),

                          // Liaison compte
                          _buildFilterLabel('COMPTE UTILISATEUR'),
                          const SizedBox(height: 8),
                          _buildFilterDropdown<String?>(
                            value: _filterAccountLinked,
                            hint: 'Tous les comptes',
                            items: const [
                              DropdownMenuItem(
                                value: null,
                                child: Text('Tous les comptes'),
                              ),
                              DropdownMenuItem(
                                value: 'linked',
                                child: Text('Compte lié'),
                              ),
                              DropdownMenuItem(
                                value: 'unlinked',
                                child: Text('Non lié'),
                              ),
                            ],
                            onChanged: (v) => setState(() {
                              _filterAccountLinked = v;
                              _currentPage = 1;
                            }),
                          ),
                          const SizedBox(height: 20),

                          // Période (Date de demande)
                          _buildFilterLabel('PÉRIODE (DATE)'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildDatePickerField(
                                  value: _filterDateFrom,
                                  hint: 'Du',
                                  onTap: () async {
                                    final date = await showDatePicker(
                                      context: context,
                                      initialDate:
                                          _filterDateFrom ?? DateTime.now(),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now(),
                                    );
                                    if (date != null) {
                                      setState(() {
                                        _filterDateFrom = date;
                                        _currentPage = 1;
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildDatePickerField(
                                  value: _filterDateTo,
                                  hint: 'Au',
                                  onTap: () async {
                                    final date = await showDatePicker(
                                      context: context,
                                      initialDate:
                                          _filterDateTo ?? DateTime.now(),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now(),
                                    );
                                    if (date != null) {
                                      setState(() {
                                        _filterDateTo = date;
                                        _currentPage = 1;
                                      });
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

                  // Bottom Buttons Container
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
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
                                side:
                                    const BorderSide(color: Color(0xFFD1D5DB)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
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
                              color: const Color(0xFF6D4CF6),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      const Color(0xFF6D4CF6).withOpacity(0.3),
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
          ),
        ],
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
          hint: Text(
            hint,
            style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
          ),
          isExpanded: true,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          items: items,
          onChanged: onChanged,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          borderRadius: BorderRadius.circular(8),
          dropdownColor: Colors.white,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: AppColors.textTertiary,
          ),
        ),
      ),
    );
  }

  Widget _buildDatePickerField({
    DateTime? value,
    required String hint,
    required VoidCallback onTap,
  }) {
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
                value != null
                    ? DateFormat('d MMM yyyy', 'fr_FR').format(value)
                    : hint,
                style: TextStyle(
                  fontSize: 13,
                  color: value != null
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                ),
              ),
            ),
            const Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Icon(
              Icons.lock_open_rounded,
              size: 28,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Aucune demande trouvée',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _searchQuery.isNotEmpty
                ? 'Aucun résultat correspondant à votre recherche'
                : 'Aucune demande dans cette catégorie pour le moment',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(List<Map<String, dynamic>> items) {
    final allSelected =
        items.isNotEmpty && items.every((r) => _selectedIds.contains(r['id']));

    return Container(
      height: 44,
      color: const Color(0xFFF9FAFB),
      padding: const EdgeInsets.fromLTRB(0, 0, 20, 0),
      child: Row(
        children: [
          // Master Checkbox (EXACT CLONE OF DOCUMENTS/USER PAGE)
          SizedBox(
            width: 44,
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: Checkbox(
                  value: allSelected && items.isNotEmpty,
                  tristate: false,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(3),
                  ),
                  side: const BorderSide(color: AppColors.slate300, width: 1.5),
                  activeColor: const Color(0xFF655DD5),
                  onChanged: (val) {
                    setState(() {
                      if (allSelected) {
                        for (final r in items) {
                          _selectedIds.remove(r['id']);
                        }
                      } else {
                        _selectedIds
                            .addAll(items.map((r) => r['id'] as String));
                      }
                    });
                  },
                ),
              ),
            ),
          ),

          // Utilisateur Header
          const Expanded(
            flex: 4,
            child: Text(
              'UTILISATEUR',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
                letterSpacing: 0.5,
              ),
            ),
          ),

          // Date de demande Header
          const Expanded(
            flex: 2,
            child: Text(
              'DATE DE DEMANDE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
                letterSpacing: 0.5,
              ),
            ),
          ),

          // Traité le Header
          const Expanded(
            flex: 2,
            child: Text(
              'TRAITÉ LE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
                letterSpacing: 0.5,
              ),
            ),
          ),

          // Statut Header
          const Expanded(
            flex: 2,
            child: Text(
              'STATUT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
                letterSpacing: 0.5,
              ),
            ),
          ),

          // Actions Header
          const SizedBox(
            width: 48,
            child: Text(
              'ACTIONS',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(Map<String, dynamic> request, bool isSelected) {
    final requestId = request['id'] as String;
    final fullName = request['full_name'] as String? ?? 'Inconnu';
    final email = request['email'] as String? ?? '';
    final status = (request['status'] as String? ?? 'pending').toLowerCase();
    final userId = request['user_id'] as String?;
    final usersState = ref.watch(usersProvider).asData?.value;
    final matchedUser = usersState?.users
        .where((u) => (userId != null && u.id == userId) || (email.isNotEmpty && u.email.toLowerCase() == email.toLowerCase()))
        .firstOrNull;
    final photoUrl = matchedUser?.photoUrl ?? request['photo_url'] as String?;

    DateTime? requestedAt;
    DateTime? processedAt;
    try {
      if (request['requested_at'] != null) {
        requestedAt = DateTime.parse(request['requested_at']);
      }
      if (request['processed_at'] != null) {
        processedAt = DateTime.parse(request['processed_at']);
      }
    } catch (_) {}

    final df = DateFormat("d MMM yyyy 'à' HH:mm", 'fr_FR');

    return InkWell(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedIds.remove(requestId);
          } else {
            _selectedIds.add(requestId);
          }
        });
      },
      hoverColor: const Color(0xFFF8FAFC),
      child: Container(
        height: 64,
        padding: const EdgeInsets.fromLTRB(0, 0, 20, 0),
        color: isSelected
            ? const Color(0xFF655DD5).withOpacity(0.04)
            : Colors.transparent,
        child: Row(
          children: [
            // Checkbox
            SizedBox(
              width: 44,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: Checkbox(
                    value: isSelected,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(3),
                    ),
                    side: const BorderSide(color: AppColors.slate300, width: 1.5),
                    activeColor: const Color(0xFF655DD5),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedIds.add(requestId);
                        } else {
                          _selectedIds.remove(requestId);
                        }
                      });
                    },
                  ),
                ),
              ),
            ),

            // Utilisateur
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  UserAvatar(
                    name: fullName,
                    photoUrl: photoUrl,
                    radius: 18,
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
                                fullName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (userId != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Lié',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF059669),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          email,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
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

            // Date de demande
            Expanded(
              flex: 2,
              child: Text(
                requestedAt != null ? df.format(requestedAt) : '-',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            // Traité le
            Expanded(
              flex: 2,
              child: Text(
                processedAt != null ? df.format(processedAt) : '-',
                style: TextStyle(
                  fontSize: 12,
                  color: processedAt != null ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                  fontWeight: processedAt != null ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),

            // Statut Badge
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildStatusBadge(status),
              ),
            ),

            // Actions Menu
            SizedBox(
              width: 48,
              child: Center(
                child: PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_horiz,
                    size: 18,
                    color: Color(0xFF94A3B8),
                  ),
                  tooltip: 'Actions',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 8,
                  offset: const Offset(-140, 36),
                  onSelected: (action) => _handleRowAction(action, request),
                  itemBuilder: (ctx) => [
                    if (status == 'pending') ...[
                      _buildPopupItem(
                        'approve',
                        Icons.check_circle_outline_rounded,
                        'Approuver la demande',
                        const Color(0xFF059669),
                      ),
                      _buildPopupItem(
                        'reject',
                        Icons.highlight_off_rounded,
                        'Rejeter la demande',
                        const Color(0xFFDC2626),
                      ),
                      const PopupMenuDivider(),
                    ],
                    if (userId != null)
                      _buildPopupItem(
                        'profile',
                        Icons.person_outline_rounded,
                        'Voir le profil',
                        const Color(0xFF6D4CF6),
                      ),
                    _buildPopupItem(
                      'copy_email',
                      Icons.content_copy_rounded,
                      'Copier l\'email',
                      const Color(0xFF64748B),
                    ),
                    const PopupMenuDivider(),
                    _buildPopupItem(
                      'delete',
                      Icons.delete_outline_rounded,
                      'Supprimer',
                      AppColors.error,
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

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    IconData icon;
    String label;

    switch (status) {
      case 'approved':
        bg = const Color(0xFFECFDF5);
        fg = const Color(0xFF059669);
        icon = Icons.check_circle_rounded;
        label = 'Approuvée';
        break;
      case 'rejected':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFDC2626);
        icon = Icons.cancel_rounded;
        label = 'Rejetée';
        break;
      default:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFD97706);
        icon = Icons.hourglass_empty_rounded;
        label = 'En attente';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildPopupItem(
    String value,
    IconData icon,
    String label,
    Color color,
  ) {
    return PopupMenuItem(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: value == 'delete' ? AppColors.error : const Color(0xFF1E293B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _handleRowAction(String action, Map<String, dynamic> request) {
    switch (action) {
      case 'approve':
        _showApproveDialog(request);
        break;
      case 'reject':
        _showRejectDialog(request);
        break;
      case 'profile':
        final userId = request['user_id'] as String?;
        if (userId != null) {
          context.push('/users/$userId');
        }
        break;
      case 'copy_email':
        final email = request['email'] as String? ?? '';
        Clipboard.setData(ClipboardData(text: email));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email copié dans le presse-papiers')),
        );
        break;
      case 'delete':
        _showDeleteDialog(request);
        break;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'Approuvée';
      case 'rejected':
        return 'Rejetée';
      default:
        return 'En attente';
    }
  }

  // ─────────────────────────────────────────────────────────────
  // MODALS & DIALOGS (WITH BACKGROUND BLUR)
  // ─────────────────────────────────────────────────────────────

  /// Approve Dialog: Generates password, displays copyable code, and updates Supabase
  Future<void> _showApproveDialog(Map<String, dynamic> request) async {
    final requestId = request['id'] as String;
    final fullName = request['full_name'] as String? ?? 'l\'utilisateur';
    final email = request['email'] as String? ?? '';
    final userId = request['user_id'] as String?;

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Impossible: cette demande n\'est pas rattachée à un utilisateur existant'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final newPassword = ref.read(usersProvider.notifier).generatePassword();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF059669),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Approuver la demande',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Un nouveau mot de passe va être généré pour $fullName ($email).',
                style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 16),

              // Password container
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.key_rounded, size: 18, color: Color(0xFF6D4CF6)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        newPassword,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      tooltip: 'Copier',
                      color: const Color(0xFF64748B),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: newPassword));
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Mot de passe copié !'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Warning box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7).withOpacity(0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFD97706),
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Copiez ce mot de passe afin de le communiquer directement à l\'utilisateur.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                      ),
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
                SizedBox(
                  height: 40,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF64748B),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Confirmer et réinitialiser',
                      style: TextStyle(fontWeight: FontWeight.w600),
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

    try {
      final supabase = Supabase.instance.client;
      await UserManagementService.resetPassword(userId, newPassword: newPassword);

      await supabase
          .from('password_reset_requests')
          .update({
            'status': 'approved',
            'processed_at': DateTime.now().toIso8601String(),
            'processed_by': supabase.auth.currentUser?.id,
            'new_password_sent': true,
          })
          .eq('id', requestId);

      ref.invalidate(passwordResetRequestsProvider);
      ref.invalidate(pendingPasswordResetCountProvider);
      ref.invalidate(usersProvider);
      ref.invalidate(userProfileDataProvider(userId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mot de passe réinitialisé et demande approuvée'),
            backgroundColor: Color(0xFF059669),
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

  /// Reject Dialog
  Future<void> _showRejectDialog(Map<String, dynamic> request) async {
    final requestId = request['id'] as String;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.highlight_off_rounded,
                  color: Color(0xFFDC2626),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Rejeter la demande',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ),
          content: const Text(
            'Voulez-vous vraiment rejeter cette demande de réinitialisation de mot de passe ?',
            style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
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
                      foregroundColor: const Color(0xFF64748B),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Rejeter', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('password_reset_requests')
          .update({
            'status': 'rejected',
            'processed_at': DateTime.now().toIso8601String(),
            'processed_by': supabase.auth.currentUser?.id,
          })
          .eq('id', requestId);

      ref.invalidate(passwordResetRequestsProvider);
      ref.invalidate(pendingPasswordResetCountProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Demande rejetée'),
            backgroundColor: Color(0xFFD97706),
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

  /// Delete Dialog
  Future<void> _showDeleteDialog(Map<String, dynamic> request) async {
    final requestId = request['id'] as String;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.error,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Supprimer la demande ?',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ),
          content: const Text(
            'Cette demande sera définitivement retirée de l\'historique.',
            style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
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
                      foregroundColor: const Color(0xFF64748B),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Supprimer', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final supabase = Supabase.instance.client;
      await supabase.from('password_reset_requests').delete().eq('id', requestId);

      ref.invalidate(passwordResetRequestsProvider);
      ref.invalidate(pendingPasswordResetCountProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Demande supprimée de l\'historique'),
            backgroundColor: Color(0xFF6D4CF6),
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

  /// Batch Approve
  Future<void> _confirmBatchApprove() async {
    final pendingSelected = _selectedIds.toList();
    if (pendingSelected.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF059669),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                pendingSelected.length > 1
                    ? 'Approuver les demandes'
                    : 'Approuver la demande',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ),
          content: Text(
            pendingSelected.length > 1
                ? 'Voulez-vous marquer comme approuvées les ${pendingSelected.length} demandes sélectionnées ?'
                : 'Voulez-vous marquer comme approuvée cette demande sélectionnée ?',
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
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
                      foregroundColor: const Color(0xFF64748B),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Approuver',
                      style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
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

    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('password_reset_requests')
          .update({
            'status': 'approved',
            'processed_at': DateTime.now().toIso8601String(),
            'processed_by': supabase.auth.currentUser?.id,
          })
          .inFilter('id', pendingSelected);

      setState(() => _selectedIds.clear());
      ref.invalidate(passwordResetRequestsProvider);
      ref.invalidate(pendingPasswordResetCountProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${pendingSelected.length} demandes approuvées'),
            backgroundColor: const Color(0xFF059669),
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

  /// Batch Reject
  Future<void> _confirmBatchReject() async {
    final selected = _selectedIds.toList();
    if (selected.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.highlight_off_rounded,
                  color: Color(0xFFDC2626),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                selected.length > 1
                    ? 'Rejeter les demandes'
                    : 'Rejeter la demande',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ),
          content: Text(
            selected.length > 1
                ? 'Voulez-vous rejeter les ${selected.length} demandes sélectionnées ?'
                : 'Voulez-vous rejeter cette demande sélectionnée ?',
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
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
                      foregroundColor: const Color(0xFF64748B),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Rejeter',
                      style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
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

    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('password_reset_requests')
          .update({
            'status': 'rejected',
            'processed_at': DateTime.now().toIso8601String(),
            'processed_by': supabase.auth.currentUser?.id,
          })
          .inFilter('id', selected);

      setState(() => _selectedIds.clear());
      ref.invalidate(passwordResetRequestsProvider);
      ref.invalidate(pendingPasswordResetCountProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${selected.length} demandes rejetées'),
            backgroundColor: const Color(0xFFD97706),
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

  /// Batch Delete
  Future<void> _confirmBatchDelete() async {
    final selected = _selectedIds.toList();
    if (selected.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.error,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                selected.length > 1
                    ? 'Supprimer les demandes'
                    : 'Supprimer la demande',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ),
          content: Text(
            selected.length > 1
                ? 'Voulez-vous supprimer définitivement les ${selected.length} demandes sélectionnées ? Cette action est irréversible.'
                : 'Cette demande sera définitivement retirée de l\'historique.',
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
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
                      foregroundColor: const Color(0xFF64748B),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Supprimer',
                      style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
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

    try {
      final supabase = Supabase.instance.client;
      await supabase.from('password_reset_requests').delete().inFilter('id', selected);

      setState(() => _selectedIds.clear());
      ref.invalidate(passwordResetRequestsProvider);
      ref.invalidate(pendingPasswordResetCountProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${selected.length} demandes supprimées'),
            backgroundColor: const Color(0xFF6D4CF6),
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

  /// Direct Reset Password Dialog (Search user, generate password, copy)
  void _showDirectResetDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: const _DirectResetPasswordModal(),
      ),
    );
  }
}

/// Standalone modal for Direct Reset Password
class _DirectResetPasswordModal extends ConsumerStatefulWidget {
  const _DirectResetPasswordModal();

  @override
  ConsumerState<_DirectResetPasswordModal> createState() =>
      _DirectResetPasswordModalState();
}

class _DirectResetPasswordModalState
    extends ConsumerState<_DirectResetPasswordModal> {
  final TextEditingController _userSearchCtrl = TextEditingController();
  final TextEditingController _pwdCtrl = TextEditingController();
  UserModel? _selectedUser;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _regeneratePassword();
  }

  @override
  void dispose() {
    _userSearchCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  void _regeneratePassword() {
    final generated = ref.read(usersProvider.notifier).generatePassword();
    setState(() {
      _pwdCtrl.text = generated;
    });
  }

  Future<void> _submit() async {
    if (_selectedUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner un utilisateur')),
      );
      return;
    }

    if (_pwdCtrl.text.trim().length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le mot de passe doit comporter au moins 6 caractères')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = _selectedUser!;
      final newPwd = _pwdCtrl.text.trim();

      await UserManagementService.resetPassword(user.id, newPassword: newPwd);

      ref.invalidate(passwordResetRequestsProvider);
      ref.invalidate(pendingPasswordResetCountProvider);
      ref.invalidate(usersProvider);
      ref.invalidate(userProfileDataProvider(user.id));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mot de passe de ${user.fullName} réinitialisé avec succès'),
            backgroundColor: const Color(0xFF059669),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFriendlyError.format(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersState = ref.watch(usersProvider);
    final allUsers = usersState.value?.users ?? [];

    final searchLower = _userSearchCtrl.text.trim().toLowerCase();
    final matchingUsers = searchLower.isEmpty
        ? allUsers.take(10).toList()
        : allUsers.where((u) {
            final name = u.fullName.toLowerCase();
            final email = u.email.toLowerCase();
            final code = (u.studentCode ?? '').toLowerCase();
            return name.contains(searchLower) ||
                email.contains(searchLower) ||
                code.contains(searchLower);
          }).take(10).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6D4CF6).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.lock_reset_rounded,
                      color: Color(0xFF6D4CF6),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Réinitialiser un mot de passe',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        'Attribuer un nouveau mot de passe à un compte',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Search User Field
              const Text(
                'UTILISATEUR',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 8),

              if (_selectedUser != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF6D4CF6)),
                  ),
                  child: Row(
                    children: [
                      UserAvatar(
                        name: _selectedUser!.fullName,
                        photoUrl: _selectedUser!.photoUrl,
                        radius: 16,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedUser!.fullName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            Text(
                              _selectedUser!.email,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() => _selectedUser = null),
                        tooltip: 'Changer d\'utilisateur',
                      ),
                    ],
                  ),
                )
              else ...[
                TextField(
                  controller: _userSearchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Rechercher par nom, email ou matricule...',
                    hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // User results list
                Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: matchingUsers.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: Center(
                            child: Text(
                              'Aucun utilisateur correspondant',
                              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: matchingUsers.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          itemBuilder: (ctx, idx) {
                            final u = matchingUsers[idx];
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedUser = u;
                                  _userSearchCtrl.clear();
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  children: [
                                    UserAvatar(
                                      name: u.fullName,
                                      photoUrl: u.photoUrl,
                                      radius: 14,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            u.fullName,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            u.email,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
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
              ],

              const SizedBox(height: 18),

              // Password field
              const Text(
                'NOUVEAU MOT DE PASSE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pwdCtrl,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  suffixIcon: IconButton(
                    icon: const Icon(
                      Icons.refresh_rounded,
                      size: 18,
                      color: Color(0xFF64748B),
                    ),
                    tooltip: 'Générer un autre',
                    onPressed: _regeneratePassword,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: Color(0xFF6D4CF6), width: 1.5),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Action buttons (40px)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    height: 40,
                    child: TextButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF64748B),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _submit,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 16),
                      label: Text(
                        _isLoading ? 'Mise à jour...' : 'Réinitialiser',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6D4CF6),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
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
}
