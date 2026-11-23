import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../../core/utils/error_messages.dart';
import '../../data/models/grading_config_model.dart';
import '../../data/models/student_result_model.dart';
import '../../data/models/tunisian_coefficients.dart';
import '../../repositories/results_repository.dart';

/// Filter options for results
enum ResultsFilterType {
  byStudent, // Single student
  byClass, // By class
  byGradeLevel, // By grade level (all classes)
  bySchool, // Entire school
}

/// View mode for results
enum ResultsViewMode {
  table, // Table view
  cards, // Card view
  bulletin, // Report card view
}

/// Provider for managing results/grades
class ResultsProvider extends ChangeNotifier {
  final ResultsRepository _repository;
  final SupabaseClient _client;

  ResultsProvider(SupabaseClient client)
    : _client = client,
      _repository = ResultsRepository(client);

  // State
  bool _isLoading = true;
  String? _error;

  // Filters
  String? _selectedAcademicYearId;
  String? _selectedSemesterId;
  String? _selectedNiveauId;
  String? _selectedSectionId;
  String? _selectedClassId;
  String _searchQuery = '';
  ResultsFilterType _filterType = ResultsFilterType.byClass;
  ResultsViewMode _viewMode = ResultsViewMode.table;

  // Data
  List<Map<String, dynamic>> _academicYears = [];
  List<Map<String, dynamic>> _semesters = [];
  List<Map<String, dynamic>> _niveaux = [];
  List<Map<String, dynamic>> _sections = [];
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _subjectOfferings = [];
  List<Map<String, dynamic>> _enrolledStudents = [];
  List<Map<String, dynamic>> _allEnrolledStudents = []; // global search (not filtered by class)

  // Results
  ClassResult? _classResult;
  StudentResult? _selectedStudentResult;
  GradingConfiguration? _gradingConfig;
  Map<String, List<Map<String, dynamic>>> _gradesByEnrollmentId = {};

  // Getters
  bool get isLoading => _isLoading;
  String? get error => _error;

  String? get selectedAcademicYearId => _selectedAcademicYearId;
  String? get selectedSemesterId => _selectedSemesterId;
  String? get selectedNiveauId => _selectedNiveauId;
  String? get selectedSectionId => _selectedSectionId;
  String? get selectedClassId => _selectedClassId;
  String get searchQuery => _searchQuery;
  ResultsFilterType get filterType => _filterType;
  ResultsViewMode get viewMode => _viewMode;

  List<Map<String, dynamic>> get academicYears => _academicYears;
  List<Map<String, dynamic>> get semesters => _semesters;
  List<Map<String, dynamic>> get niveaux => _niveaux;
  List<Map<String, dynamic>> get sections => _sections;
  List<Map<String, dynamic>> get classes => _classes;

  /// Get classes filtered by selected niveau
  List<Map<String, dynamic>> get filteredClasses {
    if (_selectedNiveauId == null) {
      return _classes;
    }
    final base = _classes.where((c) => c['niveau_id'] == _selectedNiveauId);
    if (_selectedSectionId == null) {
      return base.toList();
    }
    return base.where((c) => c['section_id'] == _selectedSectionId).toList();
  }

  /// Get sections filtered by selected niveau
  List<Map<String, dynamic>> get filteredSections {
    if (_selectedNiveauId == null) {
      return [];
    }
    return _sections;
  }

  bool get selectedNiveauHasSections {
    if (_selectedNiveauId == null) return false;
    final niveau = _niveaux.firstWhere(
      (n) => n['id'] == _selectedNiveauId,
      orElse: () => {},
    );
    return (niveau['has_sections'] == true);
  }

  List<Map<String, dynamic>> get subjectOfferings => _subjectOfferings;
  List<Map<String, dynamic>> get enrolledStudents => _enrolledStudents;
  List<Map<String, dynamic>> get allEnrolledStudents => _allEnrolledStudents;

  ClassResult? get classResult => _classResult;
  StudentResult? get selectedStudentResult => _selectedStudentResult;
  GradingConfiguration? get gradingConfig => _gradingConfig;
  Map<String, List<Map<String, dynamic>>> get gradesByEnrollmentId => _gradesByEnrollmentId;

  /// Get current academic year name
  String get currentAcademicYearName {
    if (_selectedAcademicYearId == null) return '';
    final year = _academicYears.firstWhere(
      (y) => y['id'] == _selectedAcademicYearId,
      orElse: () => {},
    );
    return year['name'] ?? '';
  }

  /// Get current class name
  String get currentClassName {
    if (_selectedClassId == null) return '';
    final cls = _classes.firstWhere(
      (c) => c['id'] == _selectedClassId,
      orElse: () => {},
    );
    return cls['name'] ?? '';
  }

  /// Get filtered students based on search
  List<StudentResult> get filteredStudents {
    if (_classResult == null) return [];

    if (_searchQuery.isEmpty) {
      return _classResult!.students;
    }

    final query = _searchQuery.toLowerCase();
    return _classResult!.students.where((s) {
      return s.studentName.toLowerCase().contains(query) ||
          s.studentCode.toLowerCase().contains(query) ||
          s.className.toLowerCase().contains(query);
    }).toList();
  }

  /// Initialize provider
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    try {
      await loadAcademicYears();
      await loadNiveaux();
      await loadClasses();
      await loadEnrolledStudents(); // Load all students for search
      await loadAllEnrolledStudents(); // Separate list for global search
    } catch (e) {
      debugPrint('❌ Error initializing results provider: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load ALL enrolled students regardless of class (for global search)
  Future<void> loadAllEnrolledStudents() async {
    try {
      var students = await _repository.getEnrolledStudents(
        academicYearId: _selectedAcademicYearId,
        classId: null, // no class filter
        searchQuery: null,
      );
      // Fallback: If selected year has 0 enrolled students, load across all years so search never fails
      if (students.isEmpty) {
        students = await _repository.getEnrolledStudents(
          academicYearId: null,
          classId: null,
          searchQuery: null,
        );
      }
      _allEnrolledStudents = students;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading all enrolled students: $e');
    }
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

  /// Load niveaux (grade levels)
  Future<void> loadNiveaux() async {
    try {
      final fetched = await _repository.getNiveaux();
      fetched.sort((a, b) {
        final nameA = a['name']?.toString() ?? a['code']?.toString();
        final nameB = b['name']?.toString() ?? b['code']?.toString();
        final orderA = _getNiveauSortOrder(nameA);
        final orderB = _getNiveauSortOrder(nameB);
        if (orderA != orderB) return orderA.compareTo(orderB);
        return (nameA ?? '').compareTo(nameB ?? '');
      });
      _niveaux = fetched;
      notifyListeners();
    } catch (e) {
      _error = UserFriendlyError.format(
        e,
        fallback: 'Unable to load grade levels right now. Please try again.',
      );
      notifyListeners();
    }
  }

  /// Load sections for selected niveau
  Future<void> loadSectionsForNiveau(String? niveauId) async {
    if (niveauId == null || niveauId.isEmpty) {
      _sections = [];
      _selectedSectionId = null;
      notifyListeners();
      return;
    }

    try {
      _sections = await _repository.getSectionsForNiveau(niveauId);
      if (_selectedSectionId != null) {
        final found = _sections.any((s) => s['id'] == _selectedSectionId);
        if (!found) {
          _selectedSectionId = null;
        }
      }
      notifyListeners();
    } catch (e) {
      _error = UserFriendlyError.format(
        e,
        fallback: 'Unable to load sections right now. Please try again.',
      );
      notifyListeners();
    }
  }

  /// Helper to get current user's school_id
  Future<String?> _getSchoolId() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return null;
    try {
      final profile = await SupabaseConfig.client
          .from('users')
          .select('school_id')
          .eq('id', user.id)
          .maybeSingle();
      final id = profile?['school_id']?.toString();
      if (id != null && id.isNotEmpty) return id;
    } catch (_) {}
    try {
      final profile = await SupabaseConfig.adminClient
          .from('users')
          .select('school_id')
          .eq('id', user.id)
          .maybeSingle();
      return profile?['school_id']?.toString();
    } catch (_) {}
    return null;
  }

  /// Load academic years
  Future<void> loadAcademicYears() async {
    try {
      final schoolId = await _getSchoolId();
      if (schoolId == null) {
        _academicYears = [];
        _selectedAcademicYearId = null;
        notifyListeners();
        return;
      }

      // Load academic years for this school
      _academicYears = await _repository.getAcademicYears(schoolId: schoolId);

      // Prioritize the academic year with is_current == true for this school
      Map<String, dynamic>? selectedYear =
          _academicYears.where((y) => y['is_current'] == true).firstOrNull;
      selectedYear ??= _academicYears.isNotEmpty ? _academicYears.first : null;

      if (selectedYear != null && selectedYear.isNotEmpty) {
        _selectedAcademicYearId = selectedYear['id'];
        await loadSemesters();
      }

      notifyListeners();
    } catch (e) {
      _error = UserFriendlyError.format(
        e,
        fallback: 'Unable to load academic years right now. Please try again.',
      );
      notifyListeners();
    }
  }

  /// Load semesters — loads semesters for the selected academic year,
  /// then auto-selects is_current = true
  Future<void> loadSemesters() async {
    try {
      final schoolId = await _getSchoolId();
      if (schoolId == null) {
        _semesters = [];
        _selectedSemesterId = null;
        notifyListeners();
        return;
      }

      _semesters = await _repository.getSemesters(
        _selectedAcademicYearId,
        schoolId: schoolId,
      );

      // Sort by number
      _semesters.sort((a, b) {
        final aNum = (a['number'] as num?)?.toInt() ?? 0;
        final bNum = (b['number'] as num?)?.toInt() ?? 0;
        return aNum.compareTo(bNum);
      });

      debugPrint(
        '📅 Loaded ${_semesters.length} semesters: ${_semesters.map((s) => s['name']).toList()}',
      );

      // Always auto-select current active semester
      final now = DateTime.now();
      final current = _semesters.where((s) => s['is_current'] == true).firstOrNull;
      final byDate = _semesters.where((s) {
        try {
          if (s['start_date'] != null && s['end_date'] != null) {
            final start = DateTime.parse(s['start_date'].toString());
            final end = DateTime.parse(s['end_date'].toString());
            return !now.isBefore(start) && !now.isAfter(end);
          }
        } catch (_) {}
        return false;
      }).firstOrNull;

      if (current != null) {
        _selectedSemesterId = current['id'];
      } else if (byDate != null) {
        _selectedSemesterId = byDate['id'];
      } else if (_semesters.isNotEmpty) {
        _selectedSemesterId = _semesters.first['id'];
      }

      notifyListeners();
    } catch (e) {
      _error = UserFriendlyError.format(
        e,
        fallback: 'Unable to load semesters right now. Please try again.',
      );
      debugPrint('❌ Error loading semesters: $e');
      notifyListeners();
    }
  }

  /// Load classes
  Future<void> loadClasses() async {
    try {
      final schoolId = await _getSchoolId();
      final fetched = await _repository.getClasses(schoolId: schoolId);
      fetched.sort((a, b) => (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));
      _classes = fetched;
      notifyListeners();
    } catch (e) {
      _error = UserFriendlyError.format(
        e,
        fallback: 'Unable to load classes right now. Please try again.',
      );
      notifyListeners();
    }
  }

  /// Load subject offerings
  Future<void> loadSubjectOfferings() async {
    if (_selectedClassId == null || _selectedSemesterId == null) {
      _subjectOfferings = [];
      notifyListeners();
      return;
    }

    try {
      _subjectOfferings = await _repository.getSubjectOfferings(
        classId: _selectedClassId!,
        semesterId: _selectedSemesterId!,
      );
      notifyListeners();
    } catch (e) {
      _error = UserFriendlyError.format(
        e,
        fallback: 'Unable to load subjects right now. Please try again.',
      );
      notifyListeners();
    }
  }

  /// Load enrolled students
  Future<void> loadEnrolledStudents() async {
    try {
      // First try with academic year filter
      _enrolledStudents = await _repository.getEnrolledStudents(
        academicYearId: _selectedAcademicYearId,
        classId: _selectedClassId,
        searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
      );

      // If no students found and we have a class selected, try without academic year filter
      if (_enrolledStudents.isEmpty && _selectedClassId != null) {
        debugPrint('🔄 No students found with year filter, trying without...');
        _enrolledStudents = await _repository.getEnrolledStudents(
          academicYearId: null,
          classId: _selectedClassId,
          searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
        );
      } else if (_enrolledStudents.isEmpty && _selectedClassId == null) {
        _enrolledStudents = _allEnrolledStudents;
      }

      debugPrint(
        '📚 Loaded ${_enrolledStudents.length} students for class $_selectedClassId',
      );
      notifyListeners();
      await loadClassGrades();
    } catch (e) {
      _error = UserFriendlyError.format(
        e,
        fallback: 'Unable to load students right now. Please try again.',
      );
      debugPrint('❌ Error loading students: $e');
      notifyListeners();
    }
  }

  /// Load grades for all currently loaded enrolled students
  Future<void> loadClassGrades() async {
    final students = _enrolledStudents.isNotEmpty ? _enrolledStudents : _allEnrolledStudents;
    if (students.isEmpty) {
      _gradesByEnrollmentId = {};
      notifyListeners();
      return;
    }
    final enrollmentIds = students
        .map((s) => s['id']?.toString())
        .whereType<String>()
        .toList();
    if (enrollmentIds.isEmpty) return;

    try {
      final response = await _client
          .from('grades')
          .select('enrollment_id, student_id, subject_offering_id, component_id, grade_value, status')
          .inFilter('enrollment_id', enrollmentIds);
      final map = <String, List<Map<String, dynamic>>>{};
      for (final row in response) {
        final eId = row['enrollment_id']?.toString();
        if (eId != null) {
          map.putIfAbsent(eId, () => []).add(row);
        }
      }
      _gradesByEnrollmentId = map;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading class grades: $e');
    }
  }

  /// Load grading configuration
  Future<void> loadGradingConfig() async {
    if (_selectedClassId == null) {
      _gradingConfig = TunisianCoefficientTables.getDefaultConfiguration(
        EducationLevel.lycee1,
      );
      notifyListeners();
      return;
    }

    try {
      _gradingConfig = await _repository.getConfigurationForClass(
        _selectedClassId!,
      );
      notifyListeners();
    } catch (e) {
      _error = UserFriendlyError.format(
        e,
        fallback: 'Unable to load grading configuration right now. Please try again.',
      );
      notifyListeners();
    }
  }

  /// Calculate results for current selection
  Future<void> calculateResults() async {
    if (_selectedClassId == null || _selectedAcademicYearId == null) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Ensure config is loaded
      if (_gradingConfig == null) {
        await loadGradingConfig();
      }

      _classResult = await _repository.calculateClassResult(
        classId: _selectedClassId!,
        academicYearId: _selectedAcademicYearId!,
        config: _gradingConfig!,
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = UserFriendlyError.format(
        e,
        fallback: 'Unable to calculate results right now. Please try again.',
      );
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Calculate result for a single student
  Future<void> calculateStudentResult(String enrollmentId) async {
    if (_gradingConfig == null) {
      await loadGradingConfig();
    }

    _isLoading = true;
    notifyListeners();

    try {
      _selectedStudentResult = await _repository.calculateStudentResult(
        enrollmentId: enrollmentId,
        config: _gradingConfig!,
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = UserFriendlyError.format(
        e,
        fallback: 'Unable to calculate student results right now. Please try again.',
      );
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Save a grade
  Future<void> saveGrade({
    required String enrollmentId,
    required String studentId,
    required String subjectOfferingId,
    required String componentId,
    required double? value,
    String status = 'graded',
  }) async {
    // 1. Instant optimistic update
    final studentGrades = _gradesByEnrollmentId[enrollmentId] ?? [];
    final existingIdx = studentGrades.indexWhere(
      (g) => g['subject_offering_id'] == subjectOfferingId && g['evaluation_component_id'] == componentId,
    );
    if (existingIdx >= 0) {
      studentGrades[existingIdx]['value'] = value;
      studentGrades[existingIdx]['status'] = status;
    } else {
      studentGrades.add({
        'enrollment_id': enrollmentId,
        'subject_offering_id': subjectOfferingId,
        'evaluation_component_id': componentId,
        'value': value,
        'status': status,
      });
    }
    _gradesByEnrollmentId[enrollmentId] = studentGrades;
    notifyListeners();

    try {
      await _repository.saveGrade(
        enrollmentId: enrollmentId,
        studentId: studentId,
        subjectOfferingId: subjectOfferingId,
        componentId: componentId,
        value: value,
        status: status,
      );

      // Recalculate results silently
      await calculateResults();
      await loadClassGrades();
    } catch (e) {
      _error = UserFriendlyError.format(
        e,
        fallback: 'Unable to save the grade right now. Please try again.',
      );
      notifyListeners();
    }
  }

  /// Save multiple grades
  Future<void> saveBulkGrades(List<GradeEntry> grades) async {
    _isLoading = true;
    notifyListeners();

    try {
      final gradesData = grades.map((g) => g.toJson()).toList();
      await _repository.saveBulkGrades(gradesData);
      await calculateResults();
      await loadClassGrades();
    } catch (e) {
      _error = UserFriendlyError.format(
        e,
        fallback: 'Unable to save grades right now. Please try again.',
      );
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Save grading configuration
  Future<void> saveGradingConfig(GradingConfiguration config) async {
    try {
      await _repository.saveGradingConfiguration(config);
      _gradingConfig = config;
      notifyListeners();
    } catch (e) {
      _error = UserFriendlyError.format(
        e,
        fallback: 'Unable to save grading configuration right now. Please try again.',
      );
      notifyListeners();
    }
  }

  // Setters
  void setAcademicYear(String? yearId) {
    _selectedAcademicYearId = yearId;
    _classResult = null;
    loadSemesters();
    loadEnrolledStudents();
  }

  void setSemester(String? semesterId) {
    _selectedSemesterId = semesterId;
    loadSubjectOfferings().then((_) => loadClassGrades());
    if (_selectedClassId != null && _selectedAcademicYearId != null) {
      calculateResults();
    }
    notifyListeners();
  }

  void setNiveau(String? niveauId) {
    _selectedNiveauId = niveauId;
    // Reset section and class when niveau changes
    _selectedSectionId = null;
    _selectedClassId = null;
    _classResult = null;
    loadSectionsForNiveau(niveauId);
    notifyListeners();
  }

  void setSection(String? sectionId) {
    _selectedSectionId = sectionId;
    // Reset class when section changes
    _selectedClassId = null;
    _classResult = null;
    notifyListeners();
  }

  Future<void> setClass(String? classId) async {
    _selectedClassId = classId;
    _classResult = null;
    if (classId != null) {
      _isLoading = true;
      notifyListeners();
      try {
        await Future.wait([
          loadGradingConfig(),
          loadSubjectOfferings(),
          loadEnrolledStudents(),
        ]);
        await loadClassGrades();
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    } else {
      notifyListeners();
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    // Debounce search - call loadEnrolledStudents to search in database
    loadEnrolledStudents();
    notifyListeners();
  }

  void setFilterType(ResultsFilterType type) {
    _filterType = type;
    notifyListeners();
  }

  void setViewMode(ResultsViewMode mode) {
    _viewMode = mode;
    notifyListeners();
  }

  void selectStudent(StudentResult student) {
    _selectedStudentResult = student;
    notifyListeners();
  }

  void clearSelectedStudent() {
    _selectedStudentResult = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
