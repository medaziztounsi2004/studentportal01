import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../core/config/supabase_config.dart';
import '../../data/models/class_model.dart';

/// Represents a single absence record
class AbsenceModel {
  final String id;
  final String enrollmentId;
  final String? subjectOfferingId;
  final String studentId;
  final String studentName;
  final String? studentPhotoUrl;
  final String? studentEmail;
  final String? studentPhone;
  final String? studentCode;
  final String? niveauName;
  final String? className;
  final String? classId;
  final String? subjectName;
  final String? subjectCode;
  final String? teacherName;
  final String? teacherPhotoUrl;
  final DateTime date;
  final double hoursAbsent;
  final String? sessionType; // CI, TD, TP
  final String? reason;
  final bool justified;
  final DateTime createdAt;

  AbsenceModel({
    required this.id,
    required this.enrollmentId,
    this.subjectOfferingId,
    required this.studentId,
    required this.studentName,
    this.studentPhotoUrl,
    this.studentEmail,
    this.studentPhone,
    this.studentCode,
    this.niveauName,
    this.className,
    this.classId,
    this.subjectName,
    this.subjectCode,
    this.teacherName,
    this.teacherPhotoUrl,
    required this.date,
    this.hoursAbsent = 2.0,
    this.sessionType,
    this.reason,
    this.justified = false,
    required this.createdAt,
  });

  AbsenceModel copyWith({
    String? id,
    String? enrollmentId,
    String? subjectOfferingId,
    String? studentId,
    String? studentName,
    String? studentPhotoUrl,
    String? studentEmail,
    String? studentPhone,
    String? studentCode,
    String? niveauName,
    String? className,
    String? classId,
    String? subjectName,
    String? subjectCode,
    String? teacherName,
    String? teacherPhotoUrl,
    DateTime? date,
    double? hoursAbsent,
    String? sessionType,
    String? reason,
    bool? justified,
    DateTime? createdAt,
  }) {
    return AbsenceModel(
      id: id ?? this.id,
      enrollmentId: enrollmentId ?? this.enrollmentId,
      subjectOfferingId: subjectOfferingId ?? this.subjectOfferingId,
      studentId: studentId ?? this.studentId,
      studentName: studentName ?? this.studentName,
      studentPhotoUrl: studentPhotoUrl ?? this.studentPhotoUrl,
      studentEmail: studentEmail ?? this.studentEmail,
      studentPhone: studentPhone ?? this.studentPhone,
      studentCode: studentCode ?? this.studentCode,
      niveauName: niveauName ?? this.niveauName,
      className: className ?? this.className,
      classId: classId ?? this.classId,
      subjectName: subjectName ?? this.subjectName,
      subjectCode: subjectCode ?? this.subjectCode,
      teacherName: teacherName ?? this.teacherName,
      teacherPhotoUrl: teacherPhotoUrl ?? this.teacherPhotoUrl,
      date: date ?? this.date,
      hoursAbsent: hoursAbsent ?? this.hoursAbsent,
      sessionType: sessionType ?? this.sessionType,
      reason: reason ?? this.reason,
      justified: justified ?? this.justified,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory AbsenceModel.fromJson(Map<String, dynamic> json) {
    final enrollments = json['enrollments'] as Map<String, dynamic>?;
    final users = enrollments?['users'] as Map<String, dynamic>?;
    final classes = enrollments?['classes'] as Map<String, dynamic>?;
    final niveau = classes?['niveaux'] as Map<String, dynamic>?;
    final subjectOffering = json['subject_offerings'] as Map<String, dynamic>?;
    final subject = subjectOffering?['subjects'] as Map<String, dynamic>?;
    final teacher = subjectOffering?['users'] as Map<String, dynamic>?;

    return AbsenceModel(
      id: json['id'] as String,
      enrollmentId: json['enrollment_id'] as String? ?? '',
      subjectOfferingId: json['subject_offering_id'] as String?,
      studentId: json['student_id'] as String? ?? users?['id'] as String? ?? '',
      studentName: users?['full_name'] as String? ?? 'Inconnu',
      studentPhotoUrl: users?['photo_url'] as String? ?? users?['photo'] as String? ?? users?['avatar_url'] as String?,
      studentEmail: users?['email'] as String?,
      studentPhone: users?['phone'] as String?,
      studentCode: users?['student_code'] as String?,
      niveauName: niveau?['name'] as String?,
      className: classes?['name'] as String?,
      classId: classes?['id'] as String?,
      subjectName: subject?['name'] as String?,
      subjectCode: subject?['code'] as String?,
      teacherName: teacher?['full_name'] as String?,
      teacherPhotoUrl: teacher?['photo_url'] as String? ?? teacher?['photo'] as String?,
      date: DateTime.parse(json['date'] as String),
      hoursAbsent: (json['hours_absent'] as num?)?.toDouble() ?? 2.0,
      sessionType: json['session_type'] as String?,
      reason: json['reason'] as String?,
      justified: json['justified'] as bool? ?? false,
      createdAt: DateTime.parse(
        json['created_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
    );
  }
}

/// Represents a timetable slot for a class
class TimetableSlotInfo {
  final String id;
  final String subjectOfferingId;
  final String? classId;
  final String? className;
  final String subjectName;
  final String dayOfWeek;
  final String startTime;
  final String endTime;
  final String? room;
  final String? teacherName;
  final String? teacherPhotoUrl;
  final String sessionType;
  final double hours;

  TimetableSlotInfo({
    required this.id,
    required this.subjectOfferingId,
    this.classId,
    this.className,
    required this.subjectName,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.room,
    this.teacherName,
    this.teacherPhotoUrl,
    required this.sessionType,
    required this.hours,
  });

  factory TimetableSlotInfo.fromJson(Map<String, dynamic> json) {
    final so = json['subject_offerings'] as Map<String, dynamic>?;
    final subject = so?['subjects'] as Map<String, dynamic>?;
    final classData = so?['classes'] as Map<String, dynamic>?;
    final teacher = so?['users'] as Map<String, dynamic>?;

    // Calculate hours from start/end time
    final startParts = (json['start_time'] as String? ?? '08:00:00').split(':');
    final endParts = (json['end_time'] as String? ?? '10:00:00').split(':');
    final startHour = int.tryParse(startParts[0]) ?? 8;
    final endHour = int.tryParse(endParts[0]) ?? 10;
    final hours = (endHour - startHour).toDouble();

    return TimetableSlotInfo(
      id: json['id'] as String,
      subjectOfferingId:
          json['subject_offering_id'] as String? ?? so?['id'] as String? ?? '',
      classId: so?['class_id'] as String? ?? classData?['id'] as String?,
      className: classData?['name'] as String?,
      subjectName: subject?['name'] as String? ?? 'Matière inconnue',
      dayOfWeek: json['day_of_week'] as String? ?? 'monday',
      startTime: (json['start_time'] as String? ?? '08:00:00').substring(0, 5),
      endTime: (json['end_time'] as String? ?? '10:00:00').substring(0, 5),
      room: json['room'] as String?,
      teacherName:
          json['teacher_name'] as String? ?? teacher?['full_name'] as String?,
      teacherPhotoUrl: teacher?['photo_url'] as String? ?? teacher?['photo'] as String?,
      sessionType: json['session_type'] as String? ?? 'CI',
      hours: hours,
    );
  }

  String get dayLabel {
    switch (dayOfWeek.toLowerCase()) {
      case 'monday':
        return 'Lundi';
      case 'tuesday':
        return 'Mardi';
      case 'wednesday':
        return 'Mercredi';
      case 'thursday':
        return 'Jeudi';
      case 'friday':
        return 'Vendredi';
      case 'saturday':
        return 'Samedi';
      case 'sunday':
        return 'Dimanche';
      default:
        return dayOfWeek;
    }
  }

  int get dayIndex {
    switch (dayOfWeek.toLowerCase()) {
      case 'monday':
        return 1;
      case 'tuesday':
        return 2;
      case 'wednesday':
        return 3;
      case 'thursday':
        return 4;
      case 'friday':
        return 5;
      case 'saturday':
        return 6;
      case 'sunday':
        return 7;
      default:
        return 1;
    }
  }
}

/// Represents a subject offering (matière) for filtering
class SubjectOfferingInfo {
  final String id;
  final String? subjectId;
  final String subjectName;
  final String? subjectCode;
  final String? classId;
  final String? className;

  SubjectOfferingInfo({
    required this.id,
    this.subjectId,
    required this.subjectName,
    this.subjectCode,
    this.classId,
    this.className,
  });

  factory SubjectOfferingInfo.fromJson(Map<String, dynamic> json) {
    final subject = json['subjects'] as Map<String, dynamic>?;
    return SubjectOfferingInfo(
      id: json['id'] as String,
      subjectId: subject?['id'] as String?,
      subjectName: subject?['name'] as String? ?? 'Matière inconnue',
      subjectCode: subject?['code'] as String?,
      classId: json['class_id'] as String?,
      className: (json['classes'] as Map<String, dynamic>?)?['name'] as String?,
    );
  }
}

/// Represents a student for bulk absence creation
class StudentInfo {
  final String id;
  final String fullName;
  final String? photoUrl;
  final String? enrollmentId;
  final String? className;
  final String? classId;
  final String? studentCode;
  final String? phone;
  final String? email;

  StudentInfo({
    required this.id,
    required this.fullName,
    this.photoUrl,
    this.enrollmentId,
    this.className,
    this.classId,
    this.studentCode,
    this.phone,
    this.email,
  });

  factory StudentInfo.fromJson(Map<String, dynamic> json) {
    final enrollments = json['enrollments'] as List<dynamic>?;
    final firstEnrollment = enrollments?.isNotEmpty == true
        ? enrollments!.first as Map<String, dynamic>?
        : null;
    final classData = firstEnrollment?['classes'] as Map<String, dynamic>?;

    return StudentInfo(
      id: json['id'] as String,
      fullName: json['full_name'] as String? ?? 'Inconnu',
      photoUrl: json['photo_url'] as String? ?? json['photo'] as String? ?? json['avatar_url'] as String?,
      enrollmentId: firstEnrollment?['id'] as String?,
      className: classData?['name'] as String?,
      classId: classData?['id'] as String?,
      studentCode: json['student_code'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
    );
  }
}

/// State for the absences screen
class AbsencesState {
  final List<AbsenceModel> absences;
  final List<ClassModel> classes;
  final List<SubjectOfferingInfo> subjectOfferings;
  final List<StudentInfo> students;
  final List<TimetableSlotInfo> timetableSlots;
  final String searchQuery;
  final String? classFilter;
  final String?
  materialFilter; // Filter by subject name (unique across all classes)
  final String?
  subjectFilter; // Filter by specific subject_offering_id (class-specific)
  final String? justifiedFilter; // 'all', 'justified', 'not_justified'
  final DateTime? dateFromFilter;
  final DateTime? dateToFilter;
  final Set<String> selectedIds;
  final bool isLoading;

  AbsencesState({
    this.absences = const [],
    this.classes = const [],
    this.subjectOfferings = const [],
    this.students = const [],
    this.timetableSlots = const [],
    this.searchQuery = '',
    this.classFilter,
    this.materialFilter,
    this.subjectFilter,
    this.justifiedFilter,
    this.dateFromFilter,
    this.dateToFilter,
    this.selectedIds = const {},
    this.isLoading = false,
  });

  /// Get unique subject names for the material dropdown
  List<String> get uniqueSubjectNames {
    final names = subjectOfferings
        .map((o) => o.subjectName)
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
    names.sort();
    return names;
  }

  /// Get classes that have the selected material
  List<SubjectOfferingInfo> get classesForSelectedMaterial {
    if (materialFilter == null) return [];
    return subjectOfferings
        .where((o) => o.subjectName == materialFilter)
        .toList();
  }

  /// Apply all filters and search to get filtered list
  List<AbsenceModel> get filtered {
    var result = absences;

    // Search filter - search across many fields
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase().trim();
      result = result.where((a) {
        // Student name
        if (a.studentName.toLowerCase().contains(query)) return true;
        // Student email
        if (a.studentEmail?.toLowerCase().contains(query) ?? false) return true;
        // Student phone
        if (a.studentPhone?.contains(query) ?? false) return true;
        // Student code
        if (a.studentCode?.toLowerCase().contains(query) ?? false) return true;
        // Class name
        if (a.className?.toLowerCase().contains(query) ?? false) return true;
        // Niveau name
        if (a.niveauName?.toLowerCase().contains(query) ?? false) return true;
        // Subject name
        if (a.subjectName?.toLowerCase().contains(query) ?? false) return true;
        // Subject code
        if (a.subjectCode?.toLowerCase().contains(query) ?? false) return true;
        // Reason/motif
        if (a.reason?.toLowerCase().contains(query) ?? false) return true;
        // Session type
        if (a.sessionType?.toLowerCase().contains(query) ?? false) return true;

        return false;
      }).toList();
    }

    // Class filter
    if (classFilter != null) {
      result = result.where((a) => a.classId == classFilter).toList();
    }

    // Material filter (by subject name)
    if (materialFilter != null) {
      result = result.where((a) => a.subjectName == materialFilter).toList();
    }

    // Subject filter (specific offering with class)
    if (subjectFilter != null) {
      result = result
          .where((a) => a.subjectOfferingId == subjectFilter)
          .toList();
    }

    // Justified filter
    if (justifiedFilter == 'justified') {
      result = result.where((a) => a.justified).toList();
    } else if (justifiedFilter == 'not_justified') {
      result = result.where((a) => !a.justified).toList();
    }

    // Date range filter
    if (dateFromFilter != null) {
      result = result
          .where(
            (a) =>
                a.date.isAfter(dateFromFilter!) ||
                a.date.isAtSameMomentAs(dateFromFilter!),
          )
          .toList();
    }
    if (dateToFilter != null) {
      result = result
          .where(
            (a) => a.date.isBefore(dateToFilter!.add(const Duration(days: 1))),
          )
          .toList();
    }

    return result;
  }

  /// Get total hours for filtered absences
  double get totalHours => filtered.fold(0.0, (sum, a) => sum + a.hoursAbsent);

  /// Get justified count
  int get justifiedCount => filtered.where((a) => a.justified).length;

  /// Get not justified count
  int get notJustifiedCount => filtered.where((a) => !a.justified).length;

  AbsencesState copyWith({
    List<AbsenceModel>? absences,
    List<ClassModel>? classes,
    List<SubjectOfferingInfo>? subjectOfferings,
    List<StudentInfo>? students,
    List<TimetableSlotInfo>? timetableSlots,
    String? searchQuery,
    String? classFilter,
    String? materialFilter,
    String? subjectFilter,
    String? justifiedFilter,
    DateTime? dateFromFilter,
    DateTime? dateToFilter,
    Set<String>? selectedIds,
    bool? isLoading,
    bool clearClassFilter = false,
    bool clearMaterialFilter = false,
    bool clearSubjectFilter = false,
    bool clearJustifiedFilter = false,
    bool clearDateFromFilter = false,
    bool clearDateToFilter = false,
  }) {
    return AbsencesState(
      absences: absences ?? this.absences,
      classes: classes ?? this.classes,
      subjectOfferings: subjectOfferings ?? this.subjectOfferings,
      students: students ?? this.students,
      timetableSlots: timetableSlots ?? this.timetableSlots,
      searchQuery: searchQuery ?? this.searchQuery,
      classFilter: clearClassFilter ? null : (classFilter ?? this.classFilter),
      materialFilter: clearMaterialFilter
          ? null
          : (materialFilter ?? this.materialFilter),
      subjectFilter: clearSubjectFilter
          ? null
          : (subjectFilter ?? this.subjectFilter),
      justifiedFilter: clearJustifiedFilter
          ? null
          : (justifiedFilter ?? this.justifiedFilter),
      dateFromFilter: clearDateFromFilter
          ? null
          : (dateFromFilter ?? this.dateFromFilter),
      dateToFilter: clearDateToFilter
          ? null
          : (dateToFilter ?? this.dateToFilter),
      selectedIds: selectedIds ?? this.selectedIds,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AbsencesNotifier extends AsyncNotifier<AbsencesState> {
  @override
  Future<AbsencesState> build() async => _load();

  Future<AbsencesState> _load() async {
    final supabase = SupabaseConfig.client;
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Non connecté');

    final profile = await supabase
        .from('users')
        .select('school_id')
        .eq('id', user.id)
        .single();
    final schoolId = profile['school_id'] as String?;
    if (schoolId == null) throw Exception('École non trouvée');

    // Fetch absence records with joins - include all user fields for search
    final absData = await supabase
        .from('absence_records')
        .select('''
          *,
          enrollments(
            id,
            users(id, full_name, email, phone, student_code, photo_url),
            classes(id, name, school_id, niveaux(id, name))
          ),
          subject_offerings(
            id,
            subjects(id, name, code),
            users(id, full_name, photo_url)
          )
        ''')
        .order('date', ascending: false)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(500);

    // Fetch classes for this school with niveau and section info
    final classData = await supabase
        .from('classes')
        .select('*, niveaux(id, name), sections(id, name)')
        .eq('school_id', schoolId)
        .order('name');

    // Fetch subject offerings for this school - include subject id and code for grouping
    final offeringsData = await supabase
        .from('subject_offerings')
        .select(
          'id, class_id, subjects(id, name, code), classes(id, name, school_id)',
        )
        .order('subjects(name)');

    // Fetch students with enrollments for this school
    final studentsData = await supabase
        .from('users')
        .select(
          'id, full_name, student_code, phone, email, photo_url, enrollments(id, classes(id, name, school_id))',
        )
        .eq('role', 'student')
        .eq('school_id', schoolId)
        .order('full_name');

    // Fetch timetable slots for this school's classes
    final timetableData = await supabase
        .from('timetable_slots')
        .select('''
          id,
          subject_offering_id,
          day_of_week,
          start_time,
          end_time,
          room,
          teacher_name,
          session_type,
          subject_offerings!inner(
            id,
            class_id,
            subjects(id, name),
            classes!inner(id, name, school_id),
            users(id, full_name, photo_url)
          )
        ''')
        .eq('subject_offerings.classes.school_id', schoolId)
        .order('day_of_week')
        .order('start_time');

    // Filter absences to only those from this school
    final absences = (absData as List)
        .map((e) => AbsenceModel.fromJson(e as Map<String, dynamic>))
        .where(
          (a) => a.className != null,
        ) // Only absences with valid class data
        .toList();

    // Filter offerings to this school's classes
    final offerings = (offeringsData as List)
        .map((e) => SubjectOfferingInfo.fromJson(e as Map<String, dynamic>))
        .where((o) => o.className != null)
        .toList();

    // Parse timetable slots
    final timetableSlots = (timetableData as List)
        .map((e) => TimetableSlotInfo.fromJson(e as Map<String, dynamic>))
        .toList();

    return AbsencesState(
      absences: absences,
      classes: (classData as List)
          .map((e) => ClassModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      subjectOfferings: offerings,
      students: (studentsData as List)
          .map((e) => StudentInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      timetableSlots: timetableSlots,
    );
  }

  /// Refresh data from server
  Future<void> refresh() async {
    ref.invalidateSelf();
  }

  /// Set search query
  void setSearchQuery(String query) {
    state.whenData((s) => state = AsyncData(s.copyWith(searchQuery: query)));
  }

  /// Set class filter
  void setClassFilter(String? v) {
    state.whenData(
      (s) => state = AsyncData(
        s.copyWith(classFilter: v, clearClassFilter: v == null),
      ),
    );
  }

  /// Set subject filter
  void setSubjectFilter(String? v) {
    state.whenData(
      (s) => state = AsyncData(
        s.copyWith(subjectFilter: v, clearSubjectFilter: v == null),
      ),
    );
  }

  /// Set material filter (by subject name) - clears subject filter when changed
  void setMaterialFilter(String? v) {
    state.whenData(
      (s) => state = AsyncData(
        s.copyWith(
          materialFilter: v,
          clearMaterialFilter: v == null,
          // Clear specific subject filter when material changes
          clearSubjectFilter: true,
        ),
      ),
    );
  }

  /// Set justified filter
  void setJustifiedFilter(String? v) {
    state.whenData(
      (s) => state = AsyncData(
        s.copyWith(justifiedFilter: v, clearJustifiedFilter: v == null),
      ),
    );
  }

  /// Set date range filter
  void setDateRange(DateTime? from, DateTime? to) {
    state.whenData(
      (s) => state = AsyncData(
        s.copyWith(
          dateFromFilter: from,
          dateToFilter: to,
          clearDateFromFilter: from == null,
          clearDateToFilter: to == null,
        ),
      ),
    );
  }

  /// Clear all filters
  void clearFilters() {
    state.whenData(
      (s) => state = AsyncData(
        s.copyWith(
          searchQuery: '',
          clearClassFilter: true,
          clearMaterialFilter: true,
          clearSubjectFilter: true,
          clearJustifiedFilter: true,
          clearDateFromFilter: true,
          clearDateToFilter: true,
        ),
      ),
    );
  }

  /// Toggle selection of an absence
  void toggleSelection(String id) {
    state.whenData((s) {
      final newSelection = Set<String>.from(s.selectedIds);
      if (newSelection.contains(id)) {
        newSelection.remove(id);
      } else {
        newSelection.add(id);
      }
      state = AsyncData(s.copyWith(selectedIds: newSelection));
    });
  }

  /// Select all visible absences
  void selectAll() {
    state.whenData((s) {
      final allIds = s.filtered.map((a) => a.id).toSet();
      state = AsyncData(s.copyWith(selectedIds: allIds));
    });
  }

  /// Clear selection
  void clearSelection() {
    state.whenData((s) => state = AsyncData(s.copyWith(selectedIds: {})));
  }

  /// Create a single absence record
  Future<void> createAbsence({
    required String enrollmentId,
    String? subjectOfferingId,
    required DateTime date,
    double hoursAbsent = 2.0,
    String? sessionType,
    String? reason,
    bool justified = false,
  }) async {
    final supabase = SupabaseConfig.client;
    await supabase.from('absence_records').insert({
      'enrollment_id': enrollmentId,
      'subject_offering_id': subjectOfferingId,
      'date': date.toIso8601String().split('T')[0],
      'hours_absent': hoursAbsent,
      'session_type': sessionType,
      'reason': reason,
      'justified': justified,
    });
    ref.invalidateSelf();
  }

  /// Create bulk absences for multiple students (e.g., whole class)
  Future<int> createBulkAbsences({
    required List<String> enrollmentIds,
    String? subjectOfferingId,
    required DateTime date,
    double hoursAbsent = 2.0,
    String? sessionType,
    String? reason,
    bool justified = false,
  }) async {
    if (enrollmentIds.isEmpty) return 0;

    final supabase = SupabaseConfig.client;
    final records = enrollmentIds
        .map(
          (eid) => {
            'enrollment_id': eid,
            'subject_offering_id': subjectOfferingId,
            'date': date.toIso8601String().split('T')[0],
            'hours_absent': hoursAbsent,
            'session_type': sessionType,
            'reason': reason,
            'justified': justified,
          },
        )
        .toList();

    await supabase.from('absence_records').insert(records);
    ref.invalidateSelf();
    return records.length;
  }

  /// Update an absence record
  Future<void> updateAbsence({
    required String id,
    double? hoursAbsent,
    String? sessionType,
    String? reason,
    bool? justified,
  }) async {
    final supabase = SupabaseConfig.client;
    final updates = <String, dynamic>{};
    if (hoursAbsent != null) updates['hours_absent'] = hoursAbsent;
    if (sessionType != null) updates['session_type'] = sessionType;
    if (reason != null) updates['reason'] = reason;
    if (justified != null) updates['justified'] = justified;

    if (updates.isNotEmpty) {
      await supabase.from('absence_records').update(updates).eq('id', id);
      ref.invalidateSelf();
    }
  }

  /// Toggle justified status
  Future<void> toggleJustified(String id, bool current) async {
    // Optimistically update local state in-place so list order never shifts or jumps
    state.whenData((s) {
      final updatedList = s.absences.map((a) {
        if (a.id == id) {
          return a.copyWith(justified: !current);
        }
        return a;
      }).toList();
      state = AsyncData(s.copyWith(absences: updatedList));
    });

    try {
      await SupabaseConfig.client
          .from('absence_records')
          .update({'justified': !current})
          .eq('id', id);
    } catch (e) {
      // Revert in-place on error
      state.whenData((s) {
        final revertedList = s.absences.map((a) {
          if (a.id == id) {
            return a.copyWith(justified: current);
          }
          return a;
        }).toList();
        state = AsyncData(s.copyWith(absences: revertedList));
      });
      rethrow;
    }
  }

  /// Bulk toggle justified for selected absences
  Future<int> bulkToggleJustified(bool justified) async {
    final currentState = state.asData?.value;
    if (currentState == null || currentState.selectedIds.isEmpty) return 0;

    final supabase = SupabaseConfig.client;
    final ids = currentState.selectedIds.toList();

    // Optimistically update local state in-place
    state.whenData((s) {
      final updatedList = s.absences.map((a) {
        if (ids.contains(a.id)) {
          return a.copyWith(justified: justified);
        }
        return a;
      }).toList();
      state = AsyncData(s.copyWith(absences: updatedList, selectedIds: {}));
    });

    try {
      await supabase
          .from('absence_records')
          .update({'justified': justified})
          .inFilter('id', ids);
    } catch (e) {
      ref.invalidateSelf();
      rethrow;
    }

    return ids.length;
  }

  /// Delete a single absence
  Future<void> delete(String id) async {
    final previous = state.value;
    state.whenData((s) {
      final updatedList = s.absences.where((a) => a.id != id).toList();
      state = AsyncData(s.copyWith(absences: updatedList));
    });

    try {
      await SupabaseConfig.client.from('absence_records').delete().eq('id', id);
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }

  /// Delete selected absences
  Future<int> deleteSelected() async {
    final currentState = state.asData?.value;
    if (currentState == null || currentState.selectedIds.isEmpty) return 0;

    final previous = state.value;
    final ids = currentState.selectedIds.toSet();

    state.whenData((s) {
      final updatedList = s.absences.where((a) => !ids.contains(a.id)).toList();
      state = AsyncData(s.copyWith(absences: updatedList, selectedIds: {}));
    });

    try {
      final supabase = SupabaseConfig.client;
      await supabase.from('absence_records').delete().inFilter('id', ids.toList());
      return ids.length;
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }

  /// Get students for a specific class (for bulk absence creation)
  Future<List<StudentInfo>> getStudentsForClass(String classId) async {
    final supabase = SupabaseConfig.client;
    final data = await supabase
        .from('users')
        .select(
          'id, full_name, photo_url, enrollments!inner(id, class_id, classes(id, name))',
        )
        .eq('role', 'student')
        .eq('enrollments.class_id', classId)
        .order('full_name');

    return (data as List)
        .map((e) => StudentInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Get subject offerings for a specific class
  List<SubjectOfferingInfo> getOfferingsForClass(String classId) {
    final currentState = state.asData?.value;
    if (currentState == null) return [];
    return currentState.subjectOfferings
        .where((o) => o.classId == classId)
        .toList();
  }

  /// Get timetable slots for a specific class
  List<TimetableSlotInfo> getTimetableSlotsForClass(String classId) {
    final currentState = state.asData?.value;
    if (currentState == null) return [];
    return currentState.timetableSlots
        .where((t) => t.classId == classId)
        .toList();
  }

  /// Get timetable slots for a specific day and class
  List<TimetableSlotInfo> getTimetableSlotsForDay(
    String classId,
    int dayIndex,
  ) {
    final slots = getTimetableSlotsForClass(classId);
    return slots.where((t) => t.dayIndex == dayIndex).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  Future<String?> _currentSchoolId() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return null;
    final profile = await SupabaseConfig.client
        .from('users')
        .select('school_id')
        .eq('id', user.id)
        .single();
    return profile['school_id']?.toString();
  }

  Future<List<({DateTime start, DateTime end})>> _loadVacationRanges(String schoolId) async {
    final resp = await SupabaseConfig.client
        .from('vacation_periods')
        .select('start_date, end_date')
        .eq('school_id', schoolId);
    return (resp as List).map((r) => (
      start: DateTime.parse(r['start_date'].toString()),
      end: DateTime.parse(r['end_date'].toString()),
    )).toList();
  }

  bool _isDateInVacation(DateTime date, List<({DateTime start, DateTime end})> vacations) {
    final d = DateTime(date.year, date.month, date.day);
    for (final v in vacations) {
      if (!d.isBefore(v.start) && !d.isAfter(v.end)) return true;
    }
    return false;
  }

  /// Create absences based on timetable for a single day
  /// Returns count of absences created
  Future<int> createAbsencesFromTimetable({
    required String classId,
    required DateTime date,
    required List<String> enrollmentIds,
    List<String>? timetableSlotIds, // If null, use all slots for that day
    String? reason,
    bool justified = false,
  }) async {
    final supabase = SupabaseConfig.client;

    final schoolId = await _currentSchoolId();
    if (schoolId == null) return 0;
    final vacations = await _loadVacationRanges(schoolId);
    if (_isDateInVacation(date, vacations)) return 0;

    // Get timetable slots for that day
    final dayIndex = date.weekday; // 1=Monday, 7=Sunday
    var slots = getTimetableSlotsForDay(classId, dayIndex);

    // Filter to specific slots if provided
    if (timetableSlotIds != null && timetableSlotIds.isNotEmpty) {
      slots = slots.where((s) => timetableSlotIds.contains(s.id)).toList();
    }

    if (slots.isEmpty || enrollmentIds.isEmpty) return 0;

    // Create absence records for each student x each slot
    final records = <Map<String, dynamic>>[];
    for (final eid in enrollmentIds) {
      for (final slot in slots) {
        records.add({
          'enrollment_id': eid,
          'subject_offering_id': slot.subjectOfferingId,
          'date': date.toIso8601String().split('T')[0],
          'hours_absent': slot.hours,
          'session_type': slot.sessionType,
          'reason': reason,
          'justified': justified,
        });
      }
    }

    if (records.isNotEmpty) {
      await supabase.from('absence_records').insert(records);
      ref.invalidateSelf();
    }

    return records.length;
  }

  /// Create absences for a date range (week, month, etc.)
  /// This will create absences for selected timetable slots on each matching day
  Future<int> createAbsencesForDateRange({
    required String classId,
    required DateTime startDate,
    required DateTime endDate,
    required List<String> enrollmentIds,
    List<String>? timetableSlotIds,
    String? reason,
    bool justified = false,
  }) async {
    final supabase = SupabaseConfig.client;

    final schoolId = await _currentSchoolId();
    if (schoolId == null) return 0;
    final vacations = await _loadVacationRanges(schoolId);

    var slots = getTimetableSlotsForClass(classId);

    // Filter to only selected slots if provided
    if (timetableSlotIds != null && timetableSlotIds.isNotEmpty) {
      slots = slots.where((s) => timetableSlotIds.contains(s.id)).toList();
    }

    if (slots.isEmpty || enrollmentIds.isEmpty) return 0;

    // Group slots by day of week
    final slotsByDay = <int, List<TimetableSlotInfo>>{};
    for (final slot in slots) {
      slotsByDay.putIfAbsent(slot.dayIndex, () => []).add(slot);
    }

    // Create records for each date in range
    final records = <Map<String, dynamic>>[];
    var currentDate = startDate;

    while (!currentDate.isAfter(endDate)) {
      if (_isDateInVacation(currentDate, vacations)) {
        currentDate = currentDate.add(const Duration(days: 1));
        continue;
      }
      final daySlots = slotsByDay[currentDate.weekday] ?? [];
      for (final eid in enrollmentIds) {
        for (final slot in daySlots) {
          records.add({
            'enrollment_id': eid,
            'subject_offering_id': slot.subjectOfferingId,
            'date': currentDate.toIso8601String().split('T')[0],
            'hours_absent': slot.hours,
            'session_type': slot.sessionType,
            'reason': reason,
            'justified': justified,
          });
        }
      }
      currentDate = currentDate.add(const Duration(days: 1));
    }

    if (records.isNotEmpty) {
      // Insert in batches to avoid timeout
      const batchSize = 100;
      for (var i = 0; i < records.length; i += batchSize) {
        final batch = records.skip(i).take(batchSize).toList();
        await supabase.from('absence_records').insert(batch);
      }
      ref.invalidateSelf();
    }

    return records.length;
  }
}

final absencesProvider = AsyncNotifierProvider<AbsencesNotifier, AbsencesState>(
  AbsencesNotifier.new,
);

/// Data holder for the student absence history screen
class StudentAbsencesData {
  final Map<String, dynamic> user;
  final List<AbsenceModel> absences;
  final int totalAbsences;
  final int justifiedCount;
  final int unjustifiedCount;
  final double totalHours;

  StudentAbsencesData({
    required this.user,
    required this.absences,
    required this.totalAbsences,
    required this.justifiedCount,
    required this.unjustifiedCount,
    required this.totalHours,
  });

  StudentAbsencesData copyWith({
    Map<String, dynamic>? user,
    List<AbsenceModel>? absences,
    int? totalAbsences,
    int? justifiedCount,
    int? unjustifiedCount,
    double? totalHours,
  }) {
    return StudentAbsencesData(
      user: user ?? this.user,
      absences: absences ?? this.absences,
      totalAbsences: totalAbsences ?? this.totalAbsences,
      justifiedCount: justifiedCount ?? this.justifiedCount,
      unjustifiedCount: unjustifiedCount ?? this.unjustifiedCount,
      totalHours: totalHours ?? this.totalHours,
    );
  }
}

class StudentAbsencesNotifier extends StateNotifier<AsyncValue<StudentAbsencesData>> {
  final String studentId;
  StudentAbsencesNotifier(this.studentId) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    try {
      final data = await _fetchData(studentId);
      state = AsyncValue.data(data);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  static Future<StudentAbsencesData> _fetchData(String studentId) async {
    final supabase = SupabaseConfig.adminClient;

    final userResp = await supabase
        .from('users')
        .select('''
          id, full_name, email, phone, photo_url, student_code, gender,
          date_of_birth, nationality, address,
          enrollments(
            id,
            classes(id, name, niveaux(id, name, code))
          )
        ''')
        .eq('id', studentId)
        .maybeSingle();

    final user = userResp ?? <String, dynamic>{};

    final absencesResp = await supabase
        .from('absence_records')
        .select('''
          *,
          enrollments(
            id,
            users(id, full_name, email, phone, student_code),
            classes(id, name, niveaux(id, name, code))
          ),
          subject_offerings(
            id,
            subjects(id, name, code),
            users!teacher_id(id, full_name, photo_url)
          )
        ''')
        .eq('student_id', studentId)
        .order('date', ascending: false)
        .order('created_at', ascending: false)
        .order('id', ascending: false);

    final absences = (absencesResp as List)
        .map((json) => AbsenceModel.fromJson(json))
        .toList();

    final justifiedCount = absences.where((a) => a.justified).length;
    final totalHours = absences.fold<double>(0, (sum, a) => sum + a.hoursAbsent);

    return StudentAbsencesData(
      user: user,
      absences: absences,
      totalAbsences: absences.length,
      justifiedCount: justifiedCount,
      unjustifiedCount: absences.length - justifiedCount,
      totalHours: totalHours,
    );
  }

  void toggleJustified(String absenceId, bool newJustified) {
    final current = state.value;
    if (current == null) return;
    final updated = current.absences.map((a) {
      if (a.id == absenceId) {
        return a.copyWith(justified: newJustified);
      }
      return a;
    }).toList();
    final justifiedCount = updated.where((a) => a.justified).length;
    state = AsyncValue.data(current.copyWith(
      absences: updated,
      justifiedCount: justifiedCount,
      unjustifiedCount: updated.length - justifiedCount,
    ));
  }

  void removeAbsence(String absenceId) {
    final current = state.value;
    if (current == null) return;
    final updated = current.absences.where((a) => a.id != absenceId).toList();
    final justifiedCount = updated.where((a) => a.justified).length;
    final totalHours = updated.fold<double>(0, (sum, a) => sum + a.hoursAbsent);
    state = AsyncValue.data(current.copyWith(
      absences: updated,
      totalAbsences: updated.length,
      justifiedCount: justifiedCount,
      unjustifiedCount: updated.length - justifiedCount,
      totalHours: totalHours,
    ));
  }

  void bulkToggleJustified(List<String> ids, bool newJustified) {
    final current = state.value;
    if (current == null) return;
    final idSet = ids.toSet();
    final updated = current.absences.map((a) {
      if (idSet.contains(a.id)) {
        return a.copyWith(justified: newJustified);
      }
      return a;
    }).toList();
    final justifiedCount = updated.where((a) => a.justified).length;
    state = AsyncValue.data(current.copyWith(
      absences: updated,
      justifiedCount: justifiedCount,
      unjustifiedCount: updated.length - justifiedCount,
    ));
  }

  void bulkRemove(List<String> ids) {
    final current = state.value;
    if (current == null) return;
    final idSet = ids.toSet();
    final updated = current.absences.where((a) => !idSet.contains(a.id)).toList();
    final justifiedCount = updated.where((a) => a.justified).length;
    final totalHours = updated.fold<double>(0, (sum, a) => sum + a.hoursAbsent);
    state = AsyncValue.data(current.copyWith(
      absences: updated,
      totalAbsences: updated.length,
      justifiedCount: justifiedCount,
      unjustifiedCount: updated.length - justifiedCount,
      totalHours: totalHours,
    ));
  }
}

final studentAbsencesProvider = StateNotifierProvider.family<StudentAbsencesNotifier, AsyncValue<StudentAbsencesData>, String>((ref, studentId) {
  return StudentAbsencesNotifier(studentId);
});
