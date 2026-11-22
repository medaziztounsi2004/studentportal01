import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../../data/services/user_management_service.dart';
import '../../data/models/academic_models.dart';
import '../../data/models/school_models.dart';
import '../../data/models/tunisian_coefficients.dart';
import '../../data/models/grading_config_model.dart';
import '../../data/models/teacher_assignment_model.dart';
import '../../data/models/user_model.dart';
import '../../data/models/class_model.dart';

// ==================== STATE ====================
class SubjectsManagementState {
  final List<SubjectModel> subjects;
  final List<SubjectAssignmentModel> assignments;
  final List<GradeLevelModel> gradeLevels;
  final List<SectionModel> sections;
  final List<SemesterModel> semesters;
  final List<ExamTypeModel> examTypes;
  final List<TeacherAssignmentModel> teacherAssignments;
  final List<UserModel> teachers;
  final List<ClassModel> classes;
  final String searchQuery;
  final String? filterGradeId;
  final String? filterSectionId;
  final String teacherSearchQuery;
  final String? filterTeacherSubjectId;
  final String? filterTeacherNiveauId;
  final String? filterTeacherClassId;

  SubjectsManagementState({
    this.subjects = const [],
    this.assignments = const [],
    this.gradeLevels = const [],
    this.sections = const [],
    this.semesters = const [],
    this.examTypes = const [],
    this.teacherAssignments = const [],
    this.teachers = const [],
    this.classes = const [],
    this.searchQuery = '',
    this.filterGradeId,
    this.filterSectionId,
    this.teacherSearchQuery = '',
    this.filterTeacherSubjectId,
    this.filterTeacherNiveauId,
    this.filterTeacherClassId,
  });

  List<SubjectModel> get filteredSubjects {
    var result = subjects;
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.trim().toLowerCase();
      result = result.where((s) {
        // Search in subject name and code
        if (s.name.toLowerCase().contains(query) ||
            (s.code?.toLowerCase().contains(query) ?? false)) {
          return true;
        }
        // Search in category
        if (s.category?.toLowerCase().contains(query) ?? false) {
          return true;
        }
        // Search in Arabic name
        if (s.nameAr?.toLowerCase().contains(query) ?? false) {
          return true;
        }
        // Search in assignments - grade levels that use this subject
        final subjectAssignments = assignments.where(
          (a) => a.subjectId == s.id,
        );
        for (final assignment in subjectAssignments) {
          if (assignment.gradeLevelName?.toLowerCase().contains(query) ??
              false) {
            return true;
          }
          if (assignment.sectionName?.toLowerCase().contains(query) ?? false) {
            return true;
          }
          if (assignment.coefficient.toString().contains(query)) {
            return true;
          }
        }
        return false;
      }).toList();
    }
    return result;
  }

  List<SubjectAssignmentModel> get filteredAssignments {
    var result = assignments;
    if (filterGradeId != null) {
      result = result.where((a) => a.gradeLevelId == filterGradeId).toList();
    }
    if (filterSectionId != null) {
      result = result.where((a) => a.sectionId == filterSectionId).toList();
    }
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.trim().toLowerCase();
      result = result
          .where(
            (a) =>
                (a.subjectName?.toLowerCase().contains(query) ?? false) ||
                (a.subjectCode?.toLowerCase().contains(query) ?? false) ||
                (a.gradeLevelName?.toLowerCase().contains(query) ?? false) ||
                (a.sectionName?.toLowerCase().contains(query) ?? false) ||
                a.coefficient.toString().contains(query) ||
                a.weeklyHours.toString().contains(query),
          )
          .toList();
    }
    return result;
  }

  // Get assignments grouped by grade level
  Map<String, List<SubjectAssignmentModel>> get assignmentsByGrade {
    final map = <String, List<SubjectAssignmentModel>>{};
    for (final a in filteredAssignments) {
      final key = a.gradeLevelName ?? 'Non assigné';
      map.putIfAbsent(key, () => []).add(a);
    }
    return map;
  }

  // Get teachers grouped with their assignments
  List<TeacherWithAssignments> get teachersWithAssignments {
    var filtered = teacherAssignments;
    if (teacherSearchQuery.isNotEmpty) {
      final query = teacherSearchQuery.trim().toLowerCase();
      filtered = filtered.where((a) {
        return (a.teacherName?.toLowerCase().contains(query) ?? false) ||
            (a.teacherEmail?.toLowerCase().contains(query) ?? false) ||
            (a.subjectName?.toLowerCase().contains(query) ?? false) ||
            (a.niveauName?.toLowerCase().contains(query) ?? false) ||
            (a.className?.toLowerCase().contains(query) ?? false);
      }).toList();
    }
    if (filterTeacherSubjectId != null) {
      filtered = filtered
          .where((a) => a.subjectId == filterTeacherSubjectId)
          .toList();
    }
    if (filterTeacherNiveauId != null) {
      filtered = filtered
          .where((a) => a.niveauId == filterTeacherNiveauId)
          .toList();
    }
    if (filterTeacherClassId != null) {
      filtered = filtered
          .where((a) => a.classId == filterTeacherClassId)
          .toList();
    }
    return TeacherWithAssignments.groupByTeacher(filtered);
  }

  // Get sections for a specific grade level
  List<SectionModel> sectionsForGrade(String? gradeId) {
    if (gradeId == null) return sections;

    // Check if this grade level has any assignments with sections
    final gradeAssignments = assignments
        .where((a) => a.gradeLevelId == gradeId && a.sectionId != null)
        .toList();

    if (gradeAssignments.isEmpty) return [];

    // Return sections that are used by this grade level
    final sectionIds = gradeAssignments.map((a) => a.sectionId).toSet();
    return sections.where((s) => sectionIds.contains(s.id)).toList();
  }

  SubjectsManagementState copyWith({
    List<SubjectModel>? subjects,
    List<SubjectAssignmentModel>? assignments,
    List<GradeLevelModel>? gradeLevels,
    List<SectionModel>? sections,
    List<SemesterModel>? semesters,
    List<ExamTypeModel>? examTypes,
    List<TeacherAssignmentModel>? teacherAssignments,
    List<UserModel>? teachers,
    List<ClassModel>? classes,
    String? searchQuery,
    String? filterGradeId,
    String? filterSectionId,
    String? teacherSearchQuery,
    String? filterTeacherSubjectId,
    String? filterTeacherNiveauId,
    String? filterTeacherClassId,
    bool clearGradeFilter = false,
    bool clearSectionFilter = false,
    bool clearTeacherSubjectFilter = false,
    bool clearTeacherNiveauFilter = false,
    bool clearTeacherClassFilter = false,
  }) => SubjectsManagementState(
    subjects: subjects ?? this.subjects,
    assignments: assignments ?? this.assignments,
    gradeLevels: gradeLevels ?? this.gradeLevels,
    sections: sections ?? this.sections,
    semesters: semesters ?? this.semesters,
    examTypes: examTypes ?? this.examTypes,
    teacherAssignments: teacherAssignments ?? this.teacherAssignments,
    teachers: teachers ?? this.teachers,
    classes: classes ?? this.classes,
    searchQuery: searchQuery ?? this.searchQuery,
    filterGradeId: clearGradeFilter
        ? null
        : (filterGradeId ?? this.filterGradeId),
    filterSectionId: clearSectionFilter
        ? null
        : (filterSectionId ?? this.filterSectionId),
    teacherSearchQuery: teacherSearchQuery ?? this.teacherSearchQuery,
    filterTeacherSubjectId: clearTeacherSubjectFilter
        ? null
        : (filterTeacherSubjectId ?? this.filterTeacherSubjectId),
    filterTeacherNiveauId: clearTeacherNiveauFilter
        ? null
        : (filterTeacherNiveauId ?? this.filterTeacherNiveauId),
    filterTeacherClassId: clearTeacherClassFilter
        ? null
        : (filterTeacherClassId ?? this.filterTeacherClassId),
  );
}

// ==================== PROVIDER ====================
final subjectsManagementProvider =
    AsyncNotifierProvider<SubjectsManagementNotifier, SubjectsManagementState>(
      SubjectsManagementNotifier.new,
    );

class SubjectsManagementNotifier
    extends AsyncNotifier<SubjectsManagementState> {
  @override
  Future<SubjectsManagementState> build() async => _load();

  Future<SubjectsManagementState> _load() async {
    final supabase = Supabase.instance.client;
    final schoolId = await _getSchoolId();

    // Load subjects
    List<SubjectModel> subjects = [];
    try {
      final subjectsResp = await supabase
          .from('subjects')
          .select()
          .eq('school_id', schoolId)
          .eq('is_active', true)
          .order('name');
      subjects = (subjectsResp as List)
          .map((s) => SubjectModel.fromJson(s))
          .toList();
    } catch (e) {
      // Table might not exist or have different structure
      debugPrint('Error loading subjects: $e');
    }

    // Load curriculum (using curriculum table instead of subject_assignments)
    List<SubjectAssignmentModel> assignments = [];
    try {
      final curriculumResp = await supabase
          .from('curriculum')
          .select('''
            *,
            subjects:subject_id(id, name, code, name_ar, category),
            niveaux:niveau_id(id, name, code, cycle),
            sections:section_id(id, name, code)
          ''')
          .eq('school_id', schoolId)
          .eq('is_active', true)
          .order('coefficient', ascending: false);
      assignments = (curriculumResp as List)
          .map((c) => SubjectAssignmentModel.fromCurriculumJson(c))
          .toList();
    } catch (e) {
      debugPrint('Error loading curriculum: $e');
    }

    // Load grade levels (niveaux)
    List<GradeLevelModel> gradeLevels = [];
    try {
      final gradesResp = await supabase
          .from('niveaux')
          .select('*, niveau_sections(*, sections(*))')
          .eq('is_active', true)
          .order('display_order');
      gradeLevels = (gradesResp as List)
          .map((g) => GradeLevelModel.fromJson(g))
          .toList();
    } catch (e) {
      debugPrint('Error loading niveaux: $e');
    }

    // Load sections
    List<SectionModel> sections = [];
    try {
      final sectionsResp = await supabase
          .from('sections')
          .select()
          .eq('is_active', true)
          .order('display_order');
      sections = (sectionsResp as List)
          .map((s) => SectionModel.fromJson(s))
          .toList();
    } catch (e) {
      debugPrint('Error loading sections: $e');
    }

    // Load semesters (optional)
    List<SemesterModel> semesters = [];
    try {
      final semestersResp = await supabase
          .from('semesters')
          .select()
          .eq('school_id', schoolId)
          .order('number');
      semesters = (semestersResp as List)
          .map((s) => SemesterModel.fromJson(s))
          .toList();
    } catch (_) {
      // semesters table might not exist
    }

    // Load exam types
    List<ExamTypeModel> examTypes = [];
    try {
      final examTypesResp = await supabase
          .from('exam_types')
          .select()
          .eq('school_id', schoolId)
          .eq('is_active', true)
          .order('name');
      examTypes = (examTypesResp as List)
          .map((e) => ExamTypeModel.fromJson(e))
          .toList();
    } catch (e) {
      debugPrint('Error loading exam_types: $e');
    }

    // Load ALL teachers (active + inactive) so we can resolve assignments
    // even for teachers whose account was deactivated.
    final adminClient = SupabaseConfig.adminClient;
    List<UserModel> teachers = [];
    try {
      final teachersResp = await adminClient
          .from('users')
          .select()
          .eq('school_id', schoolId)
          .eq('role', 'teacher')
          .order('full_name');
      if (teachersResp != null) {
        teachers = (teachersResp as List)
            .map((t) => UserModel.fromJson(t))
            .toList();
      }
    } catch (e) {
      debugPrint('Error loading teachers: $e');
    }

    // Load classes
    List<ClassModel> classes = [];
    try {
      final classesResp = await supabase
          .from('classes')
          .select('''
            *,
            niveaux:niveau_id(id, name, code),
            sections:section_id(id, name, code)
          ''')
          .eq('school_id', schoolId)
          .eq('is_active', true)
          .order('name');
      if (classesResp != null) {
        classes = (classesResp as List)
            .map((c) => ClassModel.fromJson(c))
            .toList();
      }
    } catch (e) {
      debugPrint('Error loading classes: $e');
    }

    // Load teacher assignments – use adminClient to bypass RLS
    // (matches how classes_provider & teacher_profile_screen load them)
    List<TeacherAssignmentModel> teacherAssignments = [];
    try {
      final teacherAssResp = await adminClient
          .from('teacher_assignments')
          .select('''
            *,
            users:teacher_id(id, full_name, email, phone),
            subjects:subject_id(id, name, code),
            niveaux:niveau_id(id, name, code),
            classes:class_id(id, name)
          ''')
          .eq('school_id', schoolId)
          .eq('is_active', true);
      if (teacherAssResp != null) {
        teacherAssignments = (teacherAssResp as List)
            .map((a) => TeacherAssignmentModel.fromJson(a))
            .toList();
      }
      debugPrint('[SubjectsMgmt] Loaded ${teacherAssignments.length} teacher_assignments');
    } catch (e) {
      debugPrint('[SubjectsMgmt] Error loading teacher_assignments: $e');
    }

    return SubjectsManagementState(
      subjects: subjects,
      assignments: assignments,
      gradeLevels: gradeLevels,
      sections: sections,
      semesters: semesters,
      examTypes: examTypes,
      teachers: teachers,
      classes: classes,
      teacherAssignments: teacherAssignments,
    );
  }

  Future<String> _getSchoolId() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Utilisateur non authentifié');

    final profile = await supabase
        .from('users')
        .select('school_id')
        .eq('id', userId)
        .single();

    final schoolId = profile['school_id'] as String?;
    if (schoolId == null)
      throw Exception('school_id manquant pour l\'utilisateur');
    return schoolId;
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }

  void setSearch(String query) {
    state.whenData((s) {
      state = AsyncData(s.copyWith(searchQuery: query));
    });
  }

  void setTeacherSearch(String query) {
    state.whenData((s) {
      state = AsyncData(s.copyWith(teacherSearchQuery: query));
    });
  }

  void setTeacherSubjectFilter(String? subjectId) {
    state.whenData((s) {
      state = AsyncData(
        s.copyWith(
          filterTeacherSubjectId: subjectId,
          clearTeacherSubjectFilter: subjectId == null,
        ),
      );
    });
  }

  void setTeacherNiveauFilter(String? niveauId) {
    state.whenData((s) {
      state = AsyncData(
        s.copyWith(
          filterTeacherNiveauId: niveauId,
          clearTeacherNiveauFilter: niveauId == null,
          // Reset class filter when niveau changes
          clearTeacherClassFilter: true,
        ),
      );
    });
  }

  void setTeacherClassFilter(String? classId) {
    state.whenData((s) {
      state = AsyncData(
        s.copyWith(
          filterTeacherClassId: classId,
          clearTeacherClassFilter: classId == null,
        ),
      );
    });
  }

  void setGradeFilter(String? gradeId) {
    state.whenData((s) {
      state = AsyncData(
        s.copyWith(filterGradeId: gradeId, clearGradeFilter: gradeId == null),
      );
    });
  }

  void setSectionFilter(String? sectionId) {
    state.whenData((s) {
      state = AsyncData(
        s.copyWith(
          filterSectionId: sectionId,
          clearSectionFilter: sectionId == null,
        ),
      );
    });
  }

  // ==================== HELPER METHODS ====================

  /// Auto-generate subject code from name
  String generateSubjectCode(String name) {
    if (name.isEmpty) return '';

    // Remove accents and special characters
    final cleaned = name
        .replaceAll(RegExp(r'[éèê]', caseSensitive: false), 'e')
        .replaceAll(RegExp(r'[àâ]', caseSensitive: false), 'a')
        .replaceAll(RegExp(r'[ûù]', caseSensitive: false), 'u')
        .replaceAll(RegExp(r'[îï]', caseSensitive: false), 'i')
        .replaceAll(RegExp(r'[ôö]', caseSensitive: false), 'o')
        .replaceAll(RegExp(r"[']"), ' ')
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '');

    // Split into words
    final words = cleaned
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    if (words.isEmpty) return '';

    // Generate code
    String code;
    if (words.length == 1) {
      // Single word: take first 3-4 letters
      code = words[0].substring(0, words[0].length > 4 ? 4 : words[0].length);
    } else {
      // Multiple words: take initials or first letters
      code = words.map((w) => w[0]).join();
    }

    return code.toUpperCase();
  }

  /// Get suggested subjects based on grade level and section
  List<SubjectCoefficient> getSuggestedSubjects(
    String? gradeLevelCode,
    String? sectionCode,
  ) {
    if (gradeLevelCode == null) return [];

    // Import from TunisianCoefficientTables
    final grade = gradeLevelCode.toLowerCase();

    // College (7ème, 8ème, 9ème)
    if (grade.contains('7') ||
        grade.contains('8') ||
        grade.contains('9') ||
        grade.contains('college')) {
      return TunisianCoefficientTables.collegeSubjects;
    }

    // Lycée 1ère année (Tronc commun)
    if (grade.contains('1') && !grade.contains('2') && !grade.contains('3')) {
      return TunisianCoefficientTables.lycee1Subjects;
    }

    // Lycée 2ème année - check section
    if (grade.contains('2') && sectionCode != null) {
      final section = sectionCode.toLowerCase();
      if (section.contains('math')) {
        return TunisianCoefficientTables.lycee2MathSubjects;
      }
      if (section.contains('sci') || section.contains('exp')) {
        return TunisianCoefficientTables.lycee2SciencesSubjects;
      }
      if (section.contains('tech')) {
        return TunisianCoefficientTables.lycee2TechSubjects;
      }
      if (section.contains('eco') || section.contains('gestion')) {
        return TunisianCoefficientTables.lycee2EcoSubjects;
      }
      if (section.contains('lettre')) {
        return TunisianCoefficientTables.lycee2LettresSubjects;
      }
    }

    // Default to lycee1 for other cases
    return TunisianCoefficientTables.lycee1Subjects;
  }

  /// Get weekly hours from timetable for a subject
  Future<double> getWeeklyHoursFromTimetable(
    String subjectId,
    String gradeId,
    String? sectionId,
  ) async {
    try {
      final supabase = Supabase.instance.client;

      // Get timetable slots for this subject in classes of this grade/section
      final query = supabase
          .from('timetable_slots')
          .select('''
            *,
            subject_offerings!inner(
              subject_id,
              class_id,
              classes!inner(
                id,
                niveau_id,
                section_id
              )
            )
          ''')
          .eq('subject_offerings.subject_id', subjectId)
          .eq('subject_offerings.classes.niveau_id', gradeId);

      if (sectionId != null) {
        query.eq('subject_offerings.classes.section_id', sectionId);
      }

      final response = await query;
      final slots = response as List;

      if (slots.isEmpty) return 0.0;

      // Calculate total hours per week
      double totalHours = 0.0;
      for (final slot in slots) {
        final startTime = slot['start_time'] as String?;
        final endTime = slot['end_time'] as String?;

        if (startTime != null && endTime != null) {
          // Parse time format "HH:MM"
          final start = _parseTime(startTime);
          final end = _parseTime(endTime);
          final duration = end - start;
          totalHours += duration;
        }
      }

      return totalHours;
    } catch (e) {
      debugPrint('Error getting weekly hours from timetable: $e');
      return 0.0;
    }
  }

  double _parseTime(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return 0.0;
    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    return hours + (minutes / 60.0);
  }

  // ==================== SUBJECT CRUD ====================
  Future<void> addSubject(SubjectModel subject) async {
    final schoolId = await _getSchoolId();
    await Supabase.instance.client
        .from('subjects')
        .upsert(
          subject.toJson()..['school_id'] = schoolId,
          onConflict: 'school_id,code,normalized_name',
        );
    ref.invalidateSelf();
  }

  Future<void> updateSubject(String id, SubjectModel subject) async {
    final schoolId = await _getSchoolId();
    await Supabase.instance.client
        .from('subjects')
        .update(subject.toJson()..['school_id'] = schoolId)
        .eq('id', id);
    ref.invalidateSelf();
  }

  Future<void> deleteSubject(String id) async {
    final previous = state.value;
    state.whenData((s) {
      final updated = s.subjects.where((sub) => sub.id != id).toList();
      state = AsyncData(s.copyWith(subjects: updated));
    });

    try {
      await Supabase.instance.client.from('subjects').delete().eq('id', id);
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }

  // ==================== CURRICULUM CRUD (replacing subject_assignments) ====================
  Future<void> addAssignment(SubjectAssignmentModel assignment) async {
    final schoolId = await _getSchoolId();
    await Supabase.instance.client
        .from('curriculum')
        .upsert(
          assignment.toCurriculumJson()..['school_id'] = schoolId,
          onConflict: 'school_id,niveau_id,section_key,subject_id',
        );
    ref.invalidateSelf();
  }

  Future<void> updateAssignment(
    String id,
    SubjectAssignmentModel assignment,
  ) async {
    final schoolId = await _getSchoolId();
    await Supabase.instance.client
        .from('curriculum')
        .update(assignment.toCurriculumJson()..['school_id'] = schoolId)
        .eq('id', id);
    ref.invalidateSelf();
  }

  Future<void> deleteAssignment(String id) async {
    final previous = state.value;
    state.whenData((s) {
      final updated = s.assignments.where((a) => a.id != id).toList();
      state = AsyncData(s.copyWith(assignments: updated));
    });

    try {
      await Supabase.instance.client
          .from('curriculum')
          .update({'is_active': false})
          .eq('id', id);
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }

  // ==================== EXAM CONFIG CRUD ====================
  Future<void> addExamConfig(SubjectExamConfig config) async {
    await Supabase.instance.client
        .from('subject_exam_config')
        .insert(config.toJson());
    ref.invalidateSelf();
  }

  Future<void> updateExamConfig(String id, SubjectExamConfig config) async {
    await Supabase.instance.client
        .from('subject_exam_config')
        .update(config.toJson())
        .eq('id', id);
    ref.invalidateSelf();
  }

  Future<void> deleteExamConfig(String id) async {
    await Supabase.instance.client
        .from('subject_exam_config')
        .delete()
        .eq('id', id);
    ref.invalidateSelf();
  }

  // ==================== CREATE TEACHER ====================

  /// Create a new teacher user (role='teacher') and return their id
  Future<String> createTeacher({
    required String fullName,
    String? email,
    String? phone,
  }) async {
    final schoolId = await _getSchoolId();

    // Auto-generate email if not provided
    final effectiveEmail = email ?? '${fullName.toLowerCase().replaceAll(' ', '.').replaceAll(RegExp(r'[^a-z0-9.]'), '')}.${DateTime.now().millisecondsSinceEpoch}@auto.school';

    // Auto-generate password
    final password = '${fullName.split(' ').first.toLowerCase()}${DateTime.now().millisecondsSinceEpoch % 10000}';

    // Create teacher securely through Edge Function
    final createResult = await UserManagementService.createUser(
      email: effectiveEmail,
      password: password,
      fullName: fullName,
      role: 'teacher',
      phone: phone,
      schoolId: schoolId,
    );

    final userId = (createResult['user'] as Map)['id'] as String;

    ref.invalidateSelf();
    return userId;
  }

  // ==================== TEACHER ASSIGNMENT CRUD ====================

  /// Add a teacher assignment (teacher -> subject, optionally with niveau and class)
  Future<void> addTeacherAssignment(TeacherAssignmentModel assignment) async {
    final schoolId = await _getSchoolId();
    await Supabase.instance.client
        .from('teacher_assignments')
        .insert(assignment.toJson()..['school_id'] = schoolId);
    ref.invalidateSelf();
  }

  /// Add multiple teacher assignments at once (single subject, multiple niveaux/classes)
  Future<void> addTeacherAssignmentsBulk({
    required String teacherId,
    required String subjectId,
    required List<String> niveauIds,
    required List<String> classIds,
  }) async {
    final schoolId = await _getSchoolId();
    final supabase = Supabase.instance.client;

    final rows = <Map<String, dynamic>>[];

    if (niveauIds.isEmpty && classIds.isEmpty) {
      // Just teacher -> subject
      rows.add({
        'school_id': schoolId,
        'teacher_id': teacherId,
        'subject_id': subjectId,
      });
    } else if (classIds.isEmpty) {
      // teacher -> subject + niveaux
      for (final niveauId in niveauIds) {
        rows.add({
          'school_id': schoolId,
          'teacher_id': teacherId,
          'subject_id': subjectId,
          'niveau_id': niveauId,
        });
      }
    } else {
      // teacher -> subject + classes (each class has its niveau)
      for (final classId in classIds) {
        rows.add({
          'school_id': schoolId,
          'teacher_id': teacherId,
          'subject_id': subjectId,
          'class_id': classId,
        });
      }
    }

    if (rows.isNotEmpty) {
      for (final row in rows) {
        try {
          await supabase.from('teacher_assignments').insert(row);
        } catch (e) {
          debugPrint('Duplicate or error inserting teacher assignment: $e');
        }
      }
    }
    ref.invalidateSelf();
  }

  /// Delete a teacher assignment
  Future<void> deleteTeacherAssignment(String id) async {
    final previous = state.value;
    state.whenData((s) {
      final updated = s.teacherAssignments.where((ta) => ta.id != id).toList();
      state = AsyncData(s.copyWith(teacherAssignments: updated));
    });

    try {
      await Supabase.instance.client
          .from('teacher_assignments')
          .delete()
          .eq('id', id);
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }

  /// Delete all assignments for a teacher
  Future<void> deleteAllTeacherAssignments(String teacherId) async {
    final previous = state.value;
    state.whenData((s) {
      final updated = s.teacherAssignments.where((ta) => ta.teacherId != teacherId).toList();
      state = AsyncData(s.copyWith(teacherAssignments: updated));
    });

    try {
      final schoolId = await _getSchoolId();
      await Supabase.instance.client
          .from('teacher_assignments')
          .delete()
          .eq('teacher_id', teacherId)
          .eq('school_id', schoolId);
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }

  /// Remove specific subject from a teacher
  Future<void> removeTeacherSubject(String teacherId, String subjectId) async {
    final previous = state.value;
    state.whenData((s) {
      final updated = s.teacherAssignments
          .where((ta) => !(ta.teacherId == teacherId && ta.subjectId == subjectId))
          .toList();
      state = AsyncData(s.copyWith(teacherAssignments: updated));
    });

    try {
      final schoolId = await _getSchoolId();
      await Supabase.instance.client
          .from('teacher_assignments')
          .delete()
          .eq('teacher_id', teacherId)
          .eq('subject_id', subjectId)
          .eq('school_id', schoolId);
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }
}
