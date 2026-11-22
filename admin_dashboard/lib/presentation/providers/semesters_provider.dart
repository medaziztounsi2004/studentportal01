import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/config/supabase_config.dart';

class SemesterModel {
  final String id;
  final String name;
  final int number;
  final DateTime startDate;
  final DateTime endDate;
  final bool isCurrent;
  final String? academicYearId;
  final String? academicYearName;

  SemesterModel({
    required this.id,
    required this.name,
    required this.number,
    required this.startDate,
    required this.endDate,
    this.isCurrent = false,
    this.academicYearId,
    this.academicYearName,
  });

  factory SemesterModel.fromJson(Map<String, dynamic> json) => SemesterModel(
    id: json['id'],
    name: json['name'] ?? '',
    number: json['number'] ?? 1,
    startDate: DateTime.parse(json['start_date']),
    endDate: DateTime.parse(json['end_date']),
    isCurrent: json['is_current'] ?? false,
    academicYearId: json['academic_year_id'],
    academicYearName: json['academic_years']?['name'],
  );

  SemesterModel copyWith({
    String? id,
    String? name,
    int? number,
    DateTime? startDate,
    DateTime? endDate,
    bool? isCurrent,
    String? academicYearId,
    String? academicYearName,
  }) => SemesterModel(
    id: id ?? this.id,
    name: name ?? this.name,
    number: number ?? this.number,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    isCurrent: isCurrent ?? this.isCurrent,
    academicYearId: academicYearId ?? this.academicYearId,
    academicYearName: academicYearName ?? this.academicYearName,
  );
}

class AcademicYearModel {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final bool isCurrent;

  AcademicYearModel({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    this.isCurrent = false,
  });

  factory AcademicYearModel.fromJson(Map<String, dynamic> json) =>
      AcademicYearModel(
        id: json['id'],
        name: json['name'] ?? '',
        startDate: DateTime.parse(json['start_date']),
        endDate: DateTime.parse(json['end_date']),
        isCurrent: json['is_current'] ?? false,
      );
  AcademicYearModel copyWith({
    String? id,
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    bool? isCurrent,
  }) => AcademicYearModel(
    id: id ?? this.id,
    name: name ?? this.name,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    isCurrent: isCurrent ?? this.isCurrent,
  );
}

class VacationPeriodModel {
  final String id;
  final String schoolId;
  final String academicYearId;
  final String? name;
  final DateTime startDate;
  final DateTime endDate;
  final String type; // 'auto_gap' | 'manual'

  VacationPeriodModel({
    required this.id,
    required this.schoolId,
    required this.academicYearId,
    this.name,
    required this.startDate,
    required this.endDate,
    required this.type,
  });

  factory VacationPeriodModel.fromJson(Map<String, dynamic> json) =>
      VacationPeriodModel(
        id: json['id'],
        schoolId: json['school_id'],
        academicYearId: json['academic_year_id'],
        name: json['name'],
        startDate: DateTime.parse(json['start_date']),
        endDate: DateTime.parse(json['end_date']),
        type: json['type'] ?? 'manual',
      );

  VacationPeriodModel copyWith({
    String? id,
    String? schoolId,
    String? academicYearId,
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    String? type,
  }) => VacationPeriodModel(
    id: id ?? this.id,
    schoolId: schoolId ?? this.schoolId,
    academicYearId: academicYearId ?? this.academicYearId,
    name: name ?? this.name,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    type: type ?? this.type,
  );
}

class ExamPeriodModel {
  final String id;
  final String schoolId;
  final String academicYearId;
  final String? name;
  final DateTime startDate;
  final DateTime endDate;

  ExamPeriodModel({
    required this.id,
    required this.schoolId,
    required this.academicYearId,
    this.name,
    required this.startDate,
    required this.endDate,
  });

  factory ExamPeriodModel.fromJson(Map<String, dynamic> json) => ExamPeriodModel(
    id: json['id'],
    schoolId: json['school_id'],
    academicYearId: json['academic_year_id'],
    name: json['name'],
    startDate: DateTime.parse(json['start_date']),
    endDate: DateTime.parse(json['end_date']),
  );

  ExamPeriodModel copyWith({
    String? id,
    String? schoolId,
    String? academicYearId,
    String? name,
    DateTime? startDate,
    DateTime? endDate,
  }) => ExamPeriodModel(
    id: id ?? this.id,
    schoolId: schoolId ?? this.schoolId,
    academicYearId: academicYearId ?? this.academicYearId,
    name: name ?? this.name,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
  );
}

class SemestersState {
  final List<SemesterModel> semesters;
  final List<AcademicYearModel> academicYears;
  final List<VacationPeriodModel> vacationPeriods;
  final List<ExamPeriodModel> examPeriods;
  final String? selectedAcademicYearId;

  SemestersState({
    this.semesters = const [],
    this.academicYears = const [],
    this.vacationPeriods = const [],
    this.examPeriods = const [],
    this.selectedAcademicYearId,
  });

  SemesterModel? get current => semesters.where((s) => s.isCurrent).firstOrNull;

  AcademicYearModel? get currentAcademicYear =>
      academicYears.where((y) => y.isCurrent).firstOrNull ??
      academicYears.firstOrNull;

  AcademicYearModel? get selectedAcademicYear =>
      (selectedAcademicYearId != null
          ? academicYears.where((y) => y.id == selectedAcademicYearId).firstOrNull
          : null) ??
      currentAcademicYear;

  List<SemesterModel> get filteredSemesters {
    final list = selectedAcademicYearId != null
        ? semesters
              .where((s) => s.academicYearId == selectedAcademicYearId)
              .toList()
        : semesters.toList();
    list.sort((a, b) {
      final numCompare = a.number.compareTo(b.number);
      if (numCompare != 0) return numCompare;
      return a.startDate.compareTo(b.startDate);
    });
    return list;
  }

  List<VacationPeriodModel> filteredVacations(String? yearId) => yearId == null
      ? vacationPeriods
      : vacationPeriods.where((v) => v.academicYearId == yearId).toList();

  List<ExamPeriodModel> filteredExams(String? yearId) => yearId == null
      ? examPeriods
      : examPeriods.where((e) => e.academicYearId == yearId).toList();

  List<ExamPeriodModel> get filteredExamPeriods {
    final yearId = selectedAcademicYearId;
    return yearId == null
        ? examPeriods
        : examPeriods.where((e) => e.academicYearId == yearId).toList();
  }

  bool isDateVacation(DateTime date, {String? yearId}) {
    final candidates = yearId == null
        ? vacationPeriods
        : vacationPeriods.where((v) => v.academicYearId == yearId);
    final d = DateTime(date.year, date.month, date.day);
    for (final v in candidates) {
      if (!d.isBefore(v.startDate) && !d.isAfter(v.endDate)) return true;
    }
    return false;
  }

  /// Helper to get singular unit name based on number of periods
  static String getUnitNameForCount(int count) {
    switch (count) {
      case 2:
        return 'Semestre';
      case 3:
        return 'Trimestre';
      case 4:
        return 'Quadrimestre';
      case 6:
        return 'Bimestre';
      default:
        return 'Période';
    }
  }

  /// Helper to get plural unit name based on number of periods
  static String getUnitNamePluralForCount(int count) {
    switch (count) {
      case 2:
        return 'Semestres';
      case 3:
        return 'Trimestres';
      case 4:
        return 'Quadrimestres';
      case 6:
        return 'Bimestres';
      default:
        return 'Périodes';
    }
  }

  /// Period type based on number of periods in the selected academic year.
  /// 2 -> semestre, 3 -> trimestre, 4 -> quadrimestre, 6 -> bimestre, else periode.
  String get periodType {
    final count = filteredSemesters.length;
    switch (count) {
      case 2:
        return 'semestre';
      case 3:
        return 'trimestre';
      case 4:
        return 'quadrimestre';
      case 6:
        return 'bimestre';
      default:
        return count > 0 ? 'periode' : 'semestre';
    }
  }

  /// Locked period type once periods exist. Null when DB is empty (admin can choose).
  String? get allowedPeriodType {
    if (filteredSemesters.isEmpty) return null;
    return periodType;
  }

  /// Duration in days for the current period type.
  int get periodTypeDuration {
    final count = filteredSemesters.length;
    switch (count) {
      case 2:
        return 183;
      case 3:
        return 92;
      case 4:
        return 91;
      case 6:
        return 61;
      default:
        return 90;
    }
  }

  String get periodLabel => getUnitNameForCount(filteredSemesters.length);
  String get periodLabelPlural => getUnitNamePluralForCount(filteredSemesters.length);

  /// Dynamically format a semester's display name based on current total periods count.
  /// E.g. If DB has "Semestre 1" but there are 3 periods, returns "Trimestre 1".
  String formatPeriodDisplayName(SemesterModel s) {
    final count = filteredSemesters.length;
    final unit = getUnitNameForCount(count);
    final regex = RegExp(
      r'^(Semestre|Trimestre|Quadrimestre|Bimestre|P[eé]riode|Sem\.|Trim\.)\s*(\d*)',
      caseSensitive: false,
    );
    final trimmed = s.name.trim();
    if (regex.hasMatch(trimmed)) {
      return trimmed.replaceFirstMapped(regex, (m) {
        final numPart = m.group(2);
        if (numPart != null && numPart.isNotEmpty) {
          return '$unit $numPart';
        }
        return '$unit ${s.number}';
      });
    }
    if (trimmed.isEmpty) {
      return '$unit ${s.number}';
    }
    return s.name;
  }

  /// Get the next semester number for the selected academic year
  int get nextSemesterNumber {
    final filtered = filteredSemesters;
    if (filtered.isEmpty) return 1;
    return filtered.map((s) => s.number).reduce((a, b) => a > b ? a : b) + 1;
  }

  /// Generate auto name for next period
  String get nextSemesterName => '$periodLabel $nextSemesterNumber';

  /// Strip time to avoid any timezone/hour discrepancies
  static DateTime stripTime(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Check if the selected/current academic year is already fully covered by periods
  bool get isCurrentYearFullyCovered {
    final year = selectedAcademicYear;
    if (year == null) return false;
    final list = filteredSemesters;
    if (list.isEmpty) return false;
    final latestEnd = list.map((s) => s.endDate).reduce((a, b) => a.isAfter(b) ? a : b);
    final yEnd = stripTime(year.endDate);
    final lEnd = stripTime(latestEnd);
    return !lEnd.isBefore(yEnd);
  }

  /// Check if a date range overlaps with or duplicates any existing period.
  String? validateOverlap(DateTime start, DateTime end, {String? excludeId}) {
    final sStart = stripTime(start);
    final sEnd = stripTime(end);

    for (final s in filteredSemesters) {
      if (excludeId != null && s.id == excludeId) continue;
      final existStart = stripTime(s.startDate);
      final existEnd = stripTime(s.endDate);

      // Exact duplicate check
      if (sStart == existStart && sEnd == existEnd) {
        return 'Une période existe déjà avec ces dates exactes : "${s.name}" (du ${DateFormat('d MMMM yyyy', 'fr_FR').format(existStart)} au ${DateFormat('d MMMM yyyy', 'fr_FR').format(existEnd)})';
      }

      // Overlap check
      if (!sStart.isAfter(existEnd) && !sEnd.isBefore(existStart)) {
        return 'Chevauche avec "${s.name}" (du ${DateFormat('d MMMM yyyy', 'fr_FR').format(existStart)} au ${DateFormat('d MMMM yyyy', 'fr_FR').format(existEnd)})';
      }
    }
    return null;
  }

  /// Check if a name is already used by another semester in this academic year
  String? validateName(String name, {String? excludeId}) {
    final trimmed = name.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    for (final s in filteredSemesters) {
      if (excludeId != null && s.id == excludeId) continue;
      if (s.name.trim().toLowerCase() == trimmed) {
        return 'Une période nommée "${s.name}" existe déjà pour cette année scolaire.';
      }
    }
    return null;
  }


  /// Get the minimum start date for new semester (must be after previous semester ends)
  DateTime? get minStartDateForNewSemester {
    final filtered = filteredSemesters;
    if (filtered.isEmpty) return null;
    // Sort by end date descending
    final sorted = [...filtered]
      ..sort((a, b) => b.endDate.compareTo(a.endDate));
    return sorted.first.endDate.add(const Duration(days: 1));
  }

  /// Get the minimum start date for editing a specific semester
  /// Returns the day after the previous semester's end date
  DateTime? minStartDateForEditingSemester(String? semesterId) {
    final filtered = filteredSemesters;
    if (filtered.isEmpty) return null;
    
    // Find the current semester being edited
    final currentSemester = filtered.where((s) => s.id == semesterId).firstOrNull;
    if (currentSemester == null) return null;
    
    // Find the semester that ends just before this one starts
    final previousSemesters = filtered
        .where((s) => s.id != semesterId && s.endDate.isBefore(currentSemester.startDate))
        .toList()
      ..sort((a, b) => b.endDate.compareTo(a.endDate));
    
    if (previousSemesters.isEmpty) return null;
    return previousSemesters.first.endDate.add(const Duration(days: 1));
  }

  SemestersState copyWith({
    List<SemesterModel>? semesters,
    List<AcademicYearModel>? academicYears,
    List<VacationPeriodModel>? vacationPeriods,
    List<ExamPeriodModel>? examPeriods,
    String? selectedAcademicYearId,
  }) => SemestersState(
    semesters: semesters ?? this.semesters,
    academicYears: academicYears ?? this.academicYears,
    vacationPeriods: vacationPeriods ?? this.vacationPeriods,
    examPeriods: examPeriods ?? this.examPeriods,
    selectedAcademicYearId:
        selectedAcademicYearId ?? this.selectedAcademicYearId,
  );
}

class SemestersNotifier extends AsyncNotifier<SemestersState> {
  bool _isMutating = false;
  bool get isMutating => _isMutating;

  @override
  Future<SemestersState> build() async => _load();

  Future<SemestersState> _load() async {
    final admin = SupabaseConfig.adminClient;
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) throw Exception('Non connecté');

    final profile = await admin
        .from('users')
        .select('school_id')
        .eq('id', user.id)
        .single();
    final schoolId = profile['school_id'];

    // Auto-detect and refresh current semester based on today's date BEFORE loading
    await _refreshCurrentSemester(schoolId);

    // Load academic years
    var academicYearsData = await admin
        .from('academic_years')
        .select()
        .eq('school_id', schoolId)
        .order('start_date', ascending: false);

    var academicYears = (academicYearsData as List)
        .map((e) => AcademicYearModel.fromJson(e))
        .toList();

    // Ensure a current academic year exists based on today's date
    final currentYear = await _ensureCurrentAcademicYear(
      schoolId,
      academicYears,
    );

    // Sync isCurrent flag in local academicYears list
    academicYears = academicYears.map((y) {
      if (y.id == currentYear.id) {
        return y.copyWith(isCurrent: true);
      }
      return y.copyWith(isCurrent: false);
    }).toList();

    // Reload if we created a new year
    if (!academicYears.any((y) => y.id == currentYear.id)) {
      academicYearsData = await admin
          .from('academic_years')
          .select()
          .eq('school_id', schoolId)
          .order('start_date', ascending: false);
      academicYears = (academicYearsData as List)
          .map((e) => AcademicYearModel.fromJson(e))
          .toList();
    }

    // Load semesters with academic year info (ordered chronologically ascending)
    final data = await admin
        .from('semesters')
        .select('*, academic_years(id, name)')
        .eq('school_id', schoolId)
        .order('start_date', ascending: true);

    final semesters = (data as List)
        .map((e) => SemesterModel.fromJson(e))
        .toList();

    // Load vacation and exam periods for the school
    final vacationsData = await admin
        .from('vacation_periods')
        .select()
        .eq('school_id', schoolId)
        .order('start_date', ascending: false);

    final examsData = await admin
        .from('exam_periods')
        .select()
        .eq('school_id', schoolId)
        .order('start_date', ascending: false);

    final vacationPeriods = (vacationsData as List)
        .map((e) => VacationPeriodModel.fromJson(e))
        .toList();

    final examPeriods = (examsData as List)
        .map((e) => ExamPeriodModel.fromJson(e))
        .toList();

    return SemestersState(
      semesters: semesters,
      academicYears: academicYears,
      vacationPeriods: vacationPeriods,
      examPeriods: examPeriods,
      selectedAcademicYearId: currentYear.id,
    );
  }

  void selectAcademicYear(String? yearId) {
    state.whenData((current) {
      state = AsyncData(current.copyWith(selectedAcademicYearId: yearId));
    });
  }

  Future<void> updateAcademicYear({
    required String id,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required bool isCurrent,
  }) async {
    if (_isMutating) {
      throw Exception('Une opération est déjà en cours. Veuillez patienter.');
    }
    _isMutating = true;
    final previousState = state.asData?.value;
    state = const AsyncLoading();
    try {
      final admin = SupabaseConfig.adminClient;
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) throw Exception('Non connecté');

      final profile = await admin
          .from('users')
          .select('school_id')
          .eq('id', user.id)
          .single();
      final schoolId = profile['school_id'];

      final sStart = SemestersState.stripTime(startDate);
      final sEnd = SemestersState.stripTime(endDate);

      if (!sStart.isBefore(sEnd)) {
        throw Exception('La date de début doit être strictement antérieure à la date de fin.');
      }

      if (isCurrent) {
        await admin
            .from('academic_years')
            .update({'is_current': false})
            .eq('school_id', schoolId);
      }

      await admin
          .from('academic_years')
          .update({
            'name': name.trim(),
            'start_date': sStart.toIso8601String().split('T')[0],
            'end_date': sEnd.toIso8601String().split('T')[0],
            'is_current': isCurrent,
          })
          .eq('id', id);

      // Rebuild auto gap vacations with new bounds
      await _rebuildAutoGapVacations(schoolId, id);

      final fresh = await _load();
      state = AsyncData(fresh.copyWith(selectedAcademicYearId: id));
    } catch (e) {
      if (previousState != null) {
        state = AsyncData(previousState);
      }
      rethrow;
    } finally {
      _isMutating = false;
    }
  }

  Future<void> createAcademicYear({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required bool isCurrent,
  }) async {
    if (_isMutating) {
      throw Exception('Une opération est déjà en cours. Veuillez patienter.');
    }
    _isMutating = true;
    final previousState = state.asData?.value;
    state = const AsyncLoading();
    try {
      final admin = SupabaseConfig.adminClient;
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) throw Exception('Non connecté');

      final profile = await admin
          .from('users')
          .select('school_id')
          .eq('id', user.id)
          .single();
      final schoolId = profile['school_id'];

      final sStart = SemestersState.stripTime(startDate);
      final sEnd = SemestersState.stripTime(endDate);

      if (!sStart.isBefore(sEnd)) {
        throw Exception('La date de début doit être strictement antérieure à la date de fin.');
      }

      if (isCurrent) {
        await admin
            .from('academic_years')
            .update({'is_current': false})
            .eq('school_id', schoolId);
      }

      final res = await admin
          .from('academic_years')
          .insert({
            'school_id': schoolId,
            'name': name.trim(),
            'start_date': sStart.toIso8601String().split('T')[0],
            'end_date': sEnd.toIso8601String().split('T')[0],
            'is_current': isCurrent,
          })
          .select()
          .single();

      final newYearId = res['id']?.toString();

      final fresh = await _load();
      state = AsyncData(fresh.copyWith(selectedAcademicYearId: newYearId));
    } catch (e) {
      if (previousState != null) {
        state = AsyncData(previousState);
      }
      rethrow;
    } finally {
      _isMutating = false;
    }
  }

  Future<void> deleteAcademicYear(String id) async {
    _isMutating = true;
    final previousState = state.value;
    try {
      final admin = SupabaseConfig.adminClient;
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) throw Exception('Non connecté');

      final profile = await admin
          .from('users')
          .select('school_id')
          .eq('id', user.id)
          .single();
      final schoolId = profile['school_id'];
      if (schoolId == null) throw Exception('Établissement introuvable');

      final year = previousState?.academicYears.where((y) => y.id == id).firstOrNull;
      if (year?.isCurrent == true) {
        throw Exception('Impossible de supprimer l\'année scolaire actuelle.');
      }

      // Clean up linked periods for this academic year first
      await admin.from('exam_periods').delete().eq('academic_year_id', id).eq('school_id', schoolId);
      await admin.from('vacation_periods').delete().eq('academic_year_id', id).eq('school_id', schoolId);
      await admin.from('semesters').delete().eq('academic_year_id', id).eq('school_id', schoolId);
      await admin.from('academic_years').delete().eq('id', id).eq('school_id', schoolId);

      final fresh = await _load();
      state = AsyncData(fresh);
    } catch (e) {
      if (previousState != null) {
        state = AsyncData(previousState);
      }
      rethrow;
    } finally {
      _isMutating = false;
    }
  }

  Future<void> _refreshCurrentSemester(String schoolId) async {
    final admin = SupabaseConfig.adminClient;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final data = await admin
        .from('semesters')
        .select('id, start_date, end_date')
        .eq('school_id', schoolId)
        .order('start_date', ascending: true);

    String? currentId;
    for (final s in data) {
      final start = DateTime.parse(s['start_date']);
      final end = DateTime.parse(s['end_date']);
      if (!today.isBefore(start) && !today.isAfter(end)) {
        currentId = s['id'];
        break;
      }
    }

    // Clear all, then set only the one containing today (or none).
    await admin
        .from('semesters')
        .update({'is_current': false})
        .eq('school_id', schoolId);
    if (currentId != null) {
      await admin
          .from('semesters')
          .update({'is_current': true})
          .eq('id', currentId);
    }
  }

  /// Return the academic year that contains today. Auto-create it if missing.
  Future<AcademicYearModel> _ensureCurrentAcademicYear(
    String schoolId,
    List<AcademicYearModel> years,
  ) async {
    final admin = SupabaseConfig.adminClient;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Try to find a year that contains today
    var current = years.where((y) {
      return !today.isBefore(y.startDate) && !today.isAfter(y.endDate);
    }).firstOrNull;

    if (current != null) {
      // Ensure only this year is marked current
      await admin
          .from('academic_years')
          .update({'is_current': false})
          .eq('school_id', schoolId);
      await admin
          .from('academic_years')
          .update({'is_current': true})
          .eq('id', current.id);
      return current.copyWith(isCurrent: true);
    }

    // Auto-create the academic year that contains today
    // Academic year runs Sep 1 -> Aug 31
    final startYear = today.month >= 9 ? today.year : today.year - 1;
    final startDate = DateTime(startYear, 9, 1);
    final endDate = DateTime(startYear + 1, 8, 31);
    final name = '$startYear-${startYear + 1}';

    // Clear old current flags
    await admin
        .from('academic_years')
        .update({'is_current': false})
        .eq('school_id', schoolId);

    final result = await admin
        .from('academic_years')
        .insert({
          'school_id': schoolId,
          'name': name,
          'start_date': startDate.toIso8601String().split('T')[0],
          'end_date': endDate.toIso8601String().split('T')[0],
          'is_current': true,
        })
        .select()
        .single();

    return AcademicYearModel.fromJson(result);
  }

  Future<void> createPeriods({
    required String type,
    required List<({DateTime start, DateTime end})> ranges,
    List<({DateTime start, DateTime end})> manualVacations = const [],
    List<({DateTime start, DateTime end})> examPeriods = const [],
  }) async {
    if (_isMutating) {
      throw Exception('Une création de période est déjà en cours. Veuillez patienter.');
    }
    _isMutating = true;
    final previousState = state.asData?.value;
    state = const AsyncLoading();
    try {
      final admin = SupabaseConfig.adminClient;
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) throw Exception('Non connecté');

      final profile = await admin
          .from('users')
          .select('school_id')
          .eq('id', user.id)
          .single();
      final schoolId = profile['school_id'];

      var currentYear = previousState?.selectedAcademicYear ?? previousState?.currentAcademicYear;
      currentYear ??= previousState?.academicYears.where((y) => y.isCurrent).firstOrNull ?? previousState?.academicYears.firstOrNull;

      if (currentYear == null) {
        // Query active or latest academic year directly from DB as a robust fallback
        final yearRes = await admin
            .from('academic_years')
            .select('id, name, start_date, end_date, is_current')
            .eq('school_id', schoolId)
            .order('is_current', ascending: false)
            .order('start_date', ascending: false)
            .limit(1)
            .maybeSingle();
        if (yearRes != null) {
          currentYear = AcademicYearModel.fromJson(yearRes);
        }
      }

      if (currentYear == null) throw Exception('Aucune année scolaire active');
      final activeYear = currentYear;

      // Fetch fresh academic year directly from DB to verify bounds
      final yearRes = await admin
          .from('academic_years')
          .select('id, name, start_date, end_date')
          .eq('id', activeYear.id)
          .single();
      final yearStart = SemestersState.stripTime(DateTime.parse(yearRes['start_date']));
      final yearEnd = SemestersState.stripTime(DateTime.parse(yearRes['end_date']));

      if (ranges.isEmpty) throw Exception('Aucune période à créer');

      // 1. Validate each range format and bounds
      for (var i = 0; i < ranges.length; i++) {
        final rStart = SemestersState.stripTime(ranges[i].start);
        final rEnd = SemestersState.stripTime(ranges[i].end);

        if (!rStart.isBefore(rEnd)) {
          throw Exception('La date de début doit être strictement antérieure à la date de fin pour la période ${i + 1}.');
        }
        if (rStart.isBefore(yearStart) || rEnd.isAfter(yearEnd)) {
          throw Exception('La période ${i + 1} doit être comprise dans l\'année scolaire (du ${DateFormat('d MMMM yyyy', 'fr_FR').format(yearStart)} au ${DateFormat('d MMMM yyyy', 'fr_FR').format(yearEnd)}).');
        }
      }

      // 2. Validate ranges among themselves (no internal overlaps)
      for (var i = 0; i < ranges.length; i++) {
        final rStartI = SemestersState.stripTime(ranges[i].start);
        final rEndI = SemestersState.stripTime(ranges[i].end);
        for (var j = i + 1; j < ranges.length; j++) {
          final rStartJ = SemestersState.stripTime(ranges[j].start);
          final rEndJ = SemestersState.stripTime(ranges[j].end);
          if (!rStartI.isAfter(rEndJ) && !rEndI.isBefore(rStartJ)) {
            throw Exception('Les périodes à créer se chevauchent entre elles (période ${i + 1} et période ${j + 1}).');
          }
        }
      }

      // 3. FETCH LIVE SEMESTERS FROM DB (never rely solely on client cache)
      final existingDbSemesters = await admin
          .from('semesters')
          .select('id, name, number, start_date, end_date')
          .eq('school_id', schoolId)
          .eq('academic_year_id', activeYear.id)
          .order('start_date', ascending: true);

      final existingList = (existingDbSemesters as List);

      // Check for exact duplicates or overlaps against live database
      for (var i = 0; i < ranges.length; i++) {
        final rStart = SemestersState.stripTime(ranges[i].start);
        final rEnd = SemestersState.stripTime(ranges[i].end);

        for (final existing in existingList) {
          final existStart = SemestersState.stripTime(DateTime.parse(existing['start_date']));
          final existEnd = SemestersState.stripTime(DateTime.parse(existing['end_date']));
          final existName = existing['name'] ?? 'Période';

          if (rStart == existStart && rEnd == existEnd) {
            throw Exception('Impossible de créer la période : une période existe déjà avec ces dates exactes ("$existName" du ${DateFormat('d MMMM yyyy', 'fr_FR').format(existStart)} au ${DateFormat('d MMMM yyyy', 'fr_FR').format(existEnd)}).');
          }

          if (!rStart.isAfter(existEnd) && !rEnd.isBefore(existStart)) {
            throw Exception('Impossible de créer la période : elle chevauche avec "$existName" (du ${DateFormat('d MMMM yyyy', 'fr_FR').format(existStart)} au ${DateFormat('d MMMM yyyy', 'fr_FR').format(existEnd)}).');
          }
        }
      }

      // Calculate semester numbers and unique names
      int maxNumber = existingList.isEmpty
          ? 0
          : existingList
              .map((s) => (s['number'] as num?)?.toInt() ?? 0)
              .reduce((a, b) => a > b ? a : b);

      final totalCount = ranges.length + existingList.length;
      final label = SemestersState.getUnitNameForCount(totalCount);

      final rows = <Map<String, dynamic>>[];
      final existingNames = existingList.map((s) => (s['name'] as String? ?? '').trim().toLowerCase()).toSet();

      for (var i = 0; i < ranges.length; i++) {
        final range = ranges[i];
        final num = maxNumber + i + 1;
        String name = '$label $num';

        // Ensure unique name
        int nameSuffix = 1;
        String finalName = name;
        while (existingNames.contains(finalName.toLowerCase())) {
          nameSuffix++;
          finalName = '$name ($nameSuffix)';
        }
        existingNames.add(finalName.toLowerCase());

        rows.add({
          'name': finalName,
          'number': num,
          'school_id': schoolId,
          'academic_year_id': activeYear.id,
          'start_date': range.start.toIso8601String().split('T')[0],
          'end_date': range.end.toIso8601String().split('T')[0],
          'is_current': false,
        });
      }

      if (rows.isNotEmpty) {
        await admin.from('semesters').insert(rows);
      }

      // Save manual vacations (delete existing manual ones first to avoid duplicates)
      await admin
          .from('vacation_periods')
          .delete()
          .eq('academic_year_id', activeYear.id)
          .eq('type', 'manual');

      if (manualVacations.isNotEmpty) {
        final vacationRows = manualVacations.map((v) => {
          'school_id': schoolId,
          'academic_year_id': activeYear.id,
          'name': 'Vacances',
          'start_date': v.start.toIso8601String().split('T')[0],
          'end_date': v.end.toIso8601String().split('T')[0],
          'type': 'manual',
        }).toList();
        await admin.from('vacation_periods').insert(vacationRows);
      }

      // Save exam periods (delete existing ones first to avoid duplicates)
      await admin
          .from('exam_periods')
          .delete()
          .eq('academic_year_id', activeYear.id);

      if (examPeriods.isNotEmpty) {
        final examRows = examPeriods.map((e) => {
          'school_id': schoolId,
          'academic_year_id': activeYear.id,
          'name': 'Période d\'examens',
          'start_date': e.start.toIso8601String().split('T')[0],
          'end_date': e.end.toIso8601String().split('T')[0],
        }).toList();
        await admin.from('exam_periods').insert(examRows);
      }

      // Rebuild auto-gap vacations for this academic year from database
      await _rebuildAutoGapVacations(schoolId, activeYear.id);

      await _refreshCurrentSemester(schoolId);
      final fresh = await _load();
      state = AsyncData(fresh);
    } catch (e) {
      if (previousState != null) {
        state = AsyncData(previousState);
      }
      rethrow;
    } finally {
      _isMutating = false;
    }
  }

  Future<void> _rebuildAutoGapVacations(
    String schoolId,
    String yearId,
  ) async {
    final admin = SupabaseConfig.adminClient;
    final yearRes = await admin
        .from('academic_years')
        .select('*')
        .eq('id', yearId)
        .maybeSingle();
    if (yearRes == null) return;

    final yearStart = DateTime.parse(yearRes['start_date']);
    final yearEnd = DateTime.parse(yearRes['end_date']);

    // Fetch all semesters for this year sorted by start_date
    final semestersData = await admin
        .from('semesters')
        .select('*')
        .eq('academic_year_id', yearId)
        .order('start_date', ascending: true);

    final sortedSemesters = (semestersData as List)
        .map((s) => (
              start: DateTime.parse(s['start_date']),
              end: DateTime.parse(s['end_date']),
            ))
        .toList();

    // Delete existing auto-gap vacations for this year
    await admin
        .from('vacation_periods')
        .delete()
        .eq('academic_year_id', yearId)
        .eq('type', 'auto_gap');

    if (sortedSemesters.isEmpty) return;

    final gaps = <({DateTime start, DateTime end, String name})>[];

    // Gap before first semester
    if (sortedSemesters.first.start.isAfter(yearStart)) {
      final gapEnd = sortedSemesters.first.start.subtract(const Duration(days: 1));
      if (!gapEnd.isBefore(yearStart)) {
        gaps.add((start: yearStart, end: gapEnd, name: 'Vacances'));
      }
    }

    // Gaps between semesters
    for (var i = 0; i < sortedSemesters.length - 1; i++) {
      final nextStart = sortedSemesters[i + 1].start;
      final prevEnd = sortedSemesters[i].end;
      if (nextStart.isAfter(prevEnd.add(const Duration(days: 1)))) {
        gaps.add((
          start: prevEnd.add(const Duration(days: 1)),
          end: nextStart.subtract(const Duration(days: 1)),
          name: 'Vacances',
        ));
      }
    }

    // Gap after last semester (e.g. Summer Vacation)
    if (sortedSemesters.last.end.isBefore(yearEnd)) {
      final gapStart = sortedSemesters.last.end.add(const Duration(days: 1));
      if (!gapStart.isAfter(yearEnd)) {
        final isSummer = gapStart.month >= 6 || gapStart.month <= 8;
        gaps.add((
          start: gapStart,
          end: yearEnd,
          name: isSummer ? "Vacances d'été" : 'Vacances',
        ));
      }
    }

    if (gaps.isEmpty) return;

    final vacationRows = gaps.map((g) => {
      'school_id': schoolId,
      'academic_year_id': yearId,
      'name': g.name,
      'start_date': g.start.toIso8601String().split('T')[0],
      'end_date': g.end.toIso8601String().split('T')[0],
      'type': 'auto_gap',
    }).toList();

    await admin.from('vacation_periods').insert(vacationRows);
  }

  Future<void> create({
    required String name,
    required int number,
    required DateTime startDate,
    required DateTime endDate,
    required String academicYearId,
  }) async {
    if (_isMutating) {
      throw Exception('Une opération est déjà en cours. Veuillez patienter.');
    }
    _isMutating = true;
    final previousState = state.asData?.value;
    state = const AsyncLoading();
    try {
      final admin = SupabaseConfig.adminClient;
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) throw Exception('Non connecté');

      final profile = await admin
          .from('users')
          .select('school_id')
          .eq('id', user.id)
          .single();
      final schoolId = profile['school_id'];

      final sStart = SemestersState.stripTime(startDate);
      final sEnd = SemestersState.stripTime(endDate);

      if (!sStart.isBefore(sEnd)) {
        throw Exception('La date de début doit être strictement antérieure à la date de fin.');
      }

      // Fetch academic year bounds
      final yearRes = await admin
          .from('academic_years')
          .select('start_date, end_date')
          .eq('id', academicYearId)
          .single();
      final yStart = SemestersState.stripTime(DateTime.parse(yearRes['start_date']));
      final yEnd = SemestersState.stripTime(DateTime.parse(yearRes['end_date']));

      if (sStart.isBefore(yStart) || sEnd.isAfter(yEnd)) {
        throw Exception('La période doit être comprise dans les limites de l\'année scolaire (du ${DateFormat('d MMMM yyyy', 'fr_FR').format(yStart)} au ${DateFormat('d MMMM yyyy', 'fr_FR').format(yEnd)}).');
      }

      // Live DB check
      final existingDb = await admin
          .from('semesters')
          .select('id, name, start_date, end_date')
          .eq('school_id', schoolId)
          .eq('academic_year_id', academicYearId);

      for (final existing in (existingDb as List)) {
        final existStart = SemestersState.stripTime(DateTime.parse(existing['start_date']));
        final existEnd = SemestersState.stripTime(DateTime.parse(existing['end_date']));
        final existName = existing['name'] ?? '';

        if (sStart == existStart && sEnd == existEnd) {
          throw Exception('Une période existe déjà avec ces dates exactes : "$existName".');
        }

        if (!sStart.isAfter(existEnd) && !sEnd.isBefore(existStart)) {
          throw Exception('La période chevauche avec la période existante "$existName" (du ${DateFormat('d MMMM yyyy', 'fr_FR').format(existStart)} au ${DateFormat('d MMMM yyyy', 'fr_FR').format(existEnd)}).');
        }

        if ((existName as String).trim().toLowerCase() == name.trim().toLowerCase()) {
          throw Exception('Une période nommée "$name" existe déjà pour cette année scolaire.');
        }
      }

      await admin.from('semesters').insert({
        'name': name.trim(),
        'number': number,
        'school_id': schoolId,
        'academic_year_id': academicYearId,
        'start_date': startDate.toIso8601String().split('T')[0],
        'end_date': endDate.toIso8601String().split('T')[0],
        'is_current': false,
      });

      await _rebuildAutoGapVacations(schoolId, academicYearId);
      await _refreshCurrentSemester(schoolId);
      final fresh = await _load();
      state = AsyncData(fresh);
    } catch (e) {
      if (previousState != null) {
        state = AsyncData(previousState);
      }
      rethrow;
    } finally {
      _isMutating = false;
    }
  }

  Future<void> updateSemester({
    required String id,
    required String name,
    required int number,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    if (_isMutating) {
      throw Exception('Une opération est déjà en cours. Veuillez patienter.');
    }
    _isMutating = true;
    try {
      final admin = SupabaseConfig.adminClient;
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) throw Exception('Non connecté');

      final semester = await admin
          .from('semesters')
          .select('school_id, academic_year_id')
          .eq('id', id)
          .single();
      final schoolId = semester['school_id'];
      final yearId = semester['academic_year_id'];

      final sStart = SemestersState.stripTime(startDate);
      final sEnd = SemestersState.stripTime(endDate);

      if (!sStart.isBefore(sEnd)) {
        throw Exception('La date de début doit être strictement antérieure à la date de fin.');
      }

      // Check academic year bounds
      final yearRes = await admin
          .from('academic_years')
          .select('start_date, end_date')
          .eq('id', yearId)
          .single();
      final yStart = SemestersState.stripTime(DateTime.parse(yearRes['start_date']));
      final yEnd = SemestersState.stripTime(DateTime.parse(yearRes['end_date']));

      if (sStart.isBefore(yStart) || sEnd.isAfter(yEnd)) {
        throw Exception('La période doit être comprise dans les limites de l\'année scolaire (du ${DateFormat('d MMMM yyyy', 'fr_FR').format(yStart)} au ${DateFormat('d MMMM yyyy', 'fr_FR').format(yEnd)}).');
      }

      // Check live database against other semesters
      final otherSemesters = await admin
          .from('semesters')
          .select('id, name, start_date, end_date')
          .eq('school_id', schoolId)
          .eq('academic_year_id', yearId)
          .neq('id', id);

      for (final existing in (otherSemesters as List)) {
        final existStart = SemestersState.stripTime(DateTime.parse(existing['start_date']));
        final existEnd = SemestersState.stripTime(DateTime.parse(existing['end_date']));
        final existName = existing['name'] ?? '';

        if (sStart == existStart && sEnd == existEnd) {
          throw Exception('Une autre période a déjà exactement ces dates : "$existName".');
        }

        if (!sStart.isAfter(existEnd) && !sEnd.isBefore(existStart)) {
          throw Exception('La période chevauche avec la période existante "$existName" (du ${DateFormat('d MMMM yyyy', 'fr_FR').format(existStart)} au ${DateFormat('d MMMM yyyy', 'fr_FR').format(existEnd)}).');
        }

        if ((existName as String).trim().toLowerCase() == name.trim().toLowerCase()) {
          throw Exception('Une autre période avec le nom "$name" existe déjà pour cette année scolaire.');
        }
      }

      final previous = state.value;
      state.whenData((s) {
        final updated = s.semesters.map((sem) {
          if (sem.id == id) {
            return sem.copyWith(
              name: name.trim(),
              number: number,
              startDate: startDate,
              endDate: endDate,
            );
          }
          return sem;
        }).toList();
        state = AsyncData(s.copyWith(semesters: updated));
      });

      try {
        await admin
            .from('semesters')
            .update({
              'name': name.trim(),
              'number': number,
              'start_date': startDate.toIso8601String().split('T')[0],
              'end_date': endDate.toIso8601String().split('T')[0],
            })
            .eq('id', id);

        await _rebuildAutoGapVacations(schoolId, yearId);
        await _refreshCurrentSemester(schoolId);
        final fresh = await _load();
        state = AsyncData(fresh);
      } catch (e) {
        if (previous != null) state = AsyncData(previous);
        rethrow;
      }
    } finally {
      _isMutating = false;
    }
  }

  Future<void> delete(String id) async {
    final previous = state.value;
    state.whenData((s) {
      final updated = s.semesters.where((sem) => sem.id != id).toList();
      state = AsyncData(s.copyWith(semesters: updated));
    });

    final admin = SupabaseConfig.adminClient;
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) {
      if (previous != null) state = AsyncData(previous);
      throw Exception('Non connecté');
    }

    try {
      final semester = await admin
          .from('semesters')
          .select('school_id, academic_year_id')
          .eq('id', id)
          .maybeSingle();

      await admin.from('semesters').delete().eq('id', id);

      if (semester != null) {
        final schoolId = semester['school_id'];
        final yearId = semester['academic_year_id'];
        await _rebuildAutoGapVacations(schoolId, yearId);
        await _refreshCurrentSemester(schoolId);
      }

      final fresh = await _load();
      state = AsyncData(fresh);
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> deleteVacation(String id) async {
    final previous = state.value;
    state.whenData((s) {
      final updated = s.vacationPeriods.where((v) => v.id != id).toList();
      state = AsyncData(s.copyWith(vacationPeriods: updated));
    });

    try {
      final admin = SupabaseConfig.adminClient;
      await admin.from('vacation_periods').delete().eq('id', id);
      final fresh = await _load();
      state = AsyncData(fresh);
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> deleteExam(String id) async {
    final previous = state.value;
    state.whenData((s) {
      final updated = s.examPeriods.where((e) => e.id != id).toList();
      state = AsyncData(s.copyWith(examPeriods: updated));
    });

    try {
      final admin = SupabaseConfig.adminClient;
      await admin.from('exam_periods').delete().eq('id', id);
      final fresh = await _load();
      state = AsyncData(fresh);
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> addManualVacation({
    required DateTime startDate,
    required DateTime endDate,
    String? name,
  }) async {
    final admin = SupabaseConfig.adminClient;
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) throw Exception('Non connecté');

    final profile = await admin
        .from('users')
        .select('school_id')
        .eq('id', user.id)
        .single();
    final schoolId = profile['school_id'];

    final currentState = state.asData?.value;
    var year = currentState?.selectedAcademicYear ?? currentState?.currentAcademicYear;
    year ??= currentState?.academicYears.where((y) => y.isCurrent).firstOrNull ?? currentState?.academicYears.firstOrNull;
    if (year == null) {
      final yearRes = await admin
          .from('academic_years')
          .select('id, name, start_date, end_date, is_current')
          .eq('school_id', schoolId)
          .order('is_current', ascending: false)
          .order('start_date', ascending: false)
          .limit(1)
          .maybeSingle();
      if (yearRes != null) {
        year = AcademicYearModel.fromJson(yearRes);
      }
    }
    if (year == null) throw Exception('Aucune année scolaire active');
    final activeYear = year;

    await admin.from('vacation_periods').insert({
      'school_id': schoolId,
      'academic_year_id': activeYear.id,
      'name': name ?? 'Vacances',
      'start_date': startDate.toIso8601String().split('T')[0],
      'end_date': endDate.toIso8601String().split('T')[0],
      'type': 'manual',
    });
    final fresh = await _load();
    state = AsyncData(fresh);
  }

  Future<void> addExamPeriod({
    required DateTime startDate,
    required DateTime endDate,
    String? name,
  }) async {
    final admin = SupabaseConfig.adminClient;
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) throw Exception('Non connecté');

    final profile = await admin
        .from('users')
        .select('school_id')
        .eq('id', user.id)
        .single();
    final schoolId = profile['school_id'];

    final currentState = state.asData?.value;
    var year = currentState?.selectedAcademicYear ?? currentState?.currentAcademicYear;
    year ??= currentState?.academicYears.where((y) => y.isCurrent).firstOrNull ?? currentState?.academicYears.firstOrNull;
    if (year == null) {
      final yearRes = await admin
          .from('academic_years')
          .select('id, name, start_date, end_date, is_current')
          .eq('school_id', schoolId)
          .order('is_current', ascending: false)
          .order('start_date', ascending: false)
          .limit(1)
          .maybeSingle();
      if (yearRes != null) {
        year = AcademicYearModel.fromJson(yearRes);
      }
    }
    if (year == null) throw Exception('Aucune année scolaire active');
    final activeYear = year;

    await admin.from('exam_periods').insert({
      'school_id': schoolId,
      'academic_year_id': activeYear.id,
      'name': name ?? 'Examen',
      'start_date': startDate.toIso8601String().split('T')[0],
      'end_date': endDate.toIso8601String().split('T')[0],
    });
    final fresh = await _load();
    state = AsyncData(fresh);
  }
}

final semestersProvider =
    AsyncNotifierProvider<SemestersNotifier, SemestersState>(
      SemestersNotifier.new,
    );

/// Current active semester ID (from semesters where is_current == true or date range fallback)
final currentActiveSemesterIdProvider = Provider<String?>((ref) {
  final semestersAsync = ref.watch(semestersProvider);
  return semestersAsync.whenOrNull(
    data: (state) {
      if (state.current != null) return state.current!.id;
      final list = state.filteredSemesters.isNotEmpty
          ? state.filteredSemesters
          : state.semesters;
      final now = DateTime.now();
      final byDate = list.where(
        (s) => !now.isBefore(s.startDate) && !now.isAfter(s.endDate),
      ).firstOrNull;
      if (byDate != null) return byDate.id;
      final currentFlag = list.where((s) => s.isCurrent).firstOrNull;
      if (currentFlag != null) return currentFlag.id;
      return list.isNotEmpty ? list.first.id : null;
    },
  );
});

