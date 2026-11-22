import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../core/config/supabase_config.dart';
import 'dart:html' as html;

class BackupItem {
  final String id;
  final String filename;
  final String schoolId;
  final DateTime createdAt;
  final int sizeBytes;
  final String status; // 'success' | 'failed'
  final String? storagePath;
  final Map<String, int> summary;

  BackupItem({
    required this.id,
    required this.filename,
    required this.schoolId,
    required this.createdAt,
    required this.sizeBytes,
    this.status = 'success',
    this.storagePath,
    this.summary = const {},
  });

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get formattedDate {
    return DateFormat('dd/MM/yyyy HH:mm', 'fr_FR').format(createdAt);
  }

  factory BackupItem.fromJson(Map<String, dynamic> json) => BackupItem(
        id: json['id'] ?? '',
        filename: json['filename'] ?? '',
        schoolId: json['school_id'] ?? '',
        createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
        sizeBytes: json['size_bytes'] ?? 0,
        status: json['status'] ?? 'success',
        storagePath: json['storage_path'],
        summary: Map<String, int>.from(json['summary'] ?? {}),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'filename': filename,
        'school_id': schoolId,
        'created_at': createdAt.toIso8601String(),
        'size_bytes': sizeBytes,
        'status': status,
        'storage_path': storagePath,
        'summary': summary,
      };
}

class BackupConfig {
  final String cycle; // 'daily' | 'weekly' | 'monthly'
  final bool autoEnabled;
  final DateTime? lastBackupAt;

  BackupConfig({
    this.cycle = 'daily',
    this.autoEnabled = true,
    this.lastBackupAt,
  });

  factory BackupConfig.fromJson(Map<String, dynamic> json) => BackupConfig(
        cycle: json['cycle'] ?? 'daily',
        autoEnabled: json['auto_enabled'] ?? true,
        lastBackupAt: json['last_backup_at'] != null
            ? DateTime.tryParse(json['last_backup_at'])
            : null,
      );

  Map<String, dynamic> toJson() => {
        'cycle': cycle,
        'auto_enabled': autoEnabled,
        'last_backup_at': lastBackupAt?.toIso8601String(),
      };
}

class BackupService {
  static const String _bucket = 'school-backups';

  /// Performs a full data export of all admin dashboard and mobile app tables for the school
  static Future<BackupItem> createBackup(String schoolId) async {
    final client = SupabaseConfig.adminClient;
    final now = DateTime.now();
    final timestampStr = DateFormat('yyyyMMdd_HHmmss').format(now);
    final filename = 'backup_${schoolId}_$timestampStr.json';
    final storagePath = '$schoolId/$filename';

    debugPrint('[BackupService] Starting full backup for school $schoolId');

    // 1. Fetch tables with safe error handling
    Future<dynamic> safeFetch(Future<dynamic> Function() fetcher, [dynamic defaultValue = const []]) async {
      try {
        return await fetcher();
      } catch (e) {
        debugPrint('[BackupService] Table fetch error: $e');
        return defaultValue;
      }
    }

    final schoolFuture = safeFetch(() => client.from('schools').select().eq('id', schoolId).maybeSingle(), null);
    final academicYearsFuture = safeFetch(() => client.from('academic_years').select().eq('school_id', schoolId));
    final semestersFuture = safeFetch(() => client.from('semesters').select().eq('school_id', schoolId));
    final vacationsFuture = safeFetch(() => client.from('vacation_periods').select().eq('school_id', schoolId));
    final examsFuture = safeFetch(() => client.from('exam_periods').select().eq('school_id', schoolId));
    final buildingsFuture = safeFetch(() => client.from('buildings').select().eq('school_id', schoolId));
    final floorsFuture = safeFetch(() => client.from('floors').select().eq('school_id', schoolId));
    final roomsFuture = safeFetch(() => client.from('rooms').select().eq('school_id', schoolId));
    final subjectsFuture = safeFetch(() => client.from('subjects').select().eq('school_id', schoolId));
    final curriculumFuture = safeFetch(() => client.from('curriculum').select().eq('school_id', schoolId));
    final classesFuture = safeFetch(() => client.from('classes').select().eq('school_id', schoolId));
    final usersFuture = safeFetch(() => client.from('users').select().eq('school_id', schoolId));
    final enrollmentsFuture = safeFetch(() => client.from('enrollments').select());
    final absencesFuture = safeFetch(() => client.from('absence_records').select());
    final gradesFuture = safeFetch(() => client.from('grades').select().eq('school_id', schoolId));
    final gradeComponentsFuture = safeFetch(() => client.from('grade_components').select());
    final teacherAssignmentsFuture = safeFetch(() => client.from('teacher_assignments').select().eq('school_id', schoolId));
    final timetableSlotsFuture = safeFetch(() => client.from('timetable_slots').select().eq('school_id', schoolId));
    final paymentsFuture = safeFetch(() => client.from('payments').select().eq('school_id', schoolId));
    final paymentPlansFuture = safeFetch(() => client.from('payment_plans').select().eq('school_id', schoolId));
    final announcementsGlobalFuture = safeFetch(() => client.from('announcements_global').select().eq('school_id', schoolId));
    final announcementsClassFuture = safeFetch(() => client.from('announcements_class').select());
    final suggestionsFuture = safeFetch(() => client.from('suggestions').select().eq('school_id', schoolId));
    final seenItemsFuture = safeFetch(() => client.from('student_seen_items').select());

    final results = await Future.wait<dynamic>([
      schoolFuture,
      academicYearsFuture,
      semestersFuture,
      vacationsFuture,
      examsFuture,
      buildingsFuture,
      floorsFuture,
      roomsFuture,
      subjectsFuture,
      curriculumFuture,
      classesFuture,
      usersFuture,
      enrollmentsFuture,
      absencesFuture,
      gradesFuture,
      gradeComponentsFuture,
      teacherAssignmentsFuture,
      timetableSlotsFuture,
      paymentsFuture,
      paymentPlansFuture,
      announcementsGlobalFuture,
      announcementsClassFuture,
      suggestionsFuture,
      seenItemsFuture,
    ]);

    final schoolData = results[0];
    final academicYears = (results[1] as List?) ?? [];
    final semesters = (results[2] as List?) ?? [];
    final vacations = (results[3] as List?) ?? [];
    final exams = (results[4] as List?) ?? [];
    final buildings = (results[5] as List?) ?? [];
    final floors = (results[6] as List?) ?? [];
    final rooms = (results[7] as List?) ?? [];
    final subjects = (results[8] as List?) ?? [];
    final curriculum = (results[9] as List?) ?? [];
    final classes = (results[10] as List?) ?? [];
    final users = (results[11] as List?) ?? [];
    final allEnrollments = (results[12] as List?) ?? [];
    final absences = (results[13] as List?) ?? [];
    final grades = (results[14] as List?) ?? [];
    final allGradeComponents = (results[15] as List?) ?? [];
    final teacherAssignments = (results[16] as List?) ?? [];
    final timetableSlots = (results[17] as List?) ?? [];
    final payments = (results[18] as List?) ?? [];
    final paymentPlans = (results[19] as List?) ?? [];
    final announcementsGlobal = (results[20] as List?) ?? [];
    final allAnnouncementsClass = (results[21] as List?) ?? [];
    final suggestions = (results[22] as List?) ?? [];
    final allSeenItems = (results[23] as List?) ?? [];

    // Filter enrollments and grade components belonging to this school's classes/grades
    final schoolClassIds = classes.map((c) => c['id']).toSet();
    final schoolUserIds = users.map((u) => u['id']).toSet();
    final filteredEnrollments = allEnrollments.where((e) =>
      schoolClassIds.contains(e['class_id']) || schoolUserIds.contains(e['user_id'])
    ).toList();

    final filteredSeenItems = allSeenItems.where((si) =>
      schoolUserIds.contains(si['student_id'])
    ).toList();

    final schoolGradeIds = grades.map((g) => g['id']).toSet();
    final filteredGradeComponents = allGradeComponents.where((gc) =>
      schoolGradeIds.contains(gc['grade_id'])
    ).toList();

    final filteredAnnouncementsClass = allAnnouncementsClass.where((ac) =>
      schoolClassIds.contains(ac['class_id'])
    ).toList();

    final summary = <String, int>{
      'users': users.length,
      'students': users.where((u) => u['role'] == 'student').length,
      'teachers': users.where((u) => u['role'] == 'teacher').length,
      'classes': classes.length,
      'subjects': subjects.length,
      'curriculum_rules': curriculum.length,
      'grades': grades.length,
      'absences': absences.length,
      'payments': payments.length,
      'timetable_slots': timetableSlots.length,
      'buildings': buildings.length,
      'floors': floors.length,
      'rooms': rooms.length,
      'student_seen_items': filteredSeenItems.length,
    };

    final payload = {
      'version': '1.0',
      'app': 'StudentPortal SaaS Suite',
      'school_id': schoolId,
      'created_at': now.toIso8601String(),
      'summary': summary,
      'data': {
        'school': schoolData,
        'academic_years': academicYears,
        'semesters': semesters,
        'vacation_periods': vacations,
        'exam_periods': exams,
        'buildings': buildings,
        'floors': floors,
        'rooms': rooms,
        'subjects': subjects,
        'curriculum': curriculum,
        'classes': classes,
        'users': users,
        'enrollments': filteredEnrollments,
        'absence_records': absences,
        'grades': grades,
        'grade_components': filteredGradeComponents,
        'teacher_assignments': teacherAssignments,
        'timetable_slots': timetableSlots,
        'payments': payments,
        'payment_plans': paymentPlans,
        'announcements_global': announcementsGlobal,
        'announcements_class': filteredAnnouncementsClass,
        'suggestions': suggestions,
        'student_seen_items': filteredSeenItems,
      }
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
    final bytes = utf8.encode(jsonStr);
    final sizeBytes = bytes.length;

    // 2. Upload to Supabase Storage bucket
    try {
      await client.storage.from(_bucket).uploadBinary(
        storagePath,
        Uint8List.fromList(bytes),
      );
      debugPrint('[BackupService] Uploaded backup file to $_bucket/$storagePath ($sizeBytes bytes)');
    } catch (e) {
      debugPrint('[BackupService] Storage upload error: $e');
    }

    final backupItem = BackupItem(
      id: 'bkp_${now.millisecondsSinceEpoch}',
      filename: filename,
      schoolId: schoolId,
      createdAt: now,
      sizeBytes: sizeBytes,
      status: 'success',
      storagePath: storagePath,
      summary: summary,
    );

    // 3. Update backup history and last_backup_at in app_settings
    await _saveBackupToHistory(schoolId, backupItem);

    return backupItem;
  }

  /// Load backup history for school
  static Future<List<BackupItem>> getBackups(String schoolId) async {
    final client = SupabaseConfig.adminClient;
    final key = 'backup_history_$schoolId';
    try {
      final res = await client
          .from('app_settings')
          .select('value')
          .eq('key', key)
          .maybeSingle();

      if (res != null && res['value'] != null) {
        final list = res['value'] as List?;
        if (list != null) {
          return list.map((item) => BackupItem.fromJson(item as Map<String, dynamic>)).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        }
      }
    } catch (e) {
      debugPrint('[BackupService] Error loading backup history: $e');
    }
    return [];
  }

  /// Load backup configuration for school
  static Future<BackupConfig> getBackupConfig(String schoolId) async {
    final client = SupabaseConfig.adminClient;
    final key = 'backup_config_$schoolId';
    try {
      final res = await client
          .from('app_settings')
          .select('value')
          .eq('key', key)
          .maybeSingle();

      if (res != null && res['value'] != null) {
        return BackupConfig.fromJson(Map<String, dynamic>.from(res['value']));
      }
    } catch (e) {
      debugPrint('[BackupService] Error loading backup config: $e');
    }
    return BackupConfig();
  }

  /// Update backup configuration (frequency, auto enabled)
  static Future<void> saveBackupConfig(String schoolId, BackupConfig config) async {
    final client = SupabaseConfig.adminClient;
    final key = 'backup_config_$schoolId';
    try {
      final existing = await client.from('app_settings').select('id').eq('key', key).maybeSingle();
      if (existing != null) {
        await client.from('app_settings').update({
          'value': config.toJson(),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', existing['id']);
      } else {
        await client.from('app_settings').insert({
          'key': key,
          'value': config.toJson(),
          'description': 'Automated backup settings for school $schoolId',
        });
      }
    } catch (e) {
      debugPrint('[BackupService] Error saving backup config: $e');
    }
  }

  /// Check and run scheduled backup if due
  static Future<void> checkAndRunScheduledBackup(String schoolId) async {
    try {
      final config = await getBackupConfig(schoolId);
      if (!config.autoEnabled) return;

      final now = DateTime.now();
      final lastBackup = config.lastBackupAt;
      bool isDue = false;

      if (lastBackup == null) {
        // Initialize timestamp without forcing an immediate background run on first page visit
        await saveBackupConfig(
          schoolId,
          BackupConfig(
            cycle: config.cycle,
            autoEnabled: config.autoEnabled,
            lastBackupAt: now,
          ),
        );
        return;
      } else {
        final diff = now.difference(lastBackup);
        if (config.cycle == 'daily' && diff.inHours >= 24) {
          isDue = true;
        } else if (config.cycle == 'weekly' && diff.inDays >= 7) {
          isDue = true;
        } else if (config.cycle == 'monthly' && diff.inDays >= 30) {
          isDue = true;
        }
      }

      if (isDue) {
        debugPrint('[BackupService] Scheduled backup is due for school $schoolId. Executing...');
        await createBackup(schoolId);
      }
    } catch (e) {
      debugPrint('[BackupService] Scheduled backup error: $e');
    }
  }

  /// Download backup directly into the browser
  static Future<void> downloadBackup(BackupItem item) async {
    try {
      final client = SupabaseConfig.adminClient;
      Uint8List? data;
      if (item.storagePath != null && item.storagePath!.isNotEmpty) {
        data = await client.storage.from(_bucket).download(item.storagePath!);
      }

      if (data == null) {
        // Fallback: create fresh content
        final fresh = await createBackup(item.schoolId);
        if (fresh.storagePath != null) {
          data = await client.storage.from(_bucket).download(fresh.storagePath!);
        }
      }

      if (data != null) {
        final blob = html.Blob([data], 'application/json');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', item.filename)
          ..click();
        html.Url.revokeObjectUrl(url);
      }
    } catch (e) {
      debugPrint('[BackupService] Download backup error: $e');
    }
  }

  static Future<void> _saveBackupToHistory(String schoolId, BackupItem item) async {
    final client = SupabaseConfig.adminClient;
    final key = 'backup_history_$schoolId';
    try {
      final existingHistory = await getBackups(schoolId);
      final updatedHistory = [item, ...existingHistory.where((b) => b.id != item.id)];
      // Keep up to 30 most recent backups
      final trimmed = updatedHistory.take(30).map((b) => b.toJson()).toList();

      final existingRecord = await client.from('app_settings').select('id').eq('key', key).maybeSingle();
      if (existingRecord != null) {
        await client.from('app_settings').update({
          'value': trimmed,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', existingRecord['id']);
      } else {
        await client.from('app_settings').insert({
          'key': key,
          'value': trimmed,
          'description': 'Backup history for school $schoolId',
        });
      }

      // Also update last_backup_at in config
      final currentConfig = await getBackupConfig(schoolId);
      await saveBackupConfig(
        schoolId,
        BackupConfig(
          cycle: currentConfig.cycle,
          autoEnabled: currentConfig.autoEnabled,
          lastBackupAt: item.createdAt,
        ),
      );
    } catch (e) {
      debugPrint('[BackupService] Error saving to history: $e');
    }
  }
}
