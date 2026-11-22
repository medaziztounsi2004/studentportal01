import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../providers/payments_provider.dart';
import '../../widgets/admin_sidebar.dart';
import '../../widgets/admin_sort_dropdown.dart';
import '../../widgets/ios_loader.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/user_avatar.dart';
import '../users/user_profile_screen.dart';

// Maps UI plan-type keys to/from the Postgres enum values.
// UI: 'semester' = Trimestriel (3 payments) -> DB 'trimester'
// UI: 'semesterly' = Semestriel (2 payments) -> DB 'semesterly'
String _mapUiPlanTypeToDb(String uiType) {
  switch (uiType) {
    case 'semester':
      return 'trimester';
    case 'semesterly':
      return 'semesterly';
    case 'annual':
      return 'annual';
    case 'monthly':
    default:
      return 'monthly';
  }
}

String _mapDbPlanTypeToUi(String dbType) {
  switch (dbType) {
    case 'trimester':
      return 'semester';
    case 'semesterly':
      return 'semesterly';
    case 'annual':
      return 'annual';
    case 'monthly':
    default:
      return 'monthly';
  }
}

/// Modern Payment Management Screen
/// Full control over student payments with comprehensive filtering and actions
class PaymentsScreen extends ConsumerStatefulWidget {
  final String? initialStudentId;

  const PaymentsScreen({super.key, this.initialStudentId});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  final _searchController = TextEditingController();
  bool _showFilters = false;
  String _sortKey = 'student_asc';
  Set<String> _selectedPayments = {};

  // Hierarchical filter state
  List<Map<String, dynamic>> _allNiveaux = [];
  List<Map<String, dynamic>> _allSections = [];
  List<Map<String, dynamic>> _allClasses = [];
  List<Map<String, dynamic>> _allStudents = [];
  String? _selectedNiveauId;
  String? _selectedSectionId;
  String? _selectedClassId;
  bool _isLoadingHierarchy = true;
  // Classes layout state
  String? _layoutSelectedNiveauId;
  String? _layoutSelectedSectionId;
  String? _layoutSelectedClassId;
  String? _layoutSelectedClassName;
  StudentPaymentSummary? _selectedDetailStudentSummary;
  final _niveauSearchController = TextEditingController();
  String _niveauSearchQuery = '';

  int _getNiveauSortOrder(String? str) {
    if (str == null || str.trim().isEmpty) return 999;
    final s = str.toLowerCase().trim();

    if (s.contains('7') || s.startsWith('7b') || s.contains('sept')) return 10;
    if (s.contains('8') || s.startsWith('8b') || s.contains('huit')) return 20;
    if (s.contains('9') || s.startsWith('9b') || s.contains('neuf')) return 30;
    if (s.contains('1') || s.startsWith('1s') || s.contains('prem')) return 40;
    if (s.contains('2') || s.startsWith('2s') || s.contains('deux')) return 50;
    if (s.contains('3') || s.startsWith('3s') || s.contains('trois')) return 60;
    if (s.contains('4') || s.startsWith('4s') || s.contains('bac') || s.contains('quatre')) return 70;

    return 999;
  }

  // Class students pagination
  int _classStudentsPage = 0;
  int _classStudentsPerPage = 10;

  @override
  void initState() {
    super.initState();
    _loadHierarchyData();
  }

  Future<void> _loadHierarchyData() async {
    try {
      final supabase = Supabase.instance.client;

      // Load niveaux
      final niveauxResp = await supabase
          .from('niveaux')
          .select('id, name, cycle, display_order')
          .order('display_order');

      // Load sections (filières) - need to get from niveau_sections to know which sections belong to which niveau
      final sectionsResp = await supabase
          .from('sections')
          .select('id, name')
          .order('name');

      // Load niveau_sections to map sections to niveaux
      final niveauSectionsResp = await supabase
          .from('niveau_sections')
          .select('niveau_id, section_id')
          .eq('is_active', true);

      // Load all classes with niveau and section info
      final classesResp = await supabase
          .from('classes')
          .select('id, name, niveau_id, section_id')
          .eq('is_active', true)
          .order('name');

      // Load all students with their enrollments
      final studentsResp = await supabase
          .from('users')
          .select('id, full_name, email, phone, photo_url')
          .eq('role', 'student')
          .eq('is_active', true)
          .order('full_name');

      // Load enrollments separately
      final enrollmentsResp = await supabase
          .from('enrollments')
          .select(
            'id, user_id, class_id, classes(id, name, niveau_id, section_id)',
          )
          .eq('is_active', true);

      // Merge enrollments into students
      final studentsWithEnrollments = <Map<String, dynamic>>[];
      for (final student in studentsResp) {
        final studentEnrollments = (enrollmentsResp as List)
            .where((e) => e['user_id'] == student['id'])
            .toList();
        studentsWithEnrollments.add({
          ...student,
          'enrollments': studentEnrollments,
        });
      }

      // Build sections with niveau_id mapping
      final sectionsWithNiveau = <Map<String, dynamic>>[];
      for (final section in sectionsResp) {
        final niveauMapping = (niveauSectionsResp as List)
            .where((ns) => ns['section_id'] == section['id'])
            .toList();
        for (final mapping in niveauMapping) {
          sectionsWithNiveau.add({
            ...section,
            'niveau_id': mapping['niveau_id'],
          });
        }
      }

      final sortedNiveaux = List<Map<String, dynamic>>.from(niveauxResp);
      sortedNiveaux.sort((a, b) {
        final orderA = _getNiveauSortOrder(a['name']?.toString());
        final orderB = _getNiveauSortOrder(b['name']?.toString());
        if (orderA != orderB) return orderA.compareTo(orderB);
        return (a['display_order'] as num? ?? 999).compareTo(b['display_order'] as num? ?? 999);
      });

      StudentPaymentSummary? initialSummary;
      String? initialNiveauId;
      String? initialClassId;
      String? initialClassName;

      if (widget.initialStudentId != null) {
        final target = studentsWithEnrollments.where((s) => s['id'] == widget.initialStudentId).firstOrNull;
        if (target != null) {
          final enrollments = target['enrollments'] as List?;
          final firstClass = enrollments?.isNotEmpty == true ? enrollments!.first['classes'] : null;
          initialClassName = firstClass?['name'] as String?;
          initialClassId = firstClass?['id'] as String?;
          initialNiveauId = firstClass?['niveau_id'] as String?;

          final summaries = ref.read(paymentsProvider).asData?.value.studentSummaries;
          final existing = summaries?.where((s) => s.studentId == widget.initialStudentId).firstOrNull;

          initialSummary = existing ?? StudentPaymentSummary(
            studentId: widget.initialStudentId!,
            studentName: target['full_name'] as String? ?? 'Étudiant',
            studentEmail: target['email'] as String?,
            studentPhotoUrl: target['photo_url'] as String? ?? target['photo'] as String? ?? target['avatar_url'] as String?,
            classId: initialClassId,
            className: initialClassName,
            totalAmount: 0,
            paidAmount: 0,
            pendingAmount: 0,
            totalPayments: 0,
            paidPayments: 0,
            overduePayments: 0,
            plans: [],
          );
        } else {
          try {
            final userResp = await supabase
                .from('users')
                .select('id, full_name, email, photo_url, photo, avatar_url, enrollments(classes(id, name, niveau_id))')
                .eq('id', widget.initialStudentId!)
                .maybeSingle();
            if (userResp != null) {
              final enrollments = userResp['enrollments'] as List?;
              final firstClass = enrollments?.isNotEmpty == true ? enrollments!.first['classes'] : null;
              initialClassName = firstClass?['name'] as String?;
              initialClassId = firstClass?['id'] as String?;
              initialNiveauId = firstClass?['niveau_id'] as String?;

              initialSummary = StudentPaymentSummary(
                studentId: widget.initialStudentId!,
                studentName: userResp['full_name'] as String? ?? 'Étudiant',
                studentEmail: userResp['email'] as String?,
                studentPhotoUrl: userResp['photo_url'] as String? ?? userResp['photo'] as String? ?? userResp['avatar_url'] as String?,
                classId: initialClassId,
                className: initialClassName,
                totalAmount: 0,
                paidAmount: 0,
                pendingAmount: 0,
                totalPayments: 0,
                paidPayments: 0,
                overduePayments: 0,
                plans: [],
              );
            }
          } catch (_) {}
        }
      }

      setState(() {
        _allNiveaux = sortedNiveaux;
        _allSections = sectionsWithNiveau;
        _allClasses = List<Map<String, dynamic>>.from(classesResp);
        _allStudents = studentsWithEnrollments;
        _isLoadingHierarchy = false;
        if (initialSummary != null) {
          _selectedDetailStudentSummary = initialSummary;
          if (initialNiveauId != null) _layoutSelectedNiveauId = initialNiveauId;
          if (initialClassId != null) {
            _layoutSelectedClassId = initialClassId;
            _layoutSelectedClassName = initialClassName;
          }
        }
      });
    } catch (e) {
      debugPrint('Error loading hierarchy: $e');
      setState(() => _isLoadingHierarchy = false);
    }
  }

  // Get sections for selected niveau
  List<Map<String, dynamic>> get _sectionsForNiveau {
    if (_selectedNiveauId == null) return [];
    return _allSections
        .where((s) => s['niveau_id'] == _selectedNiveauId)
        .toList();
  }

  // Check if selected niveau has sections
  bool get _niveauHasSections => _sectionsForNiveau.isNotEmpty;

  // Get filtered classes based on hierarchy selection
  List<Map<String, dynamic>> get _filteredClasses {
    if (_selectedNiveauId == null) return _allClasses;

    return _allClasses.where((c) {
      if (c['niveau_id'] != _selectedNiveauId) return false;
      if (_niveauHasSections && _selectedSectionId != null) {
        return c['section_id'] == _selectedSectionId;
      }
      return true;
    }).toList();
  }

  // Get filtered students based on hierarchy and search
  List<Map<String, dynamic>> _getFilteredStudents(String query) {
    return _allStudents.where((s) {
      // Search filter
      if (query.isNotEmpty) {
        final searchLower = query.toLowerCase();
        final name = (s['full_name'] ?? '').toString().toLowerCase();
        final email = (s['email'] ?? '').toString().toLowerCase();
        final phone = (s['phone'] ?? '').toString().toLowerCase();

        if (!name.contains(searchLower) &&
            !email.contains(searchLower) &&
            !phone.contains(searchLower)) {
          return false;
        }
      }

      // Get enrollment info
      final enrollments = s['enrollments'] as List?;

      // If hierarchy filter is applied, filter by class
      if (_selectedClassId != null || _selectedNiveauId != null) {
        if (enrollments == null || enrollments.isEmpty) return false;

        final enrollment = enrollments.first as Map<String, dynamic>;
        final classData = enrollment['classes'] as Map<String, dynamic>?;

        if (_selectedClassId != null) {
          return enrollment['class_id'] == _selectedClassId ||
              classData?['id'] == _selectedClassId;
        }

        if (_selectedNiveauId != null) {
          if (classData?['niveau_id'] != _selectedNiveauId) return false;
          if (_niveauHasSections && _selectedSectionId != null) {
            return classData?['section_id'] == _selectedSectionId;
          }
        }
      }

      return true;
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _niveauSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paymentsAsync = ref.watch(paymentsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F8),
      body: Stack(
        children: [
          Row(
            children: [
              const AdminSidebar(currentRoute: '/payments'),
              Expanded(
                child: Column(
                  children: [
                    _buildHeader(paymentsAsync),
                    Expanded(
                      child: paymentsAsync.when(
                        loading: () => const PaymentsSkeletonLoader(),
                        error: (e, _) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(40),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error_outline_rounded, size: 56,
                                    color: AppColors.error.withOpacity(0.6)),
                                const SizedBox(height: 16),
                                Text(
                                  UserFriendlyError.format(
                                    e,
                                    fallback: 'Unable to load payments right now. Please try again.',
                                  ),
                                  style: TextStyle(color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  onPressed: () => ref.invalidate(paymentsProvider),
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('Réessayer'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        data: (state) => _buildMainContent(context, state),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Filter overlay — slides in from right like grade_levels
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
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              right: 0,
              top: 0,
              bottom: 0,
              width: 380,
              child: paymentsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (state) => _buildFilterPanel(context, state),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER — Premium grade-levels style
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader(AsyncValue<PaymentsState> paymentsAsync) {
    final state = paymentsAsync.asData?.value;
    final count = state?.payments.length ?? 0;
    final studentCount = state?.studentSummaries.length ?? 0;
    final hasFilters = (state?.statusFilter != null && state?.statusFilter != 'all') ||
        state?.classFilter != null ||
        state?.categoryFilter != null ||
        state?.dateFromFilter != null ||
        state?.dateToFilter != null ||
        _selectedNiveauId != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE9EAF2))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Title block
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Gestion des Paiements',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$count paiements • $studentCount étudiants',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),

          const Spacer(),

          // Bulk actions (when selection active)
          if (_selectedPayments.isNotEmpty) ...[
            SizedBox(
              height: 40,
              child: ElevatedButton.icon(
                onPressed: () => _showBulkMarkPaidDialog(context),
                icon: const Icon(Icons.check_circle, size: 16),
                label: Text('Marquer ${_selectedPayments.length} payé(s)',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 40,
              child: TextButton(
                onPressed: () => setState(() => _selectedPayments.clear()),
                child: Text('Annuler',
                    style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
              ),
            ),
            const SizedBox(width: 16),
          ],

          // Student search (Autocomplete)
          Flexible(
            child: SizedBox(
              height: 40,
              child: _buildStudentSearchBar(),
            ),
          ),

          const SizedBox(width: 12),
          AdminSortDropdown<String>(
            value: _sortKey,
            tooltip: 'Trier les étudiants',
            onChanged: (v) => setState(() => _sortKey = v),
            options: const [
              SortOption(value: 'student_asc', label: 'Étudiant (A → Z)', icon: Icons.sort_by_alpha),
              SortOption(value: 'student_desc', label: 'Étudiant (Z → A)', icon: Icons.sort_by_alpha),
              SortOption(value: 'unpaid_first', label: 'Non soldés d’abord', icon: Icons.schedule_rounded),
              SortOption(value: 'paid_first', label: 'Soldés d’abord', icon: Icons.check_circle_outline),
              SortOption(value: 'payments_desc', label: 'Paiements (Décroissant)', icon: Icons.payments_outlined),
            ],
          ),
          const SizedBox(width: 8),
          // Filter button
          _buildHeaderIconButton(
            icon: Icons.filter_list_rounded,
            tooltip: 'Filtres',
            isActive: _showFilters || hasFilters,
            onPressed: () => setState(() => _showFilters = !_showFilters),
          ),

          const SizedBox(width: 8),

          // Default payment plan settings button
          _buildHeaderIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Plan de paiement par défaut',
            onPressed: () => _showDefaultPaymentMethodDialog(context),
          ),

          const SizedBox(width: 12),

          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: () => _showPricingConfigDialog(context),
              icon: const Icon(Icons.price_change_outlined, size: 18),
              label: const Text('Tarification', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
      color: isActive ? const Color(0xFF0F172A) : const Color(0xFF64748B),
      style: IconButton.styleFrom(
        backgroundColor: isActive ? const Color(0xFFF1F5F9) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isActive ? const Color(0xFFCBD5E1) : Colors.transparent,
          ),
        ),
      ),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STUDENT SEARCH BAR WITH AUTOCOMPLETE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStudentSearchBar() {
    return Autocomplete<Map<String, dynamic>>(
        optionsBuilder: (TextEditingValue textEditingValue) {
          if (textEditingValue.text.isEmpty) {
            return const Iterable<Map<String, dynamic>>.empty();
          }
          return _getFilteredStudents(textEditingValue.text).take(10);
        },
        displayStringForOption: (option) =>
            option['full_name']?.toString() ?? '',
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Rechercher un élève...',
              hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
              prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textTertiary),
              suffixIcon: controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () => controller.clear(),
                    )
                  : Padding(
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
                    ),
              filled: true,
              fillColor: AppColors.slate50,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.slate200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.slate200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                    color: Color(0xFF6D4CF6), width: 1.5),
              ),
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(AppRadius.md),
              color: Colors.white,
              child: Container(
                width: 400,
                constraints: const BoxConstraints(maxHeight: 350),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.slate200),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final student = options.elementAt(index);
                    final enrollments = student['enrollments'] as List?;
                    final enrollment = enrollments?.isNotEmpty == true
                        ? enrollments!.first as Map<String, dynamic>
                        : null;
                    final classData =
                        enrollment?['classes'] as Map<String, dynamic>?;

                    return Material(
                      color: Colors.transparent,
                      child: ListTile(
                        mouseCursor: SystemMouseCursors.click,
                        leading: UserAvatar(
                          name: student['full_name'] ?? '?',
                          photoUrl: student['photo_url']?.toString(),
                          radius: 20,
                        ),
                        title: Text(
                          student['full_name'] ?? 'Sans nom',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${classData?['name'] ?? 'Pas de classe'} • ${student['email'] ?? ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _showCreatePaymentPlanForStudent(student),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
        onSelected: (student) => _showCreatePaymentPlanForStudent(student),
      );
  }

  void _showCreatePaymentPlanForStudent(Map<String, dynamic> student) async {
    var enrollments = student['enrollments'] as List?;

    // If enrollments not present (e.g. from DataTable), fetch them
    if (enrollments == null || enrollments.isEmpty) {
      final studentId = student['id']?.toString() ?? student['studentId']?.toString() ?? '';
      if (studentId.isEmpty) return;
      try {
        final supabase = Supabase.instance.client;
        final resp = await supabase
            .from('enrollments')
            .select('id, classes(id, name, niveau_id, section_id)')
            .eq('user_id', studentId)
            .eq('is_active', true);
        enrollments = resp as List?;
      } catch (_) {}
    }

    if (enrollments == null || enrollments.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cet élève n\'est inscrit dans aucune classe'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    final enrollment = enrollments.first as Map<String, dynamic>;
    final enrollmentId = enrollment['id']?.toString();
    final classData = enrollment['classes'] as Map<String, dynamic>?;

    _showPaymentPlanCreationDialog(
      studentId: student['id']?.toString() ?? student['studentId']?.toString() ?? '',
      studentName: student['full_name']?.toString() ?? student['studentName']?.toString() ?? '',
      enrollmentId: enrollmentId ?? '',
      className: classData?['name']?.toString() ?? '',
      niveauId: classData?['niveau_id']?.toString(),
      sectionId: classData?['section_id']?.toString(),
    );
  }

  void _showAddPaymentPlanDialog(BuildContext screenContext) {
    _showBlurredDialog(
      context: screenContext,
      child: _SelectStudentForPaymentDialog(
        allStudents: _allStudents,
        allNiveaux: _allNiveaux,
        allSections: _allSections,
        allClasses: _allClasses,
        onStudentSelected: (student) {
          Navigator.pop(screenContext);
          _showCreatePaymentPlanForStudent(student);
        },
        onStudentProfile: (student) {
          final studentId = student['id']?.toString();
          if (studentId == null) return;
          _showBlurredDialog(
            context: screenContext,
            child: UserProfileScreen(
              userId: studentId,
              userName: student['full_name']?.toString(),
              isDialogMode: true,
              onBack: () => Navigator.pop(screenContext),
            ),
          );
        },
      ),
    );
  }

  void _showPricingConfigDialog(BuildContext context) {
    _showBlurredDialog(
      context: context,
      child: _PaymentPricingDialog(
        allNiveaux: _allNiveaux,
        allSections: _allSections,
        allClasses: _allClasses,
      ),
    );
  }

  void _showDefaultPaymentMethodDialog(BuildContext context) {
    _showBlurredDialog(
      context: context,
      child: _DefaultPaymentMethodDialog(
        allNiveaux: _allNiveaux,
      ),
    );
  }

  Future<T?> _showBlurredDialog<T>({
    required BuildContext context,
    required Widget child,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              color: Colors.black.withOpacity(0.3),
              width: double.infinity,
              height: double.infinity,
              child: Material(
                type: MaterialType.transparency,
                child: SafeArea(
                  child: Center(
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showPaymentPlanCreationDialog({
    required String studentId,
    required String studentName,
    required String enrollmentId,
    required String className,
    String? niveauId,
    String? sectionId,
  }) {
    _showBlurredDialog(
      context: context,
      child: _CreatePaymentPlanDialog(
        studentId: studentId,
        studentName: studentName,
        enrollmentId: enrollmentId,
        className: className,
        niveauId: niveauId,
        sectionId: sectionId,
        onCreated: () {
          ref.invalidate(paymentsProvider);
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LEFT PANEL - FILTERS
  // ═══════════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════════════════
  // FILTER PANEL — Overlay drawer (right-side, grade_levels pattern)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFilterPanel(BuildContext context, PaymentsState state) {
    final dateFormat = DateFormat('d MMM yyyy', 'fr_FR');

    return Material(
      elevation: 16,
      shadowColor: Colors.black.withOpacity(0.15),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(left: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Column(
          children: [
            // ─── Header ───
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

            // ─── Filter body ───
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // STATUT
                    _filterLabel('Statut'),
                    const SizedBox(height: 8),
                    _buildFilterDropdown<String>(
                      value: state.statusFilter == 'all' ? null : state.statusFilter,
                      hint: 'Tous les statuts',
                      items: const [
                        DropdownMenuItem(
                          value: 'paid',
                          child: Text('Payés'),
                        ),
                        DropdownMenuItem(
                          value: 'pending',
                          child: Text('En attente'),
                        ),
                        DropdownMenuItem(
                          value: 'overdue',
                          child: Text('En retard'),
                        ),
                        DropdownMenuItem(
                          value: 'cancelled',
                          child: Text('Annulés'),
                        ),
                      ],
                      onChanged: (v) => ref
                          .read(paymentsProvider.notifier)
                          .setStatusFilter(v ?? 'all'),
                    ),

                    const SizedBox(height: 20),

                    // NIVEAU
                    _filterLabel('Niveau'),
                    const SizedBox(height: 8),
                    _buildFilterDropdown<String>(
                      value: _selectedNiveauId,
                      hint: 'Tous les niveaux',
                      items: _allNiveaux
                          .map((n) => DropdownMenuItem(
                                value: n['id']?.toString(),
                                child: Text(n['name']?.toString() ?? '',
                                    style: const TextStyle(fontSize: 13)),
                              ))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedNiveauId = v;
                          _selectedSectionId = null;
                          _selectedClassId = null;
                        });
                        ref
                            .read(paymentsProvider.notifier)
                            .setClassFilter(null);
                      },
                    ),

                    // FILIÈRE (conditional)
                    if (_selectedNiveauId != null &&
                        _niveauHasSections) ...[
                      const SizedBox(height: 20),
                      _filterLabel('Filière'),
                      const SizedBox(height: 8),
                      _buildFilterDropdown<String>(
                        value: _selectedSectionId,
                        hint: 'Toutes les filières',
                        items: _sectionsForNiveau
                            .map((s) => DropdownMenuItem(
                                  value: s['id']?.toString(),
                                  child: Text(s['name']?.toString() ?? '',
                                      style: const TextStyle(fontSize: 13)),
                                ))
                            .toList(),
                        onChanged: (v) {
                          setState(() {
                            _selectedSectionId = v;
                            _selectedClassId = null;
                          });
                          ref
                              .read(paymentsProvider.notifier)
                              .setClassFilter(null);
                        },
                      ),
                    ],

                    // CLASSE (conditional)
                    if (_selectedNiveauId != null) ...[
                      const SizedBox(height: 20),
                      _filterLabel('Classe'),
                      const SizedBox(height: 8),
                      _buildFilterDropdown<String>(
                        value: _selectedClassId,
                        hint: 'Toutes les classes',
                        items: _filteredClasses
                            .map((c) => DropdownMenuItem(
                                  value: c['id']?.toString(),
                                  child: Text(c['name']?.toString() ?? '',
                                      style: const TextStyle(fontSize: 13)),
                                ))
                            .toList(),
                        onChanged: (v) {
                          setState(() => _selectedClassId = v);
                          ref.read(paymentsProvider.notifier).setClassFilter(v);
                        },
                      ),
                    ],

                    const SizedBox(height: 20),

                    // CATÉGORIE
                    _filterLabel('Catégorie'),
                    const SizedBox(height: 8),
                    _buildFilterDropdown<String>(
                      value: state.categoryFilter,
                      hint: 'Toutes les catégories',
                      items: [
                        ...PaymentCategory.values.map(
                          (c) => DropdownMenuItem(
                            value: c.label,
                            child: Text(
                              c.label,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) => ref
                          .read(paymentsProvider.notifier)
                          .setCategoryFilter(v),
                    ),

                    const SizedBox(height: 20),

                    // PÉRIODE
                    _filterLabel("Période d'échéance"),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () =>
                                _selectDate(context, true, state),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 11),
                              decoration: BoxDecoration(
                                color: AppColors.slate50,
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: AppColors.borderLight),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      state.dateFromFilter != null
                                          ? dateFormat
                                              .format(state.dateFromFilter!)
                                          : 'Du...',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: state.dateFromFilter != null
                                            ? AppColors.textPrimary
                                            : AppColors.textTertiary,
                                      ),
                                    ),
                                  ),
                                  if (state.dateFromFilter != null) ...[
                                    GestureDetector(
                                      onTap: () => ref
                                          .read(paymentsProvider.notifier)
                                          .setDateFromFilter(null),
                                      child: const Icon(Icons.close,
                                          size: 14,
                                          color: AppColors.textTertiary),
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  const Icon(Icons.calendar_today_outlined,
                                      size: 16,
                                      color: AppColors.textTertiary),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () =>
                                _selectDate(context, false, state),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 11),
                              decoration: BoxDecoration(
                                color: AppColors.slate50,
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: AppColors.borderLight),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      state.dateToFilter != null
                                          ? dateFormat
                                              .format(state.dateToFilter!)
                                          : 'Au...',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: state.dateToFilter != null
                                            ? AppColors.textPrimary
                                            : AppColors.textTertiary,
                                      ),
                                    ),
                                  ),
                                  if (state.dateToFilter != null) ...[
                                    GestureDetector(
                                      onTap: () => ref
                                          .read(paymentsProvider.notifier)
                                          .setDateToFilter(null),
                                      child: const Icon(Icons.close,
                                          size: 14,
                                          color: AppColors.textTertiary),
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  const Icon(Icons.calendar_today_outlined,
                                      size: 16,
                                      color: AppColors.textTertiary),
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

            // ─── Footer ───
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
                          ref.read(paymentsProvider.notifier).clearFilters();
                          setState(() {
                            _selectedNiveauId = null;
                            _selectedSectionId = null;
                            _selectedClassId = null;
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF374151),
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFFD1D5DB)),
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
                        color: const Color(0xFF655DD5),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF655DD5).withOpacity(0.3),
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

  Widget _filterLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textTertiary,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildFilterDropdown<T>({
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final bool hasNull = items.any((i) => i.value == null);
    final allItems = hasNull
        ? items
        : [
            DropdownMenuItem<T>(
              value: null,
              child: Text(hint, style: const TextStyle(fontSize: 13, color: AppColors.textTertiary)),
            ),
            ...items,
          ];

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
          items: allItems,
          onChanged: onChanged,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          borderRadius: BorderRadius.circular(8),
          dropdownColor: Colors.white,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textTertiary),
        ),
      ),
    );
  }






  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(child: Divider()),
      ],
    );
  }

  Widget _buildClassFilter(PaymentsState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Niveau dropdown
        const Text(
          'Niveau',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: DropdownButtonFormField<String?>(
            value: _selectedNiveauId,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: InputBorder.none,
              isDense: true,
            ),
            hint: const Text(
              'Tous les niveaux',
              style: TextStyle(fontSize: 13),
            ),
            isExpanded: true,
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Tous les niveaux'),
              ),
              ..._allNiveaux.map(
                (n) => DropdownMenuItem<String?>(
                  value: n['id']?.toString(),
                  child: Text(
                    n['name']?.toString() ?? '',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
            onChanged: (v) {
              setState(() {
                _selectedNiveauId = v;
                _selectedSectionId = null;
                _selectedClassId = null;
              });
              ref.read(paymentsProvider.notifier).setClassFilter(null);
            },
          ),
        ),

        // Section (Filière) dropdown - only if niveau has sections
        if (_selectedNiveauId != null && _niveauHasSections) ...[
          const SizedBox(height: 12),
          const Text(
            'Filière',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: DropdownButtonFormField<String?>(
              value: _selectedSectionId,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
              hint: const Text(
                'Toutes les filières',
                style: TextStyle(fontSize: 13),
              ),
              isExpanded: true,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Toutes les filières'),
                ),
                ..._sectionsForNiveau.map(
                  (s) => DropdownMenuItem<String?>(
                    value: s['id']?.toString(),
                    child: Text(
                      s['name']?.toString() ?? '',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
              onChanged: (v) {
                setState(() {
                  _selectedSectionId = v;
                  _selectedClassId = null;
                });
                ref.read(paymentsProvider.notifier).setClassFilter(null);
              },
            ),
          ),
        ],

        // Class dropdown - always show if niveau is selected
        if (_selectedNiveauId != null) ...[
          const SizedBox(height: 12),
          const Text(
            'Classe',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: DropdownButtonFormField<String?>(
              value: _selectedClassId,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
              hint: const Text(
                'Toutes les classes',
                style: TextStyle(fontSize: 13),
              ),
              isExpanded: true,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Toutes les classes'),
                ),
                ..._filteredClasses.map(
                  (c) => DropdownMenuItem<String?>(
                    value: c['id']?.toString(),
                    child: Text(
                      c['name']?.toString() ?? '',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
              onChanged: (v) {
                setState(() => _selectedClassId = v);
                ref.read(paymentsProvider.notifier).setClassFilter(v);
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCategoryFilter(PaymentsState state) {
    final categories = PaymentCategory.values;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Catégorie',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: DropdownButtonFormField<String?>(
            initialValue: state.categoryFilter,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: InputBorder.none,
              isDense: true,
            ),
            hint: const Text(
              'Toutes les catégories',
              style: TextStyle(fontSize: 13),
            ),
            isExpanded: true,
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Toutes les catégories'),
              ),
              ...categories.map(
                (c) => DropdownMenuItem<String?>(
                  value: c.label,
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Color(c.colorValue),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(c.label, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ],
            onChanged: (v) =>
                ref.read(paymentsProvider.notifier).setCategoryFilter(v),
          ),
        ),
      ],
    );
  }

  Widget _buildDateRangeFilter(PaymentsState state) {
    final dateFormat = DateFormat('d MMM yyyy', 'fr_FR');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Période d\'échéance',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _selectDate(context, true, state),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.dateFromFilter != null
                              ? dateFormat.format(state.dateFromFilter!)
                              : 'Du...',
                          style: TextStyle(
                            fontSize: 12,
                            color: state.dateFromFilter != null
                                ? AppColors.textPrimary
                                : AppColors.textTertiary,
                          ),
                        ),
                      ),
                      if (state.dateFromFilter != null)
                        GestureDetector(
                          onTap: () => ref
                              .read(paymentsProvider.notifier)
                              .setDateFromFilter(null),
                          child: Icon(
                            Icons.close,
                            size: 14,
                            color: AppColors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () => _selectDate(context, false, state),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.dateToFilter != null
                              ? dateFormat.format(state.dateToFilter!)
                              : 'Au...',
                          style: TextStyle(
                            fontSize: 12,
                            color: state.dateToFilter != null
                                ? AppColors.textPrimary
                                : AppColors.textTertiary,
                          ),
                        ),
                      ),
                      if (state.dateToFilter != null)
                        GestureDetector(
                          onTap: () => ref
                              .read(paymentsProvider.notifier)
                              .setDateToFilter(null),
                          child: Icon(
                            Icons.close,
                            size: 14,
                            color: AppColors.textTertiary,
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
    );
  }

  bool _hasActiveFilters(PaymentsState state) {
    return state.statusFilter != 'all' ||
        state.classFilter != null ||
        state.categoryFilter != null ||
        state.dateFromFilter != null ||
        state.dateToFilter != null ||
        state.searchQuery.isNotEmpty ||
        _selectedNiveauId != null ||
        _selectedSectionId != null ||
        _selectedClassId != null;
  }

  Future<void> _selectDate(
    BuildContext context,
    bool isFrom,
    PaymentsState state,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom
          ? (state.dateFromFilter ?? DateTime.now())
          : (state.dateToFilter ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (picked != null) {
      if (isFrom) {
        ref.read(paymentsProvider.notifier).setDateFromFilter(picked);
      } else {
        ref.read(paymentsProvider.notifier).setDateToFilter(picked);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAIN CONTENT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMainContent(BuildContext context, PaymentsState state) {
    return _buildClassesLayout(context, state);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLASSES-STYLE LAYOUT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildClassesLayout(BuildContext context, PaymentsState state) {
    if (_isLoadingHierarchy) {
      return const PaymentsSkeletonLoader();
    }

    return Row(
      children: [
        // Left panel: niveaux navigation
        Container(
          width: 300,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              right: BorderSide(color: AppColors.border.withOpacity(0.5)),
            ),
          ),
          child: _buildPaymentsNiveauxPanel(),
        ),
        // Center: classes grid, class students list, or full student payments detail page
        Expanded(
          child: _selectedDetailStudentSummary != null
              ? _StudentPaymentDetailDialog(
                  student: _selectedDetailStudentSummary!,
                  ref: ref,
                  isFullPage: true,
                  onBack: () {
                    if (widget.initialStudentId != null && Navigator.canPop(context)) {
                      Navigator.pop(context);
                    } else {
                      setState(() => _selectedDetailStudentSummary = null);
                    }
                  },
                )
              : (_layoutSelectedClassId == null
                  ? _buildPaymentsClassesGrid(state)
                  : _buildClassStudentsList(state)),
        ),
      ],
    );
  }

  Widget _buildPaymentsNiveauxPanel() {
    const brand = Color(0xFF6D4CF6);
    const brandLight = Color(0xFFF3E8FF);

    final query = _niveauSearchQuery.trim().toLowerCase();
    final filteredNiveaux = _allNiveaux.where((niveau) {
      if (query.isEmpty) return true;
      final niveauName = (niveau['name'] ?? '').toString().toLowerCase();
      if (niveauName.contains(query)) return true;
      final classesForNiveau = _allClasses.where((c) => c['niveau_id'] == niveau['id']);
      return classesForNiveau.any((c) => (c['name'] ?? '').toString().toLowerCase().contains(query));
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Search bar header ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: TextField(
            controller: _niveauSearchController,
            onChanged: (v) => setState(() => _niveauSearchQuery = v),
            decoration: InputDecoration(
              hintText: 'Rechercher niveau ou classe...',
              hintStyle: const TextStyle(color: Color(0xFFB0B3BE), fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFFB0B3BE)),
              suffixIcon: _niveauSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 16, color: Color(0xFFB0B3BE)),
                      onPressed: () {
                        _niveauSearchController.clear();
                        setState(() => _niveauSearchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFFF5F6FA),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: brand, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const Divider(height: 1, color: Color(0xFFF1F1F5)),
        const SizedBox(height: 6),

        // ── "Par niveau" title ──
        const Padding(
          padding: EdgeInsets.only(left: 16, top: 10, bottom: 10),
          child: Text(
            'Par niveau',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: Color(0xFF1A1A2E),
              letterSpacing: -0.2,
            ),
          ),
        ),

        // ── Niveaux list with expandable classes ──
        Expanded(
          child: filteredNiveaux.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.school_outlined, size: 44, color: Colors.grey.shade300),
                      const SizedBox(height: 10),
                      Text(
                        _niveauSearchQuery.isNotEmpty ? 'Aucun résultat' : 'Aucun niveau',
                        style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                      ),
                      if (_niveauSearchQuery.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: () {
                            _niveauSearchController.clear();
                            setState(() => _niveauSearchQuery = '');
                          },
                          child: const Text('Effacer la recherche'),
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: filteredNiveaux.length,
                  itemBuilder: (context, index) {
                    final niveau = filteredNiveaux[index];
                    final niveauId = niveau['id'] as String;
                    final isExpanded = _layoutSelectedNiveauId == niveauId;

                    var classesForNiveau = _allClasses
                        .where((c) => c['niveau_id'] == niveauId)
                        .toList();
                    if (_niveauSearchQuery.isNotEmpty) {
                      final q = _niveauSearchQuery.toLowerCase();
                      final filtered = classesForNiveau
                          .where((c) => (c['name'] ?? '').toString().toLowerCase().contains(q))
                          .toList();
                      if (filtered.isNotEmpty) {
                        classesForNiveau = filtered;
                      }
                    }

                    final hasSelectedInNiveau = classesForNiveau.any((c) => c['id'] == _layoutSelectedClassId);
                    final count = classesForNiveau.length;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isExpanded ? const Color(0xFFF0EEFA) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            if (!isExpanded)
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                          ],
                          border: isExpanded
                              ? Border.all(color: brand.withOpacity(0.12))
                              : Border.all(color: Colors.grey.withOpacity(0.06)),
                        ),
                        child: Column(
                          children: [
                            // ── Niveau header ──
                            InkWell(
                              onTap: () => setState(() {
                                if (isExpanded) {
                                  _layoutSelectedNiveauId = null;
                                  _layoutSelectedSectionId = null;
                                  _layoutSelectedClassId = null;
                                  _layoutSelectedClassName = null;
                                } else {
                                  _layoutSelectedNiveauId = niveauId;
                                  _layoutSelectedSectionId = null;
                                  _layoutSelectedClassId = null;
                                  _layoutSelectedClassName = null;
                                }
                              }),
                              borderRadius: BorderRadius.circular(16),
                              hoverColor: brandLight.withOpacity(0.3),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        niveau['name'] ?? 'Niveau',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          color: isExpanded || hasSelectedInNiveau
                                              ? brand
                                              : const Color(0xFF2D2D3A),
                                        ),
                                      ),
                                    ),
                                    Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isExpanded ? brand : const Color(0xFFE9EAF0),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '$count',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: isExpanded ? Colors.white : const Color(0xFF7B7D8B),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // ── Expanded class list with connecting line ──
                            if (isExpanded)
                              Builder(
                                builder: (context) {
                                  // Determine sections in this niveau
                                  final sectionsInNiveau = <Map<String, dynamic>>[];
                                  final seenSecIds = <String>{};
                                  for (final sec in _allSections) {
                                    final sId = sec['id'] as String?;
                                    if (sId == null || seenSecIds.contains(sId)) continue;
                                    if (sec['niveau_id'] == niveauId || classesForNiveau.any((c) => c['section_id'] == sId)) {
                                      seenSecIds.add(sId);
                                      sectionsInNiveau.add(sec);
                                    }
                                  }
                                  for (final cls in classesForNiveau) {
                                    final sId = cls['section_id'] as String?;
                                    if (sId != null && !seenSecIds.contains(sId)) {
                                      seenSecIds.add(sId);
                                      final sec = _allSections.firstWhere(
                                        (s) => s['id'] == sId,
                                        orElse: () => {'id': sId, 'name': 'Filière'},
                                      );
                                      sectionsInNiveau.add(sec);
                                    }
                                  }

                                  final hasSections = sectionsInNiveau.isNotEmpty;

                                  return Padding(
                                    padding: const EdgeInsets.only(left: 14, right: 14, bottom: 14),
                                    child: IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Container(
                                            width: 2,
                                            margin: const EdgeInsets.only(top: 4, bottom: 4),
                                            decoration: BoxDecoration(
                                              color: brand.withOpacity(0.18),
                                              borderRadius: BorderRadius.circular(1),
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: hasSections
                                                ? Column(
                                                    children: [
                                                      ...sectionsInNiveau.map((sec) {
                                                        final sId = sec['id'] as String;
                                                        final sName = sec['name'] as String? ?? 'Filière';
                                                        final secClasses = classesForNiveau.where((c) => c['section_id'] == sId).toList();
                                                        final isSecExpanded = _layoutSelectedSectionId == sId;

                                                        return Padding(
                                                          padding: const EdgeInsets.only(bottom: 6),
                                                          child: Column(
                                                            children: [
                                                              Material(
                                                                color: Colors.transparent,
                                                                child: InkWell(
                                                                  onTap: () => setState(() {
                                                                    _layoutSelectedSectionId = isSecExpanded ? null : sId;
                                                                  }),
                                                                  borderRadius: BorderRadius.circular(12),
                                                                  hoverColor: Colors.white.withOpacity(0.8),
                                                                  child: Container(
                                                                    width: double.infinity,
                                                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                                                    decoration: BoxDecoration(
                                                                      color: isSecExpanded ? Colors.white : Colors.white.withOpacity(0.65),
                                                                      borderRadius: BorderRadius.circular(12),
                                                                      boxShadow: isSecExpanded
                                                                          ? [
                                                                              BoxShadow(
                                                                                color: brand.withOpacity(0.08),
                                                                                blurRadius: 8,
                                                                                offset: const Offset(0, 2),
                                                                              ),
                                                                            ]
                                                                          : null,
                                                                      border: isSecExpanded
                                                                          ? Border.all(color: brand.withOpacity(0.25))
                                                                          : Border.all(color: Colors.transparent),
                                                                    ),
                                                                    child: Row(
                                                                      children: [
                                                                        Expanded(
                                                                          child: Text(
                                                                            sName,
                                                                            style: TextStyle(
                                                                              fontSize: 13,
                                                                              fontWeight: isSecExpanded ? FontWeight.w600 : FontWeight.w500,
                                                                              color: isSecExpanded ? brand : const Color(0xFF2D2D3A),
                                                                            ),
                                                                            maxLines: 1,
                                                                            overflow: TextOverflow.ellipsis,
                                                                          ),
                                                                        ),
                                                                        const SizedBox(width: 8),
                                                                        Container(
                                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                                          decoration: BoxDecoration(
                                                                            borderRadius: BorderRadius.circular(9999),
                                                                            color: isSecExpanded ? brand : const Color(0xFFE9EAF0),
                                                                          ),
                                                                          child: Text(
                                                                            '${secClasses.length}',
                                                                            style: TextStyle(
                                                                              fontSize: 11,
                                                                              fontWeight: FontWeight.w700,
                                                                              color: isSecExpanded ? Colors.white : const Color(0xFF7B7D8B),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                              if (isSecExpanded)
                                                                Padding(
                                                                  padding: const EdgeInsets.only(left: 10, top: 6),
                                                                  child: IntrinsicHeight(
                                                                    child: Row(
                                                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                                                      children: [
                                                                        Container(
                                                                          width: 2,
                                                                          margin: const EdgeInsets.only(top: 2, bottom: 2),
                                                                          decoration: BoxDecoration(
                                                                            color: brand.withOpacity(0.15),
                                                                            borderRadius: BorderRadius.circular(1),
                                                                          ),
                                                                        ),
                                                                        const SizedBox(width: 10),
                                                                        Expanded(
                                                                          child: Column(
                                                                            children: secClasses.map((cls) => _buildSidebarClassCard(cls, brand)).toList(),
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                                ),
                                                            ],
                                                          ),
                                                        );
                                                      }),
                                                      ...classesForNiveau
                                                          .where((c) => c['section_id'] == null || !seenSecIds.contains(c['section_id']))
                                                          .map((cls) => _buildSidebarClassCard(cls, brand)),
                                                    ],
                                                  )
                                                : Column(
                                                    children: classesForNiveau.map((cls) => _buildSidebarClassCard(cls, brand)).toList(),
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
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSidebarClassCard(Map<String, dynamic> cls, Color brand) {
    final classId = cls['id'] as String;
    final className = cls['name'] ?? 'Classe';
    final isSelected = _layoutSelectedClassId == classId;

    // Count students in this class
    final studentCount = _allStudents.where((s) {
      final enrollments = s['enrollments'] as List? ?? [];
      return enrollments.any((e) => (e['class_id'] as String?) == classId);
    }).length;

    final section = _allSections.firstWhere(
      (s) => s['id'] == cls['section_id'],
      orElse: () => <String, dynamic>{},
    );
    final sectionName = section['name'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() {
            _layoutSelectedClassId = isSelected ? null : classId;
            _layoutSelectedClassName = isSelected ? null : className;
            _classStudentsPage = 0;
          }),
          borderRadius: BorderRadius.circular(12),
          hoverColor: Colors.white.withOpacity(0.8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: brand.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
              border: isSelected
                  ? Border.all(color: brand.withOpacity(0.2))
                  : Border.all(color: Colors.transparent),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        className,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected ? brand : const Color(0xFF5A5B6A),
                        ),
                      ),
                      if (sectionName != null || studentCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              if (sectionName != null) ...[
                                Flexible(
                                  child: Text(
                                    sectionName,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isSelected ? brand.withOpacity(0.8) : const Color(0xFF8B90A0),
                                    ),
                                  ),
                                ),
                                if (studentCount > 0)
                                  Text(
                                    ' • ',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isSelected ? brand.withOpacity(0.5) : const Color(0xFFC4C7D0),
                                    ),
                                  ),
                              ],
                              if (studentCount > 0)
                                Text(
                                  '$studentCount élève${studentCount > 1 ? 's' : ''}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isSelected ? brand.withOpacity(0.8) : const Color(0xFF8B90A0),
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
      ),
    );
  }

  List<Map<String, dynamic>> get _layoutFilteredClasses {
    if (_layoutSelectedNiveauId == null) return _allClasses;

    return _allClasses.where((c) {
      if (c['niveau_id'] != _layoutSelectedNiveauId) return false;
      final sectionsForNiveau = _allSections
          .where((s) => s['niveau_id'] == _layoutSelectedNiveauId)
          .toList();
      if (sectionsForNiveau.isNotEmpty &&
          _layoutSelectedSectionId != null) {
        return c['section_id'] == _layoutSelectedSectionId;
      }
      return true;
    }).toList();
  }

  Widget _buildPaymentsClassesGrid(PaymentsState state) {
    final classes = _layoutFilteredClasses;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Grid header
        Container(
          margin: const EdgeInsets.fromLTRB(28, 28, 28, 16),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Toutes les classes',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${classes.length} classe(s)',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (_layoutSelectedNiveauId != null)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _layoutSelectedNiveauId = null;
                    _layoutSelectedSectionId = null;
                  }),
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('Réinitialiser'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280),
                  ),
                ),
            ],
          ),
        ),

        // Grid
        Expanded(
          child: classes.isEmpty
              ? _buildEmptyState(
                  icon: Icons.meeting_room_outlined,
                  title: 'Aucune classe',
                  subtitle: 'Aucune classe ne correspond à ce niveau',
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 350,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    mainAxisExtent: 180,
                  ),
                  itemCount: classes.length,
                  itemBuilder: (context, index) {
                    final cls = classes[index];
                    final classId = cls['id'] as String;
                    final studentCount = _allStudents
                        .where((s) {
                          final enrollments =
                              s['enrollments'] as List? ?? [];
                          return enrollments.any(
                            (e) =>
                                (e['class_id'] as String?) == classId,
                          );
                        })
                        .length;
                    return _buildPaymentClassCard(
                      cls: cls,
                      studentCount: studentCount,
                      state: state,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPaymentClassCard({
    required Map<String, dynamic> cls,
    required int studentCount,
    required PaymentsState state,
  }) {
    final brand = const Color(0xFF10B981);
    final className = cls['name'] as String? ?? 'Classe';
    final classId = cls['id'] as String?;
    final sectionId = cls['section_id'] as String?;
    final niveauId = cls['niveau_id'] as String?;
    final isSelected = _layoutSelectedClassId == classId;

    String? subtitle;
    for (final s in _allSections) {
      if (s['id'] == sectionId) {
        subtitle = s['name'] as String?;
        break;
      }
    }
    if (subtitle == null) {
      for (final n in _allNiveaux) {
        if (n['id'] == niveauId) {
          subtitle = n['name'] as String?;
          break;
        }
      }
    }

    // Find all student IDs in this class
    final classStudents = _allStudents.where((s) {
      final enrollments = s['enrollments'] as List? ?? [];
      return enrollments.any((e) => (e['class_id'] as String?) == classId);
    }).toList();
    final studentIds = classStudents
        .map((s) => s['id']?.toString())
        .whereType<String>()
        .toSet();

    // Compute total to pay and amount already paid for this class
    double totalAmount = 0;
    double paidAmount = 0;

    final matchingPlans = state.paymentPlans.where(
      (p) =>
          p.classId == classId ||
          (p.studentId != null && studentIds.contains(p.studentId)),
    ).toList();

    for (final plan in matchingPlans) {
      totalAmount += plan.amountTotal;
      paidAmount += plan.paidAmount;
    }

    if (totalAmount == 0) {
      final matchingSummaries = state.studentSummaries.where(
        (s) =>
            s.classId == classId ||
            studentIds.contains(s.studentId),
      ).toList();
      for (final s in matchingSummaries) {
        totalAmount += s.totalAmount;
        paidAmount += s.paidAmount;
      }
    }

    if (totalAmount == 0) {
      final matchingPayments = state.payments.where(
        (p) =>
            p.classId == classId ||
            (p.studentId != null && studentIds.contains(p.studentId)),
      ).toList();
      for (final p in matchingPayments) {
        totalAmount += p.amount;
        if (p.status == PaymentStatus.paid) {
          paidAmount += p.amount;
        }
      }
    }

    final double remaining =
        (totalAmount - paidAmount).clamp(0.0, double.infinity);
    final double payRate =
        totalAmount > 0 ? (paidAmount / totalAmount).clamp(0.0, 1.0) : 0.0;
    final int percent = (payRate * 100).round();

    final currencyFormatter = NumberFormat('#,###', 'fr_FR');
    final formattedPaid = currencyFormatter.format(paidAmount).replaceAll('\u00A0', ' ');
    final formattedTotal = currencyFormatter.format(totalAmount).replaceAll('\u00A0', ' ');
    final formattedRemaining = currencyFormatter.format(remaining).replaceAll('\u00A0', ' ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() {
          _layoutSelectedClassId = classId;
          _layoutSelectedClassName = className;
        }),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? brand : const Color(0xFFF1F5F9),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Header: Icon + Class Info + Student count pill
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.article_rounded,
                      color: Color(0xFF475569),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          className,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
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
              const SizedBox(height: 12),

              // Amounts Row: Déjà payé (left) & Total à payer (right)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Déjà payé',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$formattedPaid TND',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6D4CF6),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Total à payer',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$formattedTotal TND',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Progress Bar + Percentage
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: payRate,
                        minHeight: 5.5,
                        backgroundColor: const Color(0xFFE2E8F0),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF6D4CF6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$percent%',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF94A3B8),
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

  Widget _buildClassStudentsList(PaymentsState state) {
    final classStudentsRaw = _allStudents.where((s) {
      final enrollments = s['enrollments'] as List? ?? [];
      return enrollments.any(
        (e) => (e['class_id'] as String?) == _layoutSelectedClassId,
      );
    }).toList();

    // Build enriched list: raw student data + payment summary
    final List<Map<String, dynamic>> enrichedStudents = [];
    for (final student in classStudentsRaw) {
      final studentId = student['id'] as String?;
      final existingSummary = state.studentSummaries.where((s) => s.studentId == studentId).firstOrNull;
      
      final studentPlans = state.paymentPlans.where((p) => p.studentId == studentId).toList();
      final totalP = (existingSummary != null && existingSummary.totalPayments > 0)
          ? existingSummary.totalPayments
          : studentPlans.fold<int>(0, (sum, p) => sum + p.payments.length);
      final paidP = (existingSummary != null && existingSummary.totalPayments > 0)
          ? existingSummary.paidPayments
          : studentPlans.fold<int>(0, (sum, p) => sum + p.paidCount);

      enrichedStudents.add({
        'id': studentId ?? '',
        'full_name': student['full_name'] as String? ?? 'Sans nom',
        'email': student['email'] as String? ?? '',
        'phone': student['phone'] as String? ?? '',
        'photo_url': student['photo_url'] ?? student['avatar_url'] ?? existingSummary?.studentPhotoUrl,
        'paidPayments': paidP,
        'totalPayments': totalP,
      });
    }

    enrichedStudents.sort((a, b) {
      int cmp;
      switch (_sortKey) {
        case 'student_desc':
          cmp = (b['full_name'] as String).toLowerCase().compareTo((a['full_name'] as String).toLowerCase());
          break;
        case 'unpaid_first':
          final aUnpaid = ((a['totalPayments'] as int) - (a['paidPayments'] as int)) > 0 ? 0 : 1;
          final bUnpaid = ((b['totalPayments'] as int) - (b['paidPayments'] as int)) > 0 ? 0 : 1;
          if (aUnpaid != bUnpaid) return aUnpaid.compareTo(bUnpaid);
          cmp = (a['full_name'] as String).toLowerCase().compareTo((b['full_name'] as String).toLowerCase());
          break;
        case 'paid_first':
          final aPaid = ((a['totalPayments'] as int) > 0 && (a['paidPayments'] as int) >= (a['totalPayments'] as int)) ? 0 : 1;
          final bPaid = ((b['totalPayments'] as int) > 0 && (b['paidPayments'] as int) >= (b['totalPayments'] as int)) ? 0 : 1;
          if (aPaid != bPaid) return aPaid.compareTo(bPaid);
          cmp = (a['full_name'] as String).toLowerCase().compareTo((b['full_name'] as String).toLowerCase());
          break;
        case 'payments_desc':
          cmp = (b['totalPayments'] as int).compareTo(a['totalPayments'] as int);
          break;
        case 'student_asc':
        default:
          cmp = (a['full_name'] as String).toLowerCase().compareTo((b['full_name'] as String).toLowerCase());
          break;
      }
      if (cmp != 0) return cmp;
      final nameCmp = (a['full_name'] as String).toLowerCase().compareTo((b['full_name'] as String).toLowerCase());
      if (nameCmp != 0) return nameCmp;
      return (a['id'] ?? '').toString().compareTo((b['id'] ?? '').toString());
    });

    final totalPages = _classStudentsPerPage > 0
        ? (enrichedStudents.length / _classStudentsPerPage).ceil()
        : 1;
    final start = _classStudentsPage * _classStudentsPerPage;
    final end = _classStudentsPerPage == -1
        ? enrichedStudents.length
        : (start + _classStudentsPerPage).clamp(0, enrichedStudents.length);
    final pageStudents = enrichedStudents.sublist(start, end);

    return Column(
      children: [
        // Header with back button
        Container(
          margin: const EdgeInsets.fromLTRB(28, 24, 28, 16),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() {
                  _layoutSelectedClassId = null;
                  _layoutSelectedClassName = null;
                  _selectedDetailStudentSummary = null;
                }),
                icon: const Icon(Icons.arrow_back_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFF3F4F6),
                  foregroundColor: const Color(0xFF374151),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                _layoutSelectedClassName ?? 'Classe',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${enrichedStudents.length} étudiant(s)',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),

        // Bordered card with DataTable
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            child: enrichedStudents.isEmpty
                ? _buildEmptyState(
                    icon: Icons.people_outline,
                    title: 'Aucun étudiant',
                    subtitle: 'Aucun étudiant inscrit dans cette classe',
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border.withOpacity(0.3)),
                      boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                    child: Column(children: [
                      // Card header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
                        ),
                        child: Row(children: [
                          Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEECFB),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.people_rounded, color: Color(0xFF655DD5), size: 16),
                          ),
                          const SizedBox(width: 12),
                          const Text('Liste des étudiants', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEECFB),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('${enrichedStudents.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF655DD5))),
                          ),
                        ]),
                      ),

                      // DataTable
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final w = constraints.maxWidth;
                            const spacerW = 48.0;
                            const actionsW = 48.0;
                            const phoneW = 160.0;
                            const paymentsW = 120.0;
                            final nameW = (w - spacerW - phoneW - paymentsW - actionsW).clamp(200.0, double.infinity);

                            final classMaxPartitions = enrichedStudents.fold<int>(0, (max, s) => (s['totalPayments'] as int) > max ? (s['totalPayments'] as int) : max);
                            final defaultPartitions = classMaxPartitions > 0 ? classMaxPartitions : 10;

                            return DataTable(
                              columnSpacing: 0,
                              horizontalMargin: 0,
                              dataRowMinHeight: 56,
                              dataRowMaxHeight: 60,
                              headingRowHeight: 44,
                              headingRowColor: WidgetStateProperty.all(Colors.white),
                              headingTextStyle: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textTertiary,
                                fontSize: 11,
                                letterSpacing: 0.5,
                              ),
                              showCheckboxColumn: false,
                              columns: [
                                DataColumn(label: SizedBox(width: spacerW, child: Container())),
                                DataColumn(label: SizedBox(width: nameW, child: _headerLabel('NOM COMPLET / EMAIL'))),
                                DataColumn(label: SizedBox(width: phoneW, child: _headerLabelCenter('TÉLÉPHONE'))),
                                DataColumn(label: SizedBox(width: paymentsW, child: _headerLabelCenter('PAIEMENTS'))),
                                DataColumn(label: SizedBox(width: actionsW, child: Container())),
                              ],
                              rows: pageStudents.map((s) {
                                final sid = s['id'] as String;
                                final fullName = s['full_name'] as String;
                                final email = s['email'] as String;
                                final phone = s['phone'] as String;
                                final paid = s['paidPayments'] as int;
                                final total = s['totalPayments'] as int;
                                final displayTotal = total > 0 ? total : defaultPartitions;
                                final isAllPaid = displayTotal > 0 && paid >= displayTotal;
                                final isNonePaid = paid == 0;

                                Color pillBg;
                                Color pillText;
                                if (isAllPaid) {
                                  pillBg = const Color(0xFFDCFCE7);
                                  pillText = const Color(0xFF16A34A);
                                } else if (isNonePaid) {
                                  pillBg = const Color(0xFFF1F5F9);
                                  pillText = const Color(0xFF64748B);
                                } else {
                                  pillBg = const Color(0xFFFEF3C7);
                                  pillText = const Color(0xFFD97706);
                                }

                                return DataRow(
                                  color: WidgetStateProperty.resolveWith<Color?>((states) {
                                    if (states.contains(WidgetState.hovered)) return const Color(0xFFF9FAFB);
                                    return null;
                                  }),
                                  cells: [
                                    DataCell(SizedBox(width: spacerW, child: Container())),
                                    DataCell(
                                      SizedBox(
                                        width: nameW,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16),
                                          child: Row(
                                            children: [
                                              UserAvatar(
                                                name: fullName,
                                                photoUrl: s['photo_url']?.toString(),
                                                radius: 17,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      fullName,
                                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                                                      overflow: TextOverflow.ellipsis,
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
                                      ),
                                      onTap: () {
                                        final existingSummary = state.studentSummaries.where((s) => s.studentId == sid).firstOrNull;
                                        final summary = existingSummary ?? StudentPaymentSummary(
                                          studentId: sid,
                                          studentName: fullName,
                                          studentEmail: email,
                                          classId: _layoutSelectedClassId,
                                          className: _layoutSelectedClassName,
                                          totalAmount: 0,
                                          paidAmount: 0,
                                          pendingAmount: 0,
                                          totalPayments: 0,
                                          paidPayments: 0,
                                          overduePayments: 0,
                                          plans: [],
                                        );
                                        setState(() {
                                          _selectedDetailStudentSummary = summary;
                                        });
                                      },
                                    ),
                                    DataCell(
                                      SizedBox(
                                        width: phoneW,
                                        child: Center(
                                          child: Text(
                                            phone.isNotEmpty ? phone : '—',
                                            style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      SizedBox(
                                        width: paymentsW,
                                        child: Center(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: pillBg,
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              '$paid/$displayTotal',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: pillText,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      SizedBox(
                                        width: actionsW,
                                        child: Center(
                                          child: PopupMenuButton<String>(
                                            icon: Icon(Icons.more_horiz, size: 18, color: AppColors.textTertiary),
                                            tooltip: 'Actions',
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            elevation: 8,
                                            offset: const Offset(-160, 40),
                                            onSelected: (action) {
                                              switch (action) {
                                                case 'profile': context.push('/users/$sid'); break;
                                                case 'edit_plan':
                                                  final studentData = s;
                                                  _showCreatePaymentPlanForStudent(studentData);
                                                  break;
                                              }
                                            },
                                            itemBuilder: (_) => [
                                              PopupMenuItem(
                                                value: 'profile',
                                                height: 40,
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.visibility_outlined, size: 18, color: Color(0xFF10B981)),
                                                    const SizedBox(width: 12),
                                                    const Text('Voir profil', style: TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'edit_plan',
                                                height: 40,
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF655DD5)),
                                                    const SizedBox(width: 12),
                                                    const Text('Modifier le plan', style: TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ),

                      // Pagination footer
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAFAFB),
                          border: Border(top: BorderSide(color: AppColors.border.withOpacity(0.3))),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                        ),
                        child: Row(children: [
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
                                value: _classStudentsPerPage,
                                isDense: true,
                                borderRadius: BorderRadius.circular(10),
                                dropdownColor: Colors.white,
                                elevation: 4,
                                menuMaxHeight: 200,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: AppColors.textTertiary),
                                items: [10, 20, 50].map((v) => DropdownMenuItem(
                                  value: v,
                                  child: Text('$v', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                                )).toList(),
                                onChanged: (v) {
                                  if (v != null) setState(() {
                                    _classStudentsPerPage = v;
                                    _classStudentsPage = 0;
                                  });
                                },
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Page ${_classStudentsPage + 1} sur ${totalPages == 0 ? 1 : totalPages}',
                            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              InkWell(
                                onTap: _classStudentsPage > 0 ? () => setState(() => _classStudentsPage--) : null,
                                borderRadius: const BorderRadius.horizontal(left: Radius.circular(5)),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(Icons.chevron_left, size: 18, color: _classStudentsPage > 0 ? AppColors.textSecondary : AppColors.textTertiary),
                                ),
                              ),
                              Container(width: 1, height: 24, color: AppColors.border),
                              InkWell(
                                onTap: _classStudentsPage < totalPages - 1 ? () => setState(() => _classStudentsPage++) : null,
                                borderRadius: const BorderRadius.horizontal(right: Radius.circular(5)),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(Icons.chevron_right, size: 18, color: _classStudentsPage < totalPages - 1 ? AppColors.textSecondary : AppColors.textTertiary),
                                ),
                              ),
                            ]),
                          ),
                        ]),
                      ),
                    ]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _headerLabel(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textTertiary, letterSpacing: 0.5),
      ),
    );
  }

  Widget _headerLabelCenter(String text) {
    return Center(
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textTertiary, letterSpacing: 0.5),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAYMENTS LIST VIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPaymentsList(BuildContext context, PaymentsState state) {
    final payments = state.filtered;

    if (payments.isEmpty) {
      return _buildEmptyState(
        icon: Icons.payments_outlined,
        title: 'Aucun paiement trouvé',
        subtitle: 'Modifiez vos filtres ou ajoutez des paiements',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: payments.length,
      itemBuilder: (context, index) {
        final payment = payments[index];
        return _buildPaymentCard(context, payment);
      },
    );
  }

  Widget _buildPaymentCard(BuildContext context, Payment payment) {
    final dateFormat = DateFormat('d MMM yyyy', 'fr_FR');
    final isOverdue = payment.isOverdue;
    final statusColor = isOverdue
        ? const Color(0xFFEF4444)
        : Color(payment.status.colorValue);
    final isSelected = _selectedPayments.contains(payment.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? const Color(0xFF10B981) : const Color(0xFFE9EAF2),
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Left accent bar (grey)
              Container(width: 4, color: const Color(0xFFE9EAF2)),

              // Card content
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _showPaymentDetails(context, payment),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          // Checkbox (if not paid/cancelled)
                          if (payment.status != PaymentStatus.paid &&
                              payment.status != PaymentStatus.cancelled)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: SizedBox(
                                height: 20,
                                width: 20,
                                child: Checkbox(
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  value: isSelected,
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selectedPayments.add(payment.id);
                                      } else {
                                        _selectedPayments.remove(payment.id);
                                      }
                                    });
                                  },
                                  activeColor: const Color(0xFF10B981),
                                ),
                              ),
                            )
                          else
                            const SizedBox(width: 28),

                          // Status icon
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              payment.status == PaymentStatus.paid
                                  ? Icons.check_circle
                                  : (payment.status == PaymentStatus.cancelled
                                      ? Icons.cancel
                                      : (isOverdue
                                          ? Icons.warning_rounded
                                          : Icons.access_time)),
                              color: statusColor,
                              size: 22,
                            ),
                          ),

                          const SizedBox(width: 14),

                          // Payment info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (payment.studentName != null) ...[
                                      UserAvatar(
                                        name: payment.studentName!,
                                        photoUrl: payment.studentPhotoUrl,
                                        radius: 12,
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Expanded(
                                      child: Text(
                                        payment.studentName ?? 'Étudiant inconnu',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          color: Color(0xFF111827),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        isOverdue
                                            ? 'En retard'
                                            : payment.status.label,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: statusColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    Icon(Icons.school_outlined,
                                        size: 13, color: AppColors.slate400),
                                    const SizedBox(width: 4),
                                    Text(
                                      payment.className ?? '-',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.slate500),
                                    ),
                                    const SizedBox(width: 14),
                                    Text(
                                      payment.category ?? '-',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.slate500),
                                    ),
                                    const SizedBox(width: 14),
                                    Icon(Icons.event_outlined,
                                        size: 13, color: AppColors.slate400),
                                    const SizedBox(width: 4),
                                    Text(
                                      dateFormat.format(payment.dueDate),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isOverdue
                                            ? const Color(0xFFEF4444)
                                            : AppColors.slate500,
                                        fontWeight: isOverdue
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                                if (payment.paidAt != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Row(
                                      children: [
                                        Icon(Icons.check_circle_outline,
                                            size: 13,
                                            color: const Color(0xFF10B981)),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Payé le ${dateFormat.format(payment.paidAt!)}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF10B981),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          // Amount
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              '${payment.amount.toStringAsFixed(0)} TND',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF111827),
                              ),
                            ),
                          ),

                          // Actions popup
                          PopupMenuButton<String>(
                            onSelected: (value) =>
                                _handlePaymentAction(context, value, payment),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            offset: const Offset(0, 40),
                            itemBuilder: (context) => [
                              if (payment.status != PaymentStatus.paid)
                                PopupMenuItem(
                                  value: 'mark_paid',
                                  child: Row(children: [
                                    Icon(Icons.check_circle,
                                        color: const Color(0xFF10B981),
                                        size: 18),
                                    const SizedBox(width: 10),
                                    const Text('Marquer payé'),
                                  ]),
                                ),
                              PopupMenuItem(
                                value: 'view',
                                child: Row(children: [
                                  Icon(Icons.visibility,
                                      color: AppColors.slate500, size: 18),
                                  const SizedBox(width: 10),
                                  const Text('Voir les détails'),
                                ]),
                              ),
                              PopupMenuItem(
                                value: 'view_profile',
                                child: Row(children: [
                                  Icon(Icons.person_outline,
                                      color: const Color(0xFF8B5CF6), size: 18),
                                  const SizedBox(width: 10),
                                  const Text('Voir profil'),
                                ]),
                              ),
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(children: [
                                  Icon(Icons.edit,
                                      color: const Color(0xFF3B82F6), size: 18),
                                  const SizedBox(width: 10),
                                  const Text('Modifier'),
                                ]),
                              ),
                              const PopupMenuDivider(),
                              if (payment.status != PaymentStatus.cancelled)
                                PopupMenuItem(
                                  value: 'cancel',
                                  child: Row(children: [
                                    Icon(Icons.cancel,
                                        color: const Color(0xFFF59E0B),
                                        size: 18),
                                    const SizedBox(width: 10),
                                    const Text('Annuler'),
                                  ]),
                                ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(children: [
                                  Icon(Icons.delete_outline,
                                      color: const Color(0xFFEF4444), size: 18),
                                  const SizedBox(width: 10),
                                  const Text('Supprimer',
                                      style:
                                          TextStyle(color: Color(0xFFEF4444))),
                                ]),
                              ),
                            ],
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.slate100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.more_vert,
                                  size: 18, color: AppColors.slate500),
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
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STUDENTS LIST VIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStudentsList(BuildContext context, PaymentsState state) {
    final students = state.filteredStudents;

    if (students.isEmpty) {
      return _buildEmptyState(
        icon: Icons.people_outline,
        title: 'Aucun étudiant trouvé',
        subtitle: 'Modifiez vos filtres pour voir les étudiants',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: students.length,
      itemBuilder: (context, index) {
        final student = students[index];
        return _buildStudentCard(context, student);
      },
    );
  }

  Widget _buildStudentCard(
    BuildContext context,
    StudentPaymentSummary student,
  ) {
    final progress = student.progressPercent;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9EAF2)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showStudentPaymentDetails(context, student),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                UserAvatar(
                  name: student.studentName,
                  photoUrl: student.studentPhotoUrl,
                  radius: 20,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.studentName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        student.className ?? 'Classe non assignée',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.slate400,
                        ),
                      ),
                    ],
                  ),
                ),
                // Payment status pill
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: progress >= 100
                        ? const Color(0xFF10B981).withOpacity(0.08)
                        : AppColors.slate50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${student.paidPayments}/${student.totalPayments}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: progress >= 100
                          ? const Color(0xFF10B981)
                          : AppColors.slate600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.slate300),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATISTICS VIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStatisticsView(BuildContext context, PaymentsState state) {
    final collectionRate = state.totalDue > 0
        ? (state.totalCollected / state.totalDue * 100)
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overview Cards
          Row(
            children: [
              Expanded(
                child: _buildOverviewCard(
                  'Taux de Recouvrement',
                  '${collectionRate.toStringAsFixed(1)}%',
                  Icons.trending_up,
                  const Color(0xFF10B981),
                  subtitle:
                      '${state.totalCollected.toStringAsFixed(0)} / ${state.totalDue.toStringAsFixed(0)} TND',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildOverviewCard(
                  'Paiements en Retard',
                  '${state.overdueCount}',
                  Icons.warning,
                  const Color(0xFFEF4444),
                  subtitle:
                      '${state.totalOverdue.toStringAsFixed(0)} TND impayés',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildOverviewCard(
                  'Étudiants à Jour',
                  '${state.studentSummaries.where((s) => s.overduePayments == 0).length}',
                  Icons.check_circle,
                  const Color(0xFF10B981),
                  subtitle: 'sur ${state.studentSummaries.length} étudiants',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildOverviewCard(
                  'À Percevoir',
                  '${state.totalPending.toStringAsFixed(0)} TND',
                  Icons.schedule,
                  const Color(0xFFF59E0B),
                  subtitle: 'paiements en attente',
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Charts row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Payment status distribution
              Expanded(
                flex: 1,
                child: _buildChartCard(
                  'Répartition par Statut',
                  _buildStatusPieChart(state),
                ),
              ),

              const SizedBox(width: 16),

              // Category breakdown
              Expanded(
                flex: 2,
                child: _buildChartCard(
                  'Paiements par Catégorie',
                  _buildCategoryBreakdown(state),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Top debtors
          _buildChartCard(
            'Étudiants avec Paiements en Retard',
            _buildDebtorsList(state),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChartCard(String title, Widget child) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _buildStatusPieChart(PaymentsState state) {
    final paid = state.payments
        .where((p) => p.status == PaymentStatus.paid)
        .length;
    final pending = state.payments
        .where((p) => p.status == PaymentStatus.pending && !p.isOverdue)
        .length;
    final overdue = state.payments.where((p) => p.isOverdue).length;
    final cancelled = state.payments
        .where((p) => p.status == PaymentStatus.cancelled)
        .length;
    final total = state.payments.length;

    if (total == 0) {
      return const Center(child: Text('Aucune donnée'));
    }

    return Row(
      children: [
        // Simple pie representation
        SizedBox(
          width: 120,
          height: 120,
          child: CustomPaint(
            painter: _SimplePieChartPainter(
              segments: [
                (paid / total, const Color(0xFF10B981)),
                (pending / total, const Color(0xFFF59E0B)),
                (overdue / total, const Color(0xFFEF4444)),
                (cancelled / total, const Color(0xFF64748B)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            children: [
              _buildLegendItem('Payés', paid, const Color(0xFF10B981)),
              _buildLegendItem('En attente', pending, const Color(0xFFF59E0B)),
              _buildLegendItem('En retard', overdue, const Color(0xFFEF4444)),
              _buildLegendItem('Annulés', cancelled, const Color(0xFF64748B)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdown(PaymentsState state) {
    final categoryTotals = <String, double>{};
    for (final p in state.payments) {
      final cat = p.category ?? 'Autres';
      categoryTotals[cat] = (categoryTotals[cat] ?? 0) + p.amount;
    }

    if (categoryTotals.isEmpty) {
      return const Center(child: Text('Aucune donnée'));
    }

    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final maxAmount = sortedCategories.first.value;

    return Column(
      children: sortedCategories.map((entry) {
        final categoryEnum = PaymentCategory.values
            .cast<PaymentCategory?>()
            .firstWhere(
              (c) => c?.label == entry.key,
              orElse: () => PaymentCategory.autres,
            )!;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color(categoryEnum.colorValue).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getCategoryIcon(categoryEnum),
                  size: 16,
                  color: Color(categoryEnum.colorValue),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: Text(
                  entry.key,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: entry.value / maxAmount,
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: Color(categoryEnum.colorValue),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 80,
                child: Text(
                  '${entry.value.toStringAsFixed(0)} TND',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  IconData _getCategoryIcon(PaymentCategory category) {
    switch (category) {
      case PaymentCategory.scolarite:
        return Icons.school;
      case PaymentCategory.transport:
        return Icons.directions_bus;
      case PaymentCategory.inscription:
        return Icons.app_registration;
      case PaymentCategory.uniforme:
        return Icons.checkroom;
      case PaymentCategory.cantine:
        return Icons.restaurant;
      case PaymentCategory.activites:
        return Icons.sports_soccer;
      case PaymentCategory.autres:
        return Icons.more_horiz;
    }
  }

  Widget _buildDebtorsList(PaymentsState state) {
    final debtors =
        state.studentSummaries.where((s) => s.overduePayments > 0).toList()
          ..sort((a, b) => b.pendingAmount.compareTo(a.pendingAmount));

    if (debtors.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: AppColors.success, size: 24),
            const SizedBox(width: 8),
            Text(
              'Aucun paiement en retard ! 🎉',
              style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
            ),
          ],
        ),
      );
    }

    return Column(
      children: debtors
          .take(5)
          .map(
            (student) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  UserAvatar(
                    name: student.studentName,
                    photoUrl: student.studentPhotoUrl,
                    radius: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student.studentName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          student.className ?? '-',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${student.pendingAmount.toStringAsFixed(0)} TND',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                      Text(
                        '${student.overduePayments} en retard',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.email_outlined, size: 20),
                    color: const Color(0xFF64748B),
                    onPressed: () => _sendReminder(student),
                    tooltip: 'Envoyer un rappel',
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: AppColors.slate200),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DIALOGS & ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void _handlePaymentAction(
    BuildContext context,
    String action,
    Payment payment,
  ) {
    switch (action) {
      case 'mark_paid':
        _showMarkPaidDialog(context, payment);
        break;
      case 'edit':
        _showEditPaymentDialog(context, payment);
        break;
      case 'view':
        _showPaymentDetails(context, payment);
        break;
      case 'view_profile':
        if (payment.studentId != null) {
          context.push('/users/${payment.studentId}');
        }
        break;
      case 'cancel':
        _confirmCancelPayment(context, payment);
        break;
      case 'delete':
        _confirmDeletePayment(context, payment);
        break;
    }
  }

  void _showMarkPaidDialog(BuildContext context, Payment payment) {
    String? selectedMethod;
    final referenceController = TextEditingController(
      text: 'PAY-${DateTime.now().millisecondsSinceEpoch.toString().substring(0, 10)}',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Marquer comme payé'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.slate50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Montant: ${payment.amount.toStringAsFixed(0)} TND',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('Étudiant: ${payment.studentName ?? "-"}'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: 'Mode de paiement',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.slate200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF10B981)),
                ),
              ),
              borderRadius: BorderRadius.circular(14),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Espèces')),
                DropdownMenuItem(
                  value: 'bank_transfer',
                  child: Text('Virement bancaire'),
                ),
                DropdownMenuItem(value: 'card', child: Text('Carte bancaire')),
                DropdownMenuItem(value: 'check', child: Text('Chèque')),
              ],
              onChanged: (v) => selectedMethod = v,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: referenceController,
              decoration: InputDecoration(
                labelText: 'Référence / Reçu',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.slate200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF10B981)),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () {
                    referenceController.text =
                        'PAY-${DateTime.now().millisecondsSinceEpoch.toString().substring(0, 10)}';
                  },
                  tooltip: 'Générer nouvelle référence',
                ),
              ),
            ),
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
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE8EAF0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                    onPressed: () {
                      ref.read(paymentsProvider.notifier).markAsPaid(
                        payment.id,
                        method: selectedMethod,
                        reference: referenceController.text.isNotEmpty ? referenceController.text : null,
                      );
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paiement marqué comme payé'), backgroundColor: Color(0xFF10B981)));
                    },
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Confirmer', style: TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showBulkMarkPaidDialog(BuildContext context) {
    String? selectedMethod;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marquer les paiements comme payés'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_selectedPayments.length} paiements sélectionnés'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Mode de paiement',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Espèces')),
                DropdownMenuItem(
                  value: 'bank_transfer',
                  child: Text('Virement bancaire'),
                ),
                DropdownMenuItem(value: 'card', child: Text('Carte bancaire')),
                DropdownMenuItem(value: 'check', child: Text('Chèque')),
              ],
              onChanged: (v) => selectedMethod = v,
            ),
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
                    onPressed: () => Navigator.pop(context),
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
                    onPressed: () async {
                      await ref.read(paymentsProvider.notifier).bulkMarkAsPaid(_selectedPayments.toList(), method: selectedMethod);
                      setState(() => _selectedPayments.clear());
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paiements marqués comme payés'), backgroundColor: Color(0xFF10B981)));
                    },
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Confirmer', style: TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
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
  }

  void _showEditPaymentDialog(BuildContext context, Payment payment) {
    final amountController = TextEditingController(
      text: payment.amount.toString(),
    );
    final notesController = TextEditingController(text: payment.notes ?? '');
    DateTime selectedDate = payment.dueDate;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Modifier le paiement'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                decoration: const InputDecoration(
                  labelText: 'Montant (TND)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) {
                    setDialogState(() => selectedDate = picked);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date d\'échéance',
                    border: OutlineInputBorder(),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(DateFormat('d MMM yyyy', 'fr_FR').format(selectedDate)),
                      const Icon(Icons.calendar_today, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
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
                      onPressed: () => Navigator.pop(context),
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
                      onPressed: () {
                        ref.read(paymentsProvider.notifier).updatePayment(
                          id: payment.id,
                          amount: double.tryParse(amountController.text),
                          dueDate: selectedDate,
                          notes: notesController.text.isNotEmpty ? notesController.text : null,
                        );
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paiement modifié')));
                      },
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
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
      ),
    );
  }

  void _showPaymentDetails(BuildContext context, Payment payment) {
    final dateFormat = DateFormat("d MMM yyyy 'à' HH:mm", 'fr_FR');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              payment.status == PaymentStatus.paid
                  ? Icons.check_circle
                  : Icons.schedule,
              color: Color(payment.status.colorValue),
            ),
            const SizedBox(width: 8),
            const Text('Détails du Paiement'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(
                'Montant',
                '${payment.amount.toStringAsFixed(0)} TND',
              ),
              _buildDetailRow('Statut', payment.status.label),
              _buildDetailRow('Étudiant', payment.studentName ?? '-'),
              _buildDetailRow('Classe', payment.className ?? '-'),
              _buildDetailRow('Catégorie', payment.category ?? '-'),
              _buildDetailRow(
                'Échéance',
                DateFormat('d MMM yyyy', 'fr_FR').format(payment.dueDate),
              ),
              if (payment.paidAt != null)
                _buildDetailRow('Payé le', dateFormat.format(payment.paidAt!)),
              if (payment.method != null)
                _buildDetailRow('Mode', payment.method!),
              if (payment.reference != null)
                _buildDetailRow('Référence', payment.reference!),
              if (payment.notes != null && payment.notes!.isNotEmpty)
                _buildDetailRow('Notes', payment.notes!),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFE8EAF0)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Fermer', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmCancelPayment(BuildContext context, Payment payment) {
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
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
              const Text('Annuler le paiement ?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          content: Text(
            'Voulez-vous annuler le paiement de ${payment.amount.toStringAsFixed(0)} TND ? Cette action est irréversible.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    ref.read(paymentsProvider.notifier).cancelPayment(payment.id);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paiement annulé')));
                  },
                  icon: const Icon(Icons.warning_outlined, size: 16),
                  label: const Text('Oui, annuler', style: TextStyle(fontWeight: FontWeight.w700)),
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

  void _confirmDeletePayment(BuildContext context, Payment payment) {
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
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
              const Text('Supprimer le paiement ?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          content: Text(
            'Cette action est irréversible. Supprimer définitivement le paiement de ${payment.amount.toStringAsFixed(0)} TND ?',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    ref.read(paymentsProvider.notifier).deletePayment(payment.id);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paiement supprimé'), backgroundColor: Color(0xFFEF4444)));
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Supprimer', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
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

  void _showStudentPaymentDetails(
    BuildContext context,
    StudentPaymentSummary student,
  ) {
    setState(() {
      _selectedDetailStudentSummary = student;
    });
  }

  void _sendReminder(StudentPaymentSummary student) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Rappel envoyé à ${student.studentName}'),
        backgroundColor: const Color(0xFF3B82F6),
      ),
    );
  }

  void _handleExport(String format) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Export $format en cours...'),
        backgroundColor: const Color(0xFF3B82F6),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SIMPLE PIE CHART PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _SimplePieChartPainter extends CustomPainter {
  final List<(double, Color)> segments;

  _SimplePieChartPainter({required this.segments});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    double startAngle = -math.pi / 2;

    for (final segment in segments) {
      if (segment.$1 <= 0) continue;

      final sweepAngle = segment.$1 * 2 * math.pi;
      final paint = Paint()
        ..color = segment.$2
        ..style = PaintingStyle.fill;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );

      startAngle += sweepAngle;
    }

    // Draw center hole for donut effect
    final holePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.5, holePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
// MODERN STUDENT PAYMENT DETAIL DIALOG
// ═══════════════════════════════════════════════════════════════════════════

class _StudentPaymentDetailDialog extends ConsumerStatefulWidget {
  final StudentPaymentSummary student;
  final WidgetRef ref;
  final bool isFullPage;
  final VoidCallback? onBack;

  const _StudentPaymentDetailDialog({
    required this.student,
    required this.ref,
    this.isFullPage = false,
    this.onBack,
  });

  @override
  ConsumerState<_StudentPaymentDetailDialog> createState() =>
      _StudentPaymentDetailDialogState();
}

class _StudentPaymentDetailDialogState
    extends ConsumerState<_StudentPaymentDetailDialog>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _paymentPlans = [];
  bool _isLoading = true;
  String _selectedCategory = 'all';
  String _detailSortKey = 'due_date_asc';
  final Set<String> _selectedPaymentIds = {};
  double _paidAmount = 0;
  double _totalAmount = 0;
  int _paidPayments = 0;
  int _totalPayments = 0;

  @override
  void initState() {
    super.initState();
    _loadStudentPayments();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadStudentPayments() async {
    final seedPayments = <Map<String, dynamic>>[];
    try {
      final supabase = Supabase.instance.client;

      // 1. Seed directly from widget.student.plans (guaranteed in memory)
      for (final pl in widget.student.plans) {
        for (final pay in pl.payments) {
          if (!seedPayments.any((sp) => sp['id'] == pay.id)) {
            seedPayments.add({
              'id': pay.id,
              'amount': pay.amount,
              'status': pay.status.name,
              'due_date': pay.dueDate.toIso8601String(),
              'paid_at': pay.paidAt?.toIso8601String(),
              'category': pl.category ?? pay.category ?? 'scolarite',
              'description': pl.description ?? pay.notes ?? 'Échéance',
              'payment_plans': {
                'id': pl.id,
                'category': pl.category ?? 'scolarite',
                'plan_type': pl.planType.name,
              },
            });
          }
        }
      }

      // 2. Also seed from Riverpod memory
      final state = widget.ref.read(paymentsProvider).asData?.value;
      if (state != null) {
        for (final p in state.payments) {
          if (p.studentId == widget.student.studentId ||
              (p.studentName != null && p.studentName == widget.student.studentName)) {
            if (!seedPayments.any((sp) => sp['id'] == p.id)) {
              seedPayments.add({
                'id': p.id,
                'amount': p.amount,
                'status': p.status.name,
                'due_date': p.dueDate.toIso8601String(),
                'paid_at': p.paidAt?.toIso8601String(),
                'category': p.category ?? 'scolarite',
                'description': p.notes ?? 'Échéance',
                'payment_plans': {
                  'id': p.paymentPlanId,
                  'category': p.category ?? 'scolarite',
                  'plan_type': 'monthly',
                },
              });
            }
          }
        }
        for (final pl in state.paymentPlans) {
          if (pl.studentId == widget.student.studentId ||
              (pl.studentName != null && pl.studentName == widget.student.studentName)) {
            for (final pay in pl.payments) {
              if (!seedPayments.any((sp) => sp['id'] == pay.id)) {
                seedPayments.add({
                  'id': pay.id,
                  'amount': pay.amount,
                  'status': pay.status.name,
                  'due_date': pay.dueDate.toIso8601String(),
                  'paid_at': pay.paidAt?.toIso8601String(),
                  'category': pl.category ?? pay.category ?? 'scolarite',
                  'description': pl.description ?? 'Échéance',
                  'payment_plans': {
                    'id': pl.id,
                    'category': pl.category ?? 'scolarite',
                    'plan_type': pl.planType.name,
                  },
                });
              }
            }
          }
        }
      }

      // 3. Query database via Supabase
      List<dynamic> enrollmentList = [];
      try {
        final enrollments = await SupabaseConfig.adminClient
            .from('enrollments')
            .select('id, school_id, class_id, classes(id, niveau_id, section_id)')
            .eq('user_id', widget.student.studentId);
        enrollmentList = (enrollments as List?) ?? [];
      } catch (e) {
        debugPrint('Error loading enrollments by user_id: $e');
        try {
          final enrollments = await supabase
              .from('enrollments')
              .select('id, school_id, class_id, classes(id, niveau_id, section_id)')
              .eq('user_id', widget.student.studentId);
          enrollmentList = (enrollments as List?) ?? [];
        } catch (_) {}
      }

      // If enrollmentList is still empty, check by id
      if (enrollmentList.isEmpty) {
        try {
          final enrollments = await SupabaseConfig.adminClient
              .from('enrollments')
              .select('id, school_id, class_id, classes(id, niveau_id, section_id)')
              .eq('id', widget.student.studentId);
          enrollmentList = (enrollments as List?) ?? [];
        } catch (_) {}
      }

      final enrollmentIds = enrollmentList.map((e) => e['id']?.toString() ?? '').where((id) => id.isNotEmpty).toList();

      String? niveauId;
      String? sectionId;
      if (enrollmentList.isNotEmpty) {
        final firstEnrollment = enrollmentList.first;
        final cls = firstEnrollment['classes'] as Map<String, dynamic>?;
        niveauId = cls?['niveau_id'] as String?;
        sectionId = cls?['section_id'] as String?;
      }

      // 4. Load payment plans by enrollment_id
      List<dynamic> plansResponse = [];
      if (enrollmentIds.isNotEmpty) {
        try {
          plansResponse = await SupabaseConfig.adminClient
              .from('payment_plans')
              .select('id, plan_type, category, enrollment_id, amount_total, created_at')
              .inFilter('enrollment_id', enrollmentIds)
              .order('created_at', ascending: false) as List<dynamic>;
        } catch (e) {
          debugPrint('Error loading plans: $e');
        }
      }

      // 5. Load payments by payment_plan_id
      final planIds = plansResponse.map((p) => p['id']?.toString() ?? '').where((id) => id.isNotEmpty).toList();
      for (final pl in widget.student.plans) {
        if (pl.id.isNotEmpty && !planIds.contains(pl.id)) {
          planIds.add(pl.id);
        }
      }

      List<dynamic> paymentsResponse = [];
      if (planIds.isNotEmpty) {
        try {
          paymentsResponse = await SupabaseConfig.adminClient
              .from('payments')
              .select('*, payment_plans(id, plan_type, category, enrollment_id)')
              .inFilter('payment_plan_id', planIds)
              .order('due_date', ascending: true) as List<dynamic>;
        } catch (e) {
          debugPrint('Error loading payments by plan_id: $e');
        }
      }

      // Also query by enrollment_id to catch payments without payment_plan_id
      if (enrollmentIds.isNotEmpty) {
        try {
          final enrPayments = await SupabaseConfig.adminClient
              .from('payments')
              .select('*, payment_plans(id, plan_type, category, enrollment_id)')
              .inFilter('enrollment_id', enrollmentIds)
              .order('due_date', ascending: true) as List<dynamic>;
          for (final ep in enrPayments) {
            final epId = ep['id']?.toString();
            if (epId != null && !paymentsResponse.any((p) => p['id']?.toString() == epId)) {
              paymentsResponse.add(ep);
            }
          }
        } catch (e) {
          debugPrint('Error loading payments by enrollment_id: $e');
        }
      }

      // Also query directly by known seed payment IDs to ensure the freshest DB data
      final seedRealIds = seedPayments
          .map((p) => p['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty && !id.startsWith('pricing_'))
          .toList();
      if (seedRealIds.isNotEmpty) {
        try {
          final idPayments = await SupabaseConfig.adminClient
              .from('payments')
              .select('*, payment_plans(id, plan_type, category, enrollment_id)')
              .inFilter('id', seedRealIds) as List<dynamic>;
          for (final ip in idPayments) {
            final ipId = ip['id']?.toString();
            final existingIdx = paymentsResponse.indexWhere((p) => p['id']?.toString() == ipId);
            if (existingIdx >= 0) {
              paymentsResponse[existingIdx] = ip;
            } else {
              paymentsResponse.add(ip);
            }
          }
        } catch (e) {
          debugPrint('Error loading payments by id: $e');
        }
      }

      final seenIds = <String>{};
      final uniquePayments = <Map<String, dynamic>>[];
      for (final p in [...paymentsResponse, ...seedPayments]) {
        final id = p['id']?.toString() ?? '';
        if (id.isNotEmpty && !seenIds.contains(id)) {
          seenIds.add(id);
          uniquePayments.add(Map<String, dynamic>.from(p));
        }
      }

      // 6. Pricing for tariffs
      if (niveauId != null) {
        try {
          var pQuery = supabase
              .from('payment_pricing')
              .select('id, category, amount, section_id, niveau_id')
              .eq('niveau_id', niveauId);
          final pricingRows = await pQuery as List<dynamic>;

          for (final pr in pricingRows) {
            final cat = pr['category']?.toString();
            final amt = (pr['amount'] as num?)?.toDouble() ?? 0.0;
            final prSecId = pr['section_id']?.toString();
            if (prSecId != null && sectionId != null && prSecId != sectionId) continue;
            if (cat == null || cat == 'scolarite' || amt <= 0) continue;

            final alreadyHasPayment = uniquePayments.any((p) {
              final pCat = p['category'] ?? (p['payment_plans'] as Map?)?['category'];
              return pCat == cat;
            });

            if (!alreadyHasPayment) {
              uniquePayments.add({
                'id': 'pricing_$cat',
                'title': _getCategoryName(cat),
                'amount': amt,
                'status': 'pending',
                'category': cat,
                'due_date': DateTime.now().toIso8601String(),
                'paid_at': null,
                'payment_method': null,
                'is_synthetic': true,
                'payment_plans': {
                  'category': cat,
                  'plan_type': 'single',
                },
              });
            }
          }
        } catch (e) {
          debugPrint('Error loading payment pricing: $e');
        }
      }

      final effectivePayments = uniquePayments.isNotEmpty ? uniquePayments : seedPayments;
      final paidAmount = effectivePayments
          .where((p) => p['status'] == 'paid')
          .fold<double>(0, (sum, p) => sum + (p['amount'] as num? ?? 0).toDouble());
      final totalAmount = effectivePayments.isNotEmpty
          ? effectivePayments.fold<double>(0, (sum, p) => sum + (p['amount'] as num? ?? 0).toDouble())
          : widget.student.totalAmount;
      final paidPayments = effectivePayments.where((p) => p['status'] == 'paid').length;
      final totalPayments = effectivePayments.isNotEmpty ? effectivePayments.length : widget.student.totalPayments;

      setState(() {
        _paymentPlans = List<Map<String, dynamic>>.from(plansResponse);
        _payments = effectivePayments;
        _paidAmount = paidAmount > 0 ? paidAmount : widget.student.paidAmount;
        _totalAmount = totalAmount;
        _paidPayments = paidPayments > 0 ? paidPayments : widget.student.paidPayments;
        _totalPayments = totalPayments;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading payments: $e');
      final fallbackPayments = seedPayments;
      final paidAmount = fallbackPayments
          .where((p) => p['status'] == 'paid')
          .fold<double>(0, (sum, p) => sum + (p['amount'] as num? ?? 0).toDouble());
      final totalAmount = fallbackPayments.isNotEmpty
          ? fallbackPayments.fold<double>(0, (sum, p) => sum + (p['amount'] as num? ?? 0).toDouble())
          : widget.student.totalAmount;
      setState(() {
        _payments = fallbackPayments;
        _paidAmount = paidAmount > 0 ? paidAmount : widget.student.paidAmount;
        _totalAmount = totalAmount;
        _paidPayments = fallbackPayments.where((p) => p['status'] == 'paid').length;
        _totalPayments = fallbackPayments.isNotEmpty ? fallbackPayments.length : widget.student.totalPayments;
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredPayments {
    List<Map<String, dynamic>> result;
    if (_selectedCategory == 'all') {
      result = List.from(_payments);
    } else if (_selectedCategory == 'scolarite') {
      result = _payments.where((p) {
        final plan = p['payment_plans'] as Map<String, dynamic>?;
        final cat = p['category'] ?? plan?['category'];
        return _normalizeCategory(cat?.toString()) == 'scolarite';
      }).toList();
    } else {
      // 'autres' - other fees like Cantine, Uniforme, Transport, etc.
      result = _payments.where((p) {
        final plan = p['payment_plans'] as Map<String, dynamic>?;
        final cat = p['category'] ?? plan?['category'];
        return _normalizeCategory(cat?.toString()) != 'scolarite';
      }).toList();
    }
    result.sort((a, b) {
      int cmp;
      final da = DateTime.tryParse(a['due_date']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = DateTime.tryParse(b['due_date']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      switch (_detailSortKey) {
        case 'due_date_desc':
          cmp = db.compareTo(da);
          break;
        case 'amount_desc':
          cmp = ((b['amount'] as num?) ?? 0).compareTo((a['amount'] as num?) ?? 0);
          break;
        case 'amount_asc':
          cmp = ((a['amount'] as num?) ?? 0).compareTo((b['amount'] as num?) ?? 0);
          break;
        case 'pending_first':
          final sA = a['status'] == 'pending' ? 0 : 1;
          final sB = b['status'] == 'pending' ? 0 : 1;
          if (sA != sB) return sA.compareTo(sB);
          cmp = da.compareTo(db);
          break;
        case 'paid_first':
          final sA = a['status'] == 'paid' ? 0 : 1;
          final sB = b['status'] == 'paid' ? 0 : 1;
          if (sA != sB) return sA.compareTo(sB);
          cmp = da.compareTo(db);
          break;
        case 'due_date_asc':
        default:
          cmp = da.compareTo(db);
          break;
      }
      if (cmp != 0) return cmp;
      final dCmp = da.compareTo(db);
      if (dCmp != 0) return dCmp;
      return (a['id'] ?? '').toString().compareTo((b['id'] ?? '').toString());
    });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isFullPage) {
      return Container(
        color: const Color(0xFFF8FAFC),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? _buildStudentPaymentsSkeleton()
                  : _buildPaymentsListView(),
            ),
          ],
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 1080,
          height: 760,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _isLoading
                    ? _buildStudentPaymentsSkeleton()
                    : _buildPaymentsListView(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentPaymentsSkeleton() {
    return ShimmerLoading(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category pills skeleton
            Row(
              children: List.generate(5, (index) => Container(
                width: 90,
                height: 34,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
              )),
            ),
            const SizedBox(height: 20),
            // Table skeleton
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.slate200),
                ),
                child: Column(
                  children: [
                    Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppColors.slate50,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      child: Row(
                        children: [
                          Container(width: 20, height: 20, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                          const SizedBox(width: 20),
                          Container(width: 140, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                          const Spacer(),
                          Container(width: 80, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                          const SizedBox(width: 40),
                          Container(width: 80, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                          const SizedBox(width: 40),
                          Container(width: 70, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                          const SizedBox(width: 20),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 6,
                        separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.slate100),
                        itemBuilder: (_, __) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Container(width: 18, height: 18, decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(4))),
                              const SizedBox(width: 20),
                              Container(width: 32, height: 32, decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(8))),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(width: 120, height: 12, decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(4))),
                                  const SizedBox(height: 6),
                                  Container(width: 80, height: 10, decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(4))),
                                ],
                              ),
                              const Spacer(),
                              Container(width: 60, height: 14, decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(4))),
                              const SizedBox(width: 50),
                              Container(width: 70, height: 12, decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(4))),
                              const SizedBox(width: 40),
                              Container(width: 65, height: 22, decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(20))),
                              const SizedBox(width: 20),
                            ],
                          ),
                        ),
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

  Widget _buildHeader() {
    final progress = _totalAmount > 0 ? (_paidAmount / _totalAmount) * 100 : 0.0;
    final isComplete = progress >= 100;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 24),
      child: Row(
        children: [
          UserAvatar(
            name: widget.student.studentName,
            photoUrl: widget.student.studentPhotoUrl,
            radius: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.student.studentName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      widget.student.className ?? 'Non assigné',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.slate400,
                      ),
                    ),
                    if (_paymentPlans.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _buildPaymentModeBadge(),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Summary info - clean typography without pill background containers
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '${_paidAmount.toStringAsFixed(0)} TND ',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                ),
                TextSpan(
                  text: 'payé sur ${_totalAmount.toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 13, color: AppColors.slate500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$_paidPayments/$_totalPayments ',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                ),
                TextSpan(
                  text: 'paiements',
                  style: TextStyle(fontSize: 13, color: AppColors.slate500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isComplete ? Icons.check_circle_rounded : Icons.schedule_rounded,
                size: 14,
                color: isComplete ? const Color(0xFF10B981) : AppColors.slate400,
              ),
              const SizedBox(width: 4),
              Text(
                isComplete ? 'Soldé' : '${progress.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isComplete ? const Color(0xFF10B981) : const Color(0xFF374151),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: widget.isFullPage
                ? (widget.onBack ?? () => Navigator.pop(context))
                : () => Navigator.pop(context),
            icon: Icon(
              widget.isFullPage ? Icons.arrow_back_rounded : Icons.close_rounded,
              size: 20,
              color: AppColors.slate600,
            ),
            tooltip: widget.isFullPage ? 'Retour à la classe' : 'Fermer',
          ),
        ],
      ),
    );
  }

  Widget _headerPill(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.slate800,
              ),
            ),
            TextSpan(
              text: ' $label',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.slate400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentModeBadge() {
    // Get the most recent active plan type
    String planType = 'monthly';
    for (final p in _paymentPlans) {
      if (p['is_active'] != false) {
        planType = p['plan_type']?.toString() ?? 'monthly';
        break;
      }
    }
    if (_paymentPlans.isNotEmpty) {
      planType = _paymentPlans.first['plan_type']?.toString() ?? planType;
    }

    final String label;
    switch (planType) {
      case 'annual':
        label = 'Annuel';
        break;
      case 'semester':
      case 'trimester':
        label = 'Trimestriel';
        break;
      case 'semesterly':
        label = 'Semestriel';
        break;
      case 'monthly':
      default:
        label = 'Mensuel';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.slate100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildSummaryRow() {
    final s = widget.student;
    final progress = s.progressPercent;
    final isComplete = progress >= 100;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        children: [
          _summaryPill(
            '${s.paidAmount.toStringAsFixed(0)} TND',
            'payé sur ${s.totalAmount.toStringAsFixed(0)}',
          ),
          const SizedBox(width: 10),
          _summaryPill(
            '${s.paidPayments}/${s.totalPayments}',
            'paiements',
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isComplete
                  ? const Color(0xFF10B981).withOpacity(0.08)
                  : AppColors.slate50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isComplete ? Icons.check_circle_rounded : Icons.schedule_rounded,
                  size: 14,
                  color: isComplete ? const Color(0xFF10B981) : AppColors.slate400,
                ),
                const SizedBox(width: 6),
                Text(
                  isComplete ? 'Soldé' : '${progress.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isComplete ? const Color(0xFF10B981) : AppColors.slate600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryPill(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.slate800,
              ),
            ),
            TextSpan(
              text: ' $label',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.slate400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _progressColor(double progress) {
    if (progress >= 100) return const Color(0xFF10B981);
    if (progress >= 50) return const Color(0xFF655DD5);
    return AppColors.slate400;
  }

  static const _monthNames = [
    '', 'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];

  String _monthName(int month) => month >= 1 && month <= 12 ? _monthNames[month] : '';

  Widget _buildMonthlyTimelineView() {
    // Group payments by month
    final Map<String, List<Map<String, dynamic>>> paymentsByMonth = {};

    for (final payment in _payments) {
      final dueDate = DateTime.tryParse(payment['due_date'] ?? '');
      if (dueDate != null) {
        final monthKey =
            '${dueDate.year}-${dueDate.month.toString().padLeft(2, '0')}';
        paymentsByMonth.putIfAbsent(monthKey, () => []);
        paymentsByMonth[monthKey]!.add(payment);
      }
    }

    // Sort months
    final sortedMonths = paymentsByMonth.keys.toList()..sort();

    if (sortedMonths.isEmpty) {
      return _buildEmptyState('Aucun paiement programmé', Icons.calendar_today);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category filter
          _buildCategoryFilter(),
          const SizedBox(height: 20),
          // Monthly timeline
          ...sortedMonths.map((month) {
            final payments = paymentsByMonth[month]!;
            final date = DateTime.parse('$month-01');
            return _buildMonthSection(date, payments);
          }),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    int getCount(String cat) {
      if (cat == 'all') return _payments.length;
      if (cat == 'scolarite') {
        return _payments.where((p) {
          final plan = p['payment_plans'] as Map<String, dynamic>?;
          final c = p['category'] ?? plan?['category'];
          return _normalizeCategory(c?.toString()) == 'scolarite';
        }).length;
      }
      return _payments.where((p) {
        final plan = p['payment_plans'] as Map<String, dynamic>?;
        final c = p['category'] ?? plan?['category'];
        return _normalizeCategory(c?.toString()) != 'scolarite';
      }).length;
    }

    final categories = [
      ('all', 'Tous', Icons.apps_rounded),
      ('scolarite', 'Scolarité', Icons.school_outlined),
      ('autres', 'Autres paiements', Icons.receipt_long_rounded),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.slate100.withOpacity(0.8),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: categories.map((cat) {
            final isSelected = _selectedCategory == cat.$1;
            final count = getCount(cat.$1);

            return MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => setState(() => _selectedCategory = cat.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        cat.$3,
                        size: 14,
                        color: isSelected ? const Color(0xFF655DD5) : AppColors.textTertiary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        cat.$2,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected ? AppColors.textPrimary : AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected
                              ? AppColors.textSecondary
                              : AppColors.textTertiary.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildMonthSection(
    DateTime date,
    List<Map<String, dynamic>> payments,
  ) {
    final monthNames = [
      '',
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

    // Filter by category
    final filteredPayments = _selectedCategory == 'all'
        ? payments
        : payments.where((p) {
            final plan = p['payment_plans'] as Map<String, dynamic>?;
            return plan?['category'] == _selectedCategory;
          }).toList();

    if (filteredPayments.isEmpty) return const SizedBox.shrink();

    final totalMonth = filteredPayments.fold<double>(
      0,
      (sum, p) => sum + (p['amount'] as num? ?? 0).toDouble(),
    );
    final paidMonth = filteredPayments
        .where((p) => p['status'] == 'paid')
        .fold<double>(
          0,
          (sum, p) => sum + (p['amount'] as num? ?? 0).toDouble(),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF667EEA).withOpacity(0.1),
                  Colors.white,
                ],
              ),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: const Color(0xFF667EEA).withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF667EEA),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Center(
                    child: Text(
                      date.month.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${monthNames[date.month]} ${date.year}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${filteredPayments.length} paiement(s) • $paidMonth / $totalMonth TND',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Progress indicator for month
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: paidMonth >= totalMonth
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    paidMonth >= totalMonth
                        ? 'Complet'
                        : '${((paidMonth / totalMonth) * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Payment cards
          ...filteredPayments.map(
            (payment) => _buildPaymentTimelineCard(payment),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentTimelineCard(Map<String, dynamic> payment) {
    final status = payment['status'] ?? 'pending';
    final amount = (payment['amount'] as num? ?? 0).toDouble();
    final dueDate = DateTime.tryParse(payment['due_date'] ?? '');
    final paidAt = payment['paid_at'] != null
        ? DateTime.tryParse(payment['paid_at'])
        : null;
    final plan = payment['payment_plans'] as Map<String, dynamic>?;
    final category = payment['category'] ?? plan?['category'] ?? 'scolarite';

    final isOverdue =
        status == 'pending' &&
        dueDate != null &&
        dueDate.isBefore(DateTime.now());
    final isPaid = status == 'paid';

    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (isPaid) {
      statusColor = const Color(0xFF10B981);
      statusIcon = Icons.check_circle;
      statusText = 'Payé';
    } else if (isOverdue) {
      statusColor = const Color(0xFFEF4444);
      statusIcon = Icons.warning_rounded;
      statusText = 'En retard';
    } else {
      statusColor = const Color(0xFFF59E0B);
      statusIcon = Icons.access_time;
      statusText = 'En attente';
    }

    return InkWell(
      onTap: isPaid ? () => _showPaymentReceipt(payment) : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _selectedPaymentIds.contains(payment['id']?.toString())
                ? const Color(0xFF655DD5).withOpacity(0.4)
                : AppColors.slate100,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _selectedPaymentIds.contains(payment['id']?.toString()),
                onChanged: (value) {
                  final id = payment['id']?.toString();
                  if (id == null) return;
                  setState(() {
                    if (value == true) {
                      _selectedPaymentIds.add(id);
                    } else {
                      _selectedPaymentIds.remove(id);
                    }
                  });
                },
                activeColor: const Color(0xFF655DD5),
                side: BorderSide(color: AppColors.slate300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _getCategoryColor(category).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _getCategoryIcon(category),
                color: _getCategoryColor(category),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getCategoryName(category),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.slate800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dueDate != null
                        ? 'Échéance: ${dueDate.day} ${_monthName(dueDate.month)} ${dueDate.year}'
                        : 'Date non définie',
                    style: TextStyle(color: AppColors.slate400, fontSize: 12),
                  ),
                  if (paidAt != null)
                    Text(
                      'Payé le: ${paidAt.day} ${_monthName(paidAt.month)} ${paidAt.year}',
                      style: TextStyle(
                        color: AppColors.slate400,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${amount.toStringAsFixed(0)} TND',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.slate700,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 11, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
            if (!isPaid)
              PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz, size: 18, color: AppColors.slate400),
                tooltip: '',
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 8,
                offset: const Offset(-8, 32),
                onSelected: (action) => _handlePaymentAction(action, payment),
                itemBuilder: (context) => [
                  _buildPopupItem('mark_paid', Icons.check_circle_outline_rounded, 'Marquer payé', const Color(0xFF10B981)),
                  _buildPopupItem('edit', Icons.edit_outlined, 'Modifier', const Color(0xFF655DD5)),
                  const PopupMenuDivider(height: 1),
                  _buildPopupItem('cancel', Icons.close_rounded, 'Annuler', AppColors.error),
                ],
              ),
            if (isPaid)
              PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz, size: 18, color: AppColors.slate400),
                tooltip: '',
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 8,
                offset: const Offset(-8, 32),
                onSelected: (action) => _handlePaymentAction(action, payment),
                itemBuilder: (context) => [
                  _buildPopupItem('view_receipt', Icons.receipt_long_rounded, 'Voir reçu', const Color(0xFF3B82F6)),
                  _buildPopupItem('mark_unpaid', Icons.cancel_outlined, 'Marquer impayé', const Color(0xFFF59E0B)),
                ],
              ),
          ],
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
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: value == 'cancel' ? AppColors.error : AppColors.slate700,
            ),
          ),
        ],
      ),
    );
  }

  void _handlePaymentAction(String action, Map<String, dynamic> payment) async {
    final paymentId = payment['id'];

    switch (action) {
      case 'mark_paid':
        await _markPaymentAsPaid(paymentId, payment);
        break;
      case 'mark_unpaid':
        await _markPaymentAsUnpaid(paymentId);
        break;
      case 'view_receipt':
        _showPaymentReceipt(payment);
        break;
      case 'edit':
        await _showEditPaymentDialog(payment);
        break;
      case 'cancel':
        await _cancelPayment(paymentId);
        break;
    }
  }

  Future<void> _markPaymentAsPaid(dynamic paymentId, [Map<String, dynamic>? payment]) async {
    try {
      final supabase = Supabase.instance.client;
      if (payment != null && payment['is_synthetic'] == true) {
        final enrollments = await supabase
            .from('enrollments')
            .select('id')
            .eq('user_id', widget.student.studentId);
        final enrollId = (enrollments as List).isNotEmpty ? enrollments.first['id'] : null;
        if (enrollId != null) {
          await supabase.from('payments').insert({
            'enrollment_id': enrollId,
            'amount': payment['amount'] ?? 0,
            'status': 'paid',
            'paid_at': DateTime.now().toIso8601String(),
            'due_date': payment['due_date'] ?? DateTime.now().toIso8601String(),
            'payment_method': 'cash',
            'notes': payment['category'] ?? 'Autre paiement',
          });
        }
      } else {
        await supabase
            .from('payments')
            .update({
              'status': 'paid',
              'paid_at': DateTime.now().toIso8601String(),
            })
            .eq('id', paymentId);
      }

      final payIdStr = paymentId.toString();
      for (final p in _payments) {
        if (p['id']?.toString() == payIdStr) {
          p['status'] = 'paid';
          p['paid_at'] = DateTime.now().toIso8601String();
        }
      }
      for (int i = 0; i < widget.student.plans.length; i++) {
        final plan = widget.student.plans[i];
        final updatedPayments = plan.payments.map((pay) {
          if (pay.id == payIdStr) {
            return pay.copyWith(status: PaymentStatus.paid, paidAt: DateTime.now());
          }
          return pay;
        }).toList();
        try {
          widget.student.plans[i] = plan.copyWith(payments: updatedPayments);
        } catch (_) {}
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paiement marqué comme payé'),
          backgroundColor: Color(0xFF10B981),
        ),
      );

      await _loadStudentPayments();
      ref.read(paymentsProvider.notifier).refresh();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFriendlyError.format(
              e,
              fallback: 'Unable to mark this payment as paid right now. Please try again.',
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _markPaymentAsUnpaid(String paymentId) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('payments')
          .update({
            'status': 'pending',
            'paid_at': null,
          })
          .eq('id', paymentId);

      final payIdStr = paymentId.toString();
      for (final p in _payments) {
        if (p['id']?.toString() == payIdStr) {
          p['status'] = 'pending';
          p['paid_at'] = null;
        }
      }
      for (int i = 0; i < widget.student.plans.length; i++) {
        final plan = widget.student.plans[i];
        final updatedPayments = plan.payments.map((pay) {
          if (pay.id == payIdStr) {
            return pay.copyWith(status: PaymentStatus.pending, paidAt: null);
          }
          return pay;
        }).toList();
        try {
          widget.student.plans[i] = plan.copyWith(payments: updatedPayments);
        } catch (_) {}
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paiement marqué comme impayé'),
          backgroundColor: Color(0xFFF59E0B),
        ),
      );

      await _loadStudentPayments();
      ref.read(paymentsProvider.notifier).refresh();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFriendlyError.format(
              e,
              fallback: 'Unable to mark this payment as unpaid right now. Please try again.',
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _cancelPayment(String paymentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => BackdropFilter(
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
              const Text('Confirmer l\'annulation', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          content: const Text(
            'Voulez-vous vraiment annuler ce paiement ? Cette action est irréversible.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.warning_outlined, size: 16),
                  label: const Text('Oui, annuler', style: TextStyle(fontWeight: FontWeight.w700)),
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

    if (confirm != true) return;

    try {
      final supabase = SupabaseConfig.adminClient;
      await supabase
          .from('payments')
          .update({'status': 'pending', 'paid_at': null})
          .eq('id', paymentId);

      await _loadStudentPayments();
      ref.invalidate(paymentsProvider);
    } catch (e) {
      debugPrint('Error canceling payment: $e');
    }
  }

  Future<void> _showEditPaymentDialog(Map<String, dynamic> payment) async {
    final amountController = TextEditingController(
      text: (payment['amount'] as num? ?? 0).toString(),
    );
    final dueDate = DateTime.tryParse(payment['due_date'] ?? '');
    DateTime? selectedDate = dueDate;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEECFB),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.edit_rounded, color: Color(0xFF655DD5), size: 18),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Modifier le paiement', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    Text('Modifier le montant ou l\'échéance', style: TextStyle(fontSize: 12, color: AppColors.textTertiary, fontWeight: FontWeight.normal)),
                  ],
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('MONTANT (TND)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: 'Ex: 150.000',
                      prefixIcon: const Icon(Icons.payments_outlined, size: 18, color: Color(0xFF655DD5)),
                      suffixText: 'TND',
                      suffixStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF655DD5)),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF655DD5), width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('DATE D\'ÉCHÉANCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 18, color: Color(0xFF655DD5)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              selectedDate != null
                                  ? DateFormat('d MMMM yyyy', 'fr_FR').format(selectedDate!)
                                  : 'Sélectionner une date',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: selectedDate != null
                                    ? AppColors.textPrimary
                                    : AppColors.textTertiary,
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            actions: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context, {
                        'amount': double.tryParse(amountController.text) ?? 0,
                        'due_date': selectedDate?.toIso8601String(),
                      });
                    },
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF655DD5),
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
      ),
    );

    if (result != null) {
      try {
        final paymentId = payment['id'].toString();
        if (paymentId.startsWith('pricing_')) {
          final enrollments = await SupabaseConfig.adminClient
              .from('enrollments')
              .select('id')
              .eq('user_id', widget.student.studentId);
          final enrollId = (enrollments as List).isNotEmpty ? enrollments.first['id'] : null;
          if (enrollId != null) {
            await SupabaseConfig.adminClient.from('payments').insert({
              'enrollment_id': enrollId,
              'amount': result['amount'],
              'status': 'pending',
              'due_date': result['due_date'],
              'payment_method': 'cash',
              'notes': payment['category'] ?? 'Autre paiement',
            });
          }
        } else {
          await SupabaseConfig.adminClient.from('payments').update({
            'amount': result['amount'],
            if (result['due_date'] != null) 'due_date': result['due_date'],
          }).eq('id', paymentId);
        }

        await _loadStudentPayments();
        ref.invalidate(paymentsProvider);
      } catch (e) {
        debugPrint('Error updating payment: $e');
      }
    }
  }

  void _showPaymentReceipt(Map<String, dynamic> payment) {
    final amount = (payment['amount'] as num? ?? 0).toDouble();
    final paidAt = payment['paid_at'] != null
        ? DateTime.tryParse(payment['paid_at'])
        : null;
    final reference = payment['reference'] ?? 'N/A';
    final method = payment['method'] ?? 'cash';
    final plan = payment['payment_plans'] as Map<String, dynamic>?;
    final category = plan?['category'] ?? 'scolarite';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 380,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long_rounded, size: 18, color: AppColors.slate400),
                      const SizedBox(width: 8),
                      const Text(
                        'Reçu de Paiement',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close_rounded, size: 18, color: AppColors.slate400),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          color: Color(0xFF655DD5),
                          size: 36,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${amount.toStringAsFixed(0)} TND',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 24,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Paiement effectué',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.slate400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Column(
                    children: [
                      _receiptRow('Étudiant', widget.student.studentName),
                      _receiptRow('Catégorie', _getCategoryName(category)),
                      _receiptRow('Méthode', _getPaymentMethodName(method)),
                      _receiptRow('Référence', reference),
                      if (paidAt != null)
                        _receiptRow(
                          'Date',
                          DateFormat('d MMM yyyy', 'fr_FR').format(paidAt),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.slate200),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Fermer',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.slate500,
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
  }

  Widget _receiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: AppColors.slate400),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.slate700,
            ),
          ),
        ],
      ),
    );
  }

  String _getPaymentMethodName(String method) {
    switch (method) {
      case 'cash':
        return 'Espèces';
      case 'bank_transfer':
        return 'Virement bancaire';
      case 'check':
        return 'Chèque';
      case 'card':
        return 'Carte bancaire';
      default:
        return method;
    }
  }

  Widget _buildPaymentsListView() {
    if (_filteredPayments.isEmpty && _payments.isEmpty) {
      return _buildEmptyState('Aucun paiement trouvé', Icons.payments);
    }

    final allFilteredSelected = _filteredPayments.isNotEmpty &&
        _filteredPayments.every((p) => _selectedPaymentIds.contains(p['id']?.toString()));

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  Expanded(child: _buildCategoryFilter()),
                  const SizedBox(width: 8),
                  AdminSortDropdown<String>(
                    value: _detailSortKey,
                    tooltip: 'Trier les échéances',
                    height: 32,
                    radius: 8,
                    onChanged: (v) => setState(() => _detailSortKey = v),
                    options: const [
                      SortOption(value: 'due_date_asc', label: 'Échéance (Croissant)', icon: Icons.calendar_today_outlined),
                      SortOption(value: 'due_date_desc', label: 'Échéance (Décroissant)', icon: Icons.calendar_today_outlined),
                      SortOption(value: 'amount_desc', label: 'Montant (Plus élevé)', icon: Icons.arrow_upward),
                      SortOption(value: 'amount_asc', label: 'Montant (Moins élevé)', icon: Icons.arrow_downward),
                      SortOption(value: 'pending_first', label: 'En attente d’abord', icon: Icons.schedule_rounded),
                      SortOption(value: 'paid_first', label: 'Payés d’abord', icon: Icons.check_circle_outline),
                    ],
                  ),
                  if (_selectedPaymentIds.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${_selectedPaymentIds.length} sélectionné(s)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.slate600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _filteredPayments.isEmpty
                  ? Center(
                      child: Text(
                        'Aucun paiement pour cette catégorie',
                        style: TextStyle(fontSize: 13, color: AppColors.slate400),
                      ),
                    )
                  : Container(
                      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border.withOpacity(0.3)),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.shadow.withOpacity(0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final w = constraints.maxWidth;
                            const checkboxW = 48.0;
                            const amountW = 105.0;
                            const paidAtW = 120.0;
                            const statusW = 120.0;
                            const actionsW = 48.0;
                            final titleW = (w - checkboxW - amountW - paidAtW - statusW - actionsW).clamp(180.0, double.infinity);

                            return SingleChildScrollView(
                              padding: const EdgeInsets.only(bottom: 60),
                              child: DataTable(
                                columnSpacing: 0,
                                horizontalMargin: 0,
                                dataRowMinHeight: 52,
                                dataRowMaxHeight: 56,
                                headingRowHeight: 44,
                                headingRowColor: WidgetStateProperty.all(Colors.white),
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
                                        child: Checkbox(
                                          value: allFilteredSelected,
                                          tristate: true,
                                          onChanged: (value) {
                                            setState(() {
                                              if (allFilteredSelected) {
                                                for (final p in _filteredPayments) {
                                                  final id = p['id']?.toString();
                                                  if (id != null) _selectedPaymentIds.remove(id);
                                                }
                                              } else {
                                                for (final p in _filteredPayments) {
                                                  final id = p['id']?.toString();
                                                  if (id != null) _selectedPaymentIds.add(id);
                                                }
                                              }
                                            });
                                          },
                                          activeColor: const Color(0xFF655DD5),
                                          side: BorderSide(color: AppColors.slate300),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: SizedBox(
                                      width: titleW,
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 16),
                                        child: Text('CATÉGORIE / ÉCHÉANCE'),
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: SizedBox(
                                      width: amountW,
                                      child: const Center(child: Text('MONTANT')),
                                    ),
                                  ),
                                  DataColumn(
                                    label: SizedBox(
                                      width: paidAtW,
                                      child: const Center(child: Text('PAYÉ LE')),
                                    ),
                                  ),
                                  DataColumn(
                                    label: SizedBox(
                                      width: statusW,
                                      child: const Center(child: Text('STATUT')),
                                    ),
                                  ),
                                  DataColumn(
                                    label: SizedBox(
                                      width: actionsW,
                                      child: Container(),
                                    ),
                                  ),
                                ],
                                rows: _filteredPayments.map((payment) {
                                  final id = payment['id']?.toString() ?? '';
                                  final isSelected = _selectedPaymentIds.contains(id);
                                  final status = payment['status'] ?? 'pending';
                                  final amount = (payment['amount'] as num? ?? 0).toDouble();
                                  final dueDate = DateTime.tryParse(payment['due_date'] ?? '');
                                  final paidAt = payment['paid_at'] != null ? DateTime.tryParse(payment['paid_at']) : null;
                                  final plan = payment['payment_plans'] as Map<String, dynamic>?;
                                  final category = payment['category'] ?? plan?['category'] ?? 'scolarite';

                                  final isOverdue = status == 'pending' && dueDate != null && dueDate.isBefore(DateTime.now());
                                  final isPaid = status == 'paid';

                                  Color statusColor;
                                  IconData statusIcon;
                                  String statusText;

                                  if (isPaid) {
                                    statusColor = const Color(0xFF10B981);
                                    statusIcon = Icons.check_circle;
                                    statusText = 'Payé';
                                  } else if (isOverdue) {
                                    statusColor = const Color(0xFFEF4444);
                                    statusIcon = Icons.warning_rounded;
                                    statusText = 'En retard';
                                  } else {
                                    statusColor = const Color(0xFFF59E0B);
                                    statusIcon = Icons.access_time;
                                    statusText = 'En attente';
                                  }

                                  return DataRow(
                                    selected: isSelected,
                                    color: WidgetStateProperty.resolveWith<Color?>((states) {
                                      if (isSelected) return const Color(0xFF655DD5).withOpacity(0.04);
                                      if (states.contains(WidgetState.hovered)) return const Color(0xFFF9FAFB);
                                      return null;
                                    }),
                                    cells: [
                                      DataCell(
                                        SizedBox(
                                          width: checkboxW,
                                          child: Center(
                                            child: Checkbox(
                                              value: isSelected,
                                              onChanged: (val) {
                                                setState(() {
                                                  if (val == true) {
                                                    _selectedPaymentIds.add(id);
                                                  } else {
                                                    _selectedPaymentIds.remove(id);
                                                  }
                                                });
                                              },
                                              activeColor: const Color(0xFF655DD5),
                                              side: BorderSide(color: AppColors.slate300),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: titleW,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 16),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 32,
                                                  height: 32,
                                                  decoration: BoxDecoration(
                                                    color: _getCategoryColor(category).withOpacity(0.08),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Icon(
                                                    _getCategoryIcon(category),
                                                    color: _getCategoryColor(category),
                                                    size: 16,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Text(
                                                        _getCategoryName(category),
                                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        dueDate != null
                                                            ? 'Échéance: ${DateFormat('d MMMM yyyy', 'fr_FR').format(dueDate)}'
                                                            : 'Date non définie',
                                                        style: TextStyle(color: AppColors.slate400, fontSize: 11),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        onTap: isPaid ? () => _showPaymentReceipt(payment) : null,
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: amountW,
                                          child: Center(
                                            child: Text(
                                              '${amount.toStringAsFixed(0)} TND',
                                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: paidAtW,
                                          child: Center(
                                            child: Text(
                                              paidAt != null
                                                  ? DateFormat('d MMM yyyy', 'fr_FR').format(paidAt)
                                                  : '—',
                                              style: TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: statusW,
                                          child: Center(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: statusColor.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(statusIcon, size: 11, color: statusColor),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    statusText,
                                                    style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: actionsW,
                                          child: Center(
                                            child: PopupMenuButton<String>(
                                              icon: Icon(Icons.more_horiz, size: 18, color: AppColors.slate400),
                                              tooltip: '',
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              elevation: 8,
                                              offset: const Offset(-8, 32),
                                              onSelected: (action) => _handlePaymentAction(action, payment),
                                              itemBuilder: (context) => [
                                                if (!isPaid) ...[
                                                  _buildPopupItem('mark_paid', Icons.check_circle_outline_rounded, 'Marquer payé', const Color(0xFF10B981)),
                                                  _buildPopupItem('edit', Icons.edit_outlined, 'Modifier', const Color(0xFF655DD5)),
                                                  const PopupMenuDivider(height: 1),
                                                  _buildPopupItem('cancel', Icons.close_rounded, 'Annuler', AppColors.error),
                                                ],
                                                if (isPaid) ...[
                                                  _buildPopupItem('view_receipt', Icons.receipt_long_rounded, 'Voir reçu', const Color(0xFF3B82F6)),
                                                  _buildPopupItem('mark_unpaid', Icons.cancel_outlined, 'Marquer impayé', const Color(0xFFF59E0B)),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ],
        ),
        // Floating bulk action bar
        if (_selectedPaymentIds.isNotEmpty)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF655DD5).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_selectedPaymentIds.length}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFA5B4FC),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'paiement(s) sélectionné(s)',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ),
                  // Mark as paid
                  _bulkActionButton(
                    icon: Icons.check_circle_outline_rounded,
                    label: 'Marquer payé',
                    color: const Color(0xFF10B981),
                    onPressed: () => _bulkMarkPaid(),
                  ),
                  const SizedBox(width: 8),
                  // Mark as unpaid
                  _bulkActionButton(
                    icon: Icons.cancel_outlined,
                    label: 'Marquer impayé',
                    color: const Color(0xFFF59E0B),
                    onPressed: () => _bulkMarkUnpaid(),
                  ),
                  const SizedBox(width: 8),
                  // Delete
                  _bulkActionButton(
                    icon: Icons.delete_outline_rounded,
                    label: 'Supprimer',
                    color: const Color(0xFFEF4444),
                    onPressed: () => _bulkDelete(),
                  ),
                  const SizedBox(width: 8),
                  // Clear selection
                  _bulkActionButton(
                    icon: Icons.close_rounded,
                    label: '',
                    color: AppColors.slate400,
                    onPressed: () => setState(() => _selectedPaymentIds.clear()),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _bulkActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _bulkMarkPaid() async {
    final ids = _selectedPaymentIds.toList();
    if (ids.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final realIds = ids.where((id) => !id.startsWith('pricing_')).toList();
      final syntheticIds = ids.where((id) => id.startsWith('pricing_')).toList();
      final nowIso = DateTime.now().toIso8601String();
      final now = DateTime.now();

      // 1. Optimistic update in-memory _payments
      for (final p in _payments) {
        if (ids.contains(p['id']?.toString())) {
          p['status'] = 'paid';
          p['paid_at'] = nowIso;
        }
      }

      // 2. Update widget.student.plans in memory
      for (int i = 0; i < widget.student.plans.length; i++) {
        final plan = widget.student.plans[i];
        final updatedPayments = plan.payments.map((pay) {
          if (ids.contains(pay.id)) {
            return pay.copyWith(
              status: PaymentStatus.paid,
              paidAt: now,
            );
          }
          return pay;
        }).toList();
        try {
          widget.student.plans[i] = plan.copyWith(payments: updatedPayments);
        } catch (_) {}
      }

      // 3. Update Supabase
      if (realIds.isNotEmpty) {
        try {
          await SupabaseConfig.adminClient
              .from('payments')
              .update({'status': 'paid', 'paid_at': nowIso})
              .inFilter('id', realIds);
        } catch (e) {
          debugPrint('Error updating payments with adminClient: $e');
          try {
            await Supabase.instance.client
                .from('payments')
                .update({'status': 'paid', 'paid_at': nowIso})
                .inFilter('id', realIds);
          } catch (e2) {
            debugPrint('Fallback Supabase client error: $e2');
          }
        }
      }

      if (syntheticIds.isNotEmpty) {
        try {
          final enrollments = await SupabaseConfig.adminClient
              .from('enrollments')
              .select('id')
              .eq('user_id', widget.student.studentId);
          final enrollId = (enrollments as List).isNotEmpty ? enrollments.first['id'] : null;
          if (enrollId != null) {
            final toInsert = syntheticIds.map((sId) {
              final p = _payments.firstWhere(
                (item) => item['id'] == sId,
                orElse: () => <String, dynamic>{},
              );
              return {
                'enrollment_id': enrollId,
                'amount': p['amount'] ?? 0,
                'status': 'paid',
                'paid_at': nowIso,
                'due_date': p['due_date'] ?? nowIso,
                'payment_method': 'cash',
                'notes': p['category'] ?? 'Autre paiement',
              };
            }).toList();
            await SupabaseConfig.adminClient.from('payments').insert(toInsert);
          }
        } catch (e) {
          debugPrint('Error inserting synthetic payments: $e');
        }
      }

      setState(() {
        _selectedPaymentIds.clear();
      });

      await _loadStudentPayments();

      try {
        await ref.read(paymentsProvider.notifier).bulkMarkAsPaid(realIds);
      } catch (_) {
        ref.invalidate(paymentsProvider);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${ids.length} paiement${ids.length > 1 ? 's' : ''} marqué${ids.length > 1 ? 's' : ''} comme payé${ids.length > 1 ? 's' : ''}'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error bulk marking paid: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _bulkMarkUnpaid() async {
    final ids = _selectedPaymentIds.toList();
    if (ids.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final realIds = ids.where((id) => !id.startsWith('pricing_')).toList();

      // 1. Optimistic update in-memory _payments
      for (final p in _payments) {
        if (ids.contains(p['id']?.toString())) {
          p['status'] = 'pending';
          p['paid_at'] = null;
        }
      }

      // 2. Update widget.student.plans in memory
      for (int i = 0; i < widget.student.plans.length; i++) {
        final plan = widget.student.plans[i];
        final updatedPayments = plan.payments.map((pay) {
          if (ids.contains(pay.id)) {
            return pay.copyWith(
              status: PaymentStatus.pending,
              paidAt: null,
            );
          }
          return pay;
        }).toList();
        try {
          widget.student.plans[i] = plan.copyWith(payments: updatedPayments);
        } catch (_) {}
      }

      // 3. Update Supabase
      if (realIds.isNotEmpty) {
        try {
          await SupabaseConfig.adminClient
              .from('payments')
              .update({'status': 'pending', 'paid_at': null})
              .inFilter('id', realIds);
        } catch (e) {
          debugPrint('Error updating payments with adminClient: $e');
          try {
            await Supabase.instance.client
                .from('payments')
                .update({'status': 'pending', 'paid_at': null})
                .inFilter('id', realIds);
          } catch (e2) {
            debugPrint('Fallback Supabase client error: $e2');
          }
        }
      }

      setState(() {
        _selectedPaymentIds.clear();
      });

      await _loadStudentPayments();

      try {
        await ref.read(paymentsProvider.notifier).bulkMarkAsUnpaid(realIds);
      } catch (_) {
        ref.invalidate(paymentsProvider);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${ids.length} paiement${ids.length > 1 ? 's' : ''} marqué${ids.length > 1 ? 's' : ''} comme impayé${ids.length > 1 ? 's' : ''}'),
            backgroundColor: const Color(0xFFF59E0B),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error bulk marking unpaid: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _bulkDelete() async {
    final count = _selectedPaymentIds.length;
    if (count == 0) return;

    final confirm = await showDialog<bool>(
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
                'Supprimer $count paiement${count > 1 ? 's' : ''} ?',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ),
          content: Text(
            'Cette action est irréversible. $count paiement${count > 1 ? 's seront supprimés' : ' sera supprimé'} définitivement.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
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

    if (confirm != true) return;

    final ids = _selectedPaymentIds.toList();
    setState(() => _isLoading = true);
    try {
      final realIds = ids.where((id) => !id.startsWith('pricing_')).toList();

      // 1. Remove from local _payments
      _payments.removeWhere((p) => ids.contains(p['id']?.toString()));

      // 2. Remove from widget.student.plans in memory
      for (int i = 0; i < widget.student.plans.length; i++) {
        final plan = widget.student.plans[i];
        final updatedPayments = plan.payments.where((pay) => !ids.contains(pay.id)).toList();
        try {
          widget.student.plans[i] = plan.copyWith(payments: updatedPayments);
        } catch (_) {}
      }

      // 3. Delete from Supabase
      if (realIds.isNotEmpty) {
        try {
          await SupabaseConfig.adminClient.from('payments').delete().inFilter('id', realIds);
        } catch (e) {
          debugPrint('Error deleting payments with adminClient: $e');
          try {
            await Supabase.instance.client.from('payments').delete().inFilter('id', realIds);
          } catch (e2) {
            debugPrint('Fallback Supabase client error: $e2');
          }
        }
      }

      setState(() {
        _selectedPaymentIds.clear();
      });

      await _loadStudentPayments();

      try {
        await ref.read(paymentsProvider.notifier).refresh();
      } catch (_) {
        ref.invalidate(paymentsProvider);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count paiement${count > 1 ? 's' : ''} supprimé${count > 1 ? 's' : ''}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error bulk deleting: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildPaymentPlansView() {
    if (_paymentPlans.isEmpty) {
      return _buildEmptyState(
        'Aucun plan de paiement',
        Icons.account_balance_wallet,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _paymentPlans.length,
      itemBuilder: (context, index) =>
          _buildPaymentPlanCard(_paymentPlans[index]),
    );
  }

  Widget _buildPaymentPlanCard(Map<String, dynamic> plan) {
    final planType = plan['plan_type'] ?? 'monthly';
    final category = plan['category'] ?? 'scolarite';
    final totalAmount = (plan['amount_total'] as num? ?? 0).toDouble();
    final payments = List<Map<String, dynamic>>.from(plan['payments'] ?? []);
    final paidAmount = payments
        .where((p) => p['status'] == 'paid')
        .fold<double>(
          0,
          (sum, p) => sum + (p['amount'] as num? ?? 0).toDouble(),
        );
    final progress = totalAmount > 0 ? (paidAmount / totalAmount * 100) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _getCategoryColor(category).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  _getCategoryIcon(category),
                  color: _getCategoryColor(category),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getCategoryName(category),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      _getPlanTypeName(planType),
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${totalAmount.toStringAsFixed(0)} TND',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    '${payments.length} échéances',
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Progress bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${paidAmount.toStringAsFixed(0)} / ${totalAmount.toStringAsFixed(0)} TND',
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                  ),
                  Text(
                    '${progress.toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: _progressColor(progress),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: LinearProgressIndicator(
                  value: progress / 100,
                  minHeight: 8,
                  backgroundColor: AppColors.slate200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _progressColor(progress),
                  ),
                ),
              ),
            ],
          ),
          // Payment status badges
          if (payments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: payments.take(12).map((p) {
                final status = p['status'] ?? 'pending';
                final isPaid = status == 'paid';
                final isOverdue =
                    status == 'pending' &&
                    DateTime.tryParse(
                          p['due_date'] ?? '',
                        )?.isBefore(DateTime.now()) ==
                        true;

                return Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isPaid
                        ? const Color(0xFF10B981)
                        : (isOverdue
                              ? const Color(0xFFEF4444)
                              : AppColors.slate200),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPaid
                        ? Icons.check
                        : (isOverdue ? Icons.priority_high : Icons.access_time),
                    color: Colors.white,
                    size: 16,
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.schedule, size: 14, color: AppColors.textTertiary),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _showChangeFrequencyDialog(plan),
                child: Text(
                  'Modifier la fréquence',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF655DD5),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showChangeFrequencyDialog(Map<String, dynamic> plan) {
    final currentType = _mapDbPlanTypeToUi(plan['plan_type']?.toString() ?? 'monthly');
    final planId = plan['id']?.toString() ?? '';
    final totalAmount = (plan['amount_total'] as num?)?.toDouble() ?? 0;
    String selectedType = currentType;

    final planTypes = [
      ('monthly', 'Mensuel', '9x', Icons.calendar_view_month_rounded),
      ('semester', 'Trimestriel', '3x', Icons.view_week_rounded),
      ('semesterly', 'Semestriel', '2x', Icons.view_day_rounded),
      ('annual', 'Annuel', '1x', Icons.event_available_rounded),
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF655DD5).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.schedule, color: Color(0xFF655DD5), size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Modifier la fréquence',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Les paiements existants seront supprimés et recalculés selon la nouvelle fréquence.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: planTypes.map((pt) {
                    final isSelected = selectedType == pt.$1;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: pt != planTypes.last ? 8 : 0),
                        child: GestureDetector(
                          onTap: () => setDialogState(() => selectedType = pt.$1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF655DD5).withOpacity(0.05) : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF655DD5) : const Color(0xFFE5E7EB),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(pt.$4, color: isSelected ? const Color(0xFF655DD5) : const Color(0xFF6B7280), size: 22),
                                const SizedBox(height: 6),
                                Text(
                                  pt.$2,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected ? const Color(0xFF655DD5) : const Color(0xFF374151),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  pt.$3,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isSelected ? const Color(0xFF655DD5).withOpacity(0.7) : AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Annuler'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: selectedType == currentType
                          ? null
                          : () async {
                              Navigator.pop(ctx);
                              await _applyFrequencyChange(planId, selectedType, totalAmount);
                            },
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Appliquer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF655DD5),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  Future<void> _applyFrequencyChange(String planId, String newUiType, double totalAmount) async {
    try {
      final supabase = Supabase.instance.client;
      final dbType = _mapUiPlanTypeToDb(newUiType);

      setState(() => _isLoading = true);

      // 1. Update the plan_type on the plan
      await supabase
          .from('payment_plans')
          .update({'plan_type': dbType})
          .eq('id', planId);

      // 2. Delete ALL existing payments for this plan
      await supabase
          .from('payments')
          .delete()
          .eq('payment_plan_id', planId);

      // 3. Determine number of payments
      int numPayments;
      switch (newUiType) {
        case 'semester':
          numPayments = 3;
          break;
        case 'semesterly':
          numPayments = 2;
          break;
        case 'annual':
          numPayments = 1;
          break;
        case 'monthly':
        default:
          numPayments = 9;
          break;
      }

      // 4. Load the enrollment to get academic year dates
      final planData = await supabase
          .from('payment_plans')
          .select('enrollment_id')
          .eq('id', planId)
          .single();

      final enrollmentId = planData['enrollment_id']?.toString();
      if (enrollmentId == null) {
        throw Exception('Enrollment not found');
      }

      final enrollment = await supabase
          .from('enrollments')
          .select('academic_year_id, classes(niveau_id)')
          .eq('id', enrollmentId)
          .single();

      final academicYearId = enrollment['academic_year_id']?.toString();

      DateTime startDate = DateTime(DateTime.now().year, 9, 1);
      int totalMonths = 9;

      if (academicYearId != null) {
        final yearData = await supabase
            .from('academic_years')
            .select('start_date, end_date')
            .eq('id', academicYearId)
            .maybeSingle();

        if (yearData != null) {
          final s = DateTime.tryParse(yearData['start_date']?.toString() ?? '');
          final e = DateTime.tryParse(yearData['end_date']?.toString() ?? '');
          if (s != null && e != null && e.isAfter(s)) {
            startDate = DateTime(s.year, s.month, 1);
            totalMonths = (e.year - s.year) * 12 + (e.month - s.month) + 1;
          }
        }
      }

      // 5. Create new payments
      final paymentAmount = totalAmount / numPayments;
      final newPayments = <Map<String, dynamic>>[];

      for (int i = 0; i < numPayments; i++) {
        DateTime dueDate;
        if (newUiType == 'monthly') {
          dueDate = DateTime(startDate.year, startDate.month + i, 1);
        } else {
          final monthsPerPart = (totalMonths / numPayments).ceil();
          dueDate = DateTime(startDate.year, startDate.month + (i * monthsPerPart), 1);
        }

        newPayments.add({
          'payment_plan_id': planId,
          'amount': paymentAmount,
          'due_date': dueDate.toIso8601String(),
          'status': 'pending',
        });
      }

      if (newPayments.isNotEmpty) {
        await supabase.from('payments').insert(newPayments);
      }

      // 6. Reload
      await _loadStudentPayments();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fréquence changée en ${_getPlanTypeName(newUiType)}'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error changing frequency: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFriendlyError.format(
                e,
                fallback: 'Unable to update the payment schedule right now. Please try again.',
              ),
            ),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  String _getPlanTypeName(String planType) {
    switch (planType) {
      case 'monthly':
        return 'Paiement mensuel (9x)';
      case 'semester':
      case 'trimester':
        return 'Paiement trimestriel (3x)';
      case 'semesterly':
        return 'Paiement semestriel (2x)';
      case 'annual':
        return 'Paiement annuel (1x)';
      default:
        return planType;
    }
  }

  String _normalizeCategory(String? category) {
    if (category == null || category.trim().isEmpty) return 'autres';
    final c = category.toLowerCase().trim().replaceAll('é', 'e').replaceAll('è', 'e');
    if (c.contains('scolar') || c.contains('tuition')) return 'scolarite';
    if (c.contains('transp') || c.contains('bus')) return 'transport';
    if (c.contains('cantin') || c.contains('restau') || c.contains('repas')) return 'cantine';
    if (c.contains('inscript') || c.contains('regist') || c.contains('frais')) return 'inscription';
    if (c.contains('uniform') || c.contains('tenue') || c.contains('vetement') || c.contains('vêtement')) return 'uniforme';
    if (c.contains('activit') || c.contains('sport') || c.contains('club') || c.contains('culture')) return 'activites';
    return 'autres';
  }

  Color _getCategoryColor(String category) {
    switch (_normalizeCategory(category)) {
      case 'scolarite':
        return const Color(0xFF3B82F6);
      case 'transport':
        return const Color(0xFF10B981);
      case 'cantine':
        return const Color(0xFFF59E0B);
      case 'inscription':
        return const Color(0xFF8B5CF6);
      case 'uniforme':
        return const Color(0xFFEC4899);
      case 'activites':
        return const Color(0xFF14B8A6);
      case 'autres':
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (_normalizeCategory(category)) {
      case 'scolarite':
        return Icons.school_rounded;
      case 'transport':
        return Icons.directions_bus_rounded;
      case 'cantine':
        return Icons.restaurant_rounded;
      case 'inscription':
        return Icons.assignment_rounded;
      case 'uniforme':
        return Icons.checkroom_rounded;
      case 'activites':
        return Icons.sports_soccer_rounded;
      case 'autres':
      default:
        return Icons.more_horiz_rounded;
    }
  }

  String _getCategoryName(String category) {
    switch (_normalizeCategory(category)) {
      case 'scolarite':
        return 'Scolarité';
      case 'transport':
        return 'Transport';
      case 'cantine':
        return 'Cantine';
      case 'inscription':
        return 'Inscription';
      case 'uniforme':
        return 'Uniforme';
      case 'activites':
        return 'Activités';
      case 'autres':
      default:
        return 'Autres';
    }
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: AppColors.slate200),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: AppColors.textTertiary, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SELECT STUDENT DIALOG
// ═══════════════════════════════════════════════════════════════════════════

class _SelectStudentForPaymentDialog extends StatefulWidget {
  final List<Map<String, dynamic>> allStudents;
  final List<Map<String, dynamic>> allNiveaux;
  final List<Map<String, dynamic>> allSections;
  final List<Map<String, dynamic>> allClasses;
  final Function(Map<String, dynamic>) onStudentSelected;
  final Function(Map<String, dynamic>)? onStudentProfile;

  const _SelectStudentForPaymentDialog({
    required this.allStudents,
    required this.allNiveaux,
    required this.allSections,
    required this.allClasses,
    required this.onStudentSelected,
    this.onStudentProfile,
  });

  @override
  State<_SelectStudentForPaymentDialog> createState() =>
      _SelectStudentForPaymentDialogState();
}

class _SelectStudentForPaymentDialogState
    extends State<_SelectStudentForPaymentDialog> {
  final _searchController = TextEditingController();
  String? _selectedNiveauId;
  String? _selectedSectionId;
  String? _selectedClassId;
  final GlobalKey _filterIconKey = GlobalKey();

  static const Color _brand = Color(0xFF6D4CF6);
  static const Color _brandLight = Color(0xFFF3E8FF);

  List<Map<String, dynamic>> get _sectionsForNiveau {
    if (_selectedNiveauId == null) return [];
    return widget.allSections
        .where((s) => s['niveau_id'] == _selectedNiveauId)
        .toList();
  }

  bool get _niveauHasSections => _sectionsForNiveau.isNotEmpty;

  List<Map<String, dynamic>> get _filteredClasses {
    if (_selectedNiveauId == null) return widget.allClasses;
    return widget.allClasses.where((c) {
      if (c['niveau_id'] != _selectedNiveauId) return false;
      if (_niveauHasSections && _selectedSectionId != null) {
        return c['section_id'] == _selectedSectionId;
      }
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredStudents {
    final query = _searchController.text.toLowerCase();

    return widget.allStudents.where((s) {
      if (query.isNotEmpty) {
        final name = (s['full_name'] ?? '').toString().toLowerCase();
        final email = (s['email'] ?? '').toString().toLowerCase();
        final phone = (s['phone'] ?? '').toString().toLowerCase();
        if (!name.contains(query) &&
            !email.contains(query) &&
            !phone.contains(query)) {
          return false;
        }
      }

      final enrollments = s['enrollments'] as List?;

      if (_selectedClassId != null || _selectedNiveauId != null) {
        if (enrollments == null || enrollments.isEmpty) return false;

        final enrollment = enrollments.first as Map<String, dynamic>;
        final classData = enrollment['classes'] as Map<String, dynamic>?;

        if (_selectedClassId != null) {
          return enrollment['class_id'] == _selectedClassId ||
              classData?['id'] == _selectedClassId;
        }

        if (_selectedNiveauId != null) {
          if (classData?['niveau_id'] != _selectedNiveauId) return false;
          if (_niveauHasSections && _selectedSectionId != null) {
            return classData?['section_id'] == _selectedSectionId;
          }
        }
      }

      return true;
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _navigateToStudentProfile(Map<String, dynamic> student) {
    if (widget.onStudentProfile != null) {
      widget.onStudentProfile!(student);
    } else {
      final studentId = student['id']?.toString();
      if (studentId == null) return;
      Navigator.pop(context);
      context.push('/users/$studentId');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 680,
      height: 670,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Column(
          children: [
            // ── Header ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.slate200)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _brandLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person_search_rounded, color: _brand, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sélectionner un élève',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Choisissez un élève pour créer un plan de paiement',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Close button - borderless
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.close, size: 20, color: AppColors.textTertiary),
                    ),
                  ),
                ],
              ),
            ),

            // ── Search Bar with Filter Icon ──
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Rechercher par nom, email ou téléphone...',
                        hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                        prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textTertiary),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_searchController.text.isNotEmpty)
                              InkWell(
                                onTap: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(Icons.close, size: 16, color: AppColors.textTertiary),
                                ),
                              ),
                            // Filter icon for niveau selection
                            InkWell(
                              key: _filterIconKey,
                              onTap: () => _showNiveauFilter(context),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.tune_rounded,
                                      size: 18,
                                      color: _selectedNiveauId != null
                                          ? _brand
                                          : AppColors.textTertiary,
                                    ),
                                    if (_selectedNiveauId != null) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: _brand,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        filled: true,
                        fillColor: AppColors.slate50,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.slate200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.slate200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _brand, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Active filter chips ──
            if (_selectedNiveauId != null || _selectedClassId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: Row(
                  children: [
                    if (_selectedNiveauId != null)
                      _buildFilterChip(
                        _getNiveauName(_selectedNiveauId!),
                        () => setState(() {
                          _selectedNiveauId = null;
                          _selectedSectionId = null;
                          _selectedClassId = null;
                        }),
                      ),
                    if (_selectedClassId != null) ...[
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        _getClassName(_selectedClassId!),
                        () => setState(() => _selectedClassId = null),
                      ),
                    ],
                  ],
                ),
              ),

            // ── Students List ──
            Expanded(
              child: _filteredStudents.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded, size: 56, color: AppColors.slate200),
                          const SizedBox(height: 16),
                          Text(
                            'Aucun élève trouvé',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Modifiez vos filtres pour voir les résultats',
                            style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      itemCount: _filteredStudents.length,
                      itemBuilder: (context, index) {
                        final student = _filteredStudents[index];
                        final enrollments = student['enrollments'] as List?;
                        final enrollment = enrollments?.isNotEmpty == true
                            ? enrollments!.first as Map<String, dynamic>
                            : null;
                        final classData = enrollment?['classes'] as Map<String, dynamic>?;

                        return _buildStudentRow(student, classData);
                      },
                    ),
            ),

            // ── Footer ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.slate200)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.slate100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_filteredStudents.length} élève(s)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Annuler button - styled like "Ajouter un niveau" button
                  SizedBox(
                    height: 42,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brand,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        shadowColor: _brand.withOpacity(0.3),
                      ),
                      child: const Text(
                        'Annuler',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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

  void _showNiveauFilter(BuildContext context) {
    final RenderBox renderBox = _filterIconKey.currentContext!.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx - 280 + size.width,
        position.dy + size.height + 8,
        position.dx,
        position.dy + size.height + 400,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.15),
      constraints: const BoxConstraints(
        minWidth: 280,
        maxWidth: 280,
      ),
      items: [
        PopupMenuItem(
          enabled: false,
          padding: EdgeInsets.zero,
          child: StatefulBuilder(
            builder: (ctx, setMenuState) {
              return Container(
                width: 280,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.tune_rounded, size: 18, color: _brand),
                          const SizedBox(width: 8),
                          const Text(
                            'Filtrer par niveau',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // Niveau options
                    _buildNiveauOption(null, 'Tous les niveaux', ctx),
                    ...widget.allNiveaux.map(
                      (n) => _buildNiveauOption(
                        n['id']?.toString(),
                        n['name']?.toString() ?? '',
                        ctx,
                      ),
                    ),
                    // Class filter (if niveau selected)
                    if (_selectedNiveauId != null && _filteredClasses.isNotEmpty) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            Icon(Icons.class_outlined, size: 16, color: AppColors.textTertiary),
                            const SizedBox(width: 8),
                            Text(
                              'Filtrer par classe',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildClassOption(null, 'Toutes les classes', ctx),
                      ..._filteredClasses.map(
                        (c) => _buildClassOption(
                          c['id']?.toString(),
                          c['name']?.toString() ?? '',
                          ctx,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNiveauOption(String? id, String label, BuildContext menuContext) {
    final isSelected = _selectedNiveauId == id;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedNiveauId = id;
          _selectedSectionId = null;
          _selectedClassId = null;
        });
        Navigator.pop(menuContext);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: isSelected ? _brandLight : Colors.transparent,
        child: Row(
          children: [
            Icon(
              Icons.school_outlined,
              size: 18,
              color: isSelected ? _brand : AppColors.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? _brand : const Color(0xFF374151),
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, size: 18, color: _brand),
          ],
        ),
      ),
    );
  }

  Widget _buildClassOption(String? id, String label, BuildContext menuContext) {
    final isSelected = _selectedClassId == id;
    return InkWell(
      onTap: () {
        setState(() => _selectedClassId = id);
        Navigator.pop(menuContext);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: isSelected ? _brandLight : Colors.transparent,
        child: Row(
          children: [
            Icon(
              Icons.class_outlined,
              size: 16,
              color: isSelected ? _brand : AppColors.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? _brand : const Color(0xFF374151),
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check, size: 16, color: _brand),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _brandLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _brand.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _brand,
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(10),
            child: const Icon(Icons.close, size: 14, color: _brand),
          ),
        ],
      ),
    );
  }

  String _getNiveauName(String id) {
    final niveau = widget.allNiveaux.firstWhere(
      (n) => n['id']?.toString() == id,
      orElse: () => {'name': 'Niveau'},
    );
    return niveau['name']?.toString() ?? 'Niveau';
  }

  String _getClassName(String id) {
    final cls = widget.allClasses.firstWhere(
      (c) => c['id']?.toString() == id,
      orElse: () => {'name': 'Classe'},
    );
    return cls['name']?.toString() ?? 'Classe';
  }

  Widget _buildStudentRow(Map<String, dynamic> student, Map<String, dynamic>? classData) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slate200.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: [
            // Avatar - clickable to go to profile
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _navigateToStudentProfile(student),
                child: UserAvatar(
                  name: student['full_name'] ?? '?',
                  photoUrl: student['photo_url']?.toString(),
                  radius: 22,
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Info - clickable to go to profile
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _navigateToStudentProfile(student),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student['full_name'] ?? 'Sans nom',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.school_outlined, size: 13, color: AppColors.textTertiary),
                          const SizedBox(width: 4),
                          Text(
                            classData?['name'] ?? 'Pas de classe',
                            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                          ),
                          if (student['email'] != null) ...[
                            const SizedBox(width: 12),
                            Icon(Icons.email_outlined, size: 13, color: AppColors.textTertiary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                student['email'] ?? '',
                                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Select button - clickable
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => widget.onStudentSelected(student),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _brand,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: _brand.withOpacity(0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 16, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'Sélectionner',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CREATE PAYMENT PLAN DIALOG
// ═══════════════════════════════════════════════════════════════════════════

class _CreatePaymentPlanDialog extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String enrollmentId;
  final String className;
  final String? niveauId;
  final String? sectionId;
  final VoidCallback onCreated;

  const _CreatePaymentPlanDialog({
    required this.studentId,
    required this.studentName,
    required this.enrollmentId,
    required this.className,
    this.niveauId,
    this.sectionId,
    required this.onCreated,
  });

  @override
  State<_CreatePaymentPlanDialog> createState() =>
      _CreatePaymentPlanDialogState();
}

class _CreatePaymentPlanDialogState extends State<_CreatePaymentPlanDialog> {
  String _selectedCategory = 'scolarite';
  String _selectedPlanType = 'monthly';
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isLoading = false;
  bool _isLoadingPricing = true;
  DateTime _startDate = DateTime.now();

  // Dynamic plan counts from academic year
  int _monthCount = 9;
  int _semesterCount = 3;

  static const Color _brand = Color(0xFF6D4CF6);
  static const Color _brandLight = Color(0xFFF3E8FF);

  final _categories = const [
    ('scolarite', 'Scolarité', Icons.school, Color(0xFF3B82F6)),
    ('transport', 'Transport', Icons.directions_bus, Color(0xFF10B981)),
    ('cantine', 'Cantine', Icons.restaurant, Color(0xFFF59E0B)),
    ('inscription', 'Inscription', Icons.assignment, Color(0xFF8B5CF6)),
    ('uniforme', 'Uniforme', Icons.checkroom, Color(0xFFEC4899)),
    ('activites', 'Activités', Icons.sports_soccer, Color(0xFF14B8A6)),
    ('autres', 'Autres', Icons.more_horiz, Color(0xFF6B7280)),
  ];

  final _planTypes = [
    ('monthly', 'Mensuel', 9),
    ('semester', 'Trimestriel', 3),
    ('semesterly', 'Semestriel', 2),
    ('annual', 'Annuel', 1),
  ];

  @override
  void initState() {
    super.initState();
    _loadAcademicYearAndPricing();
  }

  Future<void> _loadAcademicYearAndPricing() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final userData = await supabase
          .from('users')
          .select('school_id')
          .eq('id', user.id)
          .single();
      final schoolId = userData['school_id']?.toString();

      if (schoolId != null) {
        // Load current academic year, fallback to most recent
        var yearData = await supabase
            .from('academic_years')
            .select('id, start_date, end_date')
            .eq('school_id', schoolId)
            .eq('is_current', true)
            .maybeSingle();

        yearData ??= await supabase
            .from('academic_years')
            .select('id, start_date, end_date')
            .eq('school_id', schoolId)
            .order('start_date', ascending: false)
            .limit(1)
            .maybeSingle();

        if (yearData != null) {
          // Load actual semesters to compute real month count and start date
          final semesterResp = await supabase
              .from('semesters')
              .select('start_date, end_date')
              .eq('academic_year_id', yearData['id'].toString())
              .order('start_date', ascending: true);

          final semesterList = semesterResp as List;

          if (semesterList.isNotEmpty) {
            // Use first semester's start date as the real start
            final firstStart = DateTime.tryParse(semesterList.first['start_date'].toString());
            final lastEnd = DateTime.tryParse(semesterList.last['end_date'].toString());

            if (firstStart != null) _startDate = firstStart;

            if (firstStart != null && lastEnd != null) {
              // Count months spanning all semesters
              _monthCount = (lastEnd.year - firstStart.year) * 12 + (lastEnd.month - firstStart.month) + 1;
            }
          } else {
            // Fallback to academic year dates
            final start = DateTime.tryParse(yearData['start_date'].toString());
            final end = DateTime.tryParse(yearData['end_date'].toString());
            if (start != null && end != null && end.isAfter(start)) {
              _monthCount = (end.year - start.year) * 12 + (end.month - start.month) + 1;
              _startDate = start;
            }
          }

          _semesterCount = semesterList.length;
        }

        if (_semesterCount <= 0) {
          final semesterCount = await supabase.rpc(
            'get_current_academic_year_semester_count',
            params: {'p_school_id': schoolId},
          );
          if (semesterCount != null) {
            _semesterCount = (semesterCount as num).toInt();
          }
        }
        if (_semesterCount <= 0) _semesterCount = 3;
        if (_monthCount <= 0) _monthCount = 9;

        // Load pricing for scolarite if niveauId available
        if (widget.niveauId != null && _amountController.text.isEmpty) {
          final pricing = await supabase.rpc(
            'get_payment_pricing_for_enrollment',
            params: {
              'p_enrollment_id': widget.enrollmentId,
              'p_category': 'scolarite',
            },
          );
          if (pricing != null && (pricing as List).isNotEmpty) {
            final amount = (pricing.first['amount'] as num?)?.toDouble();
            if (amount != null && amount > 0) {
              _amountController.text = amount.toStringAsFixed(0);
            }
          } else {
            // Fallback: try by niveau/section directly for scolarite
            final query = supabase
                .from('payment_pricing')
                .select('amount')
                .eq('school_id', schoolId)
                .eq('category', 'scolarite')
                .eq('niveau_id', widget.niveauId!);

            final pricingData = widget.sectionId == null
                ? await query.isFilter('section_id', null).limit(1)
                : await query.eq('section_id', widget.sectionId!).limit(1);

            if (pricingData.isNotEmpty) {
              final amount = (pricingData.first['amount'] as num?)?.toDouble();
              if (amount != null && amount > 0) {
                _amountController.text = amount.toStringAsFixed(0);
              }
            }
          }
        }

        await _loadExistingPlanForCategory(_selectedCategory);
      }
    } catch (e) {
      debugPrint('Error loading academic year/pricing: $e');
    } finally {
      if (mounted) setState(() => _isLoadingPricing = false);
    }
  }

  List<(String, String, int)> get _dynamicPlanTypes {
    final list = <(String, String, int)>[
      ('monthly', 'Mensuel ($_monthCount paiements)', _monthCount),
    ];
    if (_semesterCount == 2) {
      list.add(('semesterly', 'Semestriel (2 paiements)', 2));
    } else {
      list.add(('semester', 'Trimestriel ($_semesterCount paiements)', _semesterCount));
    }
    list.add(('annual', 'Annuel (1 paiement)', 1));
    return list;
  }

  bool get _isScolarite => _selectedCategory == 'scolarite';

  void _onCategoryChanged(String category) {
    setState(() {
      _selectedCategory = category;
      if (!_isScolarite) {
        _selectedPlanType = 'annual';
      } else if (!_dynamicPlanTypes.any((p) => p.$1 == _selectedPlanType)) {
        _selectedPlanType = 'monthly';
      }
    });
    _loadPricingForCategory(category);
    _loadExistingPlanForCategory(category);
  }

  Future<void> _loadPricingForCategory(String category) async {
    if (widget.niveauId == null) return;
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final userData = await supabase.from('users').select('school_id').eq('id', user.id).single();
      final schoolId = userData['school_id']?.toString();
      if (schoolId == null) return;

      final pricing = await supabase.rpc(
        'get_payment_pricing_for_enrollment',
        params: {
          'p_enrollment_id': widget.enrollmentId,
          'p_category': category,
        },
      );
      if (pricing != null && (pricing as List).isNotEmpty) {
        final amount = (pricing.first['amount'] as num?)?.toDouble();
        if (amount != null && amount > 0) {
          setState(() => _amountController.text = amount.toStringAsFixed(0));
        } else {
          setState(() => _amountController.clear());
        }
      } else {
        setState(() => _amountController.clear());
      }
    } catch (e) {
      debugPrint('Error loading category pricing: $e');
    }
  }

  Future<void> _loadExistingPlanForCategory(String category) async {
    // Reset fields for the newly selected category first so stale values
    // from a previous category don't leak through.
    setState(() {
      _descriptionController.clear();
      if (!_isScolarite) {
        _selectedPlanType = 'annual';
      } else {
        _selectedPlanType = 'monthly';
      }
    });

    try {
      final supabase = Supabase.instance.client;
      final existingPlan = await supabase
          .from('payment_plans')
          .select('plan_type, category, amount_total, description')
          .eq('enrollment_id', widget.enrollmentId)
          .eq('category', category)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existingPlan != null && mounted) {
        final dbType = existingPlan['plan_type']?.toString() ?? 'monthly';
        final amt = (existingPlan['amount_total'] as num?)?.toDouble() ?? 0;
        final desc = existingPlan['description']?.toString() ?? '';

        setState(() {
          _selectedPlanType = _mapDbPlanTypeToUi(dbType);
          if (amt > 0) {
            _amountController.text = amt.toStringAsFixed(0);
          }
          if (desc.isNotEmpty) {
            _descriptionController.text = desc;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading existing plan for category: $e');
    }
  }

  double? get _currentAmount {
    final text = _amountController.text;
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  Widget _buildAmountPreview() {
    final amount = _currentAmount;
    if (amount == null || amount <= 0) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFBBF24).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tarification non définie',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Configurez-la dans la page Tarification.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final planType = _isScolarite ? _selectedPlanType : 'annual';
    final plan = _dynamicPlanTypes.firstWhere(
      (pt) => pt.$1 == planType,
      orElse: () => ('annual', 'Annuel (1 paiement)', 1),
    );
    final count = plan.$3;
    final installment = amount / count;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              count == 1 ? 'Paiement unique' : 'Plan en $count fois',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _brand),
            ),
            const SizedBox(height: 12),
            Text(
              '${_formatCurrency(amount)} TND',
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
                letterSpacing: -1,
              ),
            ),
            if (count > 1) ...[
              const SizedBox(height: 20),
              // Timeline header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _brandLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timeline_rounded, color: _brand, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          '$count échéances',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _brand),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${DateFormat('MMM yyyy', 'fr').format(_startDate)} → ${DateFormat('MMM yyyy', 'fr').format(_getEndDate(planType, count))}',
                    style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Horizontal timeline
              SizedBox(
                height: 110,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: count,
                  itemBuilder: (context, i) {
                    DateTime dueDate;
                    if (planType == 'monthly') {
                      dueDate = DateTime(_startDate.year, _startDate.month + i, 1);
                    } else if (planType == 'semester' || planType == 'trimester' || planType == 'semesterly') {
                      final monthsPerPart = (_monthCount / count).ceil();
                      dueDate = DateTime(_startDate.year, _startDate.month + (i * monthsPerPart), 1);
                    } else {
                      dueDate = _startDate;
                    }
                    final isFirst = i == 0;
                    final isLast = i == count - 1;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (i == 0) const SizedBox(width: 4),
                        Column(
                          children: [
                            // Month label
                            Text(
                              DateFormat('MMM', 'fr').format(dueDate).toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textTertiary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Node
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: _brandLight,
                                shape: BoxShape.circle,
                                border: Border.all(color: _brand.withOpacity(0.3)),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _brand),
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Amount
                            Text(
                              '${_formatCurrency(installment)}',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                            ),
                            Text(
                              'TND',
                              style: TextStyle(fontSize: 9, color: AppColors.textTertiary),
                            ),
                          ],
                        ),
                        // Connector line
                        if (!isLast)
                          Container(
                            margin: const EdgeInsets.only(top: 18),
                            width: 24,
                            height: 2,
                            decoration: BoxDecoration(
                              color: _brand.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        if (isLast) const SizedBox(width: 4),
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat('#,###.##', 'fr_FR');
    return formatter.format(amount);
  }

  DateTime _getEndDate(String planType, int count) {
    if (planType == 'monthly') {
      return DateTime(_startDate.year, _startDate.month + count - 1, 1);
    } else if (planType == 'semester' || planType == 'trimester') {
      final monthsPerPart = (_monthCount / count).ceil();
      return DateTime(_startDate.year, _startDate.month + ((count - 1) * monthsPerPart), 1);
    } else if (planType == 'semesterly') {
      final monthsPerPart = (_monthCount / count).ceil();
      return DateTime(_startDate.year, _startDate.month + ((count - 1) * monthsPerPart), 1);
    }
    return _startDate;
  }

  Widget _buildCreatePlanSkeleton() {
    return ShimmerLoading(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBox(width: 80, height: 16, borderRadius: 4),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(
                5,
                (i) => const SkeletonBox(width: 95, height: 38, borderRadius: 12),
              ),
            ),
            const SizedBox(height: 24),
            const SkeletonBox(width: 140, height: 16, borderRadius: 4),
            const SizedBox(height: 12),
            Row(
              children: List.generate(
                3,
                (i) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                    child: const SkeletonBox(height: 72, borderRadius: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const SkeletonBox(height: 120, borderRadius: 16),
            const SizedBox(height: 20),
            const SkeletonBox(height: 50, borderRadius: 10),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 620,
      height: 720,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header matching select-student dialog ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.slate200)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _brandLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.payment_rounded, color: _brand, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Nouveau Plan de Paiement',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.studentName} • ${widget.className}',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Close button - borderless
                InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.close, size: 20, color: AppColors.textTertiary),
                  ),
                ),
              ],
            ),
          ),

          // ── Form ──
          Expanded(
            child: _isLoadingPricing
                ? _buildCreatePlanSkeleton()
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                  // Plan type
                  Row(
                    children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _brand.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.schedule_rounded, color: _brand, size: 18),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Fréquence de paiement',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF111827)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: _dynamicPlanTypes.map((pt) {
                        final isSelected = _selectedPlanType == pt.$1;
                        final icons = {'monthly': Icons.calendar_view_month_rounded, 'semester': Icons.view_week_rounded, 'trimester': Icons.view_week_rounded, 'semesterly': Icons.view_day_rounded, 'annual': Icons.event_available_rounded};
                        final icon = icons[pt.$1] ?? Icons.payments_rounded;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: pt != _dynamicPlanTypes.last ? 8 : 0),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () => setState(() => _selectedPlanType = pt.$1),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeInOut,
                                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isSelected ? _brand : const Color(0xFFE5E7EB),
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(icon, color: isSelected ? _brand : const Color(0xFF6B7280), size: 22),
                                      const SizedBox(height: 6),
                                      Text(
                                        pt.$1 == 'monthly' ? 'Mensuel' : (pt.$1 == 'semester' || pt.$1 == 'trimester') ? 'Trimestriel' : pt.$1 == 'semesterly' ? 'Semestriel' : 'Annuel',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isSelected ? _brand : const Color(0xFF374151),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${pt.$3}×',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: isSelected ? _brand.withOpacity(0.7) : const Color(0xFF9CA3AF),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                  // Amount preview from pricing
                  _buildAmountPreview(),

                  const SizedBox(height: 20),

                  // Start date
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _startDate,
                        firstDate: DateTime(2024),
                        lastDate: DateTime(2030),
                        builder: (context, child) => Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: Theme.of(context).colorScheme.copyWith(
                              primary: _brand,
                            ),
                          ),
                          child: child!,
                        ),
                      );
                      if (picked != null) {
                        setState(() => _startDate = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, color: AppColors.slate400, size: 18),
                          const SizedBox(width: 10),
                          Text(
                            'Date de début :',
                            style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('d MMMM yyyy', 'fr_FR').format(_startDate),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.slate400, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Footer matching select-student dialog ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.slate200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  height: 42,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF374151),
                      elevation: 0,
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'Annuler',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 42,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _createPaymentPlan,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: IosLoader.small(color: Colors.white),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: const Text(
                      'Créer le plan',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      shadowColor: const Color(0xFF10B981).withOpacity(0.3),
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

  Future<void> _createPaymentPlan() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tarification non définie pour cette catégorie. Veuillez la configurer dans la page Tarification.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;

      // Create payment plan
      // First: delete any existing plans for this enrollment+category to prevent accumulation
      final existingPlans = await supabase
          .from('payment_plans')
          .select('id')
          .eq('enrollment_id', widget.enrollmentId)
          .eq('category', _selectedCategory);

      if ((existingPlans as List).isNotEmpty) {
        final oldPlanIds = existingPlans.map((p) => p['id'].toString()).toList();
        // Delete payments for old plans first
        await supabase.from('payments').delete().inFilter('payment_plan_id', oldPlanIds);
        // Delete old plans
        await supabase.from('payment_plans').delete().inFilter('id', oldPlanIds);
      }

      final planResult = await supabase
          .from('payment_plans')
          .insert({
            'enrollment_id': widget.enrollmentId,
            'plan_type': _mapUiPlanTypeToDb(_selectedPlanType),
            'amount_total': amount,
            'currency': 'TND',
            'description': _getCategoryLabel(_selectedCategory),
            'category': _selectedCategory,
          })
          .select()
          .single();

      final planId = planResult['id'];

      // Create individual payments based on plan type
      final numPayments = _isScolarite
          ? _dynamicPlanTypes.firstWhere((pt) => pt.$1 == _selectedPlanType).$3
          : 1;
      final paymentAmount = amount / numPayments;

      final payments = <Map<String, dynamic>>[];
      for (int i = 0; i < numPayments; i++) {
        DateTime dueDate;
        if (_selectedPlanType == 'monthly' && _isScolarite) {
          dueDate = DateTime(_startDate.year, _startDate.month + i, 1);
        } else if ((_selectedPlanType == 'semester' || _selectedPlanType == 'semesterly') && _isScolarite) {
          // Distribute evenly based on count, starting from start date
          final monthsPerPart = _monthCount / numPayments;
          dueDate = DateTime(_startDate.year, _startDate.month + (i * monthsPerPart.ceil()), 1);
        } else {
          dueDate = _startDate;
        }

        payments.add({
          'payment_plan_id': planId,
          'amount': paymentAmount,
          'due_date': dueDate.toIso8601String(),
          'status': 'pending',
        });
      }

      await supabase.from('payments').insert(payments);

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pop();
            widget.onCreated();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Plan de paiement créé pour ${widget.studentName}'),
                backgroundColor: const Color(0xFF10B981),
              ),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFriendlyError.format(e, fallback: 'Unable to save payment settings right now. Please try again.')), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getCategoryLabel(String category) {
    return _categories
        .firstWhere(
          (c) => c.$1 == category,
          orElse: () => ('', 'Autres', Icons.more_horiz, AppColors.textTertiary),
        )
        .$2;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PAYMENT PRICING CONFIGURATION DIALOG
// ═══════════════════════════════════════════════════════════════════════════

class _PaymentPricingDialog extends StatefulWidget {
  final List<Map<String, dynamic>> allNiveaux;
  final List<Map<String, dynamic>> allSections;
  final List<Map<String, dynamic>> allClasses;

  const _PaymentPricingDialog({
    required this.allNiveaux,
    required this.allSections,
    required this.allClasses,
  });

  @override
  State<_PaymentPricingDialog> createState() => _PaymentPricingDialogState();
}

class _PaymentPricingDialogState extends State<_PaymentPricingDialog> {
  String _selectedCategory = 'scolarite';
  bool _isLoading = true;
  bool _isSaving = false;
  String? _schoolId;
  String? _academicYearId;

  // Map: category -> { niveauId -> { sectionId (null for niveau-level) -> amount } }
  final Map<String, Map<String, Map<String?, double>>> _allPricing = {};

  static const Color _brand = Color(0xFF6D4CF6);
  static const Color _brandLight = Color(0xFFF3E8FF);

  final _categories = const [
    ('scolarite', 'Scolarité', Icons.school, Color(0xFF3B82F6)),
    ('transport', 'Transport', Icons.directions_bus, Color(0xFF10B981)),
    ('cantine', 'Cantine', Icons.restaurant, Color(0xFFF59E0B)),
    ('inscription', 'Inscription', Icons.assignment, Color(0xFF8B5CF6)),
    ('uniforme', 'Uniforme', Icons.checkroom, Color(0xFFEC4899)),
    ('activites', 'Activités', Icons.sports_soccer, Color(0xFF14B8A6)),
    ('autres', 'Autres', Icons.more_horiz, Color(0xFF6B7280)),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  List<Map<String, dynamic>> get _sortedNiveaux {
    final sorted = List<Map<String, dynamic>>.from(widget.allNiveaux);
    sorted.sort((a, b) {
      // Put base cycle (primaire + collège) before secondaire (lycée)
      final cycleA = a['cycle']?.toString() ?? '';
      final cycleB = b['cycle']?.toString() ?? '';
      final cycleCompare = cycleA.compareTo(cycleB);
      if (cycleCompare != 0) return cycleCompare;

      // Then by display order
      final orderA = (a['display_order'] as num?)?.toInt() ?? 0;
      final orderB = (b['display_order'] as num?)?.toInt() ?? 0;
      return orderA.compareTo(orderB);
    });
    return sorted;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final userData = await supabase
          .from('users')
          .select('school_id')
          .eq('id', user.id)
          .single();
      _schoolId = userData['school_id']?.toString();

      if (_schoolId != null) {
        final yearData = await supabase
            .from('academic_years')
            .select('id')
            .eq('school_id', _schoolId!)
            .eq('is_current', true)
            .maybeSingle();
        _academicYearId = yearData?['id']?.toString();
      }

      await _loadPricing();
    } catch (e) {
      debugPrint('Error loading pricing data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPricing() async {
    if (_schoolId == null) return;
    try {
      final supabase = Supabase.instance.client;
      // Load all pricing rows across all categories for this school
      final response = await supabase
          .from('payment_pricing')
          .select()
          .eq('school_id', _schoolId!);

      _allPricing.clear();
      // First pass: rows with matching academic_year_id
      for (final row in response) {
        final yearId = row['academic_year_id']?.toString();
        if (yearId != null && yearId == _academicYearId) {
          final cat = row['category']?.toString();
          final niveauId = row['niveau_id']?.toString();
          final sectionId = row['section_id']?.toString();
          final amount = (row['amount'] as num?)?.toDouble() ?? 0.0;
          if (cat != null && niveauId != null) {
            _allPricing.putIfAbsent(cat, () => {});
            _allPricing[cat]!.putIfAbsent(niveauId, () => {});
            _allPricing[cat]![niveauId]![sectionId] = amount;
          }
        }
      }
      // Second pass: fallback to null academic_year_id only if no specific year row exists
      for (final row in response) {
        final yearId = row['academic_year_id']?.toString();
        if (yearId == null) {
          final cat = row['category']?.toString();
          final niveauId = row['niveau_id']?.toString();
          final sectionId = row['section_id']?.toString();
          final amount = (row['amount'] as num?)?.toDouble() ?? 0.0;
          if (cat != null && niveauId != null) {
            _allPricing.putIfAbsent(cat, () => {});
            _allPricing[cat]!.putIfAbsent(niveauId, () => {});
            if (!_allPricing[cat]![niveauId]!.containsKey(sectionId)) {
              _allPricing[cat]![niveauId]![sectionId] = amount;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading pricing: $e');
    }
  }

  Future<void> _savePricing() async {
    if (_schoolId == null) return;
    setState(() => _isSaving = true);
    try {
      final supabase = Supabase.instance.client;

      for (final catEntry in _allPricing.entries) {
        final category = catEntry.key;
        for (final entry in catEntry.value.entries) {
          final niveauId = entry.key;
          for (final sectionEntry in entry.value.entries) {
            final sectionId = sectionEntry.key;
            final amount = sectionEntry.value;

            var query = supabase
                .from('payment_pricing')
                .select('id')
                .eq('school_id', _schoolId!)
                .eq('category', category)
                .eq('niveau_id', niveauId);

            if (_academicYearId != null) {
              query = query.eq('academic_year_id', _academicYearId!);
            }

            final existingList = await (sectionId == null
                ? query.isFilter('section_id', null).limit(1)
                : query.eq('section_id', sectionId).limit(1));

            final existing = (existingList as List).isNotEmpty ? existingList.first : null;

            if (existing != null) {
              await supabase
                  .from('payment_pricing')
                  .update({'amount': amount, 'updated_at': DateTime.now().toIso8601String()})
                  .eq('id', existing['id']);
            } else {
              await supabase.from('payment_pricing').insert({
                'school_id': _schoolId,
                'academic_year_id': _academicYearId,
                'category': category,
                'niveau_id': niveauId,
                'section_id': sectionId,
                'amount': amount,
              });
            }
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tarification enregistrée avec succès'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFriendlyError.format(
                e,
                fallback: 'Unable to save pricing settings right now. Please try again.',
              ),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  List<Map<String, dynamic>> _sectionsForNiveau(String niveauId) {
    return widget.allSections
        .where((s) => s['niveau_id']?.toString() == niveauId)
        .toList();
  }

  bool _niveauHasSections(String niveauId) {
    return _sectionsForNiveau(niveauId).isNotEmpty;
  }

  double? _getAmount(String niveauId, String? sectionId) {
    return _allPricing[_selectedCategory]?[niveauId]?[sectionId];
  }

  void _setAmount(String niveauId, String? sectionId, double? amount) {
    _allPricing.putIfAbsent(_selectedCategory, () => {});
    _allPricing[_selectedCategory]!.putIfAbsent(niveauId, () => {});
    if (amount == null || amount <= 0) {
      _allPricing[_selectedCategory]![niveauId]!.remove(sectionId);
    } else {
      _allPricing[_selectedCategory]![niveauId]![sectionId] = amount;
    }
  }

  Widget _buildPricingSkeleton() {
    return ShimmerLoading(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: const [
                SkeletonBox(width: 3, height: 14, borderRadius: 2),
                SizedBox(width: 10),
                SkeletonBox(width: 140, height: 12, borderRadius: 4),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: 6,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1)),
                ),
                child: Row(
                  children: const [
                    SkeletonCircle(size: 8),
                    SizedBox(width: 12),
                    SkeletonBox(width: 130, height: 16, borderRadius: 6),
                    Spacer(),
                    SkeletonBox(width: 100, height: 32, borderRadius: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 520,
      height: 700,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.slate200)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _brandLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.price_change_outlined, color: _brand, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tarification des paiements',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Définissez les montants par niveau et section',
                        style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.close, size: 20, color: AppColors.textTertiary),
                  ),
                ),
              ],
            ),
          ),

          // Category selector
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 3,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _brand,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'CATÉGORIE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _categories.map((cat) {
                    final isSelected = _selectedCategory == cat.$1;
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedCategory = cat.$1;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? cat.$4.withOpacity(0.08) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? cat.$4 : const Color(0xFFE5E7EB),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(cat.$3, size: 18, color: cat.$4),
                              const SizedBox(width: 8),
                              Text(
                                cat.$2,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                  color: isSelected ? const Color(0xFF111827) : const Color(0xFF374151),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          // Apply to all (non-scolarité)
          if (_selectedCategory != 'scolarite') ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _showApplyToAllDialog,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _brand.withOpacity(0.25)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _brand.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.content_copy_rounded, size: 16, color: _brand),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Appliquer un montant aux niveaux',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _brand),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Copier ce montant pour tous les niveaux',
                                style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded, size: 14, color: _brand.withOpacity(0.5)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],

          // Pricing list
          Expanded(
            child: _isLoading
                ? _buildPricingSkeleton()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            Container(
                              width: 3,
                              height: 14,
                              decoration: BoxDecoration(
                                color: _brand,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'MONTANTS PAR NIVEAU',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                          itemCount: _sortedNiveaux.length,
                          itemBuilder: (context, index) {
                            final niveau = _sortedNiveaux[index];
                            final niveauId = niveau['id']?.toString() ?? '';
                            final sections = _sectionsForNiveau(niveauId);
                            return _buildNiveauPricingCard(niveau, sections);
                          },
                        ),
                      ),
                    ],
                  ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.slate200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  height: 42,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.slate100,
                      foregroundColor: AppColors.textPrimary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Fermer', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 42,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _savePricing,
                    icon: _isSaving
                        ? const SizedBox(width: 18, height: 18, child: IosLoader.small(color: Colors.white))
                        : const Icon(Icons.save, size: 18),
                    label: const Text('Enregistrer', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brand,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      shadowColor: _brand.withOpacity(0.3),
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

  Widget _buildNiveauPricingCard(Map<String, dynamic> niveau, List<Map<String, dynamic>> sections) {
    final niveauId = niveau['id']?.toString() ?? '';
    final hasSections = sections.isNotEmpty;
    final niveauAmount = _getAmount(niveauId, null);
    final niveauName = niveau['name']?.toString() ?? 'Niveau';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.transparent,
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  niveauName,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              if (!hasSections) ...[
                SizedBox(
                  width: 130,
                  child: _PricingAmountField(
                    key: ValueKey('amount_${_selectedCategory}_${niveauId}_none_$niveauAmount'),
                    initialValue: niveauAmount,
                    onChanged: (v) => _setAmount(niveauId, null, v),
                    brandColor: _brand,
                  ),
                ),
              ],
            ],
          ),
          if (hasSections) ...[
            const SizedBox(height: 10),
            ...sections.map((section) {
              final sectionId = section['id']?.toString() ?? '';
              final amount = _getAmount(niveauId, sectionId);
              return Padding(
                padding: const EdgeInsets.only(left: 20, top: 6, bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary.withOpacity(0.7),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        section['name']?.toString() ?? 'Section',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 130,
                      child: _PricingAmountField(
                        key: ValueKey('amount_${_selectedCategory}_${niveauId}_${sectionId}_$amount'),
                        initialValue: amount,
                        onChanged: (v) => _setAmount(niveauId, sectionId, v),
                        brandColor: _brand,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }


  void _showApplyToAllDialog() {
    final selectedNiveaux = <String>{};
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
                    ),
                    child: Row(children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEECFB),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.content_copy_rounded, size: 16, color: _brand),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Appliquer un montant', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, size: 18, color: Color(0xFF9CA3AF)),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ]),
                  ),

                  // Content
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Amount field
                        TextField(
                          controller: amountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: false),
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Montant',
                            hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                            suffixText: 'TND',
                            suffixStyle: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                            filled: true,
                            fillColor: const Color(0xFFF9FAFB),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: AppColors.slate200),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: AppColors.slate200),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _brand, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Niveaux label + select all/none
                        Row(
                          children: [
                            Text(
                              'Niveaux',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () => setState(() {
                                if (selectedNiveaux.length == _sortedNiveaux.length) {
                                  selectedNiveaux.clear();
                                } else {
                                  selectedNiveaux.addAll(_sortedNiveaux.map((n) => n['id']?.toString() ?? '').where((id) => id.isNotEmpty));
                                }
                              }),
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: Text(
                                  selectedNiveaux.length == _sortedNiveaux.length ? 'Tout désélectionner' : 'Tout sélectionner',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _brand),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Niveau chips
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _sortedNiveaux.map((niveau) {
                            final niveauId = niveau['id']?.toString() ?? '';
                            final niveauName = niveau['name']?.toString() ?? 'Niveau';
                            final isSelected = selectedNiveaux.contains(niveauId);
                            return MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      selectedNiveaux.remove(niveauId);
                                    } else {
                                      selectedNiveaux.add(niveauId);
                                    }
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected ? _brand.withOpacity(0.08) : Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected ? _brand : const Color(0xFFE5E7EB),
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isSelected) ...[
                                        Icon(Icons.check_rounded, size: 14, color: _brand),
                                        const SizedBox(width: 6),
                                      ],
                                      Text(
                                        niveauName,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                          color: isSelected ? const Color(0xFF111827) : const Color(0xFF374151),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),

                  // Footer
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          height: 36,
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF374151),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Annuler', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 36,
                          child: ElevatedButton(
                            onPressed: () {
                              final amount = double.tryParse(amountController.text);
                              if (amount != null && amount > 0 && selectedNiveaux.isNotEmpty) {
                                _applyToSelectedNiveaux(selectedNiveaux.toList(), amount);
                                Navigator.pop(ctx);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _brand,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 18),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Appliquer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
    );
  }

  void _applyToSelectedNiveaux(List<String> niveauIds, double amount) {
    for (final niveauId in niveauIds) {
      final sections = _sectionsForNiveau(niveauId);
      _setAmount(niveauId, null, amount);
      for (final section in sections) {
        final secId = section['id']?.toString();
        if (secId != null && secId.isNotEmpty) {
          _setAmount(niveauId, secId, amount);
        }
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    super.dispose();
  }
}

class _PricingAmountField extends StatefulWidget {
  final double? initialValue;
  final ValueChanged<double?> onChanged;
  final Color brandColor;

  const _PricingAmountField({
    super.key,
    required this.initialValue,
    required this.onChanged,
    required this.brandColor,
  });

  @override
  State<_PricingAmountField> createState() => _PricingAmountFieldState();
}

class _PricingAmountFieldState extends State<_PricingAmountField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue != null && widget.initialValue! > 0
          ? widget.initialValue!.toStringAsFixed(0)
          : '',
    );
  }

  @override
  void didUpdateWidget(covariant _PricingAmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      final currentAmount = double.tryParse(_controller.text);
      if (currentAmount != widget.initialValue) {
        _controller.text = widget.initialValue != null && widget.initialValue! > 0
            ? widget.initialValue!.toStringAsFixed(0)
            : '';
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: false),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFF0F172A),
      ),
      textAlign: TextAlign.end,
      decoration: InputDecoration(
        hintText: '0',
        hintStyle: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        suffixText: ' TND',
        suffixStyle: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        filled: false,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: widget.brandColor, width: 2),
        ),
      ),
      onChanged: (v) {
        final amount = double.tryParse(v);
        widget.onChanged(amount);
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DEFAULT PAYMENT METHOD CONFIGURATION DIALOG
// ═══════════════════════════════════════════════════════════════════════════

class _DefaultPaymentMethodDialog extends StatefulWidget {
  final List<Map<String, dynamic>> allNiveaux;

  const _DefaultPaymentMethodDialog({
    required this.allNiveaux,
  });

  @override
  State<_DefaultPaymentMethodDialog> createState() => _DefaultPaymentMethodDialogState();
}

class _DefaultPaymentMethodDialogState extends State<_DefaultPaymentMethodDialog> {
  static const Color _brand = Color(0xFF6D4CF6);
  static const Color _brandLight = Color(0xFFF3E8FF);

  bool _isLoading = true;
  bool _isSaving = false;
  String _defaultMethod = 'monthly';
  final Map<String, String> _niveauOverrides = {};

  static const _methods = [
    ('monthly', 'Mensuel', Icons.calendar_view_month_rounded),
    ('semester', 'Trimestriel', Icons.view_timeline_outlined),
    ('annual', 'Annuel', Icons.event_repeat_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDefault = prefs.getString('default_payment_plan') ?? prefs.getString('default_payment_method');
      if (savedDefault != null && savedDefault.isNotEmpty && _methods.any((m) => m.$1 == savedDefault)) {
        _defaultMethod = savedDefault;
      }
      for (final n in widget.allNiveaux) {
        final id = n['id']?.toString() ?? '';
        final override = prefs.getString('payment_plan_niveau_$id') ?? prefs.getString('payment_method_niveau_$id');
        if (override != null && override.isNotEmpty && _methods.any((m) => m.$1 == override)) {
          _niveauOverrides[id] = override;
        }
      }
    } catch (e) {
      debugPrint('Error loading payment method settings: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('default_payment_plan', _defaultMethod);
      await prefs.setString('default_payment_method', _defaultMethod);
      for (final n in widget.allNiveaux) {
        final id = n['id']?.toString() ?? '';
        final method = _niveauOverrides[id];
        if (method != null && method.isNotEmpty) {
          await prefs.setString('payment_plan_niveau_$id', method);
          await prefs.setString('payment_method_niveau_$id', method);
        } else {
          await prefs.remove('payment_plan_niveau_$id');
          await prefs.remove('payment_method_niveau_$id');
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Plan de paiement par défaut enregistré avec succès'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFriendlyError.format(e, fallback: 'Erreur lors de l\'enregistrement.')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 520,
      height: 640,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.slate200)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _brandLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.tune_rounded, color: _brand, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Plan de paiement par défaut',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Définissez la fréquence de paiement par défaut pour votre établissement',
                        style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.close, size: 20, color: AppColors.textTertiary),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: IosLoader(color: _brand))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // School default method section
                        Row(
                          children: [
                            Container(
                              width: 3,
                              height: 14,
                              decoration: BoxDecoration(
                                color: _brand,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'PLAN PAR DÉFAUT ÉTABLISSEMENT',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // 3 selectable cards
                        GridView.count(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          shrinkWrap: true,
                          childAspectRatio: 2.2,
                          physics: const NeverScrollableScrollPhysics(),
                          children: _methods.map((m) {
                            final isSelected = _defaultMethod == m.$1;
                            return MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () => setState(() => _defaultMethod = m.$1),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFFF5F3FF) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected ? _brand.withOpacity(0.5) : Colors.transparent,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(m.$3, size: 20, color: isSelected ? _brand : AppColors.textSecondary),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          m.$2,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                            color: isSelected ? _brand : AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                      if (isSelected)
                                        const Icon(Icons.check_circle_rounded, size: 16, color: _brand),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 28),

                        // Per-niveau overrides section
                        if (widget.allNiveaux.isNotEmpty) ...[
                          Row(
                            children: [
                              Container(
                                width: 3,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: _brand,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'EXCEPTIONS PAR NIVEAU (OPTIONNEL)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...widget.allNiveaux.map((niveau) {
                            final niveauId = niveau['id']?.toString() ?? '';
                            final niveauName = niveau['name']?.toString() ?? 'Niveau';
                            final currentMethod = _niveauOverrides[niveauId];

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.transparent),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      niveauName,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                  ),
                                  DropdownButtonHideUnderline(
                                    child: DropdownButton<String?>(
                                      value: currentMethod,
                                      borderRadius: BorderRadius.circular(12),
                                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
                                      hint: Text(
                                        'Hériter (${_methods.firstWhere((m) => m.$1 == _defaultMethod).$2})',
                                        style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                                      ),
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF1E293B)),
                                      items: [
                                        DropdownMenuItem<String?>(
                                          value: null,
                                          child: Text(
                                            'Hériter du défaut',
                                            style: TextStyle(color: AppColors.textTertiary),
                                          ),
                                        ),
                                        ..._methods.map(
                                          (m) => DropdownMenuItem<String?>(
                                            value: m.$1,
                                            child: Text(m.$2),
                                          ),
                                        ),
                                      ],
                                      onChanged: (val) {
                                        setState(() {
                                          if (val == null) {
                                            _niveauOverrides.remove(niveauId);
                                          } else {
                                            _niveauOverrides[niveauId] = val;
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.slate200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  height: 42,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.slate100,
                      foregroundColor: AppColors.textPrimary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Fermer', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 42,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveSettings,
                    icon: _isSaving
                        ? const SizedBox(width: 18, height: 18, child: IosLoader.small(color: Colors.white))
                        : const Icon(Icons.save, size: 18),
                    label: const Text('Enregistrer', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brand,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      shadowColor: _brand.withOpacity(0.3),
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
}
