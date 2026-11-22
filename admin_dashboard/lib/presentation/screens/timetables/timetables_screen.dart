import 'dart:math' as math;
import 'dart:ui';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../../../core/config/supabase_config.dart';
import '../../../data/models/tunisian_coefficients.dart';
import '../../../data/models/grading_config_model.dart';
import '../../../data/models/building_models.dart';
import '../../providers/building_provider.dart';
import '../../providers/semesters_provider.dart';
import '../../widgets/admin_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../widgets/ios_loader.dart';

// ===================== MODELS =====================

class TimetableSlotAdmin {
  final String id;
  final String subjectOfferingId;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final String? room;
  final String? subjectName;
  final String? subjectCode;
  final String? className;
  final String? teacherName;
  final String? teacherPhotoUrl;
  final String timetableType;
  final String? examPeriodId;

  TimetableSlotAdmin({
    required this.id,
    required this.subjectOfferingId,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.room,
    this.subjectName,
    this.subjectCode,
    this.className,
    this.teacherName,
    this.teacherPhotoUrl,
    this.timetableType = 'regular',
    this.examPeriodId,
  });

  factory TimetableSlotAdmin.fromJson(Map<String, dynamic> json) {
    // Convert day_of_week from string enum to integer
    int parseDayOfWeek(dynamic value) {
      if (value is int) return value;
      if (value is String) {
        switch (value.toLowerCase()) {
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
      return 1;
    }

    return TimetableSlotAdmin(
      id: json['id']?.toString() ?? '',
      subjectOfferingId: json['subject_offering_id']?.toString() ?? '',
      dayOfWeek: parseDayOfWeek(json['day_of_week']),
      startTime: json['start_time']?.toString() ?? '08:00',
      endTime: json['end_time']?.toString() ?? '09:00',
      room: json['room']?.toString(),
      subjectName: json['subject_offerings']?['subjects']?['name']?.toString(),
      subjectCode: json['subject_offerings']?['subjects']?['code']?.toString(),
      className: json['subject_offerings']?['classes']?['name']?.toString(),
      teacherName: json['subject_offerings']?['users']?['full_name']
          ?.toString(),
      timetableType: json['timetable_type']?.toString() ?? 'regular',
      examPeriodId: json['exam_period_id']?.toString(),
    );
  }
}

class ClassInfo {
  final String id;
  final String name;
  final String? gradeLevelId;
  final String? gradeLevelCode;
  final String? gradeLevelName;
  final String? sectionId;
  final String? sectionCode;
  final String? sectionName;
  final String? cycle; // 'base' or 'secondaire'
  final bool? hasSections;

  ClassInfo({
    required this.id,
    required this.name,
    this.gradeLevelId,
    this.gradeLevelCode,
    this.gradeLevelName,
    this.sectionId,
    this.sectionCode,
    this.sectionName,
    this.cycle,
    this.hasSections,
  });

  factory ClassInfo.fromJson(Map<String, dynamic> json) => ClassInfo(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    gradeLevelId:
        json['niveau_id']?.toString() ?? json['grade_level_id']?.toString(),
    gradeLevelCode:
        json['niveaux']?['code']?.toString() ??
        json['grade_levels']?['code']?.toString(),
    gradeLevelName:
        json['niveaux']?['name']?.toString() ??
        json['grade_levels']?['name']?.toString(),
    sectionId:
        json['section_id']?.toString() ?? json['sections']?['id']?.toString(),
    sectionCode: json['sections']?['code']?.toString(),
    sectionName: json['sections']?['name']?.toString(),
    cycle: json['niveaux']?['cycle']?.toString(),
    hasSections: json['niveaux']?['has_sections'] as bool?,
  );
}

class SubjectOfferingInfo {
  final String id;
  final String subjectName;
  final String? subjectCode;
  final String? teacherName;
  final double weeklyCiHours;
  final double weeklyTpHours;

  SubjectOfferingInfo({
    required this.id,
    required this.subjectName,
    this.subjectCode,
    this.teacherName,
    this.weeklyCiHours = 0,
    this.weeklyTpHours = 0,
  });

  factory SubjectOfferingInfo.fromJson(Map<String, dynamic> json) =>
      SubjectOfferingInfo(
        id: json['id']?.toString() ?? '',
        subjectName: json['subjects']?['name']?.toString() ?? 'N/A',
        subjectCode: json['subjects']?['code']?.toString(),
        teacherName: json['users']?['full_name']?.toString(),
        weeklyCiHours: (json['weekly_ci_hours'] as num?)?.toDouble() ?? 0,
        weeklyTpHours: (json['weekly_tp_hours'] as num?)?.toDouble() ?? 0,
      );
}

// ===================== PROVIDERS =====================

// Selected class provider
final selectedClassProvider = StateProvider<ClassInfo?>((ref) => null);

// Classes list provider
final classesListProvider = FutureProvider.autoDispose<List<ClassInfo>>((ref) async {
  ref.keepAlive();
  final supabase = SupabaseConfig.adminClient;
  final user = SupabaseConfig.client.auth.currentUser;
  if (user == null) return [];

  final profile = await supabase
      .from('users')
      .select('school_id')
      .eq('id', user.id)
      .single();
  final schoolId = profile['school_id'];
  if (schoolId == null) return [];

  try {
    final data = await supabase
        .from('classes')
        .select(
          'id, name, niveau_id, section_id, niveaux(name, code, cycle, has_sections), sections(id, name, code)',
        )
        .eq('school_id', schoolId)
        .order('name');

    return (data as List).map((e) => ClassInfo.fromJson(e)).toList();
  } catch (e) {
    // Fallback query without relations
    final data = await supabase
        .from('classes')
        .select('id, name')
        .eq('school_id', schoolId)
        .order('name');
    return (data as List).map((e) => ClassInfo.fromJson(e)).toList();
  }
});

// Subject offerings for selected class (filtered by semester)
final classSubjectOfferingsProvider =
    FutureProvider.family.autoDispose<List<SubjectOfferingInfo>, (String, String?)>((ref, params) async {
      ref.keepAlive();
      final classId = params.$1;
      final semesterId = params.$2;
      final supabase = SupabaseConfig.adminClient;

      try {
        // Get class info to determine niveau_id and section_id
        final classData = await supabase
            .from('classes')
            .select('id, niveau_id, section_id')
            .eq('id', classId)
            .single();
        
        final niveauId = classData['niveau_id'];
        final sectionId = classData['section_id'];

        // Get curriculum for this niveau/section to get weekly_hours
        var curriculumQuery = supabase
            .from('curriculum')
            .select('subject_id, weekly_hours')
            .eq('niveau_id', niveauId);
        
        if (sectionId != null) {
          curriculumQuery = curriculumQuery.eq('section_id', sectionId);
        } else {
          curriculumQuery = curriculumQuery.isFilter('section_id', null);
        }
        
        final curriculumData = await curriculumQuery;
        
        // Create map of subject_id -> weekly_hours from curriculum
        final Map<String, double> weeklyHoursMap = {};
        for (var c in (curriculumData as List)) {
          weeklyHoursMap[c['subject_id']?.toString() ?? ''] = 
              (c['weekly_hours'] as num?)?.toDouble() ?? 0;
        }

        var offeringsQuery = supabase
            .from('subject_offerings')
            .select(
              'id, subject_id, teacher_id, subjects(name, code), users(full_name)',
            )
            .eq('class_id', classId)
            .eq('is_active', true);

        if (semesterId != null) {
          offeringsQuery = offeringsQuery.eq('semester_id', semesterId);
        }

        final data = await offeringsQuery;

        return (data as List).map((e) {
          final subjectId = e['subject_id']?.toString() ?? '';
          final weeklyHours = weeklyHoursMap[subjectId] ?? 0;
          
          return SubjectOfferingInfo(
            id: e['id']?.toString() ?? '',
            subjectName: e['subjects']?['name']?.toString() ?? 'N/A',
            subjectCode: e['subjects']?['code']?.toString(),
            teacherName: e['users']?['full_name']?.toString(),
            weeklyCiHours: weeklyHours, // From curriculum
            weeklyTpHours: 0, // Not used anymore, all in weeklyCiHours
          );
        }).toList();
      } catch (e) {
        // Fallback: fetch without nested relations and join manually
        debugPrint('classSubjectOfferingsProvider error: $e - using fallback');
        try {
          // Get class info
          final classData = await supabase
              .from('classes')
              .select('id, niveau_id, section_id')
              .eq('id', classId)
              .single();
          
          final niveauId = classData['niveau_id'];
          final sectionId = classData['section_id'];

          // Get curriculum for weekly_hours
          var curriculumQuery = supabase
              .from('curriculum')
              .select('subject_id, weekly_hours')
              .eq('niveau_id', niveauId);
          
          if (sectionId != null) {
            curriculumQuery = curriculumQuery.eq('section_id', sectionId);
          } else {
            curriculumQuery = curriculumQuery.isFilter('section_id', null);
          }
          
          final curriculumData = await curriculumQuery;
          
          final Map<String, double> weeklyHoursMap = {};
          for (var c in (curriculumData as List)) {
            weeklyHoursMap[c['subject_id']?.toString() ?? ''] = 
                (c['weekly_hours'] as num?)?.toDouble() ?? 0;
          }

          var fallbackOfferingsQuery = supabase
              .from('subject_offerings')
              .select('id, subject_id, teacher_id')
              .eq('class_id', classId)
              .eq('is_active', true);

          if (semesterId != null) {
            fallbackOfferingsQuery = fallbackOfferingsQuery.eq('semester_id', semesterId);
          }

          final offerings = await fallbackOfferingsQuery;

          if ((offerings as List).isEmpty) return [];

          // Fetch subjects separately
          final subjectIds = offerings
              .map((o) => o['subject_id'])
              .where((id) => id != null)
              .toSet()
              .toList();
          final teacherIds = offerings
              .map((o) => o['teacher_id'])
              .where((id) => id != null)
              .toSet()
              .toList();

          Map<String, dynamic> subjectsMap = {};
          Map<String, dynamic> teachersMap = {};

          if (subjectIds.isNotEmpty) {
            final subjects = await supabase
                .from('subjects')
                .select('id, name, code')
                .inFilter('id', subjectIds);
            for (var s in (subjects as List)) {
              subjectsMap[s['id']] = s;
            }
          }

          if (teacherIds.isNotEmpty) {
            final teachers = await supabase
                .from('users')
                .select('id, full_name')
                .inFilter('id', teacherIds);
            for (var t in (teachers as List)) {
              teachersMap[t['id']] = t;
            }
          }

          return offerings.map((o) {
            final subject = subjectsMap[o['subject_id']];
            final teacher = teachersMap[o['teacher_id']];
            final subjectId = o['subject_id']?.toString() ?? '';
            final weeklyHours = weeklyHoursMap[subjectId] ?? 0;
            
            return SubjectOfferingInfo(
              id: o['id']?.toString() ?? '',
              subjectName: subject?['name']?.toString() ?? 'N/A',
              subjectCode: subject?['code']?.toString(),
              teacherName: teacher?['full_name']?.toString(),
              weeklyCiHours: weeklyHours, // From curriculum
              weeklyTpHours: 0, // Not used anymore
            );
          }).toList();
        } catch (e2) {
          debugPrint('classSubjectOfferingsProvider fallback error: $e2');
          return [];
        }
      }
    });

// Timetable slots for selected class
// Timetable slots for selected class (with semester filter)
final classTimetableSlotsProvider =
    FutureProvider.family.autoDispose<List<TimetableSlotAdmin>, String>((ref, classId) async {
      ref.keepAlive();
      final supabase = SupabaseConfig.adminClient;
      final semesterId = ref.watch(currentSemesterIdProvider);
      final timetableType = ref.watch(timetableTypeFilterProvider);
      final examPeriodId = ref.watch(selectedExamPeriodFilterProvider);

      try {
        // Query subject_offerings for this class, filtered by the effective semester
        var offeringsQuery = supabase
            .from('subject_offerings')
            .select('id, subject_id, teacher_id, subjects(name, code)')
            .eq('class_id', classId);

        if (semesterId != null) {
          offeringsQuery = offeringsQuery.eq('semester_id', semesterId);
        }

        final offeringsResp = await offeringsQuery;

        final offerings = offeringsResp as List;
        if (offerings.isEmpty) return [];

        final offeringIds = offerings.map((o) => o['id'] as String).toList();

        // Get timetable slots for these offerings, filtered by type
        var slotsQuery = supabase
            .from('timetable_slots')
            .select('*')
            .inFilter('subject_offering_id', offeringIds)
            .eq('timetable_type', timetableType);

        if (timetableType == 'exam' && examPeriodId != null) {
          slotsQuery = slotsQuery.eq('exam_period_id', examPeriodId);
        }

        final slotsResp = await slotsQuery
            .order('day_of_week')
            .order('start_time');

        final slots = slotsResp as List;
        if (slots.isEmpty) return [];

        // Build lookup maps
        final Map<String, dynamic> offeringsMap = {};
        final Map<String, String> offeringSubjectIdMap = {};
        for (var o in offerings) {
          offeringsMap[o['id']] = o;
          offeringSubjectIdMap[o['id'] as String] = (o['subject_id'] as String?) ?? '';
        }

        // Fetch teacher_assignments to resolve teachers (subject_offerings.teacher_id may be NULL)
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

        // Get class name
        final classData = await supabase
            .from('classes')
            .select('id, name')
            .eq('id', classId)
            .maybeSingle();

        return slots.map((slot) {
          final offering = offeringsMap[slot['subject_offering_id']];
          final subject = offering?['subjects'];
          final subjectId = offering?['subject_id'] as String?;

          // Resolve teacher: teacher_assignments → timetable_slots.teacher_name
          String teacherName = subjectClassTeacherMap['${subjectId}_$classId'] ?? '';
          String teacherPhoto = subjectClassTeacherPhotoMap['${subjectId}_$classId'] ?? '';
          if (teacherName.isEmpty) {
            teacherName = (slot['teacher_name'] as String?) ?? '';
          }

          // Shorten room: extract just the room name from "Bloc A – Principal · 2ème étage · Salle 204"
          String rawRoom = (slot['room'] as String?) ?? '';
          String shortRoom = rawRoom;
          if (rawRoom.contains('·')) {
            final parts = rawRoom.split('·').map((s) => s.trim()).toList();
            shortRoom = parts.last; // last part is the room name
          }

          int parseDayOfWeek(dynamic value) {
            if (value is int) return value;
            if (value is String) {
              switch (value.toLowerCase()) {
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
            return 1;
          }

          return TimetableSlotAdmin(
            id: slot['id']?.toString() ?? '',
            subjectOfferingId: slot['subject_offering_id']?.toString() ?? '',
            dayOfWeek: parseDayOfWeek(slot['day_of_week']),
            startTime: slot['start_time']?.toString() ?? '08:00',
            endTime: slot['end_time']?.toString() ?? '09:00',
            room: shortRoom.isNotEmpty ? shortRoom : rawRoom,
            subjectName: subject?['name']?.toString(),
            subjectCode: subject?['code']?.toString(),
            className: classData?['name']?.toString(),
            teacherName: teacherName.isNotEmpty ? teacherName : null,
            teacherPhotoUrl: teacherPhoto.isNotEmpty ? teacherPhoto : null,
          );
        }).toList();
      } catch (e) {
        debugPrint('classTimetableSlotsProvider error: $e');
        return [];
      }
    });

// Provider to calculate scheduled hours per offering
final scheduledHoursPerOfferingProvider =
    FutureProvider.family.autoDispose<Map<String, double>, String>((ref, classId) async {
  ref.keepAlive();
      final slots = await ref.watch(
        classTimetableSlotsProvider(classId).future,
      );

      // Group slots by subject_offering_id and calculate total hours
      final hoursMap = <String, double>{};

      for (final slot in slots) {
        // Parse times to calculate duration
        final startParts = slot.startTime.split(':').map(int.parse).toList();
        final endParts = slot.endTime.split(':').map(int.parse).toList();

        final startMinutes =
            startParts[0] * 60 + (startParts.length > 1 ? startParts[1] : 0);
        final endMinutes =
            endParts[0] * 60 + (endParts.length > 1 ? endParts[1] : 0);

        final durationHours = (endMinutes - startMinutes) / 60.0;

        hoursMap[slot.subjectOfferingId] =
            (hoursMap[slot.subjectOfferingId] ?? 0) + durationHours;
      }

      return hoursMap;
    });

// ===================== CONSTANTS =====================

const List<String> _dayLabels = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
];
const List<String> _dayLabelsShort = [
  'Lun',
  'Mar',
  'Mer',
  'Jeu',
  'Ven',
  'Sam',
  'Dim',
];

// 30-minute time slots for flexible scheduling (08:00 – 19:00)
const List<String> _timeSlots = [
  '08:00', '08:30',
  '09:00', '09:30',
  '10:00', '10:30',
  '11:00', '11:30',
  '12:00', '12:30',
  '13:00', '13:30',
  '14:00', '14:30',
  '15:00', '15:30',
  '16:00', '16:30',
  '17:00', '17:30',
  '18:00', '18:30',
  '19:00',
];

// Round-hour labels for the grid header
const List<String> _gridHourLabels = [
  '08:00', '09:00', '10:00', '11:00', '12:00',
  '13:00', '14:00', '15:00', '16:00', '17:00',
  '18:00', '19:00',
];

// Subject colors
final Map<String, Color> _subjectColors = {};
Color _getSubjectColor(String code) {
  if (!_subjectColors.containsKey(code)) {
    final colors = [
      const Color(0xFF6366F1),
      const Color(0xFFEC4899),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFF8B5CF6),
      const Color(0xFF06B6D4),
      const Color(0xFFEF4444),
      const Color(0xFF14B8A6),
      const Color(0xFFF97316),
      const Color(0xFF3B82F6),
      const Color(0xFF84CC16),
      const Color(0xFFE11D48),
    ];
    _subjectColors[code] = colors[_subjectColors.length % colors.length];
  }
  return _subjectColors[code]!;
}

// ===================== MAIN SCREEN =====================

// Search/filter provider for classes
final classSearchQueryProvider = StateProvider<String>((ref) => '');
final selectedNiveauFilterProvider = StateProvider<String?>((ref) => null);

// Student search result - returns class IDs of students matching search query
final studentSearchClassIdsProvider =
    FutureProvider.family<Set<String>, String>((ref, searchQuery) async {
      if (searchQuery.isEmpty || searchQuery.length < 2) return {};

      final supabase = SupabaseConfig.client;
      try {
        // Search students by name and get their active enrollments
        final result = await supabase
            .from('users')
            .select('id, full_name, enrollments!inner(class_id, is_active)')
            .eq('role', 'student')
            .eq('enrollments.is_active', true)
            .ilike('full_name', '%$searchQuery%')
            .limit(50);

        final classIds = <String>{};
        for (final user in result as List) {
          final enrollments = user['enrollments'] as List?;
          if (enrollments != null) {
            for (final enrollment in enrollments) {
              if (enrollment['class_id'] != null) {
                classIds.add(enrollment['class_id'] as String);
              }
            }
          }
        }
        return classIds;
      } catch (e) {
        debugPrint('Error searching students: $e');
        return {};
      }
    });

// Student count per class provider
final classStudentCountProvider = FutureProvider.family<int, String>((
  ref,
  classId,
) async {
  final supabase = SupabaseConfig.client;
  try {
    final result = await supabase
        .from('enrollments')
        .select('id')
        .eq('class_id', classId)
        .eq('is_active', true);
    return (result as List).length;
  } catch (e) {
    return 0;
  }
});

// Timetable search/filter providers
final timetableSearchQueryProvider = StateProvider<String>((ref) => '');
final selectedDayFilterProvider = StateProvider<int?>(
  (ref) => null,
); // 1-6 for Mon-Sat
final selectedSubjectFilterProvider = StateProvider<String?>((ref) => null);

// Selected semester view/target filter for timetable:
// null = default to current active semester
// <id> = selected semester
final selectedSemesterOverrideProvider = StateProvider<String?>((ref) => null);

// Effective Semester ID selected for timetable grid and slot actions
final effectiveSemesterIdProvider = Provider<String?>((ref) {
  final override = ref.watch(selectedSemesterOverrideProvider);
  if (override != null) return override;
  return ref.watch(currentActiveSemesterIdProvider);
});

// Alias for backwards compatibility
final currentSemesterIdProvider = effectiveSemesterIdProvider;

enum TimetableSemesterStatus { past, current, future }

// Status of the selected semester
final selectedSemesterStatusProvider = Provider<TimetableSemesterStatus>((ref) {
  final effectiveId = ref.watch(effectiveSemesterIdProvider);
  final activeId = ref.watch(currentActiveSemesterIdProvider);
  final semestersAsync = ref.watch(semestersProvider);

  if (effectiveId == null || activeId == null) {
    return TimetableSemesterStatus.current;
  }
  if (effectiveId == activeId) {
    return TimetableSemesterStatus.current;
  }

  final semestersState = semestersAsync.asData?.value;
  if (semestersState == null) return TimetableSemesterStatus.current;

  final allSemesters = semestersState.filteredSemesters.isNotEmpty
      ? semestersState.filteredSemesters
      : semestersState.semesters;

  final currentSem = allSemesters.firstWhereOrNull((s) => s.id == activeId || s.isCurrent);
  final selectedSem = allSemesters.firstWhereOrNull((s) => s.id == effectiveId);

  if (currentSem == null || selectedSem == null) {
    return TimetableSemesterStatus.current;
  }

  if (selectedSem.number < currentSem.number) {
    return TimetableSemesterStatus.past;
  } else if (selectedSem.number > currentSem.number) {
    return TimetableSemesterStatus.future;
  }
  return TimetableSemesterStatus.current;
});

// Editable if status is current or future (past semester is read-only)
final isSemesterEditableProvider = Provider<bool>((ref) {
  final status = ref.watch(selectedSemesterStatusProvider);
  return status != TimetableSemesterStatus.past;
});

// Exam periods from semestersProvider
final examPeriodsListProvider = Provider<List<ExamPeriodModel>>((ref) {
  final semestersAsync = ref.watch(semestersProvider);
  return semestersAsync.whenOrNull(data: (state) {
    final yearId = state.selectedAcademicYearId;
    return yearId != null ? state.filteredExams(yearId) : state.examPeriods;
  }) ?? [];
});

// Timetable type filter: 'regular' or 'exam' (used by classTimetableSlotsProvider)
final timetableTypeFilterProvider = StateProvider<String>((ref) => 'regular');
final selectedExamPeriodFilterProvider = StateProvider<String?>((ref) => null);

// Filtered classes provider
final filteredClassesProvider = Provider<AsyncValue<List<ClassInfo>>>((ref) {
  final classesAsync = ref.watch(classesListProvider);
  final searchQuery = ref.watch(classSearchQueryProvider).toLowerCase();
  final niveauFilter = ref.watch(selectedNiveauFilterProvider);

  // Watch student search results
  final studentClassIdsAsync = ref.watch(
    studentSearchClassIdsProvider(searchQuery),
  );
  final studentClassIds = studentClassIdsAsync.when(
    data: (ids) => ids,
    loading: () => <String>{},
    error: (_, __) => <String>{},
  );

  return classesAsync.whenData((classes) {
    var filtered = classes;

    // Filter by search query (class name OR student name)
    if (searchQuery.isNotEmpty) {
      filtered = filtered
          .where(
            (c) =>
                c.name.toLowerCase().contains(searchQuery) ||
                (c.gradeLevelCode?.toLowerCase().contains(searchQuery) ??
                    false) ||
                (c.sectionCode?.toLowerCase().contains(searchQuery) ?? false) ||
                studentClassIds.contains(
                  c.id,
                ), // Include classes with matching students
          )
          .toList();
    }

    // Filter by niveau
    if (niveauFilter != null && niveauFilter.isNotEmpty) {
      filtered = filtered
          .where((c) => c.gradeLevelCode == niveauFilter)
          .toList();
    }

    return filtered;
  });
});

// Filtered timetable slots provider
final filteredTimetableSlotsProvider =
    Provider.family<AsyncValue<List<TimetableSlotAdmin>>, String>((
      ref,
      classId,
    ) {
      final slotsAsync = ref.watch(classTimetableSlotsProvider(classId));
      final searchQuery = ref.watch(timetableSearchQueryProvider).toLowerCase();
      final dayFilter = ref.watch(selectedDayFilterProvider);
      final subjectFilter = ref.watch(selectedSubjectFilterProvider);

      return slotsAsync.whenData((slots) {
        var filtered = slots;

        // Filter by search query (subject name, teacher name, room)
        if (searchQuery.isNotEmpty) {
          filtered = filtered
              .where(
                (s) =>
                    (s.subjectName?.toLowerCase().contains(searchQuery) ??
                        false) ||
                    (s.subjectCode?.toLowerCase().contains(searchQuery) ??
                        false) ||
                    (s.teacherName?.toLowerCase().contains(searchQuery) ??
                        false) ||
                    (s.room?.toLowerCase().contains(searchQuery) ?? false),
              )
              .toList();
        }

        // Filter by day
        if (dayFilter != null) {
          filtered = filtered.where((s) => s.dayOfWeek == dayFilter).toList();
        }

        // Filter by subject
        if (subjectFilter != null && subjectFilter.isNotEmpty) {
          filtered = filtered
              .where(
                (s) =>
                    s.subjectCode == subjectFilter ||
                    s.subjectName == subjectFilter,
              )
              .toList();
        }

        return filtered;
      });
    });

// Get unique niveaux for filter dropdown (filtered by cycle if selected)
final niveauxListProvider = Provider<List<String>>((ref) {
  final classesAsync = ref.watch(classesListProvider);

  return classesAsync.when(
    data: (classes) {
      final niveaux = classes
          .map((c) => c.gradeLevelCode)
          .whereType<String>()
          .toSet()
          .toList();
      niveaux.sort();
      return niveaux;
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

// Map grade level code → full name (e.g. "4S" → "4ème année secondaire")
final niveauxNameMapProvider = Provider<Map<String, String>>((ref) {
  final classesAsync = ref.watch(classesListProvider);
  return classesAsync.when(
    data: (classes) {
      final Map<String, String> map = {};
      for (final c in classes) {
        if (c.gradeLevelCode != null) {
          map[c.gradeLevelCode!] = c.gradeLevelName ?? c.gradeLevelCode!;
        }
      }
      return map;
    },
    loading: () => {},
    error: (_, __) => {},
  );
});

// Get unique subjects from current class offerings
final uniqueSubjectsProvider = Provider.family<List<String>, (String, String?)>(
  (ref, params) {
    final offeringsAsync = ref.watch(classSubjectOfferingsProvider(params));
    return offeringsAsync.when(
      data: (offerings) =>
          offerings.map((o) => o.subjectName).toSet().toList()..sort(),
      loading: () => [],
      error: (_, __) => [],
    );
  },
);

class TimetablesScreen extends ConsumerStatefulWidget {
  const TimetablesScreen({super.key});

  @override
  ConsumerState<TimetablesScreen> createState() => _TimetablesScreenState();
}

const _brand = Color(0xFF655DD5);
const _brandLight = Color(0xFFEEECFB);

class _TimetablesScreenState extends ConsumerState<TimetablesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _timetableSearchController =
      TextEditingController();
  bool _showFilterDrawer = false;
  bool _showTimetableFilterDrawer = false;
  String? _expandedNiveauId;
  String? _expandedSectionKey;

  // Timetable type: 'regular' or 'exam'
  String _timetableType = 'regular';
  String? _selectedExamPeriodId;

  @override
  void dispose() {
    _searchController.dispose();
    _timetableSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(filteredClassesProvider);
    final selectedClass = ref.watch(selectedClassProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Stack(
        children: [
          Row(
            children: [
              const AdminSidebar(currentRoute: '/timetables'),
              Expanded(
                child: Row(
                  children: [
                    // ── Left sidebar — Par niveau class selector ──
                    Container(
                      width: 280,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(right: BorderSide(color: AppColors.border.withOpacity(0.5))),
                      ),
                      child: _buildClassSelector(classesAsync, selectedClass),
                    ),
                    // ── Main content ──
                    Expanded(
                      child: Column(
                        children: [
                          _buildTopBar(context),
                          Expanded(
                            child: selectedClass != null
                                ? Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: _buildTimetableEditor(selectedClass),
                                  )
                                : _buildNoClassSelected(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // ── Filter drawer overlay ──
          if (_showFilterDrawer) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showFilterDrawer = false),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(color: Colors.black.withOpacity(0.28)),
                ),
              ),
            ),
            Positioned(
              right: 0, top: 0, bottom: 0,
              width: 370,
              child: _buildFilterDrawer(),
            ),
          ],
          // ── Timetable filter drawer overlay ──
          if (_showTimetableFilterDrawer) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showTimetableFilterDrawer = false),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(color: Colors.black.withOpacity(0.28)),
                ),
              ),
            ),
            Positioned(
              right: 0, top: 0, bottom: 0,
              width: 370,
              child: _buildTimetableFilterDrawer(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final selectedClass = ref.watch(selectedClassProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.5))),
      ),
      child: Row(
        children: [
          // Left: Title + subtitle
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Emploi du temps',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
              ),
              const SizedBox(height: 4),
              Text(
                selectedClass != null
                    ? 'Classe: ${selectedClass.name} — Cliquez sur une cellule vide pour ajouter un cours'
                    : 'Sélectionnez une classe pour gérer son emploi du temps',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
          const Spacer(),
          // Right: Suggested subjects button (icon only)
          if (selectedClass != null)
            Tooltip(
              message: 'Matières suggérées',
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () => _showSuggestedSubjects(selectedClass),
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.lightbulb_outline, size: 20, color: Color(0xFFF59E0B)),
                  ),
                ),
              ),
            ),
        ],
      ),
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

  Widget _buildClassSelector(
    AsyncValue<List<ClassInfo>> classesAsync,
    ClassInfo? selectedClass,
  ) {
    final searchQuery = ref.watch(classSearchQueryProvider);
    final selectedNiveau = ref.watch(selectedNiveauFilterProvider);
    final niveauxNames = ref.watch(niveauxNameMapProvider);
    final hasFilters = selectedNiveau != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header: search + filter icon ──
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.school_rounded, color: AppColors.textSecondary, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Sélectionner une classe',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1A1A2E), letterSpacing: -0.2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => ref.read(classSearchQueryProvider.notifier).state = v,
                      decoration: InputDecoration(
                        hintText: 'Rechercher classe ou élève...',
                        hintStyle: const TextStyle(color: Color(0xFFB0B3BE), fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFFB0B3BE)),
                        suffixIcon: searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 16, color: Color(0xFFB0B3BE)),
                                onPressed: () {
                                  _searchController.clear();
                                  ref.read(classSearchQueryProvider.notifier).state = '';
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFFF5F6FA),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _brand, width: 1.5)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: hasFilters ? _brand.withOpacity(0.08) : const Color(0xFFF5F6FA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: hasFilters ? _brand.withOpacity(0.4) : const Color(0xFFE5E7EB)),
                    ),
                    child: IconButton(
                      onPressed: () => setState(() => _showFilterDrawer = !_showFilterDrawer),
                      icon: Icon(
                        Icons.filter_list_rounded,
                        size: 18,
                        color: hasFilters ? _brand : const Color(0xFF8B90A0),
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
              // ── Active filter chips ──
              if (hasFilters) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (selectedNiveau != null)
                      _buildFilterChip(
                        label: 'Niveau: ${niveauxNames[selectedNiveau] ?? selectedNiveau}',
                        onRemove: () {
                          ref.read(selectedNiveauFilterProvider.notifier).state = null;
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFF1F1F5)),
        const SizedBox(height: 6),
        // ── "Par niveau" title ──
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 10, bottom: 10),
          child: Text(
            'Par niveau',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: const Color(0xFF1A1A2E), letterSpacing: -0.2),
          ),
        ),
        // ── Niveau list with expandable classes ──
        Expanded(
          child: classesAsync.when(
            loading: () => const Center(child: IosLoader()),
            error: (e, _) => Center(
              child: Text(
                UserFriendlyError.format(
                  e,
                  fallback: 'Unable to load classes right now. Please try again.',
                ),
                style: TextStyle(color: AppColors.slate500),
              ),
            ),
            data: (classes) {
              if (classes.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.class_outlined, size: 48, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(
                        hasFilters || searchQuery.isNotEmpty ? 'Aucun résultat' : 'Aucune classe',
                        style: TextStyle(color: AppColors.slate500, fontSize: 13),
                      ),
                      if (hasFilters || searchQuery.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            _searchController.clear();
                            ref.read(classSearchQueryProvider.notifier).state = '';
                            ref.read(selectedNiveauFilterProvider.notifier).state = null;
                          },
                          child: const Text('Effacer les filtres'),
                        ),
                      ],
                    ],
                  ),
                );
              }

              // Group by grade level code
              final groupedClasses = <String, List<ClassInfo>>{};
              for (final cls in classes) {
                final key = cls.gradeLevelCode ?? 'Autre';
                groupedClasses.putIfAbsent(key, () => []).add(cls);
              }

              final sortedEntries = groupedClasses.entries.toList()
                ..sort((a, b) {
                  final orderA = _getNiveauSortOrder(a.value.firstOrNull?.gradeLevelName ?? a.key);
                  final orderB = _getNiveauSortOrder(b.value.firstOrNull?.gradeLevelName ?? b.key);
                  if (orderA != orderB) return orderA.compareTo(orderB);
                  return a.key.compareTo(b.key);
                });

              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                children: sortedEntries.map((entry) {
                  final niveauCode = entry.key;
                  final niveauClasses = entry.value;
                  final isExpanded = _expandedNiveauId == niveauCode;
                  final hasSelectedInNiveau = niveauClasses.any((c) => c.id == selectedClass?.id);
                  // Get full name from the first class in the group
                  final niveauFullName = niveauClasses.first.gradeLevelName ?? niveauCode;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isExpanded ? const Color(0xFFF0EEFA) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          if (!isExpanded)
                            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 2)),
                        ],
                        border: isExpanded
                            ? Border.all(color: _brand.withOpacity(0.12))
                            : Border.all(color: Colors.grey.withOpacity(0.06)),
                      ),
                      child: Column(
                        children: [
                          // ── Niveau header ──
                          InkWell(
                            onTap: () => setState(() {
                              _expandedNiveauId = isExpanded ? null : niveauCode;
                              _expandedSectionKey = null;
                            }),
                            borderRadius: BorderRadius.circular(16),
                            hoverColor: _brandLight.withOpacity(0.3),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      niveauFullName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600, fontSize: 14,
                                        color: isExpanded || hasSelectedInNiveau ? _brand : const Color(0xFF2D2D3A),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 30, height: 30,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isExpanded ? _brand : const Color(0xFFE9EAF0),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${niveauClasses.length}',
                                      style: TextStyle(
                                        fontSize: 12, fontWeight: FontWeight.w700,
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
                                final hasSections = niveauClasses.any((c) =>
                                    (c.sectionName != null && c.sectionName!.isNotEmpty) ||
                                    (c.sectionCode != null && c.sectionCode!.isNotEmpty));

                                final sectionsMap = <String, List<ClassInfo>>{};
                                final unassignedClasses = <ClassInfo>[];

                                if (hasSections) {
                                  for (final cls in niveauClasses) {
                                    final secName = cls.sectionName ?? cls.sectionCode;
                                    if (secName != null && secName.isNotEmpty) {
                                      sectionsMap.putIfAbsent(secName, () => []).add(cls);
                                    } else {
                                      unassignedClasses.add(cls);
                                    }
                                  }
                                }

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
                                            color: _brand.withOpacity(0.18),
                                            borderRadius: BorderRadius.circular(1),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: hasSections
                                              ? Column(
                                                  children: [
                                                    ...sectionsMap.entries.map((entry) {
                                                      final secKey = entry.key;
                                                      final secClasses = entry.value;
                                                      final isSecExpanded = _expandedSectionKey == secKey;

                                                      return Padding(
                                                        padding: const EdgeInsets.only(bottom: 6),
                                                        child: Column(
                                                          children: [
                                                            Material(
                                                              color: Colors.transparent,
                                                              child: InkWell(
                                                                onTap: () => setState(() {
                                                                  _expandedSectionKey = isSecExpanded ? null : secKey;
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
                                                                              color: _brand.withOpacity(0.08),
                                                                              blurRadius: 8,
                                                                              offset: const Offset(0, 2),
                                                                            ),
                                                                          ]
                                                                        : null,
                                                                    border: isSecExpanded
                                                                        ? Border.all(color: _brand.withOpacity(0.25))
                                                                        : Border.all(color: Colors.transparent),
                                                                  ),
                                                                  child: Row(
                                                                    children: [
                                                                      Expanded(
                                                                        child: Text(
                                                                          secKey,
                                                                          style: TextStyle(
                                                                            fontSize: 13,
                                                                            fontWeight: isSecExpanded ? FontWeight.w600 : FontWeight.w500,
                                                                            color: isSecExpanded ? _brand : const Color(0xFF2D2D3A),
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
                                                                          color: isSecExpanded ? _brand : const Color(0xFFE9EAF0),
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
                                                                          color: _brand.withOpacity(0.15),
                                                                          borderRadius: BorderRadius.circular(1),
                                                                        ),
                                                                      ),
                                                                      const SizedBox(width: 10),
                                                                      Expanded(
                                                                        child: Column(
                                                                          children: secClasses.map((cls) {
                                                                            final isSelected = selectedClass?.id == cls.id;
                                                                            return _buildTimetableSidebarClassCard(cls, isSelected);
                                                                          }).toList(),
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
                                                    ...unassignedClasses.map((cls) {
                                                      final isSelected = selectedClass?.id == cls.id;
                                                      return _buildTimetableSidebarClassCard(cls, isSelected);
                                                    }),
                                                  ],
                                                )
                                              : Column(
                                                  children: niveauClasses.map((cls) {
                                                    final isSelected = selectedClass?.id == cls.id;
                                                    return _buildTimetableSidebarClassCard(cls, isSelected);
                                                  }).toList(),
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
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTimetableSidebarClassCard(ClassInfo cls, bool isSelected) {
    return Consumer(
      builder: (context, ref, _) {
        final studentCountAsync = ref.watch(classStudentCountProvider(cls.id));
        final studentCount = studentCountAsync.whenOrNull(data: (c) => c);
        final secLabel = cls.sectionName ?? cls.sectionCode;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => ref.read(selectedClassProvider.notifier).state = cls,
              borderRadius: BorderRadius.circular(12),
              hoverColor: Colors.white.withOpacity(0.8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.white.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected ? [
                    BoxShadow(color: _brand.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2)),
                  ] : null,
                  border: isSelected
                      ? Border.all(color: _brand.withOpacity(0.2))
                      : Border.all(color: Colors.transparent),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cls.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                              color: isSelected ? _brand : const Color(0xFF5A5B6A),
                            ),
                          ),
                          if (secLabel != null || studentCount != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                children: [
                                  if (secLabel != null) ...[
                                    Flexible(
                                      child: Text(
                                        secLabel,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isSelected ? _brand.withOpacity(0.6) : const Color(0xFF9B9DAB),
                                        ),
                                      ),
                                    ),
                                    if (studentCount != null)
                                      const Text(' • ', style: TextStyle(fontSize: 11, color: Color(0xFF9B9DAB))),
                                  ],
                                  if (studentCount != null)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.people_outline, size: 11, color: isSelected ? _brand.withOpacity(0.6) : const Color(0xFF9B9DAB)),
                                        const SizedBox(width: 3),
                                        Text('$studentCount', style: TextStyle(fontSize: 11, color: isSelected ? _brand.withOpacity(0.6) : const Color(0xFF9B9DAB))),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_circle, color: _brand, size: 18),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChip({
    required String label,
    required VoidCallback onRemove,
    Color? color,
  }) {
    final chipColor = color ?? const Color(0xFF8B5CF6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: chipColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: chipColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              Icons.close,
              size: 14,
              color: chipColor.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  // ── Filter drawer (right-side panel with blur backdrop) ──
  Widget _buildFilterDrawer() {
    final niveaux = ref.watch(niveauxListProvider);
    final niveauxNames = ref.watch(niveauxNameMapProvider);
    final selectedNiveau = ref.watch(selectedNiveauFilterProvider);

    Widget filterLabel(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textTertiary, letterSpacing: 1.0)),
        );

    Widget filterDropdown<T>({
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
                    onPressed: () => setState(() => _showFilterDrawer = false),
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
                    // Niveau
                    filterLabel('NIVEAU'),
                    filterDropdown<String?>(
                      value: selectedNiveau,
                      hint: 'Tous les niveaux',
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Tous les niveaux')),
                        ...niveaux.map((n) => DropdownMenuItem(value: n, child: Text(niveauxNames[n] ?? n))),
                      ],
                      onChanged: (v) {
                        ref.read(selectedNiveauFilterProvider.notifier).state = v;
                      },
                    ),
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
                          ref.read(selectedNiveauFilterProvider.notifier).state = null;
                        },
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
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => setState(() => _showFilterDrawer = false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _brand,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          shadowColor: _brand.withOpacity(0.3),
                        ),
                        child: const Text('Appliquer', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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

  // ── Timetable-specific filter drawer (day + matière) ──
  Widget _buildTimetableFilterDrawer() {
    final selectedClass = ref.watch(selectedClassProvider);
    final semesterId = ref.watch(currentSemesterIdProvider);
    final subjects = selectedClass != null
        ? ref.watch(uniqueSubjectsProvider((selectedClass.id, semesterId)))
        : <String>[];
    final dayFilter = ref.watch(selectedDayFilterProvider);
    final subjectFilter = ref.watch(selectedSubjectFilterProvider);

    Widget filterLabel(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textTertiary, letterSpacing: 1.0)),
        );

    Widget filterDropdown<T>({
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
                  const Text('Filtres emploi du temps', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => setState(() => _showTimetableFilterDrawer = false),
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
                    // Day filter
                    filterLabel('JOUR'),
                    filterDropdown<int?>(
                      value: dayFilter,
                      hint: 'Tous les jours',
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Tous les jours')),
                        ...List.generate(
                          6,
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text(_dayLabels[i]),
                          ),
                        ),
                      ],
                      onChanged: (v) => ref.read(selectedDayFilterProvider.notifier).state = v,
                    ),
                    const SizedBox(height: 20),
                    // Subject filter
                    filterLabel('MATIÈRE'),
                    filterDropdown<String?>(
                      value: subjectFilter,
                      hint: 'Toutes les matières',
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Toutes les matières')),
                        ...subjects.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                      ],
                      onChanged: (v) => ref.read(selectedSubjectFilterProvider.notifier).state = v,
                    ),
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
                          ref.read(selectedDayFilterProvider.notifier).state = null;
                          ref.read(selectedSubjectFilterProvider.notifier).state = null;
                        },
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
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => setState(() => _showTimetableFilterDrawer = false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _brand,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          shadowColor: _brand.withOpacity(0.3),
                        ),
                        child: const Text('Appliquer', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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

  Widget _buildNoClassSelected() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.calendar_month_rounded,
                size: 64,
                color: Color(0xFF8B5CF6),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Sélectionnez une classe',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.slate800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choisissez une classe dans la liste pour gérer son emploi du temps',
              style: TextStyle(color: AppColors.slate500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimetableEditor(ClassInfo selectedClass) {
    final slotsAsync = ref.watch(
      filteredTimetableSlotsProvider(selectedClass.id),
    );
    final allSlotsAsync = ref.watch(
      classTimetableSlotsProvider(selectedClass.id),
    );
    final semesterId = ref.watch(currentSemesterIdProvider);
    final offeringsAsync = ref.watch(
      classSubjectOfferingsProvider((selectedClass.id, semesterId)),
    );
    final searchQuery = ref.watch(timetableSearchQueryProvider);
    final dayFilter = ref.watch(selectedDayFilterProvider);
    final subjectFilter = ref.watch(selectedSubjectFilterProvider);
    final hasTimetableFilters = dayFilter != null || subjectFilter != null;
    final hasFilters =
        searchQuery.isNotEmpty || dayFilter != null || subjectFilter != null;
    final semesterState = ref.watch(semestersProvider).asData?.value;
    final isVacationToday = semesterState?.isDateVacation(DateTime.now()) ?? false;
    final examPeriods = ref.watch(examPeriodsListProvider);
    final currentTimetableType = ref.watch(timetableTypeFilterProvider);
    final selectedExamPeriodId = ref.watch(selectedExamPeriodFilterProvider);
    final isEditable = ref.watch(isSemesterEditableProvider);
    final semesterStatus = ref.watch(selectedSemesterStatusProvider);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: offeringsAsync.when(
        loading: () => const SizedBox(
          height: 400,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                IosLoader(),
                SizedBox(height: 16),
                Text('Chargement des matières...'),
              ],
            ),
          ),
        ),
        error: (e, _) => SizedBox(
          height: 400,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, color: AppColors.error, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'Unable to load subjects',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8),
                  Text(
                    UserFriendlyError.format(
                      e,
                      fallback: 'Unable to load subjects right now. Please try again.',
                    ),
                    style: TextStyle(color: AppColors.slate300),
                  ),
                ],
              ),
            ),
          ),
        ),
        data: (offerings) => Column(
          children: [
            if (isVacationToday)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.beach_access, size: 18, color: Color(0xFF92400E)),
                    SizedBox(width: 8),
                    Text(
                      'Vacances en cours',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
              ),
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.grid_view_rounded,
                          color: Color(0xFF8B5CF6),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentTimetableType == 'exam'
                                  ? 'Emploi d\'examen: ${selectedClass.name}'
                                  : 'Emploi du temps: ${selectedClass.name}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            Text(
                              currentTimetableType == 'exam'
                                  ? 'Emploi d\'examen — cliquez pour ajouter un cours'
                                  : 'Cliquez sur une cellule vide pour ajouter un cours',
                              style: TextStyle(
                                color: AppColors.slate500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Semester selector dropdown
                      Consumer(
                        builder: (context, ref, _) {
                          final semestersAsync = ref.watch(semestersProvider);
                          final activeSemesterId = ref.watch(currentActiveSemesterIdProvider);
                          final currentSelectedId = ref.watch(effectiveSemesterIdProvider);

                          return semestersAsync.when(
                            data: (semestersState) {
                              final rawSemesters = semestersState.filteredSemesters.isNotEmpty
                                  ? semestersState.filteredSemesters
                                  : semestersState.semesters;

                              if (rawSemesters.isEmpty) return const SizedBox.shrink();

                              final Map<String, SemesterModel> uniqueMap = {};
                              for (final sem in rawSemesters) {
                                uniqueMap[sem.id] = sem;
                              }
                              final semesters = uniqueMap.values.toList()
                                ..sort((a, b) => a.number.compareTo(b.number));

                              String? effectiveSelectedId;
                              if (currentSelectedId != null && uniqueMap.containsKey(currentSelectedId)) {
                                effectiveSelectedId = currentSelectedId;
                              } else if (activeSemesterId != null && uniqueMap.containsKey(activeSemesterId)) {
                                effectiveSelectedId = activeSemesterId;
                              } else if (semesters.isNotEmpty) {
                                effectiveSelectedId = semesters.first.id;
                              }

                              final periodLabel = semestersState.periodLabel;

                              return Container(
                                height: 38,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.slate100,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: AppColors.borderLight),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String?>(
                                    value: effectiveSelectedId,
                                    borderRadius: BorderRadius.circular(16),
                                    dropdownColor: Colors.white,
                                    elevation: 6,
                                    icon: const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: Color(0xFF8B5CF6),
                                      size: 18,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                    items: semesters.map((sem) {
                                      final now = DateTime.now();
                                      final isSemCurrent = sem.id == activeSemesterId ||
                                          sem.isCurrent ||
                                          (!now.isBefore(sem.startDate) && !now.isAfter(sem.endDate));

                                      return DropdownMenuItem<String?>(
                                        value: sem.id,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              sem.name.isNotEmpty
                                                  ? sem.name
                                                  : '$periodLabel ${sem.number}',
                                              style: TextStyle(
                                                fontWeight: isSemCurrent ? FontWeight.bold : FontWeight.w500,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                            if (isSemCurrent) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF3F0FF),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Text(
                                                  'En cours',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF6D4CF6),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      ref.read(selectedSemesterOverrideProvider.notifier).state = val;
                                    },
                                  ),
                                ),
                              );
                            },
                            loading: () => const SizedBox.shrink(),
                            error: (_, __) => const SizedBox.shrink(),
                          );
                        },
                      ),
                      // Timetable type toggle
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.slate100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.all(3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () {
                                ref.read(timetableTypeFilterProvider.notifier).state = 'regular';
                                ref.read(selectedExamPeriodFilterProvider.notifier).state = null;
                                setState(() {
                                  _timetableType = 'regular';
                                  _selectedExamPeriodId = null;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: currentTimetableType == 'regular' ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: currentTimetableType == 'regular'
                                      ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.schedule, size: 14, color: currentTimetableType == 'regular' ? _brand : AppColors.slate400),
                                    const SizedBox(width: 5),
                                    Text('Régulier', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: currentTimetableType == 'regular' ? _brand : AppColors.slate400)),
                                  ],
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                if (examPeriods.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Aucune période d\'examen configurée. Ajoutez-en depuis la page Périodes.'), backgroundColor: AppColors.warning),
                                  );
                                  return;
                                }
                                if (selectedExamPeriodId == null || examPeriods.every((e) => e.id != selectedExamPeriodId)) {
                                  final picked = await _showExamPeriodPicker(examPeriods);
                                  if (picked != null) {
                                    ref.read(selectedExamPeriodFilterProvider.notifier).state = picked.id;
                                    setState(() {
                                      _timetableType = 'exam';
                                      _selectedExamPeriodId = picked.id;
                                    });
                                    ref.read(timetableTypeFilterProvider.notifier).state = 'exam';
                                  }
                                } else {
                                  ref.read(timetableTypeFilterProvider.notifier).state = 'exam';
                                  setState(() {
                                    _timetableType = 'exam';
                                    _selectedExamPeriodId = selectedExamPeriodId;
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: currentTimetableType == 'exam' ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: currentTimetableType == 'exam'
                                      ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.school, size: 14, color: currentTimetableType == 'exam' ? _brand : AppColors.slate400),
                                    const SizedBox(width: 5),
                                    Text('Examen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: currentTimetableType == 'exam' ? _brand : AppColors.slate400)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Bulk upload button (icon only)
                      Tooltip(
                        message: !isEditable
                            ? 'Ce semestre archivé est en lecture seule'
                            : 'Import CSV',
                        child: Material(
                          color: !isEditable
                              ? AppColors.slate300.withOpacity(0.12)
                              : const Color(0xFF8B5CF6).withOpacity(0.10),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            onTap: !isEditable ? null : () => _showBulkUploadDialog(selectedClass, offerings),
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 36, height: 36,
                              child: Icon(
                                Icons.upload_file,
                                size: 18,
                                color: !isEditable ? AppColors.textSecondary : const Color(0xFF8B5CF6),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Delete all button (icon only)
                      Tooltip(
                        message: !isEditable
                            ? 'Ce semestre archivé est en lecture seule'
                            : 'Supprimer tout',
                        child: Material(
                          color: !isEditable
                              ? AppColors.slate300.withOpacity(0.12)
                              : const Color(0xFF8B5CF6).withOpacity(0.10),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            onTap: !isEditable ? null : () => _showDeleteAllDialog(selectedClass),
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 36, height: 36,
                              child: Icon(
                                Icons.delete_sweep,
                                size: 18,
                                color: !isEditable ? AppColors.textSecondary : const Color(0xFF8B5CF6),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Add course button (icon only)
                      Tooltip(
                        message: !isEditable
                            ? 'Ce semestre archivé est en lecture seule'
                            : offerings.isEmpty
                                ? 'Aucune matière configurée pour cette classe'
                                : 'Ajouter un nouveau cours',
                        child: Material(
                          color: (!isEditable || offerings.isEmpty)
                              ? AppColors.slate300.withOpacity(0.12)
                              : const Color(0xFF8B5CF6).withOpacity(0.10),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            onTap: (!isEditable || offerings.isEmpty)
                                ? null
                                : () => _showAddSlotDialog(selectedClass, offerings),
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 36, height: 36,
                              child: Icon(
                                Icons.add,
                                size: 18,
                                color: (!isEditable || offerings.isEmpty)
                                    ? AppColors.textSecondary
                                    : const Color(0xFF8B5CF6),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Smart search row — search + filter icon
                  Row(
                    children: [
                      // Search field
                      Expanded(
                        child: TextField(
                          controller: _timetableSearchController,
                          onChanged: (v) =>
                              ref
                                      .read(
                                        timetableSearchQueryProvider.notifier,
                                      )
                                      .state =
                                  v,
                          decoration: InputDecoration(
                            hintText: 'Rechercher matière, prof, salle...',
                            hintStyle: TextStyle(
                              color: AppColors.slate400,
                              fontSize: 13,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              color: AppColors.slate400,
                              size: 20,
                            ),
                            suffixIcon: searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: Icon(
                                      Icons.close,
                                      color: AppColors.slate400,
                                      size: 18,
                                    ),
                                    onPressed: () {
                                      _timetableSearchController.clear();
                                      ref
                                              .read(
                                                timetableSearchQueryProvider
                                                    .notifier,
                                              )
                                              .state =
                                          '';
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: AppColors.slate100,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Filter icon button
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: hasTimetableFilters ? _brand.withOpacity(0.08) : AppColors.slate100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: hasTimetableFilters ? _brand.withOpacity(0.4) : const Color(0xFFE5E7EB)),
                        ),
                        child: IconButton(
                          onPressed: () => setState(() => _showTimetableFilterDrawer = !_showTimetableFilterDrawer),
                          icon: Icon(
                            Icons.filter_list_rounded,
                            size: 18,
                            color: hasTimetableFilters ? _brand : const Color(0xFF8B90A0),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  // Active filters
                  if (hasFilters) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Filtres actifs:',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (dayFilter != null)
                          _buildTimetableFilterChip(
                            label: _dayLabels[dayFilter - 1],
                            onRemove: () =>
                                ref
                                        .read(
                                          selectedDayFilterProvider.notifier,
                                        )
                                        .state =
                                    null,
                          ),
                        if (subjectFilter != null) ...[
                          const SizedBox(width: 6),
                          _buildTimetableFilterChip(
                            label: subjectFilter.length > 12
                                ? '${subjectFilter.substring(0, 12)}...'
                                : subjectFilter,
                            onRemove: () =>
                                ref
                                        .read(
                                          selectedSubjectFilterProvider
                                              .notifier,
                                        )
                                        .state =
                                    null,
                          ),
                        ],
                        if (searchQuery.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _buildTimetableFilterChip(
                            label: '"$searchQuery"',
                            onRemove: () {
                              _timetableSearchController.clear();
                              ref
                                      .read(
                                        timetableSearchQueryProvider.notifier,
                                      )
                                      .state =
                                  '';
                            },
                          ),
                        ],
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            _timetableSearchController.clear();
                            ref
                                    .read(timetableSearchQueryProvider.notifier)
                                    .state =
                                '';
                            ref.read(selectedDayFilterProvider.notifier).state =
                                null;
                            ref
                                    .read(
                                      selectedSubjectFilterProvider.notifier,
                                    )
                                    .state =
                                null;
                          },
                          icon: const Icon(Icons.clear_all, size: 16),
                          label: const Text('Effacer'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            if (semesterStatus == TimetableSemesterStatus.past)
              _buildPastSemesterBanner(
                ref: ref,
                selectedClass: selectedClass,
                semesterState: semesterState,
              ),
            // Timetable grid
            Expanded(
              child: allSlotsAsync.when(
                loading: () => const Center(child: IosLoader()),
                error: (e, _) => Center(
                  child: Text(
                    UserFriendlyError.format(
                      e,
                      fallback: 'Unable to load the timetable right now. Please try again.',
                    ),
                  ),
                ),
                data: (allSlots) {
                  final filteredSlots = slotsAsync.hasValue
                      ? slotsAsync.value!
                      : allSlots;
                  return _buildGrid(
                    hasFilters ? filteredSlots : allSlots,
                    selectedClass,
                    offerings,
                    highlightSlots: hasFilters ? filteredSlots : null,
                    isEditable: isEditable,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimetableFilterChip({
    required String label,
    required VoidCallback onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF10B981),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              Icons.close,
              size: 14,
              color: const Color(0xFF10B981).withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPastSemesterBanner({
    required WidgetRef ref,
    required ClassInfo selectedClass,
    required SemestersState? semesterState,
  }) {
    final activeId = ref.watch(currentActiveSemesterIdProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border(
          bottom: BorderSide(color: AppColors.slate200, width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.archive_outlined,
              size: 18,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Semestre archivé (Mode consultation uniquement)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Cet emploi du temps appartient à un semestre passé. Il est consultable mais non modifiable.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          if (activeId != null)
            TextButton.icon(
              onPressed: () {
                ref.read(selectedSemesterOverrideProvider.notifier).state = activeId;
              },
              icon: const Icon(Icons.arrow_forward_rounded, size: 14),
              label: const Text('Revenir au semestre actuel'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF8B5CF6),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid(
    List<TimetableSlotAdmin> slots,
    ClassInfo selectedClass,
    List<SubjectOfferingInfo> offerings, {
    List<TimetableSlotAdmin>? highlightSlots,
    bool isEditable = true,
  }) {
    // Proportional grid: Days as ROWS, Time positioned proportionally
    const dayColumnWidth = 55.0;
    const cellHeight = 65.0;
    const dayRowsCount = 6;
    const timelineWidth = 1100.0; // Total width for 11 hours (08:00-19:00)
    const dayStartMinutes = 8 * 60; // 08:00
    const dayEndMinutes = 19 * 60; // 19:00
    const totalMinutes = dayEndMinutes - dayStartMinutes; // 660 minutes
    final gridLineColor = AppColors.slate300;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: gridLineColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: dayColumnWidth + timelineWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // === TIME HEADER ROW ===
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withOpacity(0.08),
                        border: Border(
                          bottom: BorderSide(color: gridLineColor, width: 2),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Corner cell
                          Container(
                            width: dayColumnWidth,
                            height: 36,
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                  color: gridLineColor,
                                  width: 2,
                                ),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const Text(''),
                          ),
                          // Time markers - proportionally positioned
                          SizedBox(
                            width: timelineWidth,
                            height: 36,
                            child: Stack(
                              children: [
                                for (int i = 0; i < _gridHourLabels.length; i++)
                                  Positioned(
                                    left:
                                        (i / (_gridHourLabels.length - 1)) *
                                            timelineWidth -
                                        15,
                                    top: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 50,
                                      alignment: Alignment.center,
                                      child: Text(
                                        _gridHourLabels[i],
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF8B5CF6),
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
                    // === DAY ROWS ===
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: List.generate(dayRowsCount, (dayIndex) {
                            final dayNum = dayIndex + 1;
                            final daySlots = slots
                                .where((s) => s.dayOfWeek == dayNum)
                                .toList();

                            return Container(
                              height: cellHeight,
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: gridLineColor),
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Day label column
                                  Container(
                                    width: dayColumnWidth,
                                    height: cellHeight,
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF8B5CF6,
                                      ).withOpacity(0.05),
                                      border: Border(
                                        right: BorderSide(
                                          color: gridLineColor,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      _dayLabelsShort[dayIndex],
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                  ),
                                  // Timeline with proportionally positioned slots
                                  SizedBox(
                                    width: timelineWidth,
                                    height: cellHeight,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        // Hour grid lines
                                        for (
                                          int i = 1;
                                          i < _gridHourLabels.length;
                                          i++
                                        )
                                          Positioned(
                                            left:
                                                (i / (_gridHourLabels.length - 1)) *
                                                timelineWidth,
                                            top: 0,
                                            bottom: 0,
                                            child: Container(
                                              width: 0.5,
                                              color: gridLineColor,
                                            ),
                                          ),
                                        // Click areas for adding slots (between hours) - only when editable
                                        if (isEditable)
                                          for (
                                            int i = 0;
                                            i < _gridHourLabels.length - 1;
                                            i++
                                          )
                                            Positioned(
                                              left:
                                                  (i / (_gridHourLabels.length - 1)) *
                                                  timelineWidth,
                                              top: 0,
                                              width:
                                                  timelineWidth /
                                                  (_gridHourLabels.length - 1),
                                              height: cellHeight,
                                              child: _buildEmptySlotArea(
                                                selectedClass,
                                                offerings,
                                                dayNum,
                                                _gridHourLabels[i],
                                                daySlots,
                                              ),
                                            ),
                                        // Slots - proportionally positioned
                                        for (final slot in daySlots)
                                          _buildProportionalSlot(
                                            slot: slot,
                                            timelineWidth: timelineWidth,
                                            rowHeight: cellHeight,
                                            dayStartMinutes: dayStartMinutes,
                                            totalMinutes: totalMinutes,
                                            isEditable: isEditable,
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Build empty slot click area (only shows + if no slot covers this area)
  Widget _buildEmptySlotArea(
    ClassInfo selectedClass,
    List<SubjectOfferingInfo> offerings,
    int dayNum,
    String timeStart,
    List<TimetableSlotAdmin> daySlots,
  ) {
    final timeStartMin = _timeToMinutes(timeStart);
    final timeEndMin = timeStartMin + 60;

    // Check if any slot covers this time range
    final hasCoveringSlot = daySlots.any((slot) {
      final slotStart = _timeToMinutes(slot.startTime);
      final slotEnd = _timeToMinutes(slot.endTime);
      return slotStart < timeEndMin && slotEnd > timeStartMin;
    });

    if (hasCoveringSlot) {
      return const SizedBox.shrink();
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showAddSlotDialogForCell(
          selectedClass,
          offerings,
          dayNum,
          timeStart,
        ),
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.slate50,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Icon(Icons.add, size: 14, color: AppColors.slate300),
          ),
        ),
      ),
    );
  }

  /// Build a slot positioned proportionally on the timeline
  Widget _buildProportionalSlot({
    required TimetableSlotAdmin slot,
    required double timelineWidth,
    required double rowHeight,
    required int dayStartMinutes,
    required int totalMinutes,
    bool isEditable = true,
  }) {
    final startMinutes = _timeToMinutes(slot.startTime);
    final endMinutes = _timeToMinutes(slot.endTime);

    // Skip invalid or zero-duration slots to avoid zero-size render boxes
    if (endMinutes <= startMinutes) {
      return const SizedBox.shrink();
    }

    // Calculate position and width as percentage of timeline
    final startPercent = (startMinutes - dayStartMinutes) / totalMinutes;
    final endPercent = (endMinutes - dayStartMinutes) / totalMinutes;
    final widthPercent = endPercent - startPercent;

    final left = startPercent * timelineWidth;
    final rawWidth = widthPercent * timelineWidth;
    final slotWidth = math.max(
      rawWidth - 4,
      12.0,
    ); // ensure a minimum visible width

    final color = _getSubjectColor(slot.subjectCode ?? 'default');

    return Positioned(
      left: left + 2,
      top: 3,
      width: slotWidth,
      height: rowHeight - 6,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTapDown: (details) => _showSlotOptions(
            slot,
            details.globalPosition,
            isEditable: isEditable,
          ),
          child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, color.withOpacity(0.85)],
            ),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.25),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    slot.subjectCode ?? 'N/A',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              if (slotWidth > 60)
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      slot.room ?? '',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 9,
                      ),
                    ),
                  ),
                ),
              if (slot.teacherName != null && slot.teacherName!.isNotEmpty)
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      slot.teacherName!,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 8,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),
              if (slotWidth > 80)
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_formatTime(slot.startTime)}-${_formatTime(slot.endTime)}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 8,
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

  // Helper to format time (removes seconds if present)
  String _formatTime(String time) {
    final parts = time.split(':');
    return '${parts[0]}:${parts[1]}';
  }

  // Find slot that overlaps with the given hour
  TimetableSlotAdmin? _findSlotInHour(
    List<TimetableSlotAdmin> slots,
    int day,
    String hourStart,
    String hourEnd,
  ) {
    final hourStartMin = _timeToMinutes(hourStart);
    final hourEndMin = _timeToMinutes(hourEnd);

    for (final slot in slots) {
      if (slot.dayOfWeek == day) {
        final slotStart = _timeToMinutes(slot.startTime);
        final slotEnd = _timeToMinutes(slot.endTime);
        // Slot overlaps if it starts before hour ends AND ends after hour starts
        if (slotStart < hourEndMin && slotEnd > hourStartMin) {
          return slot;
        }
      }
    }
    return null;
  }

  // Check if slot starts within this hour
  bool _isSlotStartingInHour(
    String slotStart,
    String hourStart,
    String hourEnd,
  ) {
    final slotStartMin = _timeToMinutes(slotStart);
    final hourStartMin = _timeToMinutes(hourStart);
    final hourEndMin = _timeToMinutes(hourEnd);
    return slotStartMin >= hourStartMin && slotStartMin < hourEndMin;
  }

  int _calculateSpan(TimetableSlotAdmin slot) {
    final start = _timeToMinutes(slot.startTime);
    final end = _timeToMinutes(slot.endTime);
    // Using 60-minute slots now
    return ((end - start) / 60).ceil().clamp(1, 9);
  }

  int _timeToMinutes(String time) {
    // Handle both "HH:MM" and "HH:MM:SS" formats
    final parts = time.split(':');
    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return hours * 60 + minutes;
  }

  void _showSlotOptions(
    TimetableSlotAdmin slot,
    Offset tapPosition, {
    bool isEditable = true,
  }) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final items = <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: 'view',
        height: 44,
        child: Row(
          children: const [
            Icon(Icons.visibility_outlined, size: 18, color: Color(0xFF3B82F6)),
            SizedBox(width: 12),
            Text('Voir', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
          ],
        ),
      ),
    ];

    if (isEditable) {
      items.addAll([
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'edit',
          height: 44,
          child: Row(
            children: const [
              Icon(Icons.edit_outlined, size: 18, color: Color(0xFF6366F1)),
              SizedBox(width: 12),
              Text('Modifier', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'delete',
          height: 44,
          child: Row(
            children: const [
              Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
              SizedBox(width: 12),
              Text('Supprimer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFEF4444))),
            ],
          ),
        ),
      ]);
    }

    showMenu<String>(
      context: context,
      elevation: 8,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromRect(
        tapPosition & const Size(48, 48),
        Offset.zero & overlay.size,
      ),
      items: items,
    ).then((value) {
      if (value == 'view') _showSlotDetailsDialog(slot);
      if (value == 'edit') _showEditSlotDialog(slot);
      if (value == 'delete') _showDeleteSlotConfirmation(slot);
    });
  }

  void _showSlotDetailsDialog(TimetableSlotAdmin slot) {
    final color = _getSubjectColor(slot.subjectCode ?? 'default');
    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with gradient
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color, color.withOpacity(0.85)],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          slot.subjectCode ?? '?',
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            slot.subjectName ?? slot.subjectCode ?? 'N/A',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          if (slot.className != null)
                            Text(
                              'Classe: ${slot.className}',
                              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.pop(ctx),
                      child: Icon(Icons.close, color: Colors.white.withOpacity(0.7), size: 20),
                    ),
                  ],
                ),
              ),
              // Details
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    _buildTeacherRow(slot.teacherName ?? 'Non assigné', slot.teacherPhotoUrl),
                    const SizedBox(height: 14),
                    _buildDetailRow(Icons.calendar_today_outlined, 'Jour', _dayLabels[slot.dayOfWeek - 1]),
                    const SizedBox(height: 14),
                    _buildDetailRow(Icons.access_time_rounded, 'Horaire', '${_formatTime(slot.startTime)} - ${_formatTime(slot.endTime)}'),
                    const SizedBox(height: 14),
                    _buildDetailRow(Icons.door_sliding_outlined, 'Salle', slot.room ?? 'Non définie'),
                  ],
                ),
              ),
              // Footer
              Container(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Fermer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeacherRow(String teacherName, String? photoUrl) {
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFFF3F4F6),
          backgroundImage: photoUrl != null && photoUrl.isNotEmpty
              ? NetworkImage(photoUrl)
              : null,
          child: (photoUrl == null || photoUrl.isEmpty)
              ? const Icon(Icons.person_outline_rounded, size: 18, color: Color(0xFF6B7280))
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Professeur', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
              Text(teacherName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF6B7280)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
            ],
          ),
        ),
      ],
    );
  }

  void _showEditSlotDialog(TimetableSlotAdmin slot) {
    // Pre-populate with current slot data
    String selectedDay = _dayLabels[slot.dayOfWeek - 1];
    String selectedStartTime = slot.startTime.substring(0, 5);
    String selectedEndTime = slot.endTime.substring(0, 5);
    String? selectedRoomLabel = slot.room;

    // Ensure time values are in _timeSlots, fallback to closest
    if (!_timeSlots.contains(selectedStartTime)) {
      selectedStartTime = _timeSlots.first;
    }
    if (!_timeSlots.contains(selectedEndTime)) {
      selectedEndTime = _timeSlots.last;
    }

    BuildingModel? selectedBuilding;
    FloorModel? selectedFloor;
    RoomModel? selectedRoom;

    final buildingAsync = ref.read(buildingProvider);

    // Try to pre-select building, floor and room from existing slot.room
    // Supports new format "Building · Floor · Room" and legacy "Building · Room"
    buildingAsync.whenData((buildingState) {
      if (slot.room != null && slot.room!.contains(' · ')) {
        final parts = slot.room!.split(' · ');
        if (parts.length >= 3) {
          // New format: Building · Floor · Room
          try {
            selectedBuilding = buildingState.buildings.firstWhere((b) => b.name == parts[0]);
            selectedFloor = selectedBuilding!.floors.where((f) => f.isActive).firstWhere((f) => f.name == parts[1]);
            selectedRoom = selectedFloor!.rooms.where((r) => r.isActive).firstWhere((r) => r.name == parts[2]);
          } catch (_) {}
        } else {
          // Legacy format: Building · Room
          final buildingName = parts[0];
          final roomName = parts[1];
          try {
            selectedBuilding = buildingState.buildings.firstWhere((b) => b.name == buildingName);
            for (final f in selectedBuilding!.floors.where((f) => f.isActive)) {
              final match = f.rooms.where((r) => r.isActive && r.name == roomName).toList();
              if (match.isNotEmpty) { selectedFloor = f; selectedRoom = match.first; break; }
            }
          } catch (_) {}
        }
      } else if (slot.room != null && slot.room!.isNotEmpty) {
        // Legacy: just room name without building
        for (final b in buildingState.buildings) {
          for (final f in b.floors.where((f) => f.isActive)) {
            final match = f.rooms.where((r) => r.isActive && r.name == slot.room).toList();
            if (match.isNotEmpty) {
              selectedBuilding = b;
              selectedFloor = f;
              selectedRoom = match.first;
              break;
            }
          }
          if (selectedRoom != null) break;
        }
      }
    });

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Container(
                  width: 480,
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 48, offset: const Offset(0, 16)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 28, 24, 20),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.edit_outlined, color: Color(0xFF6366F1), size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Modifier le cours', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                                      const SizedBox(height: 3),
                                      Text(slot.subjectName ?? 'N/A', style: const TextStyle(fontSize: 12.5, color: Color(0xFF9CA3AF))),
                                    ],
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.pop(ctx),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(Icons.close, size: 18, color: Color(0xFFB0B8C8)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Content
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(28, 4, 28, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(width: 3, height: 15, decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(2))),
                                    const SizedBox(width: 8),
                                    const Text('PLANIFICATION', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF4B5563), letterSpacing: 0.8)),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                const Text('JOUR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9CA3AF), letterSpacing: 0.5)),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  value: selectedDay,
                                  isExpanded: true,
                                  borderRadius: BorderRadius.circular(12),
                                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF9CA3AF), size: 20),
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(Icons.calendar_today_outlined, size: 17, color: Color(0xFF9CA3AF)),
                                    filled: true, fillColor: const Color(0xFFF8F9FB),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE8EAF0))),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                  ),
                                  items: _dayLabels.take(6).map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937))))).toList(),
                                  onChanged: (v) => setDialogState(() => selectedDay = v!),
                                ),
                                const SizedBox(height: 14),
                                // HEURE DE DÉBUT + HEURE DE FIN side by side
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('HEURE DE DÉBUT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9CA3AF), letterSpacing: 0.5)),
                                          const SizedBox(height: 8),
                                          DropdownButtonFormField<String>(
                                            value: selectedStartTime,
                                            isExpanded: true,
                                            borderRadius: BorderRadius.circular(12),
                                            icon: const Icon(Icons.access_time, size: 17, color: Color(0xFF9CA3AF)),
                                            decoration: InputDecoration(
                                              prefixIcon: const Icon(Icons.schedule_outlined, size: 17, color: Color(0xFF9CA3AF)),
                                              filled: true, fillColor: const Color(0xFFF8F9FB),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE8EAF0))),
                                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                            ),
                                            items: _timeSlots.take(_timeSlots.length - 1).map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937))))).toList(),
                                            onChanged: (v) => setDialogState(() => selectedStartTime = v!),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('HEURE DE FIN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9CA3AF), letterSpacing: 0.5)),
                                          const SizedBox(height: 8),
                                          DropdownButtonFormField<String>(
                                            value: selectedEndTime,
                                            isExpanded: true,
                                            borderRadius: BorderRadius.circular(12),
                                            icon: const Icon(Icons.access_time, size: 17, color: Color(0xFF9CA3AF)),
                                            decoration: InputDecoration(
                                              prefixIcon: const Icon(Icons.schedule_outlined, size: 17, color: Color(0xFF9CA3AF)),
                                              filled: true, fillColor: const Color(0xFFF8F9FB),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE8EAF0))),
                                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                            ),
                                            items: _timeSlots.skip(1).map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937))))).toList(),
                                            onChanged: (v) => setDialogState(() => selectedEndTime = v!),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                // BLOC
                                const Text('BLOC', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9CA3AF), letterSpacing: 0.5)),
                                const SizedBox(height: 8),
                                Consumer(
                                  builder: (context, ref, _) {
                                    final buildingLive = ref.watch(buildingProvider);
                                    return buildingLive.when(
                                      loading: () => DropdownButtonFormField<BuildingModel>(
                                        value: null,
                                        decoration: InputDecoration(
                                          hintText: 'Chargement...',
                                          hintStyle: const TextStyle(color: Color(0xFFBCC3CE), fontSize: 13),
                                          prefixIcon: const Icon(Icons.apartment_outlined, size: 17, color: Color(0xFF9CA3AF)),
                                          filled: true, fillColor: const Color(0xFFF8F9FB),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE8EAF0))),
                                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE8EAF0))),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                        ),
                                        items: const [],
                                        onChanged: null,
                                      ),
                                      error: (e, _) => Text(UserFriendlyError.format(e, fallback: 'Unable to load rooms right now.'), style: const TextStyle(color: AppColors.error, fontSize: 12)),
                                      data: (buildingState) {
                                        // Auto pre-select when data arrives
                                        if (selectedBuilding == null && slot.room != null) {
                                          if (slot.room!.contains(' · ')) {
                                            final parts = slot.room!.split(' · ');
                                            try {
                                              selectedBuilding = buildingState.buildings.firstWhere((b) => b.name == parts[0]);
                                              if (parts.length >= 3) {
                                                selectedFloor = selectedBuilding!.floors.where((f) => f.isActive).firstWhere((f) => f.name == parts[1]);
                                                selectedRoom = selectedFloor!.rooms.where((r) => r.isActive).firstWhere((r) => r.name == parts[2]);
                                              } else {
                                                for (final f in selectedBuilding!.floors.where((f) => f.isActive)) {
                                                  final match = f.rooms.where((r) => r.isActive && r.name == parts[1]).toList();
                                                  if (match.isNotEmpty) { selectedFloor = f; selectedRoom = match.first; break; }
                                                }
                                              }
                                            } catch (_) {}
                                          } else {
                                            for (final b in buildingState.buildings) {
                                              for (final f in b.floors.where((f) => f.isActive)) {
                                                final match = f.rooms.where((r) => r.isActive && r.name == slot.room).toList();
                                                if (match.isNotEmpty) { selectedBuilding = b; selectedFloor = f; selectedRoom = match.first; break; }
                                              }
                                              if (selectedRoom != null) break;
                                            }
                                          }
                                        }
                                        return DropdownButtonFormField<BuildingModel>(
                                          value: selectedBuilding,
                                          isExpanded: true, menuMaxHeight: 300,
                                          borderRadius: BorderRadius.circular(12),
                                          icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF9CA3AF), size: 20),
                                          decoration: InputDecoration(
                                            hintText: 'Sélectionner un bloc',
                                            hintStyle: const TextStyle(color: Color(0xFFBCC3CE), fontSize: 13),
                                            prefixIcon: const Icon(Icons.apartment_outlined, size: 17, color: Color(0xFF9CA3AF)),
                                            filled: true, fillColor: const Color(0xFFF8F9FB),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE8EAF0))),
                                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                          ),
                                          items: buildingState.buildings.map((b) => DropdownMenuItem<BuildingModel>(
                                            value: b,
                                            child: Text(b.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937))),
                                          )).toList(),
                                          onChanged: (v) => setDialogState(() { selectedBuilding = v; selectedFloor = null; selectedRoom = null; }),
                                        );
                                      },
                                    );
                                  },
                                ),
                                const SizedBox(height: 14),
                                // ÉTAGE
                                const Text('ÉTAGE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9CA3AF), letterSpacing: 0.5)),
                                const SizedBox(height: 8),
                                Builder(
                                  builder: (context) {
                                    final floors = selectedBuilding?.floors.where((f) => f.isActive).toList() ?? [];
                                    return DropdownButtonFormField<FloorModel>(
                                      value: selectedFloor,
                                      isExpanded: true, menuMaxHeight: 300,
                                      borderRadius: BorderRadius.circular(12),
                                      icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF9CA3AF), size: 20),
                                      decoration: InputDecoration(
                                        hintText: selectedBuilding == null ? 'Sélectionnez d\'abord un bloc' : 'Sélectionner un étage',
                                        hintStyle: const TextStyle(color: Color(0xFFBCC3CE), fontSize: 13),
                                        prefixIcon: const Icon(Icons.layers_outlined, size: 17, color: Color(0xFF9CA3AF)),
                                        filled: true, fillColor: const Color(0xFFF8F9FB),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE8EAF0))),
                                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                      ),
                                      items: floors.map((f) => DropdownMenuItem<FloorModel>(
                                        value: f,
                                        child: Text(f.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937))),
                                      )).toList(),
                                      onChanged: selectedBuilding == null ? null : (v) => setDialogState(() { selectedFloor = v; selectedRoom = null; }),
                                    );
                                  },
                                ),
                                const SizedBox(height: 14),
                                // SALLE
                                const Text('SALLE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9CA3AF), letterSpacing: 0.5)),
                                const SizedBox(height: 8),
                                Builder(
                                  builder: (context) {
                                    final rooms = selectedFloor?.rooms.where((r) => r.isActive).toList() ?? [];
                                    return DropdownButtonFormField<RoomModel>(
                                      value: selectedRoom,
                                      isExpanded: true, menuMaxHeight: 300,
                                      borderRadius: BorderRadius.circular(12),
                                      icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF9CA3AF), size: 20),
                                      decoration: InputDecoration(
                                        hintText: selectedFloor == null ? 'Sélectionnez d\'abord un étage' : 'Sélectionner une salle',
                                        hintStyle: const TextStyle(color: Color(0xFFBCC3CE), fontSize: 13),
                                        prefixIcon: const Icon(Icons.meeting_room_outlined, size: 17, color: Color(0xFF9CA3AF)),
                                        filled: true, fillColor: const Color(0xFFF8F9FB),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE8EAF0))),
                                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                      ),
                                      items: rooms.map((r) => DropdownMenuItem<RoomModel>(
                                        value: r,
                                        child: Text(r.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937))),
                                      )).toList(),
                                      onChanged: selectedFloor == null ? null : (v) => setDialogState(() => selectedRoom = v),
                                    );
                                  },
                                ),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ),
                        // Footer
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(
                                height: 40,
                                child: TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF6B7280),
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                  ),
                                  child: const Text('Annuler', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                height: 40,
                                child: ElevatedButton.icon(
                                    onPressed: () async {
                                      final roomLabel = selectedRoom != null
                                          ? '${selectedBuilding?.name ?? ''} · ${selectedFloor?.name ?? ''} · ${selectedRoom!.name}'
                                          : null;
                                      final dayIndex = _dayLabels.indexOf(selectedDay) + 1;
                                      // Check room conflict before saving
                                      if (roomLabel != null) {
                                        final conflict = await _checkRoomConflict(
                                          roomLabel: roomLabel,
                                          dayOfWeek: dayIndex,
                                          startTime: selectedStartTime,
                                          endTime: selectedEndTime,
                                          excludeSlotId: slot.id,
                                        );
                                        if (conflict != null) {
                                          if (!ctx.mounted) return;
                                          final proceed = await showDialog<bool>(
                                            context: ctx,
                                            builder: (dCtx) => AlertDialog(
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                              title: Row(
                                                children: [
                                                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 22),
                                                  const SizedBox(width: 8),
                                                  const Text('Conflit de salle', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                                ],
                                              ),
                                              content: Text(conflict, style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563))),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Annuler')),
                                                TextButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Forcer', style: TextStyle(color: Colors.orange))),
                                              ],
                                            ),
                                          );
                                          if (proceed != true) return;
                                        }
                                      }
                                      if (!ctx.mounted) return;
                                      Navigator.pop(ctx);
                                      await _updateSlot(
                                        slot.id,
                                        dayIndex,
                                        selectedStartTime,
                                        selectedEndTime,
                                        roomLabel,
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF6D4CF6),
                                      foregroundColor: Colors.white,
                                      elevation: 2,
                                      padding: const EdgeInsets.symmetric(horizontal: 20),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: const Icon(Icons.check, size: 16),
                                    label: const Text('Enregistrer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
          },
        );
      },
    );
  }

  void _showDeleteSlotConfirmation(TimetableSlotAdmin slot) {
    final color = _getSubjectColor(slot.subjectCode ?? 'default');

    showDialog(
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
              const Text('Supprimer le cours ?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cette action est irréversible. Le cours sélectionné sera définitivement supprimé de l\'emploi du temps.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                      child: Center(
                        child: Text(
                          slot.subjectCode ?? '?',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(slot.subjectName ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(
                            '${_dayLabels[slot.dayOfWeek - 1]} • ${_formatTime(slot.startTime)} - ${_formatTime(slot.endTime)}${slot.room != null ? ' • ${slot.room}' : ''}',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                          ),
                        ],
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
                    Navigator.pop(ctx);
                    _deleteSlot(slot);
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Supprimer', style: TextStyle(fontWeight: FontWeight.w700)),
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

  /// Check if a room is already used at the given day/time by another slot.
  /// Returns a description of the conflict or null if no conflict.
  Future<String?> _checkRoomConflict({
    required String roomLabel,
    required int dayOfWeek,
    required String startTime,
    required String endTime,
    String? excludeSlotId,
  }) async {
    try {
      final dayEnum = _dayToEnum(dayOfWeek);
      // Query all timetable slots for the same room + day that overlap
      var query = SupabaseConfig.client
          .from('timetable_slots')
          .select('id, start_time, end_time, room, subject_offering_id, subject_offerings(subjects(name), classes(name))')
          .eq('room', roomLabel)
          .eq('day_of_week', dayEnum);

      final results = await query;
      for (final row in (results as List)) {
        if (excludeSlotId != null && row['id'] == excludeSlotId) continue;
        final existStart = (row['start_time'] as String).substring(0, 5);
        final existEnd = (row['end_time'] as String).substring(0, 5);
        // Check time overlap: new slot overlaps if newStart < existEnd AND newEnd > existStart
        if (startTime.compareTo(existEnd) < 0 && endTime.compareTo(existStart) > 0) {
          final subjectName = row['subject_offerings']?['subjects']?['name'] ?? '?';
          final className = row['subject_offerings']?['classes']?['name'] ?? '?';
          return '$roomLabel est déjà utilisée par "$subjectName" (classe $className) de $existStart à $existEnd';
        }
      }
      return null;
    } catch (e) {
      debugPrint('Room conflict check error: $e');
      return null; // Don't block on check errors
    }
  }

  Future<void> _updateSlot(
    String slotId,
    int dayOfWeek,
    String startTime,
    String endTime,
    String? room,
  ) async {
    final selectedClass = ref.read(selectedClassProvider);
    if (selectedClass != null) {
      final currentSlots = ref.read(filteredTimetableSlotsProvider(selectedClass.id)).asData?.value ?? [];
      final newStartMin = _timeToMinutes(startTime);
      final newEndMin = _timeToMinutes(endTime);

      final classConflict = currentSlots.firstWhereOrNull((s) {
        if (s.id == slotId) return false; // skip self
        if (s.dayOfWeek != dayOfWeek) return false;
        final sStart = _timeToMinutes(s.startTime);
        final sEnd = _timeToMinutes(s.endTime);
        return newStartMin < sEnd && newEndMin > sStart;
      });

      if (classConflict != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Impossible : chevauchement avec ${classConflict.subjectName ?? "un cours"} (${classConflict.startTime} - ${classConflict.endTime})'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }
    }

    try {
      await SupabaseConfig.adminClient.from('timetable_slots').update({
        'day_of_week': _dayToEnum(dayOfWeek),
        'start_time': startTime,
        'end_time': endTime,
        'room': room,
      }).eq('id', slotId);
      ref.invalidate(classTimetableSlotsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cours modifié'), backgroundColor: AppColors.success),
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

  Future<void> _deleteSlot(TimetableSlotAdmin slot) async {
    try {
      await SupabaseConfig.client
          .from('timetable_slots')
          .delete()
          .eq('id', slot.id);
      ref.invalidate(classTimetableSlotsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cours supprimé'),
            backgroundColor: AppColors.success,
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

  void _showDeleteAllDialog(ClassInfo selectedClass) {
    // Fetch classes for current niveau that have timetable slots
    _showDeleteClassesDialog(selectedClass);
  }

  void _showDeleteClassesDialog(ClassInfo selectedClass) async {
    List<ClassInfo> allClasses = [];
    try {
      final cachedClasses = ref.read(classesListProvider).asData?.value;
      List<ClassInfo> sourceClasses = [];
      if (cachedClasses != null && cachedClasses.isNotEmpty) {
        sourceClasses = cachedClasses;
      } else {
        final data = await SupabaseConfig.adminClient
            .from('classes')
            .select('id, name, niveau_id, niveaux(name, code, cycle, has_sections), sections(code)')
            .order('name');
        sourceClasses = (data as List).map((e) => ClassInfo.fromJson(e)).toList();
      }

      // Filter classes to the same niveau as selectedClass
      final targetNiveauId = selectedClass.gradeLevelId;
      final targetCode = selectedClass.gradeLevelCode?.toUpperCase();
      final targetPrefix = selectedClass.name.contains('-') ? selectedClass.name.split('-').first.trim().toUpperCase() : '';

      final classesInNiveau = sourceClasses.where((c) {
        if (targetNiveauId != null && c.gradeLevelId == targetNiveauId) return true;
        if (targetCode != null && c.gradeLevelCode?.toUpperCase() == targetCode) return true;
        if (targetPrefix.isNotEmpty && c.name.toUpperCase().startsWith(targetPrefix)) return true;
        return false;
      }).toList();

      // Check which of these classes have timetable slots
      final classIds = (classesInNiveau.isNotEmpty ? classesInNiveau : [selectedClass]).map((c) => c.id).toList();
      final offerings = await SupabaseConfig.adminClient
          .from('subject_offerings')
          .select('id, class_id')
          .inFilter('class_id', classIds);

      final offeringIds = (offerings as List).map((o) => o['id'].toString()).toList();
      final classIdsWithTimetable = <String>{};

      if (offeringIds.isNotEmpty) {
        final slots = await SupabaseConfig.adminClient
            .from('timetable_slots')
            .select('subject_offering_id')
            .inFilter('subject_offering_id', offeringIds);

        final offMap = <String, String>{};
        for (final o in offerings) {
          offMap[o['id'].toString()] = o['class_id'].toString();
        }

        for (final s in (slots as List)) {
          final cId = offMap[s['subject_offering_id']?.toString()];
          if (cId != null) classIdsWithTimetable.add(cId);
        }
      }

      allClasses = classesInNiveau
          .where((c) => classIdsWithTimetable.contains(c.id) || c.id == selectedClass.id)
          .toList();

      if (allClasses.isEmpty) {
        allClasses = classesInNiveau.isNotEmpty ? classesInNiveau : [selectedClass];
      }
    } catch (e) {
      debugPrint('Error fetching delete classes: $e');
      allClasses = [selectedClass];
    }

    if (!mounted) return;

    // Selected classes set (default: preselect selectedClass)
    final selectedClassIds = <String>{};
    if (allClasses.any((c) => c.id == selectedClass.id)) {
      selectedClassIds.add(selectedClass.id);
    } else if (allClasses.isNotEmpty) {
      selectedClassIds.add(allClasses.first.id);
    }

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final isAllSelected = allClasses.isNotEmpty && selectedClassIds.length == allClasses.length;
            final isIndeterminate = selectedClassIds.isNotEmpty && selectedClassIds.length < allClasses.length;

            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.errorSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.delete_sweep, color: AppColors.error),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Supprimer emplois du temps',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sélectionnez les classes dont vous voulez supprimer l\'emploi du temps:',
                      style: TextStyle(color: AppColors.slate700, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    // Class selection list container with master checkbox header
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: AppColors.slate200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Master Checkbox Header
                          Container(
                            decoration: const BoxDecoration(
                              color: Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(11),
                                topRight: Radius.circular(11),
                              ),
                              border: Border(bottom: BorderSide(color: AppColors.slate200)),
                            ),
                            child: CheckboxListTile(
                              value: isAllSelected ? true : (isIndeterminate ? null : false),
                              tristate: true,
                              onChanged: (val) {
                                setDialogState(() {
                                  if (isAllSelected) {
                                    selectedClassIds.clear();
                                  } else {
                                    selectedClassIds.addAll(allClasses.map((c) => c.id));
                                  }
                                });
                              },
                              title: Text(
                                'Tout sélectionner (${selectedClassIds.length}/${allClasses.length})',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                              ),
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              activeColor: AppColors.error,
                            ),
                          ),
                          // Class items
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: allClasses.length,
                              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                              itemBuilder: (context, index) {
                                final classInfo = allClasses[index];
                                final isSelected = selectedClassIds.contains(classInfo.id);
                                return CheckboxListTile(
                                  value: isSelected,
                                  onChanged: (val) {
                                    setDialogState(() {
                                      if (val == true) {
                                        selectedClassIds.add(classInfo.id);
                                      } else {
                                        selectedClassIds.remove(classInfo.id);
                                      }
                                    });
                                  },
                                  title: Text(
                                    classInfo.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${classInfo.gradeLevelCode ?? ''} ${classInfo.sectionCode ?? ''}'.trim(),
                                    style: const TextStyle(fontSize: 11, color: AppColors.slate500),
                                  ),
                                  dense: true,
                                  controlAffinity: ListTileControlAffinity.leading,
                                  activeColor: AppColors.error,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Borderless warning banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFDC2626),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Cette action est irréversible !',
                              style: TextStyle(
                                color: Color(0xFFDC2626),
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                SizedBox(
                  height: 40,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: selectedClassIds.isEmpty
                        ? null
                        : () async {
                            final classesToDelete = allClasses
                                .where((c) => selectedClassIds.contains(c.id))
                                .toList();

                            // Confirmation Popup with Blur
                            final confirmed = await showDialog<bool>(
                              context: context,
                              barrierColor: Colors.black.withOpacity(0.4),
                              builder: (confirmCtx) => BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                child: AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  backgroundColor: Colors.white,
                                  title: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF2F2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.delete_forever, color: Color(0xFFDC2626), size: 24),
                                      ),
                                      const SizedBox(width: 12),
                                      const Text('Confirmer la suppression', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  content: Text(
                                    'Êtes-vous sûr de vouloir supprimer définitivement l\'emploi du temps de ${classesToDelete.length} classe(s) ?\n\nCette action est irréversible.',
                                    style: const TextStyle(fontSize: 13, color: AppColors.slate700, height: 1.5),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(confirmCtx, false),
                                      child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(confirmCtx, true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFDC2626),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: const Text('Oui, supprimer', style: TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ),
                            );

                            if (confirmed == true && mounted) {
                              Navigator.pop(context);
                              _deleteMultipleClassSlots(classesToDelete);
                            }
                          },
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    label: Text('Supprimer (${selectedClassIds.length})'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.slate300,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _deleteMultipleClassSlots(List<ClassInfo> classes) async {
    int totalDeleted = 0;
    List<String> errors = [];

    for (final classInfo in classes) {
      try {
        // Get all subject_offering_ids for this class
        final offerings = await SupabaseConfig.client
            .from('subject_offerings')
            .select('id')
            .eq('class_id', classInfo.id);

        if ((offerings as List).isNotEmpty) {
          final offeringIds = offerings.map((o) => o['id'] as String).toList();

          // Delete only slots of the current timetable type
          await SupabaseConfig.client
              .from('timetable_slots')
              .delete()
              .inFilter('subject_offering_id', offeringIds)
              .eq('timetable_type', _timetableType);

          totalDeleted++;
        }
      } catch (e) {
        errors.add(
          '${classInfo.name}: ${UserFriendlyError.format(e, fallback: 'Unable to delete this timetable.')}',
        );
      }
    }

    ref.invalidate(classTimetableSlotsProvider);

    if (mounted) {
      if (errors.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$totalDeleted emploi(s) du temps supprimé(s)'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to update: ${errors.join(", ")}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<ExamPeriodModel?> _showExamPeriodPicker(List<ExamPeriodModel> examPeriods) async {
    return showGeneralDialog<ExamPeriodModel>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      transitionBuilder: (ctx, a1, a2, child) {
        final curve = CurvedAnimation(parent: a1, curve: Curves.easeOutCubic);
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12 * a1.value, sigmaY: 12 * a1.value),
          child: FadeTransition(
            opacity: curve,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1.0).animate(curve),
              child: child,
            ),
          ),
        );
      },
      pageBuilder: (ctx, _, __) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 400,
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 48, offset: const Offset(0, 16)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEA580C).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.school, color: Color(0xFFEA580C), size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Choisir la période d\'examen',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close, size: 20),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: examPeriods.length,
                      itemBuilder: (ctx, i) {
                        final ep = examPeriods[i];
                        final startStr = DateFormat('d MMM yyyy', 'fr_FR').format(ep.startDate);
                        final endStr = DateFormat('d MMM yyyy', 'fr_FR').format(ep.endDate);
                        return ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEA580C).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.event, color: Color(0xFFEA580C), size: 20),
                          ),
                          title: Text(ep.name ?? 'Examen', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('$startStr — $endStr', style: const TextStyle(fontSize: 12)),
                          onTap: () => Navigator.of(ctx).pop(ep),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showAddSlotDialog(
    ClassInfo selectedClass,
    List<SubjectOfferingInfo> offerings,
  ) {
    _showAddSlotDialogForCell(selectedClass, offerings, 1, '08:00');
  }

  void _showAddSlotDialogForCell(
    ClassInfo selectedClass,
    List<SubjectOfferingInfo> offerings,
    int dayOfWeek,
    String startTime,
  ) {
    if (offerings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aucune matière configurée pour cette classe. Configurez d\'abord les offres de matières.',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    // Get scheduled hours for offerings
    final scheduledHoursAsync = ref.read(
      scheduledHoursPerOfferingProvider(selectedClass.id),
    );
    final scheduledHours = scheduledHoursAsync.asData?.value ?? {};

    SubjectOfferingInfo? selectedOffering = offerings.isNotEmpty
        ? offerings.first
        : null;
    String selectedDay = _dayLabels[dayOfWeek - 1];
    String selectedStartTime = startTime;
    String selectedEndTime = _getNextTimeSlot(startTime, 4);
    BuildingModel? selectedBuilding;
    FloorModel? selectedFloor;
    RoomModel? selectedRoom;

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        return Consumer(
          builder: (ctx, ref, child) {
            final buildingAsync = ref.watch(buildingProvider);

            return StatefulBuilder(
              builder: (ctx, setDialogState) {
                double expectedHours = 0;
                double scheduledHoursForOffering = 0;
                double newSlotDuration = 0;
                double remainingHours = 0;

                if (selectedOffering != null) {
                  expectedHours = selectedOffering!.weeklyCiHours + selectedOffering!.weeklyTpHours;
                  scheduledHoursForOffering = scheduledHours[selectedOffering!.id] ?? 0;
                  final startParts = selectedStartTime.split(':').map(int.parse).toList();
                  final endParts = selectedEndTime.split(':').map(int.parse).toList();
                  final startMin = startParts[0] * 60 + (startParts.length > 1 ? startParts[1] : 0);
                  final endMin = endParts[0] * 60 + (endParts.length > 1 ? endParts[1] : 0);
                  newSlotDuration = (endMin - startMin) / 60.0;
                  remainingHours = expectedHours - scheduledHoursForOffering - newSlotDuration;
                }

                return BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Dialog(
                    backgroundColor: Colors.transparent,
                    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Container(
                      width: 520,
                      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.92),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 48, offset: const Offset(0, 16)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ═══ HEADER ═══
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 28, 24, 20),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.add, color: Color(0xFF6366F1), size: 22),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Ajouter un cours', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                                      const SizedBox(height: 3),
                                      const Text('Configurez une nouvelle session académique', style: TextStyle(fontSize: 12.5, color: Color(0xFF9CA3AF))),
                                    ],
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.pop(ctx),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(Icons.close, size: 18, color: Color(0xFFB0B8C8)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ═══ CONTENT ═══
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(28, 4, 28, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── DÉTAILS DU COURS ──
                                Row(
                                  children: [
                                    Container(width: 3, height: 15, decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(2))),
                                    const SizedBox(width: 8),
                                    const Text('DÉTAILS DU COURS', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF4B5563), letterSpacing: 0.8)),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                // MATIÈRE – full width
                                const Text('MATIÈRE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9CA3AF), letterSpacing: 0.5)),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<SubjectOfferingInfo>(
                                  value: selectedOffering,
                                  isExpanded: true,
                                  menuMaxHeight: 300,
                                  borderRadius: BorderRadius.circular(12),
                                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF9CA3AF), size: 20),
                                  decoration: InputDecoration(
                                    hintText: 'Sélectionner la matière',
                                    hintStyle: const TextStyle(color: Color(0xFFBCC3CE), fontSize: 13),
                                    prefixIcon: const Icon(Icons.book_outlined, size: 18, color: Color(0xFF9CA3AF)),
                                    filled: true, fillColor: const Color(0xFFF8F9FB),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE8EAF0))),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                  ),
                                  items: offerings.map((o) => DropdownMenuItem<SubjectOfferingInfo>(
                                    value: o,
                                    child: Text('${o.subjectCode ?? ''} - ${o.subjectName}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937))),
                                  )).toList(),
                                  onChanged: (v) => setDialogState(() => selectedOffering = v),
                                ),
                                const SizedBox(height: 24),
                                // ── PLANIFICATION ──
                                Row(
                                  children: [
                                    Container(width: 3, height: 15, decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(2))),
                                    const SizedBox(width: 8),
                                    const Text('PLANIFICATION', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF4B5563), letterSpacing: 0.8)),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                // JOUR
                                const Text('JOUR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9CA3AF), letterSpacing: 0.5)),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  value: selectedDay,
                                  isExpanded: true,
                                  borderRadius: BorderRadius.circular(12),
                                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF9CA3AF), size: 20),
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(Icons.calendar_today_outlined, size: 17, color: Color(0xFF9CA3AF)),
                                    filled: true, fillColor: const Color(0xFFF8F9FB),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE8EAF0))),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                  ),
                                  items: _dayLabels.take(6).map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937))))).toList(),
                                  onChanged: (v) => setDialogState(() => selectedDay = v!),
                                ),
                                const SizedBox(height: 14),
                                // HEURE DE DÉBUT + HEURE DE FIN side by side
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('HEURE DE DÉBUT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9CA3AF), letterSpacing: 0.5)),
                                          const SizedBox(height: 8),
                                          DropdownButtonFormField<String>(
                                            value: selectedStartTime,
                                            isExpanded: true,
                                            borderRadius: BorderRadius.circular(12),
                                            icon: const Icon(Icons.access_time, size: 17, color: Color(0xFF9CA3AF)),
                                            decoration: InputDecoration(
                                              prefixIcon: const Icon(Icons.schedule_outlined, size: 17, color: Color(0xFF9CA3AF)),
                                              filled: true, fillColor: const Color(0xFFF8F9FB),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE8EAF0))),
                                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                            ),
                                            items: _timeSlots.take(_timeSlots.length - 1).map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937))))).toList(),
                                            onChanged: (v) => setDialogState(() {
                                              selectedStartTime = v!;
                                              selectedEndTime = _getNextTimeSlot(v, 4);
                                            }),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('HEURE DE FIN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9CA3AF), letterSpacing: 0.5)),
                                          const SizedBox(height: 8),
                                          DropdownButtonFormField<String>(
                                            value: selectedEndTime,
                                            isExpanded: true,
                                            borderRadius: BorderRadius.circular(12),
                                            icon: const Icon(Icons.access_time, size: 17, color: Color(0xFF9CA3AF)),
                                            decoration: InputDecoration(
                                              prefixIcon: const Icon(Icons.schedule_outlined, size: 17, color: Color(0xFF9CA3AF)),
                                              filled: true, fillColor: const Color(0xFFF8F9FB),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE8EAF0))),
                                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                            ),
                                            items: _timeSlots.skip(1).map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937))))).toList(),
                                            onChanged: (v) => setDialogState(() => selectedEndTime = v!),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                // BLOC
                                const Text('BLOC', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9CA3AF), letterSpacing: 0.5)),
                                const SizedBox(height: 8),
                                buildingAsync.when(
                                  loading: () => DropdownButtonFormField<BuildingModel>(
                                    value: null,
                                    decoration: InputDecoration(
                                      hintText: 'Chargement...',
                                      hintStyle: const TextStyle(color: Color(0xFFBCC3CE), fontSize: 13),
                                      prefixIcon: const Icon(Icons.apartment_outlined, size: 17, color: Color(0xFF9CA3AF)),
                                      filled: true, fillColor: const Color(0xFFF8F9FB),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE8EAF0))),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE8EAF0))),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                    ),
                                    items: const [],
                                    onChanged: null,
                                  ),
                                  error: (e, _) => Text(UserFriendlyError.format(e, fallback: 'Unable to load rooms right now.'), style: const TextStyle(color: AppColors.error, fontSize: 12)),
                                  data: (buildingState) {
                                    final buildings = buildingState.buildings;
                                    return DropdownButtonFormField<BuildingModel>(
                                      value: selectedBuilding,
                                      isExpanded: true, menuMaxHeight: 300,
                                      borderRadius: BorderRadius.circular(12),
                                      icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF9CA3AF), size: 20),
                                      decoration: InputDecoration(
                                        hintText: 'Sélectionner un bloc',
                                        hintStyle: const TextStyle(color: Color(0xFFBCC3CE), fontSize: 13),
                                        prefixIcon: const Icon(Icons.apartment_outlined, size: 17, color: Color(0xFF9CA3AF)),
                                        filled: true, fillColor: const Color(0xFFF8F9FB),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE8EAF0))),
                                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                      ),
                                      items: buildings.map((b) => DropdownMenuItem<BuildingModel>(
                                        value: b,
                                        child: Text(b.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937))),
                                      )).toList(),
                                      onChanged: (v) => setDialogState(() {
                                        selectedBuilding = v;
                                        selectedFloor = null;
                                        selectedRoom = null;
                                      }),
                                    );
                                  },
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // ÉTAGE
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('ÉTAGE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9CA3AF), letterSpacing: 0.5)),
                                          const SizedBox(height: 8),
                                          Builder(
                                            builder: (context) {
                                              final floors = selectedBuilding?.floors.where((f) => f.isActive).toList() ?? [];
                                              return DropdownButtonFormField<FloorModel>(
                                                value: selectedFloor,
                                                isExpanded: true, menuMaxHeight: 300,
                                                borderRadius: BorderRadius.circular(12),
                                                icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF9CA3AF), size: 20),
                                                decoration: InputDecoration(
                                                  hintText: selectedBuilding == null ? 'Choisir bloc' : 'Sélectionner un étage',
                                                  hintStyle: const TextStyle(color: Color(0xFFBCC3CE), fontSize: 13),
                                                  prefixIcon: const Icon(Icons.layers_outlined, size: 17, color: Color(0xFF9CA3AF)),
                                                  filled: true, fillColor: const Color(0xFFF8F9FB),
                                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE8EAF0))),
                                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
                                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                                ),
                                                items: floors.map((f) => DropdownMenuItem<FloorModel>(
                                                  value: f,
                                                  child: Text(f.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937))),
                                                )).toList(),
                                                onChanged: selectedBuilding == null ? null : (v) => setDialogState(() { selectedFloor = v; selectedRoom = null; }),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    // SALLE
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('SALLE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9CA3AF), letterSpacing: 0.5)),
                                          const SizedBox(height: 8),
                                          Builder(
                                            builder: (context) {
                                              final rooms = selectedFloor?.rooms.where((r) => r.isActive).toList() ?? [];
                                              return DropdownButtonFormField<RoomModel>(
                                                value: selectedRoom,
                                                isExpanded: true, menuMaxHeight: 300,
                                                borderRadius: BorderRadius.circular(12),
                                                icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF9CA3AF), size: 20),
                                                decoration: InputDecoration(
                                                  hintText: selectedFloor == null ? 'Choisir étage' : 'Sélectionner une salle',
                                                  hintStyle: const TextStyle(color: Color(0xFFBCC3CE), fontSize: 13),
                                                  prefixIcon: const Icon(Icons.meeting_room_outlined, size: 17, color: Color(0xFF9CA3AF)),
                                                  filled: true, fillColor: const Color(0xFFF8F9FB),
                                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE8EAF0))),
                                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
                                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                                ),
                                                items: rooms.map((r) => DropdownMenuItem<RoomModel>(
                                                  value: r,
                                                  child: Text(r.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937))),
                                                )).toList(),
                                                onChanged: selectedFloor == null ? null : (v) => setDialogState(() => selectedRoom = v),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ),
                        // ═══ FOOTER ═══
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(
                                height: 40,
                                child: TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF6B7280),
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                  ),
                                  child: const Text('Annuler', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                height: 40,
                                child: ElevatedButton.icon(
                                    onPressed: selectedOffering == null ? null : () async {
                                      final roomLabel = selectedRoom != null
                                          ? '${selectedBuilding?.name ?? ''} · ${selectedFloor?.name ?? ''} · ${selectedRoom!.name}'
                                          : null;
                                      final dayIndex = _dayLabels.indexOf(selectedDay) + 1;
                                      // Check room conflict before creating
                                      if (roomLabel != null) {
                                        final conflict = await _checkRoomConflict(
                                          roomLabel: roomLabel,
                                          dayOfWeek: dayIndex,
                                          startTime: selectedStartTime,
                                          endTime: selectedEndTime,
                                        );
                                        if (conflict != null) {
                                          if (!ctx.mounted) return;
                                          final proceed = await showDialog<bool>(
                                            context: ctx,
                                            builder: (dCtx) => AlertDialog(
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                              title: Row(
                                                children: [
                                                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 22),
                                                  const SizedBox(width: 8),
                                                  const Text('Conflit de salle', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                                ],
                                              ),
                                              content: Text(conflict, style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563))),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Annuler')),
                                                TextButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Forcer', style: TextStyle(color: Colors.orange))),
                                              ],
                                            ),
                                          );
                                          if (proceed != true) return;
                                        }
                                      }
                                      if (!ctx.mounted) return;
                                      Navigator.pop(ctx);
                                      await _createSlot(
                                        selectedOffering!.id,
                                        dayIndex,
                                        selectedStartTime,
                                        selectedEndTime,
                                        roomLabel,
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF6D4CF6),
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor: const Color(0xFFD1D5DB),
                                      elevation: 2,
                                      padding: const EdgeInsets.symmetric(horizontal: 20),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: const Icon(Icons.check, size: 16),
                                    label: const Text('Créer le cours', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
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
          },
        );
      },
    );
  },
);
  }

  // Helper widget for hours chip
  Widget _buildHoursChip(
    String label, 
    double hours, 
    Color color,
    {bool isLabel = false}
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: isLabel 
        ? Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${hours.toStringAsFixed(0)}h',
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
    );
  }

  String _getNextTimeSlot(String time, int slotsAhead) {
    // With 30-min increments, 2 slotsAhead = 1 hour, 3 = 1.5h, 4 = 2h
    final index = _timeSlots.indexOf(time);
    if (index >= 0 && index + slotsAhead < _timeSlots.length) {
      return _timeSlots[index + slotsAhead];
    }
    return _timeSlots.last;
  }

  // Convert day integer to day_of_week enum string for database
  String _dayToEnum(int day) {
    switch (day) {
      case 1:
        return 'monday';
      case 2:
        return 'tuesday';
      case 3:
        return 'wednesday';
      case 4:
        return 'thursday';
      case 5:
        return 'friday';
      case 6:
        return 'saturday';
      case 7:
        return 'sunday';
      default:
        return 'monday';
    }
  }

  Future<void> _createSlot(
    String subjectOfferingId,
    int dayOfWeek,
    String startTime,
    String endTime,
    String? room,
  ) async {
    final selectedClass = ref.read(selectedClassProvider);
    if (selectedClass != null) {
      final currentSlots = ref.read(filteredTimetableSlotsProvider(selectedClass.id)).asData?.value ?? [];
      final newStartMin = _timeToMinutes(startTime);
      final newEndMin = _timeToMinutes(endTime);

      final classConflict = currentSlots.firstWhereOrNull((s) {
        if (s.dayOfWeek != dayOfWeek) return false;
        final sStart = _timeToMinutes(s.startTime);
        final sEnd = _timeToMinutes(s.endTime);
        return newStartMin < sEnd && newEndMin > sStart;
      });

      if (classConflict != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Impossible : ${classConflict.subjectName ?? "Un cours"} est déjà planifié (${classConflict.startTime} - ${classConflict.endTime}) pour cette classe.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }
    }

    try {
      final data = <String, dynamic>{
        'subject_offering_id': subjectOfferingId,
        'day_of_week': _dayToEnum(dayOfWeek),
        'start_time': startTime,
        'end_time': endTime,
        'room': room,
        'timetable_type': _timetableType,
      };
      if (_timetableType == 'exam' && _selectedExamPeriodId != null) {
        data['exam_period_id'] = _selectedExamPeriodId;
      }
      await SupabaseConfig.adminClient.from('timetable_slots').insert(data);
      ref.invalidate(classTimetableSlotsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_timetableType == 'exam' ? 'Cours d\'examen ajouté' : 'Cours ajouté'),
            backgroundColor: AppColors.success,
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

  void _showSuggestedSubjects(ClassInfo selectedClass) {
    // Get suggested subjects based on niveau (grade level code)
    List<SubjectCoefficient> suggested = [];
    final code = selectedClass.gradeLevelCode?.toUpperCase() ?? '';

    if (code.contains('7') || code.contains('8') || code.contains('9')) {
      suggested = TunisianCoefficientTables.collegeSubjects;
    } else if (code.contains('1') &&
        (code.contains('S') || code.contains('L'))) {
      suggested = TunisianCoefficientTables.lycee1Subjects;
    } else if (code.contains('2')) {
      if (code.contains('M') || code.contains('MATH')) {
        suggested = TunisianCoefficientTables.lycee2MathSubjects;
      } else if (code.contains('SC') || code.contains('EXP')) {
        suggested = TunisianCoefficientTables.lycee2SciencesSubjects;
      } else if (code.contains('T') || code.contains('TECH')) {
        suggested = TunisianCoefficientTables.lycee2TechSubjects;
      } else if (code.contains('E') || code.contains('ECO')) {
        suggested = TunisianCoefficientTables.lycee2EcoSubjects;
      } else if (code.contains('L') || code.contains('LET')) {
        suggested = TunisianCoefficientTables.lycee2LettresSubjects;
      } else {
        suggested = TunisianCoefficientTables.lycee1Subjects;
      }
    } else {
      suggested = TunisianCoefficientTables.collegeSubjects;
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (ctx, a1, a2, child) {
        final curve = CurvedAnimation(parent: a1, curve: Curves.easeOutCubic);
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16 * a1.value, sigmaY: 16 * a1.value),
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
            child: Container(
              width: 480,
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 48, offset: const Offset(0, 16)),
                  BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.08), blurRadius: 80, offset: const Offset(0, -8)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ══ HEADER ══
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(28, 24, 20, 20),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F5))),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Matières suggérées', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEEF2FF),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        selectedClass.gradeLevelCode ?? 'N/A',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6366F1)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${suggested.length} matière${suggested.length > 1 ? 's' : ''}',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.close, size: 16, color: Color(0xFFB0B8C8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ══ SUBJECT LIST ══
                    Flexible(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                        itemCount: suggested.length,
                        itemBuilder: (context, index) {
                          final subject = suggested[index];
                          final color = _getSubjectColor(subject.subjectCode);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFF3F4F6), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.015),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40, height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    subject.subjectCode,
                                    style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        subject.subjectName,
                                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF1F2937)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 5),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF3F4F6),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Coef: ${subject.coefficient}',
                                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)),
                                            ),
                                          ),
                                          if (subject.hasPractical) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFDEF7EC),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text('TP', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF03543F))),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    // ══ FOOTER ══
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(top: BorderSide(color: Color(0xFFF0F0F5))),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(ctx),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFFE8EAF0)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Fermer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: SizedBox(
                              height: 44,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  await _createSubjectOfferingsForClass(selectedClass, suggested);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6366F1),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  shadowColor: const Color(0xFF6366F1).withOpacity(0.3),
                                ),
                                icon: const Icon(Icons.add_circle_outline, size: 17),
                                label: const Text('Créer toutes les matières', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
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
          ),
        );
      },
    );
  }

  Future<void> _createSubjectOfferingsForClass(
    ClassInfo selectedClass,
    List<SubjectCoefficient> suggested,
  ) async {
    try {
      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                IosLoader.small(color: Colors.white),
                SizedBox(width: 12),
                Text('Création des matières en cours...'),
              ],
            ),
            duration: Duration(seconds: 30),
          ),
        );
      }

      // Get user's school_id and current semester
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) throw Exception('Non connecté');

      final profile = await SupabaseConfig.client
          .from('users')
          .select('school_id')
          .eq('id', user.id)
          .single();
      final schoolId = profile['school_id'];

      // Get current academic year - first try is_current=true, then fallback to most recent
      var years = await SupabaseConfig.client
          .from('academic_years')
          .select('id')
          .eq('school_id', schoolId)
          .eq('is_current', true)
          .limit(1);

      if ((years as List).isEmpty) {
        // Fallback: get the most recent academic year by start_date
        years = await SupabaseConfig.client
            .from('academic_years')
            .select('id')
            .eq('school_id', schoolId)
            .order('start_date', ascending: false)
            .limit(1);
      }

      if ((years as List).isEmpty) {
        throw Exception(
          'Aucune année académique trouvée. Veuillez créer une année académique.',
        );
      }
      final yearId = years[0]['id'];

      // Get semesters for this year
      final semesters = await SupabaseConfig.client
          .from('semesters')
          .select('id, number')
          .eq('academic_year_id', yearId)
          .order('number');

      if ((semesters as List).isEmpty) {
        throw Exception('Aucun semestre configuré');
      }

      // Get existing subjects in the database (by code AND name for matching)
      final existingSubjects = await SupabaseConfig.client
          .from('subjects')
          .select('id, code, name, normalized_name')
          .eq('school_id', schoolId);

      final subjectsByCode = <String, String>{};
      final subjectsByNormalizedName = <String, String>{};
      for (final s in (existingSubjects as List)) {
        subjectsByCode[s['code'].toString().toUpperCase()] = s['id'];
        // Also index by normalized name (lowercase, trimmed)
        final normalizedName =
            (s['normalized_name'] ??
                s['name']?.toString().toLowerCase().trim()) ??
            '';
        if (normalizedName.isNotEmpty) {
          subjectsByNormalizedName[normalizedName] = s['id'];
        }
      }

      // Create missing subjects (check both code and normalized name)
      final subjectsToCreate = <Map<String, dynamic>>[];
      for (final s in suggested) {
        final codeUpper = s.subjectCode.toUpperCase();
        final normalizedName = s.subjectName.toLowerCase().trim();

        // Skip if we already have this subject by code or name
        if (subjectsByCode.containsKey(codeUpper)) continue;
        if (subjectsByNormalizedName.containsKey(normalizedName)) {
          // Map the code to the existing subject ID
          subjectsByCode[codeUpper] = subjectsByNormalizedName[normalizedName]!;
          continue;
        }

        subjectsToCreate.add({
          'school_id': schoolId,
          'code': s.subjectCode,
          'name': s.subjectName,
          'name_ar': s.subjectName,
          'is_active': true,
        });
      }

      if (subjectsToCreate.isNotEmpty) {
        try {
          final created = await SupabaseConfig.client
              .from('subjects')
              .insert(subjectsToCreate)
              .select('id, code');
          for (final s in (created as List)) {
            subjectsByCode[s['code'].toString().toUpperCase()] = s['id'];
          }
        } catch (e) {
          // If insert fails due to duplicates, re-fetch subjects
          debugPrint('Subject insert failed (likely duplicates): $e');
          final refreshedSubjects = await SupabaseConfig.client
              .from('subjects')
              .select('id, code')
              .eq('school_id', schoolId);
          for (final s in (refreshedSubjects as List)) {
            subjectsByCode[s['code'].toString().toUpperCase()] = s['id'];
          }
        }
      }

      // Get existing offerings for this class
      final existingOfferings = await SupabaseConfig.client
          .from('subject_offerings')
          .select('semester_id, subject_id')
          .eq('class_id', selectedClass.id);

      final existingKeys = <String>{};
      for (final o in (existingOfferings as List)) {
        existingKeys.add('${o['semester_id']}_${o['subject_id']}');
      }

      // Create subject_offerings for each semester
      int totalCreated = 0;
      for (final semester in semesters) {
        final offeringsToCreate = <Map<String, dynamic>>[];

        for (final s in suggested) {
          final subjectId = subjectsByCode[s.subjectCode.toUpperCase()];
          if (subjectId != null) {
            // Skip if already exists
            final key = '${semester['id']}_$subjectId';
            if (existingKeys.contains(key)) continue;

            offeringsToCreate.add({
              'semester_id': semester['id'],
              'class_id': selectedClass.id,
              'subject_id': subjectId,
              'coefficient': s.coefficient,
              'total_hours': 28,
              'weekly_ci_hours': s.hasPractical ? 1.5 : 2.0,
              'weekly_tp_hours': s.hasPractical ? 0.5 : 0.0,
              'weeks': 14,
              'is_active': true,
            });
          }
        }

        if (offeringsToCreate.isNotEmpty) {
          await SupabaseConfig.client
              .from('subject_offerings')
              .insert(offeringsToCreate);
          totalCreated += offeringsToCreate.length;
        }
      }

      // Clear snackbar and show success
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$totalCreated offres de matières créées pour ${semesters.length} semestre(s)',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }

      // Refresh the offerings list
      final semesterId = ref.read(currentSemesterIdProvider);
      ref.invalidate(
        classSubjectOfferingsProvider((selectedClass.id, semesterId)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFriendlyError.format(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showBulkUploadDialog(
    ClassInfo selectedClass,
    List<SubjectOfferingInfo> offerings,
  ) async {
    final csvController = TextEditingController();
    List<Map<String, dynamic>> parsedRows = [];
    String? parseError;
    bool isUploading = false;

    // Fetch semesters, subjects, and rooms directly from database
    List<Map<String, dynamic>> semesters = [];
    List<Map<String, dynamic>> allSubjects = [];
    List<Map<String, dynamic>> allRooms = [];
    String? selectedSemesterId;

    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        final profile = await SupabaseConfig.client
            .from('users')
            .select('school_id')
            .eq('id', user.id)
            .single();

        // Fetch semesters
        final semData = await SupabaseConfig.client
            .from('semesters')
            .select('id, name, number, is_current')
            .eq('school_id', profile['school_id'])
            .order('number');

        semesters = List<Map<String, dynamic>>.from(semData);

      final activeViewSemId = ref.read(effectiveSemesterIdProvider) ?? ref.read(currentActiveSemesterIdProvider);
      selectedSemesterId = activeViewSemId;
      if (selectedSemesterId == null) {
        final current = semesters
            .where((s) => s['is_current'] == true)
            .firstOrNull;
        selectedSemesterId =
            current?['id'] ??
            (semesters.isNotEmpty ? semesters.first['id'] : null);
      }

        // Fetch all subjects
        final subData = await SupabaseConfig.client
            .from('subjects')
            .select('id, code, name')
            .eq('school_id', profile['school_id'])
            .order('code');

        allSubjects = List<Map<String, dynamic>>.from(subData);

        // Fetch all rooms
        final roomData = await SupabaseConfig.client
            .from('rooms')
            .select('id, name, room_type')
            .order('name');

        allRooms = List<Map<String, dynamic>>.from(roomData);
      }
    } catch (e) {
      debugPrint('Error fetching data: $e');
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final hasFile = parsedRows.isNotEmpty;
            final fileName = hasFile ? 'Données chargées (${parsedRows.length} lignes)' : 'Aucun fichier prêt';
            final fileSub = hasFile ? 'PRÊT POUR L\'IMPORTATION' : 'SÉLECTIONNEZ UN DOCUMENT';

            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 800,
                  maxHeight: MediaQuery.of(context).size.height * 0.88,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- Header ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF3F0FF),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.description, color: Color(0xFF6D4CF6), size: 24),
                                    ),
                                    const SizedBox(width: 16),
                                    const Text(
                                      'Importation en masse',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1E1E1E),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Ajoutez rapidement vos cours. Suivez les étapes pour garantir la qualité de vos\ndonnées.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF6B7280),
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close, color: Color(0xFF9CA3AF)),
                            splashRadius: 24,
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // --- Body ---
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Left Column: Step 1
                            Expanded(
                              flex: 4,
                              child: Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFAFAFD),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFE5E7EB)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              width: 32,
                                              height: 32,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF6D4CF6),
                                                shape: BoxShape.circle,
                                              ),
                                              alignment: Alignment.center,
                                              child: const Text('1', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                            ),
                                            const SizedBox(width: 16),
                                            const Expanded(
                                              child: Text(
                                                'Télécharger le\nmodèle',
                                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E1E1E)),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        const Text(
                                          'Téléchargez notre fichier structuré pour vous assurer que les colonnes sont correctement nommées et prêtes à l\'importation.',
                                          style: TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.5),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          // Generate CSV template and trigger download
                                          final csv = StringBuffer();
                                          csv.writeln('Matiere,Jour (1-6),Debut (HH:MM),Fin (HH:MM),Salle (optionnel)');
                                          csv.writeln('MATH,1,08:00,09:30,Salle 1');
                                          csv.writeln('FRANCAIS,2,08:00,09:30,Salle 2');
                                          csv.writeln('PHYS,3,10:00,11:30,Labo 5');
                                          final bytes = utf8.encode(csv.toString());
                                          final blob = [bytes];
                                          final url = html.Url.createObjectUrlFromBlob(html.Blob(blob, 'text/csv'));
                                          html.AnchorElement(href: url)
                                            ..setAttribute('download', 'emploi_modele.csv')
                                            ..click();
                                          html.Url.revokeObjectUrl(url);
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Modèle CSV téléchargé'), backgroundColor: AppColors.success),
                                            );
                                          }
                                        },
                                        icon: const Icon(Icons.download, size: 18, color: Colors.white),
                                        label: const Text('Télécharger .CSV'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF6D4CF6),
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(vertical: 16),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),

                            // Right Column: Step 2
                            Expanded(
                              flex: 6,
                              child: Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFAFAFD),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFF6D4CF6).withOpacity(0.3), width: 1.5),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFF3F0FF),
                                            shape: BoxShape.circle,
                                          ),
                                          alignment: Alignment.center,
                                          child: const Text('2', style: TextStyle(color: Color(0xFF6D4CF6), fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 16),
                                        const Text(
                                          'Téléverser le fichier',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E1E1E)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFF3F0FF),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.cloud_upload, color: Color(0xFF6D4CF6), size: 32),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Glissez votre fichier ici',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E1E1E)),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Formats : .csv, .txt (Max 10 Mo)',
                                      style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                                    ),
                                    const SizedBox(height: 16),
                                    OutlinedButton(
                                      onPressed: () async {
                                        try {
                                          final result = await FilePicker.platform.pickFiles(
                                            type: FileType.custom,
                                            allowedExtensions: ['csv', 'txt'],
                                            withData: true,
                                          );
                                          if (result != null && result.files.single.bytes != null) {
                                            final content = utf8.decode(result.files.single.bytes!);
                                            final parseResult = _parseCSV(content, offerings);
                                            setDialogState(() {
                                              parsedRows = parseResult['rows'] as List<Map<String, dynamic>>;
                                              parseError = parseResult['error'] as String?;
                                            });
                                          }
                                        } catch (e) {
                                          setDialogState(() {
                                            parseError = UserFriendlyError.format(
                                              e,
                                              fallback: 'Unable to read the selected file. Please verify the file and try again.',
                                            );
                                          });
                                        }
                                      },
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF1E1E1E),
                                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: const Text('Parcourir les fichiers', style: TextStyle(fontWeight: FontWeight.w600)),
                                    ),
                                    if (parseError != null) ...[
                                      const SizedBox(height: 12),
                                      Text(parseError!, style: const TextStyle(color: Colors.red, fontSize: 12), textAlign: TextAlign.center),
                                    ]
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      const SizedBox(height: 24),

                      // Footer
                      Row(
                        children: [
                          // File status
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9FAFB),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: const Icon(Icons.description_outlined, color: Color(0xFF9CA3AF), size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fileName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: hasFile ? const Color(0xFF1E1E1E) : const Color(0xFF9CA3AF),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  fileSub,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: hasFile ? const Color(0xFF10B981) : const Color(0xFF9CA3AF),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          // Action buttons
                          SizedBox(
                            height: 40,
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF6B7280),
                                side: const BorderSide(color: Color(0xFFD1D5DB)),
                                backgroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            height: 40,
                            child: ElevatedButton(
                              onPressed: (parsedRows.isEmpty || isUploading || parseError != null || selectedSemesterId == null)
                                  ? null
                                  : () async {
                                      setDialogState(() => isUploading = true);
                                      try {
                                        await _bulkCreateSlots(parsedRows, selectedClass.id, selectedSemesterId!);
                                        if (context.mounted) Navigator.pop(context);
                                      } catch (e) {
                                        debugPrint('Import error: $e');
                                        setDialogState(() => isUploading = false);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                UserFriendlyError.format(
                                                  e,
                                                  fallback: 'Unable to import timetable entries right now. Please try again.',
                                                ),
                                              ),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6D4CF6),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: const Color(0xFFC4B5FD),
                                disabledForegroundColor: Colors.white,
                                elevation: 2,
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                shadowColor: const Color(0xFF6D4CF6).withOpacity(0.3),
                              ),
                              child: isUploading
                                  ? const IosLoader.small(color: Colors.white)
                                  : const Text('Lancer l\'importation', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Map<String, dynamic> _parseCSV(
    String csv,
    List<SubjectOfferingInfo> offerings,
  ) {
    final rows = <Map<String, dynamic>>[];
    final lines = csv
        .replaceAll('\r', '')
        .trim()
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return {'rows': rows, 'error': 'Aucune donnée'};
    }

    int startIndex = 0;
    // Skip header row if present
    final firstParts = lines[0].split(',').map((p) => p.trim()).toList();
    if (firstParts.isNotEmpty) {
      final firstCol = firstParts[0].toLowerCase();
      final secondCol = firstParts.length > 1 ? firstParts[1] : '';
      if (firstCol.contains('mati') ||
          firstCol.contains('subject') ||
          int.tryParse(secondCol) == null) {
        startIndex = 1;
      }
    }

    for (int i = startIndex; i < lines.length; i++) {
      final line = lines[i].trim();
      final parts = line.split(',').map((p) => p.trim()).toList();

      if (parts.length < 4) {
        return {
          'rows': <Map<String, dynamic>>[],
          'error': 'Ligne ${i + 1}: format invalide (4 colonnes minimum)',
        };
      }

      final subjectCode = parts[0].toUpperCase();
      final dayStr = parts[1];
      final start = parts[2];
      final end = parts[3];
      final room = parts.length > 4 ? parts[4] : null;

      // Find matching offering (if exists)
      final offering = offerings.firstWhere(
        (o) =>
            o.subjectCode?.toUpperCase() == subjectCode ||
            o.subjectName.toUpperCase() == subjectCode,
        orElse: () => SubjectOfferingInfo(
          id: '',
          subjectName: subjectCode,
          subjectCode: subjectCode,
        ),
      );

      final day = int.tryParse(dayStr);
      if (day == null || day < 1 || day > 6) {
        return {
          'rows': <Map<String, dynamic>>[],
          'error': 'Ligne ${i + 1}: jour invalide "$dayStr" (1-6)',
        };
      }

      // Validate time format
      if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(start)) {
        return {
          'rows': <Map<String, dynamic>>[],
          'error': 'Ligne ${i + 1}: heure début invalide "$start"',
        };
      }
      if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(end)) {
        return {
          'rows': <Map<String, dynamic>>[],
          'error': 'Ligne ${i + 1}: heure fin invalide "$end"',
        };
      }

      // Check for overlap within the CSV rows themselves
      final currentStartMin = _timeToMinutes(start);
      final currentEndMin = _timeToMinutes(end);
      for (final existingRow in rows) {
        if (existingRow['day'] == day) {
          final existStartMin = _timeToMinutes(existingRow['start'] as String);
          final existEndMin = _timeToMinutes(existingRow['end'] as String);
          if (currentStartMin < existEndMin && currentEndMin > existStartMin) {
            return {
              'rows': <Map<String, dynamic>>[],
              'error': 'Conflit dans le CSV (Ligne ${i + 1}) : chevauchement d\'horaire le même jour (Jour $dayStr) entre $start-$end et ${existingRow['start']}-${existingRow['end']}',
            };
          }
        }
      }

      rows.add({
        'offering_id': offering.id.isNotEmpty ? offering.id : null,
        'subject_code': subjectCode,
        'subject_name': offering.subjectName.isNotEmpty
            ? offering.subjectName
            : subjectCode,
        'day': day,
        'start': start,
        'end': end,
        'room': (room == null || room.isEmpty) ? null : room,
      });
    }

    return {'rows': rows, 'error': null};
  }

  Future<void> _bulkCreateSlots(
    List<Map<String, dynamic>> rows,
    String classId,
    String semesterId,
  ) async {
    try {
      // Get unique subject codes that need offerings
      final subjectCodesToCreate = rows
          .where((r) => r['offering_id'] == null)
          .map((r) => r['subject_code'] as String)
          .toSet()
          .toList();

      // Create subject_offerings for missing subjects
      if (subjectCodesToCreate.isNotEmpty) {
        // Find subject IDs by code or name
        final subjectsData = await SupabaseConfig.client
            .from('subjects')
            .select('id, code, name');

        final subjectsMap = <String, Map<String, dynamic>>{};
        for (final s in (subjectsData as List)) {
          final c = s['code']?.toString().toUpperCase();
          final n = s['name']?.toString().toUpperCase();
          if (c != null && c.isNotEmpty) subjectsMap[c] = s;
          if (n != null && n.isNotEmpty) subjectsMap[n] = s;
        }

        // Create subject_offerings for each unique subject
        final offeringsToInsert = <Map<String, dynamic>>[];
        for (final code in subjectCodesToCreate) {
          final subject = subjectsMap[code.toUpperCase()];
          if (subject != null) {
            offeringsToInsert.add({
              'semester_id': semesterId,
              'class_id': classId,
              'subject_id': subject['id'],
              'coefficient': 1.0,
              'total_hours': 28,
              'weekly_ci_hours': 2,
              'weekly_tp_hours': 0,
              'weeks': 14,
              'is_active': true,
            });
          }
        }

        if (offeringsToInsert.isNotEmpty) {
          await SupabaseConfig.client
              .from('subject_offerings')
              .upsert(
                offeringsToInsert,
                onConflict: 'semester_id,class_id,subject_id',
              );
        }

        // Re-fetch offerings to get the new IDs
        final newOfferings = await SupabaseConfig.client
            .from('subject_offerings')
            .select('id, subjects(code, name)')
            .eq('class_id', classId)
            .eq('semester_id', semesterId);

        final offeringsByCode = <String, String>{};
        for (final o in newOfferings) {
          final code = o['subjects']?['code']?.toString().toUpperCase();
          final name = o['subjects']?['name']?.toString().toUpperCase();
          if (code != null) offeringsByCode[code] = o['id'].toString();
          if (name != null) offeringsByCode[name] = o['id'].toString();
        }

        // Update rows with new offering IDs
        for (final row in rows) {
          if (row['offering_id'] == null) {
            final code = row['subject_code'].toString().toUpperCase();
            row['offering_id'] = offeringsByCode[code];
          }
        }
      }

      // Filter out any rows that still don't have offering_id
      final validRows = rows.where((r) => r['offering_id'] != null).toList();

      if (validRows.isEmpty) {
        throw Exception('Aucune matière valide trouvée dans le système');
      }

      // Delete existing timetable slots for this class and semester so old slots never overlap with new imported ones
      final allOfferingsForClassSem = await SupabaseConfig.client
          .from('subject_offerings')
          .select('id')
          .eq('class_id', classId)
          .eq('semester_id', semesterId);

      final offeringIdsToClear = (allOfferingsForClassSem as List)
          .map((o) => o['id'].toString())
          .toList();

      if (offeringIdsToClear.isNotEmpty) {
        await SupabaseConfig.adminClient
            .from('timetable_slots')
            .delete()
            .inFilter('subject_offering_id', offeringIdsToClear);
      }

      // Convert day integer to day_of_week enum string
      String dayToEnum(int day) {
        switch (day) {
          case 1:
            return 'monday';
          case 2:
            return 'tuesday';
          case 3:
            return 'wednesday';
          case 4:
            return 'thursday';
          case 5:
            return 'friday';
          case 6:
            return 'saturday';
          default:
            return 'monday';
        }
      }

      final inserts = validRows
          .map(
            (row) => {
              'subject_offering_id': row['offering_id'],
              'day_of_week': dayToEnum(row['day'] as int),
              'start_time': row['start'],
              'end_time': row['end'],
              'room': row['room'],
            },
          )
          .toList();

      await SupabaseConfig.adminClient.from('timetable_slots').insert(inserts);

      // Invalidate providers to refresh the timetable display
      ref.invalidate(classTimetableSlotsProvider(classId));
      ref.invalidate(classSubjectOfferingsProvider((classId, semesterId)));
      ref.invalidate(filteredTimetableSlotsProvider(classId));
      ref.invalidate(uniqueSubjectsProvider((classId, semesterId)));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${validRows.length} cours importés'),
            backgroundColor: AppColors.success,
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
}
