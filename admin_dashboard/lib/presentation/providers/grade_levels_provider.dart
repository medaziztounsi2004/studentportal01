import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/supabase_config.dart';
import '../../data/models/academic_models.dart';

// ==================== STATE ====================
class GradeLevelsState {
  final List<GradeLevelModel> gradeLevels;
  final List<SectionModel> sections;
  final List<ExamTypeModel> examTypes;
  final String? selectedLevelType;
  final String searchQuery;

  GradeLevelsState({
    this.gradeLevels = const [],
    this.sections = const [],
    this.examTypes = const [],
    this.selectedLevelType,
    this.searchQuery = '',
  });

  List<GradeLevelModel> get filtered {
    var result = gradeLevels;

    if (selectedLevelType != null) {
      result = result.where((g) => g.levelType == selectedLevelType).toList();
    }

    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      result = result
          .where(
            (g) =>
                g.name.toLowerCase().contains(query) ||
                g.code.toLowerCase().contains(query),
          )
          .toList();
    }

    return result..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  List<GradeLevelModel> get collegeGrades {
    var result = gradeLevels.where((g) => g.levelType == 'college').toList();
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      result = result.where((g) =>
        g.name.toLowerCase().contains(q) ||
        g.code.toLowerCase().contains(q)).toList();
    }
    return result..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  List<GradeLevelModel> get secondaireGrades {
    var result = gradeLevels.where((g) => g.levelType == 'secondaire').toList();
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      result = result.where((g) =>
        g.name.toLowerCase().contains(q) ||
        g.code.toLowerCase().contains(q)).toList();
    }
    return result..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  List<SectionModel> get filteredSections {
    if (searchQuery.isEmpty) return sections;
    final q = searchQuery.toLowerCase();
    return sections.where((s) =>
      s.name.toLowerCase().contains(q) ||
      s.code.toLowerCase().contains(q) ||
      (s.description?.toLowerCase().contains(q) ?? false)
    ).toList();
  }

  List<ExamTypeModel> get filteredExamTypes {
    if (searchQuery.isEmpty) return examTypes;
    final q = searchQuery.toLowerCase();
    return examTypes.where((e) =>
      e.name.toLowerCase().contains(q) ||
      (e.code?.toLowerCase().contains(q) ?? false) ||
      (e.description?.toLowerCase().contains(q) ?? false)
    ).toList();
  }

  GradeLevelsState copyWith({
    List<GradeLevelModel>? gradeLevels,
    List<SectionModel>? sections,
    List<ExamTypeModel>? examTypes,
    String? selectedLevelType,
    String? searchQuery,
    bool clearLevelTypeFilter = false,
  }) => GradeLevelsState(
    gradeLevels: gradeLevels ?? this.gradeLevels,
    sections: sections ?? this.sections,
    examTypes: examTypes ?? this.examTypes,
    selectedLevelType: clearLevelTypeFilter
        ? null
        : (selectedLevelType ?? this.selectedLevelType),
    searchQuery: searchQuery ?? this.searchQuery,
  );
}

// ==================== PROVIDER ====================
final gradeLevelsProvider =
    AsyncNotifierProvider<GradeLevelsNotifier, GradeLevelsState>(
      GradeLevelsNotifier.new,
    );

class GradeLevelsNotifier extends AsyncNotifier<GradeLevelsState> {
  @override
  Future<GradeLevelsState> build() async => _load();

  Future<GradeLevelsState> _load() async {
    final supabase = SupabaseConfig.adminClient;

    // Load niveaux (grade levels) with their sections via niveau_sections
    final gradesResp = await supabase
        .from('niveaux')
        .select('''
          *,
          niveau_sections(
            sections(*)
          ),
          classes(id, name, section_id, sections(name))
        ''')
        .eq('is_active', true)
        .order('display_order');
    
    debugPrint('GradeLevels: Loaded ${(gradesResp as List).length} niveaux');

    // ── Fetch student counts per class via enrollments ──
    final allClassIds = <String>[];
    for (final g in gradesResp) {
      final classes = g['classes'] as List? ?? [];
      for (final c in classes) {
        if (c['id'] != null) allClassIds.add(c['id'] as String);
      }
    }
    final Map<String, int> classStudentCounts = {};
    if (allClassIds.isNotEmpty) {
      try {
        final enrollResp = await supabase
            .from('enrollments')
            .select('class_id')
            .inFilter('class_id', allClassIds)
            .eq('is_active', true);
        for (final e in (enrollResp as List)) {
          final cid = e['class_id'] as String;
          classStudentCounts[cid] = (classStudentCounts[cid] ?? 0) + 1;
        }
      } catch (e) {
        debugPrint('GradeLevels: Failed to fetch enrollment counts: $e');
      }
    }
    debugPrint('GradeLevels: Student counts per class: $classStudentCounts');

    // Inject student_count into each class JSON before parsing
    for (final g in gradesResp) {
      final classes = g['classes'] as List? ?? [];
      for (final c in classes) {
        c['student_count'] = classStudentCounts[c['id']] ?? 0;
      }
    }

    final grades = (gradesResp as List)
        .map((g) => GradeLevelModel.fromJson(g))
        .toList();

    // Load all sections
    final sectionsResp = await supabase
        .from('sections')
        .select()
        .eq('is_active', true)
        .order('display_order');
    final sections = (sectionsResp as List)
        .map((s) => SectionModel.fromJson(s))
        .toList();

    // Load exam types
    List<ExamTypeModel> examTypes = [];
    try {
      final examTypesResp = await supabase
          .from('exam_types')
          .select()
          .eq('is_active', true)
          .order('name');
      examTypes = (examTypesResp as List)
          .map((e) => ExamTypeModel.fromJson(e))
          .toList();
    } catch (e) {
      // exam_types table might not exist
    }

    return GradeLevelsState(
      gradeLevels: grades,
      sections: sections,
      examTypes: examTypes,
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }

  void setLevelTypeFilter(String? levelType) {
    state.whenData((s) {
      state = AsyncData(
        s.copyWith(
          selectedLevelType: levelType,
          clearLevelTypeFilter: levelType == null,
        ),
      );
    });
  }

  void setSearch(String query) {
    state.whenData((s) {
      state = AsyncData(s.copyWith(searchQuery: query));
    });
  }

  // ==================== GRADE LEVEL CRUD ====================
  Future<void> addGradeLevel(GradeLevelModel grade) async {
    await SupabaseConfig.adminClient.from('niveaux').insert(grade.toJson());
    ref.invalidateSelf();
  }

  Future<void> updateGradeLevel(String id, GradeLevelModel grade) async {
    await SupabaseConfig.adminClient
        .from('niveaux')
        .update(grade.toJson())
        .eq('id', id);
    ref.invalidateSelf();
  }

  Future<void> deleteGradeLevel(String id) async {
    final previous = state.value;
    state.whenData((s) {
      final updated = s.gradeLevels.where((g) => g.id != id).toList();
      state = AsyncData(s.copyWith(gradeLevels: updated));
    });

    try {
      await SupabaseConfig.adminClient
          .from('niveaux')
          .update({'is_active': false})
          .eq('id', id);
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }

  // ==================== SECTION CRUD ====================
  Future<void> addSection(SectionModel section) async {
    await SupabaseConfig.adminClient.from('sections').insert(section.toJson());
    ref.invalidateSelf();
  }

  Future<void> updateSection(String id, SectionModel section) async {
    final previous = state.value;
    state.whenData((s) {
      final updated = s.sections.map((sec) => sec.id == id ? section : sec).toList();
      state = AsyncData(s.copyWith(sections: updated));
    });

    try {
      await SupabaseConfig.adminClient
          .from('sections')
          .update(section.toJson())
          .eq('id', id);
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> deleteSection(String id) async {
    final previous = state.value;
    state.whenData((s) {
      final updated = s.sections.where((sec) => sec.id != id).toList();
      state = AsyncData(s.copyWith(sections: updated));
    });

    try {
      await SupabaseConfig.adminClient
          .from('sections')
          .update({'is_active': false})
          .eq('id', id);
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }

  // ==================== NIVEAU-SECTION MAPPING ====================
  Future<void> assignSectionToGrade(String gradeId, String sectionId) async {
    await SupabaseConfig.adminClient.from('niveau_sections').insert({
      'niveau_id': gradeId,
      'section_id': sectionId,
    });
    ref.invalidateSelf();
  }

  Future<void> removeSectionFromGrade(String gradeId, String sectionId) async {
    final previous = state.value;
    state.whenData((s) {
      final updatedGrades = s.gradeLevels.map((g) {
        if (g.id == gradeId) {
          final updatedSecs = g.sections.where((sec) => sec.id != sectionId).toList();
          return g.copyWith(sections: updatedSecs);
        }
        return g;
      }).toList();
      state = AsyncData(s.copyWith(gradeLevels: updatedGrades));
    });

    try {
      await SupabaseConfig.adminClient
          .from('niveau_sections')
          .delete()
          .eq('niveau_id', gradeId)
          .eq('section_id', sectionId);
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }

  // ==================== EXAM TYPE CRUD ====================
  Future<void> addExamType(ExamTypeModel examType) async {
    await SupabaseConfig.adminClient.from('exam_types').insert(examType.toJson());
    ref.invalidateSelf();
  }

  Future<void> updateExamType(String id, ExamTypeModel examType) async {
    final previous = state.value;
    state.whenData((s) {
      final updated = s.examTypes.map((e) => e.id == id ? examType : e).toList();
      state = AsyncData(s.copyWith(examTypes: updated));
    });

    try {
      await SupabaseConfig.adminClient
          .from('exam_types')
          .update(examType.toJson())
          .eq('id', id);
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> deleteExamType(String id) async {
    final previous = state.value;
    state.whenData((s) {
      final updated = s.examTypes.where((e) => e.id != id).toList();
      state = AsyncData(s.copyWith(examTypes: updated));
    });

    try {
      await SupabaseConfig.adminClient
          .from('exam_types')
          .update({'is_active': false})
          .eq('id', id);
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }

  // ==================== CLASS CRUD ====================
  Future<void> addClass({
    required String name,
    required String gradeLevelId,
    String? sectionId,
  }) async {
    final supabase = SupabaseConfig.adminClient;
    final userId = supabase.auth.currentUser?.id;
    final userResp = await supabase
        .from('users')
        .select('school_id')
        .eq('id', userId!)
        .single();
    final schoolId = userResp['school_id'];

    await supabase.from('classes').insert({
      'school_id': schoolId,
      'name': name,
      'niveau_id': gradeLevelId,
      'section_id': sectionId,
    });
    ref.invalidateSelf();
  }

  Future<void> updateClass(String id, {String? name, String? sectionId}) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (sectionId != null) data['section_id'] = sectionId;

    await SupabaseConfig.adminClient.from('classes').update(data).eq('id', id);
    ref.invalidateSelf();
  }

  Future<void> deleteClass(String id) async {
    final previous = state.value;
    state.whenData((s) {
      final updatedGrades = s.gradeLevels.map((g) {
        final updatedClasses = g.classes.where((c) => c.id != id).toList();
        return g.copyWith(classes: updatedClasses);
      }).toList();
      state = AsyncData(s.copyWith(gradeLevels: updatedGrades));
    });

    try {
      await SupabaseConfig.adminClient.from('classes').delete().eq('id', id);
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }
}
