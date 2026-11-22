import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as rp;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../providers/results_provider.dart';
import '../providers/semesters_provider.dart';
import '../widgets/results/grading_config_dialog.dart';
import '../widgets/results/single_student_grade_entry.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/user_avatar.dart';

/// View mode for the results screen
enum ResultsViewState {
  overview, // Show students/class overview
  gradeEntry, // Grade entry mode for selected student
}

/// Modern Results Management Screen
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  final _searchController = TextEditingController();
  bool _showFilterDrawer = false;
  ResultsViewState _viewState = ResultsViewState.overview;
  
  /// Selected students for bulk action
  final Set<String> _selectedStudentsForBulk = {};

  /// Currently selected student for grade entry
  Map<String, dynamic>? _selectedStudentForGradeEntry;

  // Pagination state
  int _currentPage = 1;
  int _itemsPerPage = 20;
  static const List<int> _perPageOptions = [10, 20, 50, 100, -1];


  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleFilters() {
    setState(() {
      _showFilterDrawer = !_showFilterDrawer;
    });
  }

  void _selectStudentForGradeEntry(Map<String, dynamic> student) {
    setState(() {
      _selectedStudentForGradeEntry = student;
      _viewState = ResultsViewState.gradeEntry;
      _searchController.clear();
      providerRef?.setSearchQuery('');
    });
  }

  void _backToOverview() {
    setState(() {
      _selectedStudentForGradeEntry = null;
      _selectedStudentsForBulk.clear();
      _viewState = ResultsViewState.overview;
      _searchController.clear();
      providerRef?.setSearchQuery('');
    });
    providerRef?.loadClassGrades();
  }

  ({int totalSubjects, int collectedCount, double? semesterAverage, bool allCollected}) _calculateStudentProgress(
    ResultsProvider provider,
    String enrollmentId,
  ) {
    final offerings = provider.subjectOfferings;
    final totalSubjects = offerings.length;
    if (totalSubjects == 0) {
      return (totalSubjects: 0, collectedCount: 0, semesterAverage: null, allCollected: false);
    }

    final grades = provider.gradesByEnrollmentId[enrollmentId] ?? [];
    int collectedCount = 0;
    double totalWeightedMoyenne = 0;
    double totalCoefficients = 0;

    for (final offering in offerings) {
      final offeringId = offering['id']?.toString();
      final coef = (offering['coefficient'] as num?)?.toDouble() ?? 1.0;
      final components = (offering['grade_components'] as List?) ?? [];

      if (components.isNotEmpty) {
        bool allComponentsFilled = true;
        double compWeightedSum = 0;
        double compTotalWeight = 0;

        for (final comp in components) {
          final compMap = comp as Map<String, dynamic>;
          final compId = compMap['id']?.toString();
          final weight = (compMap['weight_percent'] as num?)?.toDouble() ?? 0.0;

          Map<String, dynamic>? gradeEntry;
          for (final g in grades) {
            if (g['subject_offering_id']?.toString() == offeringId &&
                g['component_id']?.toString() == compId) {
              gradeEntry = g;
              break;
            }
          }

          if (gradeEntry == null) {
            allComponentsFilled = false;
            break;
          }

          final status = gradeEntry['status']?.toString() ?? 'OK';
          final val = gradeEntry['grade_value'];

          if (val == null && status == 'OK') {
            allComponentsFilled = false;
            break;
          }

          if (val != null) {
            final numVal = (val as num).toDouble();
            compWeightedSum += numVal * weight;
            compTotalWeight += weight;
          }
        }

        if (allComponentsFilled) {
          collectedCount++;
          final subjectAvg = compTotalWeight > 0 ? (compWeightedSum / compTotalWeight) : 0.0;
          totalWeightedMoyenne += subjectAvg * coef;
          totalCoefficients += coef;
        }
      } else {
        Map<String, dynamic>? gradeEntry;
        for (final g in grades) {
          if (g['subject_offering_id']?.toString() == offeringId) {
            gradeEntry = g;
            break;
          }
        }

        if (gradeEntry != null &&
            (gradeEntry['grade_value'] != null || (gradeEntry['status'] != null && gradeEntry['status'] != 'OK'))) {
          collectedCount++;
          final val = (gradeEntry['grade_value'] as num?)?.toDouble() ?? 0.0;
          totalWeightedMoyenne += val * coef;
          totalCoefficients += coef;
        }
      }
    }

    final allCollected = totalSubjects > 0 && collectedCount == totalSubjects;
    double? semesterAverage;
    if (allCollected && totalCoefficients > 0) {
      semesterAverage = totalWeightedMoyenne / totalCoefficients;
    }

    return (
      totalSubjects: totalSubjects,
      collectedCount: collectedCount,
      semesterAverage: semesterAverage,
      allCollected: allCollected,
    );
  }

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

  bool get _hasActiveFilters => false;

  ResultsProvider? providerRef;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final provider = ResultsProvider(Supabase.instance.client);
        provider.initialize();
        return provider;
      },
      child: rp.Consumer(
        builder: (context, ref, _) {
          final activeSemesterId = ref.watch(currentActiveSemesterIdProvider);
          return Consumer<ResultsProvider>(
            builder: (context, provider, _) {
              providerRef = provider;
              if (activeSemesterId != null && provider.selectedSemesterId != activeSemesterId) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  provider.setSemester(activeSemesterId);
                });
              }
              return Scaffold(
                backgroundColor: AppColors.background,
                body: Stack(
                  children: [
                    Row(
                      children: [
                        const AdminSidebar(currentRoute: '/results'),
                        Expanded(
                          child: Column(
                            children: [
                              _buildHeader(context, provider),
                              Expanded(
                                child: _buildMainContent(context, provider),
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
                        child: _buildFilterDrawer(context, provider),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════
  Widget _buildHeader(BuildContext context, ResultsProvider provider) {
    final className = _getSelectedClassName(provider);
    final isSearching = provider.searchQuery.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE9EAF2))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (provider.selectedClassId != null) ...[
            Container(
              margin: const EdgeInsets.only(right: 16),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(18),
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.arrow_back, size: 18, color: Color(0xFF4B5563)),
                onPressed: () {
                  if (_viewState == ResultsViewState.gradeEntry || _selectedStudentForGradeEntry != null) {
                    _backToOverview();
                  } else {
                    setState(() {
                      provider.setClass(null);
                      _selectedStudentForGradeEntry = null;
                      _viewState = ResultsViewState.overview;
                    });
                  }
                },
              ),
            ),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Résultats',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                className.isNotEmpty ? 'Classe : $className' : 'Sélectionnez une classe pour commencer',
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
              onChanged: provider.setSearchQuery,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: (_viewState == ResultsViewState.gradeEntry && _selectedStudentForGradeEntry != null)
                    ? 'Rechercher une matière...'
                    : 'Rechercher un élève...',
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
                          provider.setSearchQuery('');
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
          _buildHeaderIconButton(
            icon: Icons.filter_list_rounded,
            tooltip: 'Filtres',
            isActive: _showFilterDrawer || _hasActiveFilters,
            onPressed: _toggleFilters,
          ),
          const SizedBox(width: 8),
          _buildHeaderIconButton(
            icon: Icons.file_download_outlined,
            tooltip: 'Exporter',
            onPressed: () {},
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
  // FILTER DRAWER (right side)
  // ═══════════════════════════════════════════════════
  Widget _buildFilterDrawer(BuildContext context, ResultsProvider provider) {
    return Material(
      elevation: 16,
      color: Colors.white,
      child: SizedBox(
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
                    _buildFilterLabel('NIVEAU'),
                    const SizedBox(height: 8),
                    Builder(builder: (context) {
                      final sortedNiveaux = List<Map<String, dynamic>>.from(provider.niveaux)
                        ..sort((a, b) {
                          final nameA = a['name']?.toString() ?? a['code']?.toString();
                          final nameB = b['name']?.toString() ?? b['code']?.toString();
                          final orderA = _getNiveauSortOrder(nameA);
                          final orderB = _getNiveauSortOrder(nameB);
                          if (orderA != orderB) return orderA.compareTo(orderB);
                          return (nameA ?? '').compareTo(nameB ?? '');
                        });
                      return _buildFilterDropdown<String?>(
                        value: provider.selectedNiveauId,
                        hint: 'Tous les niveaux',
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Tous les niveaux')),
                          ...sortedNiveaux.map((n) => DropdownMenuItem(value: n['id'].toString(), child: Text(n['name']))),
                        ],
                        onChanged: (v) => provider.setNiveau(v),
                      );
                    }),
                    const SizedBox(height: 20),

                    if (provider.selectedNiveauHasSections) ...[
                      _buildFilterLabel('FILIÈRE'),
                      const SizedBox(height: 8),
                      _buildFilterDropdown<String?>(
                        value: provider.selectedSectionId,
                        hint: 'Toutes les filières',
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Toutes les filières')),
                          ...provider.filteredSections.map((s) => DropdownMenuItem(value: s['id'].toString(), child: Text(s['name']))),
                        ],
                        onChanged: (v) => provider.setSection(v),
                      ),
                      const SizedBox(height: 20),
                    ],

                    _buildFilterLabel('CLASSE'),
                    const SizedBox(height: 8),
                    Builder(builder: (context) {
                      final sortedClasses = List<Map<String, dynamic>>.from(provider.filteredClasses)
                        ..sort((a, b) => (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));
                      return _buildFilterDropdown<String?>(
                        value: provider.selectedClassId,
                        hint: 'Toutes les classes',
                        items: sortedClasses.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['name']))).toList(),
                        onChanged: (v) => provider.setClass(v),
                      );
                    }),
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
                          provider.setNiveau(null);
                          provider.setSection(null);
                          provider.setClass(null);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF374151),
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFFD1D5DB)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                          BoxShadow(color: const Color(0xFF6D4CF6).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => setState(() => _showFilterDrawer = false),
                          borderRadius: BorderRadius.circular(12),
                          child: const Center(
                            child: Text('Appliquer', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
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
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textTertiary, letterSpacing: 1.0),
    );
  }

  Widget _buildFilterDropdown<T>({
    required T value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    // Prevent rendering error if value is not in items list
    final values = items.map((e) => e.value).toList();
    final safeValue = values.contains(value) ? value : null;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: safeValue,
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

  /// Direct navigation to grade entry for any student
  void _navigateToStudentGradeEntry(ResultsProvider provider, Map<String, dynamic> student) {
    final academicYearId = student['academic_year_id'] as String?;
    if (academicYearId != null && academicYearId != provider.selectedAcademicYearId) {
      provider.setAcademicYear(academicYearId);
    }
    final classId = student['class_id'] as String? ?? student['classes']?['id'] as String?;
    if (classId != null) {
      provider.setClass(classId);
    }
    provider.setSearchQuery('');
    _searchController.clear();
    _selectStudentForGradeEntry(student);
  }

  /// Build search results view — searches ALL enrolled students globally
  Widget _buildSearchResults(BuildContext context, ResultsProvider provider) {
    final query = provider.searchQuery.toLowerCase();
    final all = provider.allEnrolledStudents.isNotEmpty
        ? provider.allEnrolledStudents
        : provider.enrolledStudents;
    final students = query.isEmpty
        ? all
        : all.where((s) {
            final user = s['users'] as Map<String, dynamic>? ?? {};
            final name = (user['full_name'] ?? '').toString().toLowerCase();
            final code = (s['student_code'] ?? user['student_code'] ?? '').toString().toLowerCase();
            final className = (s['classes']?['name'] ?? '').toString().toLowerCase();
            return name.contains(query) || code.contains(query) || className.contains(query);
          }).toList();

    return Container(
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
                child: students.isEmpty
                    ? _buildEmptyState('Aucun élève trouvé', Icons.search_off)
                    : _buildStudentDataTable(context, provider, students),
              ),
              _buildPagination(students.length),
            ],
          ),
        ),
      ),
    );
  }

  /// Main content area
  Widget _buildMainContent(BuildContext context, ResultsProvider provider) {
    if (provider.isLoading) return _buildLoadingState(provider);

    final isInSingleGradeEntry = _viewState == ResultsViewState.gradeEntry && _selectedStudentForGradeEntry != null;
    if (provider.searchQuery.isNotEmpty && !isInSingleGradeEntry) {
      return _buildSearchResults(context, provider);
    }

    if (provider.selectedClassId == null) {
      return _buildNiveauxCardsView(context, provider);
    }

    switch (_viewState) {
      case ResultsViewState.gradeEntry:
        return _buildGradeEntryView(context, provider);
      case ResultsViewState.overview:
        return _buildOverviewView(context, provider);
    }
  }



  /// Grade entry view - For a single selected student
  Widget _buildGradeEntryView(BuildContext context, ResultsProvider provider) {
    if (provider.selectedSemesterId == null) {
      return _buildEmptyState(
        'Sélectionnez un semestre',
        Icons.warning_amber,
        subtitle: 'Choisissez un semestre dans le panneau de filtres pour accéder à la saisie',
      );
    }

    if (_selectedStudentForGradeEntry == null) {
      return _buildStudentSelectionForGrades(context, provider);
    }

    return SingleStudentGradeEntry(
      student: _selectedStudentForGradeEntry!,
      subjectOfferings: provider.subjectOfferings,
      levelId: provider.selectedNiveauId,
      semesterId: provider.selectedSemesterId,
      externalSearchQuery: provider.searchQuery,
      onSaveGrades: (grades) async {
        for (final grade in grades) {
          await provider.saveGrade(
            enrollmentId: grade['enrollment_id'],
            studentId: grade['student_id'],
            subjectOfferingId: grade['subject_offering_id'],
            componentId: grade['component_id'],
            value: grade['grade_value'],
            status: grade['status'] ?? 'OK',
          );
        }
      },
      onBack: _backToOverview,
      onRefresh: () => provider.loadSubjectOfferings(),
    );
  }

  /// Build student selection list for grade entry
  Widget _buildStudentSelectionForGrades(BuildContext context, ResultsProvider provider) {
    final students = provider.enrolledStudents;

    if (students.isEmpty) {
      return _buildEmptyState('Aucun élève trouvé', Icons.people_outline, subtitle: 'Sélectionnez une classe pour voir les élèves');
    }

    return Container(
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
                child: _buildStudentDataTable(context, provider, students),
              ),
              _buildPagination(students.length),
            ],
          ),
        ),
      ),
    );
  }

  /// Overview view — click student row to go directly to grade entry
  Widget _buildOverviewView(BuildContext context, ResultsProvider provider) {
    final students = provider.enrolledStudents;

    if (students.isEmpty) {
      return _buildEmptyState('Aucun élève inscrit', Icons.people_outline, subtitle: 'Cette classe n\'a pas encore d\'élèves inscrits');
    }

    return Container(
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
                child: _buildStudentDataTable(context, provider, students),
              ),
              _buildPagination(students.length),
            ],
          ),
        ),
      ),
    );
  }

  // Shared student table — every row navigates directly to grade entry
  Widget _buildStudentDataTable(BuildContext context, ResultsProvider provider, List<Map<String, dynamic>> students) {
    if (provider.gradesByEnrollmentId.isEmpty && students.isNotEmpty && !provider.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        provider.loadClassGrades();
      });
    }

    final sortedStudents = List<Map<String, dynamic>>.from(students)..sort((a, b) {
      final userA = a['users'] as Map<String, dynamic>? ?? {};
      final userB = b['users'] as Map<String, dynamic>? ?? {};
      final nameA = (userA['full_name']?.toString() ?? '').toLowerCase();
      final nameB = (userB['full_name']?.toString() ?? '').toLowerCase();
      final cmp = nameA.compareTo(nameB);
      if (cmp != 0) return cmp;
      final codeA = (a['student_code'] ?? userA['student_code'] ?? '').toString();
      final codeB = (b['student_code'] ?? userB['student_code'] ?? '').toString();
      final codeCmp = codeA.compareTo(codeB);
      if (codeCmp != 0) return codeCmp;
      return (a['id']?.toString() ?? '').compareTo(b['id']?.toString() ?? '');
    });

    final totalPages = _itemsPerPage == -1 ? 1 : (sortedStudents.length / _itemsPerPage).ceil();
    if (_currentPage > totalPages && totalPages > 0) _currentPage = totalPages;
    final startIndex = _itemsPerPage == -1 ? 0 : (_currentPage - 1) * _itemsPerPage;
    final endIndex = _itemsPerPage == -1 ? sortedStudents.length : (startIndex + _itemsPerPage).clamp(0, sortedStudents.length);
    final pageStudents = sortedStudents.sublist(startIndex, endIndex);
    final allPageSelected = pageStudents.isNotEmpty && pageStudents.every((s) => _selectedStudentsForBulk.contains(s['id'].toString()));

    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            const checkboxW = 44.0;
            const niveauW = 130.0;
            const classeW = 95.0;
            const moyenneW = 160.0;
            const createdW = 120.0;
            const actionsW = 48.0;

            final totalFixed = checkboxW + niveauW + classeW + moyenneW + createdW + actionsW;
            final nameW = (availableWidth - totalFixed).clamp(240.0, 500.0);
            final minTotalW = totalFixed + nameW;

            return SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: availableWidth > minTotalW ? availableWidth : minTotalW),
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
                                value: allPageSelected && pageStudents.isNotEmpty,
                                tristate: false,
                                onChanged: (val) {
                                  setState(() {
                                    if (allPageSelected) {
                                      for (final s in pageStudents) _selectedStudentsForBulk.remove(s['id'].toString());
                                    } else {
                                      for (final s in pageStudents) _selectedStudentsForBulk.add(s['id'].toString());
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
                      DataColumn(label: SizedBox(width: niveauW, child: _headerLabel('NIVEAU'))),
                      DataColumn(label: SizedBox(width: classeW, child: _headerLabel('CLASSE'))),
                      DataColumn(label: SizedBox(width: moyenneW, child: _headerLabel('MOYENNE SEMESTRE'))),
                      DataColumn(label: SizedBox(width: createdW, child: _headerLabel('CRÉÉ LE'))),
                      DataColumn(label: SizedBox(width: actionsW, child: Container())),
                    ],
                    rows: List.generate(pageStudents.length, (i) {
                      final student = pageStudents[i];
                      final studentId = student['id'].toString();
                      final isSelected = _selectedStudentsForBulk.contains(studentId);
                      final user = student['users'] as Map<String, dynamic>? ?? {};
                      final fullName = user['full_name']?.toString() ?? 'Nom inconnu';
                      final email = user['email']?.toString() ?? '—';
                      final gender = user['gender']?.toString();
                      final niveauName = student['classes']?['niveaux']?['name']?.toString() ??
                          student['classes']?['niveaux']?['code']?.toString() ??
                          _getSelectedNiveauName(provider);
                      final className = student['classes']?['name']?.toString() ?? _getSelectedClassName(provider);
                      final createdAtRaw = user['created_at']?.toString();
                      final createdAt = createdAtRaw != null ? DateTime.tryParse(createdAtRaw) : null;

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
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) {
                                          _selectedStudentsForBulk.add(studentId);
                                        } else {
                                          _selectedStudentsForBulk.remove(studentId);
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
                          // Name + Email with avatar
                          DataCell(
                            SizedBox(
                              width: nameW,
                              child: Row(
                                children: [
                                  UserAvatar(
                                    name: fullName,
                                    photoUrl: user['photo_url']?.toString(),
                                    gender: gender,
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
                            onTap: () => _navigateToStudentGradeEntry(provider, student),
                          ),
                          // Niveau
                          DataCell(
                            SizedBox(
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
                                    niveauName.isNotEmpty ? niveauName : '—',
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF7C3AED)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                            onTap: () => _navigateToStudentGradeEntry(provider, student),
                          ),
                          // Classe
                          DataCell(
                            SizedBox(
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
                                    className,
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF059669)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                            onTap: () => _navigateToStudentGradeEntry(provider, student),
                          ),
                          // Moyenne Semestre or Notes Collected pill
                          DataCell(
                            SizedBox(
                              width: moyenneW,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: () {
                                  final progress = _calculateStudentProgress(provider, studentId);
                                  if (progress.allCollected && progress.semesterAverage != null) {
                                    final avg = progress.semesterAverage!;
                                    final isPassing = avg >= 10.0;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isPassing ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                                        borderRadius: BorderRadius.circular(9999),
                                        border: Border.all(
                                          color: isPassing ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            avg.toStringAsFixed(2),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: isPassing ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                            ),
                                          ),
                                          Text(
                                            ' / 20',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500,
                                              color: isPassing ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  } else {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFFBEB),
                                        borderRadius: BorderRadius.circular(9999),
                                        border: Border.all(color: const Color(0xFFFDE68A)),
                                      ),
                                      child: Text(
                                        progress.totalSubjects > 0
                                            ? '${progress.collectedCount} / ${progress.totalSubjects} matière${progress.totalSubjects > 1 ? 's' : ''}'
                                            : '0 matière',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFFB45309),
                                        ),
                                      ),
                                    );
                                  }
                                }(),
                              ),
                            ),
                            onTap: () => _navigateToStudentGradeEntry(provider, student),
                          ),
                          // Créé le
                          DataCell(
                            SizedBox(
                              width: createdW,
                              child: Text(
                                createdAt != null ? DateFormat('d MMM yyyy', 'fr_FR').format(createdAt) : '—',
                                style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onTap: () => _navigateToStudentGradeEntry(provider, student),
                          ),
                          // Actions (3-dots popup menu)
                          DataCell(
                            SizedBox(
                              width: actionsW,
                              child: PopupMenuButton<String>(
                                icon: Icon(Icons.more_horiz, size: 18, color: AppColors.textTertiary),
                                tooltip: 'Actions',
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 8,
                                offset: const Offset(-160, 40),
                                onSelected: (action) {
                                  if (action == 'enter_grades') {
                                    _navigateToStudentGradeEntry(provider, student);
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  PopupMenuItem(
                                    value: 'enter_grades',
                                    child: Row(
                                      children: [
                                        const Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFF6D4CF6)),
                                        const SizedBox(width: 8),
                                        const Text('Saisir les notes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            );
          },
        ),
        if (_selectedStudentsForBulk.isNotEmpty)
          Positioned(
            left: 0, right: 0, bottom: 24,
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
                                child: Text('${_selectedStudentsForBulk.length}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('Sélectionnés', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white)),
                          ],
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          if (provider.subjectOfferings.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Aucune matière pour cette classe.')),
                            );
                            return;
                          }
                          if (provider.selectedSemesterId == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Veuillez sélectionner un semestre.')),
                            );
                            return;
                          }
                          final selectedObjs = provider.enrolledStudents
                              .where((s) => _selectedStudentsForBulk.contains(s['id'].toString()))
                              .toList();
                          if (selectedObjs.isNotEmpty) {
                            final target = selectedObjs.first;
                            setState(() => _selectedStudentsForBulk.clear());
                            _navigateToStudentGradeEntry(provider, target);
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.edit_note, size: 16, color: Colors.white70),
                              SizedBox(width: 6),
                              Text('Saisie des notes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white70)),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          border: Border(left: BorderSide(color: Colors.white.withOpacity(0.15))),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.close, size: 16, color: Colors.white60),
                          onPressed: () => setState(() => _selectedStudentsForBulk.clear()),
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
    );
  }

  Widget _headerLabel(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
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
          Text(
            'Page $_currentPage sur ${totalPages == 0 ? 1 : totalPages}',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          const SizedBox(width: 12),
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

  Widget _buildEmptyState(String title, IconData icon, {String? subtitle}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: AppColors.textTertiary.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }


  // ═══════════════════════════════════════════════════
  // NIVEAUX BROWSE VIEW — exact grade_levels design
  // ═══════════════════════════════════════════════════
  Widget _buildNiveauxCardsView(BuildContext context, ResultsProvider provider) {
    if (provider.isLoading) return _buildLoadingState(provider);
    if (provider.niveaux.isEmpty) {
      return _buildEmptyState('Aucun niveau trouvé', Icons.school_outlined,
          subtitle: 'Configurez vos niveaux dans la section Niveaux & Filières');
    }

    final semLabel = provider.selectedSemesterId != null
        ? provider.semesters
            .where((s) => s['id'] == provider.selectedSemesterId)
            .map((s) => s['name']?.toString() ?? '—')
            .firstOrNull
        : null;

    return Container(
      color: const Color(0xFFF6F6F8),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info row — semester badge
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  const Text('Choisissez une classe',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                  const Spacer(),
                  if (semLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.slate200,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        semLabel.toUpperCase(),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.slate600, letterSpacing: 0.5),
                      ),
                    ),
                ],
              ),
            ),
            // Cycle card wrapper
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.slate200),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF655DD5).withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 4)),
                  BoxShadow(color: const Color(0xFF655DD5).withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2)),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  // Card header — matches _buildCycleCard header exactly
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      border: Border(bottom: BorderSide(color: AppColors.slate200)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFF655DD5).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(child: Icon(Icons.school, color: Color(0xFF655DD5), size: 20)),
                        ),
                        const SizedBox(width: 12),
                        const Text('Niveaux', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.slate200, borderRadius: BorderRadius.circular(999)),
                          child: Text(
                            '${provider.niveaux.length} NIVEAUX',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.slate600, letterSpacing: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Niveau rows — sorted from 7ème to Bac
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Builder(builder: (context) {
                      final sortedNiveaux = List<Map<String, dynamic>>.from(provider.niveaux)
                        ..sort((a, b) {
                          final nameA = a['name']?.toString() ?? a['code']?.toString();
                          final nameB = b['name']?.toString() ?? b['code']?.toString();
                          final orderA = _getNiveauSortOrder(nameA);
                          final orderB = _getNiveauSortOrder(nameB);
                          if (orderA != orderB) return orderA.compareTo(orderB);
                          return (nameA ?? '').compareTo(nameB ?? '');
                        });

                      return Column(
                        children: sortedNiveaux.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final niveau = entry.value;
                          final niveauClasses = provider.classes
                              .where((c) => c['niveau_id'] == niveau['id'])
                              .toList()
                            ..sort((a, b) => (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));
                          return Column(
                            children: [
                              _HoverableNiveauRow(
                                niveau: niveau,
                                classes: niveauClasses,
                                onClassTap: (classId) {
                                  provider.setClass(classId);
                                  provider.setSearchQuery('');
                                  _searchController.clear();
                                  setState(() => _viewState = ResultsViewState.overview);
                                },
                              ),
                              if (idx < sortedNiveaux.length - 1) const SizedBox(height: 16),
                            ],
                          );
                        }).toList(),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // STUDENT SEARCH DIALOG
  // ═══════════════════════════════════════════════════
  // ignore: unused_element
  void _showStudentSearchDialog(BuildContext context, ResultsProvider provider) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (ctx) => _StudentSearchDialog(
        provider: provider,
        onStudentSelected: (student) {
          final academicYearId = student['academic_year_id'] as String?;
          if (academicYearId != null && academicYearId != provider.selectedAcademicYearId) {
            provider.setAcademicYear(academicYearId);
          }
          final classId = student['class_id'] as String? ?? student['classes']?['id'] as String?;
          if (classId != null) {
            provider.setClass(classId);
            _selectStudentForGradeEntry(student);
            Navigator.pop(ctx);
          }
        },
      ),
    );
  }

  Widget _buildLoadingState([ResultsProvider? provider]) {
    if (provider != null && provider.selectedClassId != null) {
      return const ResultsStudentListSkeletonLoader();
    }
    return const ResultsSkeletonLoader();
  }

  // Helper methods
  String _getSelectedClassName(ResultsProvider provider) {
    final cls = provider.classes
        .where((c) => c['id'] == provider.selectedClassId)
        .firstOrNull;
    return cls?['name'] ?? '';
  }

  String _getSelectedNiveauName(ResultsProvider provider) {
    final niv = provider.niveaux
        .where((n) => n['id'] == provider.selectedNiveauId)
        .firstOrNull;
    return niv?['name'] ?? '';
  }

  // ignore: unused_element
  void _showSettingsDialog(BuildContext context, ResultsProvider provider) {
    showDialog(
      context: context,
      builder: (context) => ChangeNotifierProvider.value(
        value: provider,
        child: GradingConfigDialog(
          initialConfig: provider.gradingConfig,
          onSave: (config) {
            provider.saveGradingConfig(config);
          },
        ),
      ),
    );
  }

}

// ═══════════════════════════════════════════════════
// HOVERABLE NIVEAU ROW — exact _HoverableGradeRow pattern from grade_levels
// ═══════════════════════════════════════════════════
class _HoverableNiveauRow extends StatefulWidget {
  final Map<String, dynamic> niveau;
  final List<Map<String, dynamic>> classes;
  final void Function(String classId) onClassTap;

  const _HoverableNiveauRow({
    required this.niveau,
    required this.classes,
    required this.onClassTap,
  });

  @override
  State<_HoverableNiveauRow> createState() => _HoverableNiveauRowState();
}

class _HoverableNiveauRowState extends State<_HoverableNiveauRow> {
  String? _selectedSectionId;

  @override
  Widget build(BuildContext context) {
    final niveau = widget.niveau;
    final hasSections = niveau['has_sections'] == true;

    // Derive sections from classes (each class may have cls['sections'] nested)
    final Map<String, String> sectionMap = {}; // sectionId -> sectionName
    for (final cls in widget.classes) {
      final sectionId = cls['section_id'] as String?;
      final sectionName = cls['sections']?['name']?.toString();
      if (sectionId != null && sectionName != null) {
        sectionMap[sectionId] = sectionName;
      }
    }

    // Filter by selected section
    final displayedClasses = _selectedSectionId != null
        ? widget.classes.where((c) => c['section_id'] == _selectedSectionId).toList()
        : widget.classes;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.slate100),
        borderRadius: BorderRadius.circular(12),
        color: Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row — same as _HoverableGradeRow
          Row(
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(
                      niveau['name']?.toString() ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                    ),
                    Text(
                      '• ${widget.classes.length} classe${widget.classes.length != 1 ? 's' : ''}',
                      style: TextStyle(fontSize: 12, color: AppColors.slate400),
                    ),
                  ],
                ),
              ),
              if (niveau['code'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF655DD5).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    niveau['code'].toString(),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF655DD5)),
                  ),
                ),
            ],
          ),
          // Filières filter — same as _HoverableGradeRow sections row
          if (hasSections && sectionMap.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'FILIÈRES',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.slate400, letterSpacing: 0.5),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: sectionMap.entries.map((entry) {
                      final isSelected = _selectedSectionId == entry.key;
                      return InkWell(
                        onTap: () => setState(() {
                          _selectedSectionId = isSelected ? null : entry.key;
                        }),
                        borderRadius: BorderRadius.circular(4),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF655DD5).withOpacity(0.12) : AppColors.slate100,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF655DD5).withOpacity(0.4) : AppColors.slate200,
                            ),
                          ),
                          child: Text(
                            entry.value,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? const Color(0xFF655DD5) : AppColors.slate500,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],
          // Class pills — exact _classPill design from grade_levels
          const SizedBox(height: 12),
          displayedClasses.isEmpty
              ? Text('Aucune classe', style: TextStyle(fontSize: 12, color: AppColors.slate400))
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: displayedClasses.map((cls) {
                    return InkWell(
                      onTap: () => widget.onClassTap(cls['id'] as String),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.slate200),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 2, offset: const Offset(0, 1))],
                        ),
                        child: Text(
                          cls['name']?.toString() ?? '',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.slate600),
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// STUDENT SEARCH DIALOG WIDGET
// ═══════════════════════════════════════════════════
class _StudentSearchDialog extends StatefulWidget {
  final ResultsProvider provider;
  final void Function(Map<String, dynamic>) onStudentSelected;

  const _StudentSearchDialog({
    required this.provider,
    required this.onStudentSelected,
  });

  @override
  State<_StudentSearchDialog> createState() => _StudentSearchDialogState();
}

class _StudentSearchDialogState extends State<_StudentSearchDialog> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    final all = widget.provider.allEnrolledStudents.isNotEmpty
        ? widget.provider.allEnrolledStudents
        : widget.provider.enrolledStudents;
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((s) {
      final user = s['users'] as Map<String, dynamic>? ?? {};
      final name = (user['full_name'] ?? '').toString().toLowerCase();
      final code = (s['student_code'] ?? user['student_code'] ?? '').toString().toLowerCase();
      final className = (s['classes']?['name'] ?? '').toString().toLowerCase();
      return name.contains(q) || code.contains(q) || className.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filtered = _filtered;

    return Dialog(
      child: Container(
        width: 520,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header — matches BulkGradeEntryDialog / GradingConfigDialog pattern
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.person_search, color: colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ajouter une note', style: theme.textTheme.headlineSmall),
                      Text(
                        'Cherchez un élève pour saisir ses notes',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Search field — matches users_screen search bar pattern
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Rechercher par nom ou matricule...',
                hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textTertiary),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () { _searchCtrl.clear(); setState(() => _query = ''); },
                      )
                    : null,
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
                  borderSide: BorderSide(color: colorScheme.primary.withOpacity(0.4), width: 1.5),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Results header row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 48),
                  Expanded(child: Text('Élève', style: theme.textTheme.titleSmall)),
                  Text('Classe', style: theme.textTheme.titleSmall),
                  const SizedBox(width: 24),
                ],
              ),
            ),

            // Results list
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _query.isEmpty ? Icons.person_search_outlined : Icons.search_off,
                            size: 48,
                            color: colorScheme.outlineVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _query.isEmpty ? 'Commencez à taper un nom...' : 'Aucun élève trouvé',
                            style: TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      padding: EdgeInsets.zero,
                      itemBuilder: (ctx, i) {
                        final student = filtered[i];
                        final user = student['users'] as Map<String, dynamic>? ?? {};
                        final name = user['full_name']?.toString() ?? 'Nom inconnu';
                        final code = (student['student_code'] ?? user['student_code'] ?? '—').toString();
                        final className = student['classes']?['name']?.toString() ?? '—';
                        return InkWell(
                          onTap: () => widget.onStudentSelected(student),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: AppColors.border.withOpacity(0.5)),
                              ),
                            ),
                            child: Row(
                              children: [
                                UserAvatar(name: name, photoUrl: user['photo_url']?.toString(), radius: 16),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(name,
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 2),
                                      Text(code,
                                          style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                                          overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                                Text(className,
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward_ios, size: 12, color: AppColors.textTertiary),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
