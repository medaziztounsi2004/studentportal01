import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/supabase_config.dart';
import '../../data/models/class_model.dart';

// ═══════════════════════════════════════════════════════════════
// ░░░  Classes State  ░░░
// ═══════════════════════════════════════════════════════════════

class ClassesState {
  final List<ClassModel> classes;
  final String? selectedGroupId;
  final String? selectedGradeLevelId;
  final String? searchQuery;
  
  ClassesState({
    this.classes = const [],
    this.selectedGroupId,
    this.selectedGradeLevelId,
    this.searchQuery,
  });

  List<ClassModel> get filtered {
    var result = classes;
    if (selectedGroupId != null) {
      result = result.where((c) => c.groupId == selectedGroupId).toList();
    }
    if (selectedGradeLevelId != null) {
      result = result
          .where((c) => c.gradeLevelId == selectedGradeLevelId)
          .toList();
    }
    if (searchQuery != null && searchQuery!.isNotEmpty) {
      final query = searchQuery!.toLowerCase();
      result = result.where((c) =>
        c.name.toLowerCase().contains(query) ||
        (c.gradeLevelName?.toLowerCase().contains(query) ?? false) ||
        (c.sectionName?.toLowerCase().contains(query) ?? false) ||
        (c.room?.toLowerCase().contains(query) ?? false)
      ).toList();
    }
    return result;
  }

  ClassesState copyWith({
    List<ClassModel>? classes,
    String? selectedGroupId,
    String? selectedGradeLevelId,
    String? searchQuery,
    bool clearGroupFilter = false,
    bool clearGradeLevelFilter = false,
    bool clearSearch = false,
  }) => ClassesState(
    classes: classes ?? this.classes,
    selectedGroupId: clearGroupFilter
        ? null
        : (selectedGroupId ?? this.selectedGroupId),
    selectedGradeLevelId: clearGradeLevelFilter
        ? null
        : (selectedGradeLevelId ?? this.selectedGradeLevelId),
    searchQuery: clearSearch ? null : (searchQuery ?? this.searchQuery),
  );
}

// ═══════════════════════════════════════════════════════════════
// ░░░  Classes Notifier  ░░░
// ═══════════════════════════════════════════════════════════════

class ClassesNotifier extends AsyncNotifier<ClassesState> {
  @override
  Future<ClassesState> build() async => _load();

  Future<ClassesState> _load() async {
    final supabase = SupabaseConfig.adminClient;
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) throw Exception('Non connecté');

    final profile = await supabase
        .from('users')
        .select('school_id')
        .eq('id', user.id)
        .single();

    // Load student counts per class (active enrollments only)
    final enrollmentsResp = await supabase
        .from('enrollments')
        .select('class_id')
        .eq('is_active', true);

    final Map<String, int> studentCounts = {};
    for (final row in enrollmentsResp as List) {
      final cid = row['class_id'] as String?;
      if (cid == null) continue;
      studentCounts[cid] = (studentCounts[cid] ?? 0) + 1;
    }

    final data = await supabase
        .from('classes')
        .select(
          '*, niveaux:niveau_id(code, name), sections:section_id(code, name, color)',
        )
        .eq('school_id', profile['school_id'])
        .order('name');

    final classes = (data as List).map((e) {
      e['student_count'] = studentCounts[e['id']] ?? 0;
      return ClassModel.fromJson(e);
    }).toList();

    return ClassesState(classes: classes);
  }

  void setGroupFilter(String? groupId) {
    state.whenData(
      (c) => state = AsyncData(
        c.copyWith(selectedGroupId: groupId, clearGroupFilter: groupId == null),
      ),
    );
  }

  void setGradeLevelFilter(String? gradeLevelId) {
    state.whenData(
      (c) => state = AsyncData(
        c.copyWith(
          selectedGradeLevelId: gradeLevelId,
          clearGradeLevelFilter: gradeLevelId == null,
        ),
      ),
    );
  }

  void setSearch(String query) {
    state.whenData(
      (c) => state = AsyncData(
        c.copyWith(
          searchQuery: query,
          clearSearch: query.isEmpty,
        ),
      ),
    );
  }

  void clearFilters() {
    state.whenData(
      (c) => state = AsyncData(
        c.copyWith(
          clearGroupFilter: true,
          clearGradeLevelFilter: true,
          clearSearch: true,
        ),
      ),
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load());
  }

  Future<void> create({
    required String name,
    String? groupId,
    String? gradeLevelId,
    String? sectionId,
    String? room,
    int? capacity,
  }) async {
    final supabase = SupabaseConfig.client;
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Non connecté');

    final profile = await supabase
        .from('users')
        .select('school_id')
        .eq('id', user.id)
        .single();

    await supabase.from('classes').insert({
      'name': name,
      'school_id': profile['school_id'],
      'niveau_id': gradeLevelId,
      'section_id': sectionId,
      'room': room,
      'capacity': capacity,
    });
    ref.invalidateSelf();
  }

  Future<void> updateClass({
    required String id,
    required String name,
    String? groupId,
    String? gradeLevelId,
    String? sectionId,
    String? room,
    int? capacity,
  }) async {
    final previous = state.value;
    state.whenData((s) {
      final updated = s.classes.map((c) {
        if (c.id == id) {
          return c.copyWith(
            name: name,
            groupId: groupId ?? c.groupId,
            gradeLevelId: gradeLevelId ?? c.gradeLevelId,
            sectionId: sectionId ?? c.sectionId,
            room: room ?? c.room,
            capacity: capacity ?? c.capacity,
          );
        }
        return c;
      }).toList();
      state = AsyncData(s.copyWith(classes: updated));
    });

    try {
      await SupabaseConfig.client
          .from('classes')
          .update({
            'name': name,
            'niveau_id': gradeLevelId,
            'section_id': sectionId,
            'room': room,
            'capacity': capacity,
          })
          .eq('id', id);
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    final previous = state.value;
    state.whenData((s) {
      final updated = s.classes.where((c) => c.id != id).toList();
      state = AsyncData(s.copyWith(classes: updated));
    });

    try {
      await SupabaseConfig.client.from('classes').delete().eq('id', id);
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }
}

final classesProvider = AsyncNotifierProvider<ClassesNotifier, ClassesState>(
  ClassesNotifier.new,
);

// ═══════════════════════════════════════════════════════════════
// ░░░  Timetable Slot model for class schedule  ░░░
// ═══════════════════════════════════════════════════════════════

class ClassTimetableSlot {
  final String id;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final String? room;
  final String? subjectName;
  final String? subjectCode;
  final String? teacherName;
  final String? teacherPhotoUrl;
  final String? teacherId;

  ClassTimetableSlot({
    required this.id,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.room,
    this.subjectName,
    this.subjectCode,
    this.teacherName,
    this.teacherPhotoUrl,
    this.teacherId,
  });

  static int _parseDow(dynamic v) {
    if (v is int) return v;
    if (v is String) {
      switch (v.toLowerCase()) {
        case 'monday': return 1;
        case 'tuesday': return 2;
        case 'wednesday': return 3;
        case 'thursday': return 4;
        case 'friday': return 5;
        case 'saturday': return 6;
        case 'sunday': return 7;
      }
    }
    return 1;
  }

  static int _timeToMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  factory ClassTimetableSlot.fromJson(Map<String, dynamic> json) {
    final so = json['subject_offerings'] as Map<String, dynamic>?;
    return ClassTimetableSlot(
      id: json['id']?.toString() ?? '',
      dayOfWeek: _parseDow(json['day_of_week']),
      startTime: json['start_time']?.toString() ?? '08:00',
      endTime: json['end_time']?.toString() ?? '09:00',
      room: json['room']?.toString(),
      subjectName: so?['subjects']?['name']?.toString(),
      subjectCode: so?['subjects']?['code']?.toString(),
      teacherName: so?['users']?['full_name']?.toString(),
      teacherPhotoUrl: so?['users']?['photo_url']?.toString(),
      teacherId: so?['teacher_id']?.toString(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ░░░  Provider: Today's timetable for a class  ░░░
// ═══════════════════════════════════════════════════════════════

final classTimetableTodayProvider =
    FutureProvider.family<List<ClassTimetableSlot>, String>((ref, classId) async {
  final supabase = SupabaseConfig.adminClient;
  final now = DateTime.now();
  int dow = now.weekday;
  const dayNames = ['monday','tuesday','wednesday','thursday','friday','saturday','sunday'];
  final dayName = dayNames[dow - 1];

  try {
    // Get all subject_offerings for this class with subject details
    final offeringsResp = await supabase
        .from('subject_offerings')
        .select('id, subject_id, teacher_id, subjects(name, code), users(full_name, photo_url)')
        .eq('class_id', classId);

    final offerings = offeringsResp as List;
    if (offerings.isEmpty) return [];

    final offeringIds = offerings.map((o) => o['id'] as String).toList();

    // Get timetable slots for these offerings for today
    final slotsResp = await supabase
        .from('timetable_slots')
        .select('*')
        .inFilter('subject_offering_id', offeringIds)
        .eq('day_of_week', dayName)
        .order('start_time');

    final slots = slotsResp as List;
    if (slots.isEmpty) return [];

    // Build lookup map for offerings
    final Map<String, dynamic> offeringsMap = {};
    for (var o in offerings) {
      offeringsMap[o['id']] = o;
    }

    // Resolve teachers from teacher_assignments (subject_offerings.teacher_id may be NULL)
    final Map<String, String> subjectClassTeacherMap = {};
    final Map<String, String> subjectClassTeacherPhotoMap = {};
    try {
      final teacherAssResp = await supabase
          .from('teacher_assignments')
          .select('subject_id, class_id, users!teacher_id(full_name, photo_url)')
          .eq('is_active', true);

      for (final ta in (teacherAssResp as List)) {
        final subjectId = ta['subject_id'] as String?;
        final clsId = ta['class_id'] as String?;
        final teacherData = ta['users'] as Map<String, dynamic>?;
        if (subjectId != null && clsId != null) {
          subjectClassTeacherMap['${subjectId}_$clsId'] = teacherData?['full_name'] as String? ?? '';
          subjectClassTeacherPhotoMap['${subjectId}_$clsId'] = teacherData?['photo_url'] as String? ?? '';
        }
      }
    } catch (_) {}

    // Build slot list with resolved teachers and cleaned rooms
    final List<ClassTimetableSlot> result = [];
    for (final slot in slots) {
      final offering = offeringsMap[slot['subject_offering_id']];
      final subject = offering?['subjects'];
      final subjectId = offering?['subject_id'] as String?;

      // Resolve teacher from teacher_assignments first, then fallbacks
      String teacherName = subjectClassTeacherMap['${subjectId}_$classId'] ?? '';
      String? teacherPhoto = subjectClassTeacherPhotoMap['${subjectId}_$classId'];
      if (teacherName.isEmpty) {
        teacherName = (slot['teacher_name'] as String?) ?? (offering?['users']?['full_name'] as String?) ?? '';
        teacherPhoto = offering?['users']?['photo_url'] as String?;
      }

      // Clean room: extract just the room name from strings like "Bloc A – Principal · 2ème étage · Salle 204"
      String rawRoom = (slot['room'] as String?) ?? '';
      String shortRoom = rawRoom;
      if (rawRoom.contains('·')) {
        final parts = rawRoom.split('·').map((s) => s.trim()).toList();
        shortRoom = parts.last;
      }

      result.add(ClassTimetableSlot(
        id: slot['id']?.toString() ?? '',
        dayOfWeek: ClassTimetableSlot._parseDow(slot['day_of_week']),
        startTime: slot['start_time']?.toString() ?? '08:00',
        endTime: slot['end_time']?.toString() ?? '09:00',
        room: shortRoom.isNotEmpty ? shortRoom : null,
        subjectName: subject?['name']?.toString(),
        subjectCode: subject?['code']?.toString(),
        teacherName: teacherName.isNotEmpty ? teacherName : null,
        teacherPhotoUrl: (teacherPhoto != null && teacherPhoto.isNotEmpty) ? teacherPhoto : null,
        teacherId: offering?['teacher_id']?.toString(),
      ));
    }

    // Deduplicate: same subject + same start time = same course; keep the longest one
    final deduped = <String, ClassTimetableSlot>{};
    for (final slot in result) {
      final key = '${slot.startTime}|${slot.subjectName ?? slot.id}';
      final existing = deduped[key];
      if (existing == null) {
        deduped[key] = slot;
      } else {
        final existingDuration = ClassTimetableSlot._timeToMinutes(existing.endTime) -
            ClassTimetableSlot._timeToMinutes(existing.startTime);
        final newDuration = ClassTimetableSlot._timeToMinutes(slot.endTime) -
            ClassTimetableSlot._timeToMinutes(slot.startTime);
        if (newDuration > existingDuration) {
          deduped[key] = slot;
        }
      }
    }

    return deduped.values.toList()..sort((a, b) => a.startTime.compareTo(b.startTime));
  } catch (e) {
    debugPrint('classTimetableTodayProvider error: $e');
    return [];
  }
});

// ═══════════════════════════════════════════════════════════════
// ░░░  Provider: Main teacher for a class  ░░░
// ═══════════════════════════════════════════════════════════════

class ClassTeacherInfo {
  final String id;
  final String fullName;
  final String? email;
  final String? phone;
  final String? photoUrl;

  ClassTeacherInfo({required this.id, required this.fullName, this.email, this.phone, this.photoUrl});
}

final classMainTeacherProvider =
    FutureProvider.family<ClassTeacherInfo?, String>((ref, classId) async {
  final supabase = SupabaseConfig.adminClient;
  try {
    final assignments = await supabase
        .from('teacher_assignments')
        .select('teacher_id, users(id, full_name, email, phone, photo_url)')
        .eq('class_id', classId)
        .limit(1);

    if ((assignments as List).isNotEmpty) {
      final u = assignments[0]['users'];
      if (u != null) {
        return ClassTeacherInfo(
          id: u['id'] ?? '',
          fullName: u['full_name'] ?? '',
          email: u['email'],
          phone: u['phone'],
          photoUrl: u['photo_url'],
        );
      }
    }

    // Fallback: first subject_offering teacher
    final offerings = await supabase
        .from('subject_offerings')
        .select('teacher_id, users(id, full_name, email, phone, photo_url)')
        .eq('class_id', classId)
        .not('teacher_id', 'is', null)
        .limit(1);

    if ((offerings as List).isNotEmpty) {
      final u = offerings[0]['users'];
      if (u != null) {
        return ClassTeacherInfo(
          id: u['id'] ?? '',
          fullName: u['full_name'] ?? '',
          email: u['email'],
          phone: u['phone'],
          photoUrl: u['photo_url'],
        );
      }
    }

    return null;
  } catch (e) {
    debugPrint('classMainTeacherProvider error: $e');
    return null;
  }
});

// ═══════════════════════════════════════════════════════════════
// ░░░  Provider: All teachers for a class (with subject)  ░░░
// ═══════════════════════════════════════════════════════════════

class ClassTeacherWithSubject {
  final String id;
  final String fullName;
  final String? email;
  final String? photoUrl;
  final String? subjectName;
  final String? subjectCode;
  final String? phone;
  final bool isActive;
  final DateTime? createdAt;

  ClassTeacherWithSubject({
    required this.id,
    required this.fullName,
    this.email,
    this.photoUrl,
    this.subjectName,
    this.subjectCode,
    this.phone,
    this.isActive = true,
    this.createdAt,
  });
}

final classAllTeachersProvider =
    FutureProvider.family<List<ClassTeacherWithSubject>, String>((ref, classId) async {
  final supabase = SupabaseConfig.adminClient;
  final seen = <String>{};
  final teachers = <ClassTeacherWithSubject>[];

  debugPrint('classAllTeachersProvider: Loading teachers for class $classId');

  // ── Source 1: teacher_assignments table (Matières → Professeurs tab) ──
  try {
    final assignments = await supabase
        .from('teacher_assignments')
        .select('teacher_id, subjects(name, code), users(id, full_name, email, photo_url, phone, is_active, created_at)')
        .eq('class_id', classId)
        .eq('is_active', true);

    debugPrint('classAllTeachersProvider: teacher_assignments returned ${(assignments as List).length} rows');

    for (final a in assignments) {
      debugPrint('classAllTeachersProvider: raw assignment row: $a');
      final u = a['users'] as Map<String, dynamic>?;
      final s = a['subjects'] as Map<String, dynamic>?;
      if (u == null) {
        debugPrint('classAllTeachersProvider: users is null for row, skipping');
        continue;
      }
      final tid = u['id']?.toString() ?? '';
      final subjectName = s?['name']?.toString();
      final key = '$tid|$subjectName';
      if (seen.contains(key)) continue;
      seen.add(key);
      teachers.add(ClassTeacherWithSubject(
        id: tid,
        fullName: u['full_name']?.toString() ?? '',
        email: u['email']?.toString(),
        photoUrl: u['photo_url']?.toString(),
        subjectName: subjectName,
        subjectCode: s?['code']?.toString(),
        phone: u['phone']?.toString(),
        isActive: u['is_active'] == true,
        createdAt: u['created_at'] != null ? DateTime.tryParse(u['created_at'].toString()) : null,
      ));
    }
    debugPrint('classAllTeachersProvider: ${teachers.length} teachers from teacher_assignments');
  } catch (e, st) {
    debugPrint('classAllTeachersProvider (teacher_assignments) ERROR: $e');
    debugPrint('classAllTeachersProvider stacktrace: $st');
  }

  // ── Source 2: subject_offerings table (timetable/curriculum) ──
  try {
    final offerings = await supabase
        .from('subject_offerings')
        .select('teacher_id, subjects(name, code), users(id, full_name, email, photo_url)')
        .eq('class_id', classId)
        .not('teacher_id', 'is', null);

    debugPrint('classAllTeachersProvider: subject_offerings returned ${(offerings as List).length} rows');

    for (final o in offerings) {
      final u = o['users'] as Map<String, dynamic>?;
      final s = o['subjects'] as Map<String, dynamic>?;
      if (u == null) continue;
      final tid = u['id']?.toString() ?? '';
      final subjectName = s?['name']?.toString();
      final key = '$tid|$subjectName';
      if (seen.contains(key)) continue;
      seen.add(key);
      teachers.add(ClassTeacherWithSubject(
        id: tid,
        fullName: u['full_name']?.toString() ?? '',
        email: u['email']?.toString(),
        photoUrl: u['photo_url']?.toString(),
        subjectName: subjectName,
        subjectCode: s?['code']?.toString(),
      ));
    }
  } catch (e, st) {
    debugPrint('classAllTeachersProvider (subject_offerings) ERROR: $e');
    debugPrint('classAllTeachersProvider stacktrace: $st');
  }

  debugPrint('classAllTeachersProvider: TOTAL ${teachers.length} teachers found');
  return teachers;
});

// ═══════════════════════════════════════════════════════════════
// ░░░  Lightweight student preview for class cards  ░░░
// ═══════════════════════════════════════════════════════════════

class StudentPreview {
  final String id;
  final String fullName;
  final String? photoUrl;
  final String? gender;

  const StudentPreview({
    required this.id,
    required this.fullName,
    this.photoUrl,
    this.gender,
  });
}

/// Fetches up to [limit] students for the given class (name, photo, gender only).
final classStudentPreviewsProvider =
    FutureProvider.family<List<StudentPreview>, String>((ref, classId) async {
  final supabase = SupabaseConfig.adminClient;
  try {
    final rows = await supabase
        .from('enrollments')
        .select('user_id, users!inner(id, full_name, photo_url, gender)')
        .eq('class_id', classId)
        .eq('is_active', true)
        .limit(4);

    return (rows as List).map<StudentPreview>((e) {
      final u = e['users'] is Map ? e['users'] as Map<String, dynamic> : <String, dynamic>{};
      return StudentPreview(
        id: u['id']?.toString() ?? '',
        fullName: u['full_name']?.toString() ?? '',
        photoUrl: u['photo_url']?.toString(),
        gender: u['gender']?.toString(),
      );
    }).toList();
  } catch (e) {
    debugPrint('classStudentPreviewsProvider error: $e');
    return [];
  }
});
