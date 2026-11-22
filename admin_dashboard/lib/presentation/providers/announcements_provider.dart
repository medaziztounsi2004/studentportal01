import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../../core/config/supabase_config.dart';
import '../../core/utils/error_messages.dart';
import '../../models/announcement_model.dart';
import '../../repositories/announcement_repository.dart';

class AnnouncementModel {
  final String id;
  final String title;
  final String content;
  final String? targetRole;
  final String? targetClassId;
  final bool isPinned;
  final bool isImportant;
  final String scope;
  final DateTime createdAt;
  final String? authorName;
  final String announcementType;
  final String senderType;
  final String? senderLabel;
  final String? senderAvatarText;
  final bool hasAttachment;
  final String? className;
  final Map<String, dynamic> payload;

  String? get targetStudentId =>
      payload['target_student_id']?.toString() ??
      payload['student_id']?.toString();

  AnnouncementModel({
    required this.id,
    required this.title,
    required this.content,
    this.targetRole,
    this.targetClassId,
    this.isPinned = false,
    this.isImportant = false,
    this.scope = 'global',
    required this.createdAt,
    this.authorName,
    this.announcementType = 'general',
    this.senderType = 'administration',
    this.senderLabel,
    this.senderAvatarText,
    this.hasAttachment = false,
    this.className,
    this.payload = const {},
  });

  factory AnnouncementModel.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> payload = const {};
    if (json['payload'] is Map) {
      payload = Map<String, dynamic>.from(json['payload'] as Map);
    } else if (json['payload'] is String && (json['payload'] as String).isNotEmpty) {
      try {
        final decoded = jsonDecode(json['payload'] as String);
        if (decoded is Map) {
          payload = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    final bodyStr = (json['body'] ?? json['content'] ?? '').toString();
    final isStudent = json['scope']?.toString() == 'student' ||
        payload['scope']?.toString() == 'student' ||
        payload['target_student_id'] != null ||
        json['target_student_id'] != null ||
        bodyStr.startsWith('**@');
    final resolvedScope = isStudent ? 'student' : (json['scope']?.toString() ?? 'global');

    return AnnouncementModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      content: (json['body'] ?? json['content'] ?? '').toString(),
      targetRole: json['target_role']?.toString(),
      targetClassId:
          json['class_id']?.toString() ?? json['target_class_id']?.toString(),
      isPinned: json['is_pinned'] == true,
      isImportant: json['is_important'] == true,
      scope: resolvedScope,
      createdAt:
          DateTime.tryParse(
            json['created_at']?.toString() ??
                json['published_at']?.toString() ??
                '',
          ) ??
          DateTime.now(),
      authorName:
          json['users']?['full_name']?.toString() ??
          json['sender_label']?.toString(),
      announcementType: json['announcement_type']?.toString() ?? 'general',
      senderType: json['sender_type']?.toString() ?? 'administration',
      senderLabel: json['sender_label']?.toString(),
      senderAvatarText: json['sender_avatar_text']?.toString(),
      hasAttachment: json['has_attachment'] == true,
      className: json['class_name']?.toString(),
      payload: payload,
    );
  }

  Announcement toAnnouncement() => Announcement(
    id: id,
    scope: scope == 'class'
        ? AnnouncementScope.classScope
        : AnnouncementScope.global,
    title: title,
    body: content,
    isPinned: isPinned,
    isImportant: isImportant,
    classId: targetClassId,
    createdAt: createdAt,
    payload: payload,
  );
}

class AnnouncementsState {
  final List<AnnouncementModel> announcements;
  final String searchQuery;
  AnnouncementsState({this.announcements = const [], this.searchQuery = ''});

  List<AnnouncementModel> get filtered => searchQuery.isEmpty
      ? announcements
      : announcements
            .where(
              (a) => a.title.toLowerCase().contains(searchQuery.toLowerCase()),
            )
            .toList();

  AnnouncementsState copyWith({
    List<AnnouncementModel>? announcements,
    String? searchQuery,
  }) => AnnouncementsState(
    announcements: announcements ?? this.announcements,
    searchQuery: searchQuery ?? this.searchQuery,
  );
}

class AnnouncementsNotifier extends AsyncNotifier<AnnouncementsState> {
  AnnouncementRepository? _repository;
  AnnouncementRepository get repository =>
      _repository ??= AnnouncementRepository();

  @override
  Future<AnnouncementsState> build() async => _load();

  Future<AnnouncementsState> _load() async {
    final supabase = SupabaseConfig.client;
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Non connecte');

    final profile = await supabase
        .from('users')
        .select('school_id')
        .eq('id', user.id)
        .single();
    final schoolId = profile['school_id'] as String?;

    try {
      final data = await supabase
          .from('vw_announcements')
          .select()
          .or('school_id.eq.$schoolId,school_id.is.null')
          .order('is_pinned', ascending: false)
          .order('published_at', ascending: false);

      return AnnouncementsState(
        announcements: (data as List)
            .map((e) => AnnouncementModel.fromJson(e))
            .toList(),
      );
    } catch (e) {
      try {
        final globalData = await supabase
            .from('announcements_global')
            .select()
            .eq('school_id', schoolId ?? '')
            .order('published_at', ascending: false);

        final classData = await supabase
            .from('announcements_class')
            .select()
            .order('published_at', ascending: false);

        final List<AnnouncementModel> announcements = [
          ...(globalData as List).map(
            (e) => AnnouncementModel.fromJson({...e, 'scope': 'global'}),
          ),
          ...(classData as List).map(
            (e) {
              final rawPayload = e['payload'];
              bool isStudent = false;
              if (rawPayload is Map && rawPayload['target_student_id'] != null) isStudent = true;
              if (rawPayload is String && rawPayload.contains('target_student_id')) isStudent = true;
              if ((e['body']?.toString() ?? '').startsWith('**@')) isStudent = true;
              return AnnouncementModel.fromJson({
                ...e,
                'scope': isStudent ? 'student' : 'class',
              });
            },
          ),
        ];

        announcements.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return AnnouncementsState(announcements: announcements);
      } catch (_) {
        return AnnouncementsState(announcements: []);
      }
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load());
  }

  void setSearchQuery(String q) {
    state.whenData((c) => state = AsyncData(c.copyWith(searchQuery: q)));
  }

  Future<List<Map<String, dynamic>>> fetchClasses() async {
    final supabase = SupabaseConfig.client;
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final profile = await supabase
          .from('users')
          .select('school_id')
          .eq('id', user.id)
          .single();
      final schoolId = profile['school_id'] as String?;
      if (schoolId == null) return [];

      final classesData = await supabase
          .from('classes')
          .select('id, name, niveau_id')
          .eq('school_id', schoolId)
          .eq('is_active', true)
          .order('name');

      final classes = (classesData as List).cast<Map<String, dynamic>>();

      final niveauxData = await supabase
          .from('niveaux')
          .select('id, code, name, cycle, display_order')
          .order('display_order');

      final niveauxMap = <String, Map<String, dynamic>>{};
      for (final n in (niveauxData as List)) {
        niveauxMap[n['id'] as String] = n as Map<String, dynamic>;
      }

      final studentCounts = <String, int>{};
      try {
        final stats = await supabase.rpc('get_class_stats');
        for (final row in (stats as List)) {
          final classId = row['class_id'] as String?;
          final count = (row['student_count'] as num?)?.toInt() ?? 0;
          if (classId != null) studentCounts[classId] = count;
        }
      } catch (e) {
        debugPrint('Error fetching class stats rpc: $e');
      }

      for (final c in classes) {
        final niveauId = c['niveau_id'] as String?;
        if (niveauId != null && niveauxMap.containsKey(niveauId)) {
          c['niveaux'] = niveauxMap[niveauId];
        }
        c['student_count'] = studentCounts[c['id'] as String] ?? 0;
      }

      classes.sort((a, b) {
        final niveauA = a['niveaux'] as Map<String, dynamic>?;
        final niveauB = b['niveaux'] as Map<String, dynamic>?;
        final orderA = niveauA?['display_order'] as int? ?? 999;
        final orderB = niveauB?['display_order'] as int? ?? 999;
        if (orderA != orderB) return orderA.compareTo(orderB);
        return (a['name'] as String? ?? '').compareTo(
          b['name'] as String? ?? '',
        );
      });

      return classes;
    } catch (e) {
      debugPrint('Error fetching classes: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchNiveaux() async {
    final supabase = SupabaseConfig.client;

    try {
      final data = await supabase
          .from('niveaux')
          .select('id, code, name, cycle, display_order')
          .order('display_order');

      return (data as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Error fetching niveaux: $e');
      return [];
    }
  }

  Future<String?> create({
    required String title,
    required String content,
    String? targetClassId,
    String? targetStudentId,
    bool isPinned = false,
    bool isImportant = false,
    String scope = 'global',
    String announcementType = 'general',
    String senderType = 'administration',
    String? senderLabel,
    Map<String, dynamic>? payload,
  }) async {
    final supabase = SupabaseConfig.client;
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Non connecte');

    final profile = await supabase
        .from('users')
        .select('school_id, full_name')
        .eq('id', user.id)
        .single();
    final schoolId = profile['school_id'] as String?;
    final adminName = profile['full_name'] as String? ?? 'Admin';

    String? insertedId;

    if (scope == 'student' && targetStudentId != null) {
      // Get student's name safely
      String studentName = 'Étudiant';
      try {
        final studentProfile = await supabase
            .from('users')
            .select('full_name')
            .eq('id', targetStudentId)
            .maybeSingle();
        if (studentProfile != null && studentProfile['full_name'] != null) {
          studentName = studentProfile['full_name'] as String;
        }
      } catch (_) {}

      // Get student's class safely
      String? studentClassId;
      try {
        final enrollment = await supabase
            .from('enrollments')
            .select('class_id')
            .eq('user_id', targetStudentId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        studentClassId = enrollment?['class_id'] as String?;
      } catch (_) {}

      if (studentClassId == null) {
        try {
          final u = await supabase
              .from('users')
              .select('class_id')
              .eq('id', targetStudentId)
              .maybeSingle();
          studentClassId = u?['class_id'] as String?;
        } catch (_) {}
      }

      if (studentClassId == null && schoolId != null) {
        try {
          final anyClass = await supabase
              .from('classes')
              .select('id')
              .eq('school_id', schoolId)
              .limit(1)
              .maybeSingle();
          studentClassId = anyClass?['id'] as String?;
        } catch (_) {}
      }

      // Prepend student name to content with special marker for highlighting
      final highlightedContent = '**@$studentName** $content';

      final insertData = <String, dynamic>{
        'title': title,
        'body': highlightedContent,
        if (studentClassId != null) 'class_id': studentClassId,
        if (schoolId != null) 'school_id': schoolId,
        'is_pinned': isPinned,
        'is_important': isImportant,
        'created_by': user.id,
        'published_at': DateTime.now().toUtc().toIso8601String(),
        'announcement_type': announcementType,
        'sender_type': senderType,
        'sender_label': senderLabel ?? adminName,
        'sender_avatar_text': senderLabel != null && senderLabel.isNotEmpty
            ? senderLabel[0].toUpperCase()
            : adminName[0].toUpperCase(),
        'payload': {
          ...?payload,
          'target_student_id': targetStudentId,
          'target_student_name': studentName,
          'scope': 'student',
        },
      };

      final result = await supabase
          .from('announcements_class')
          .insert(insertData)
          .select('id')
          .single();
      insertedId = result['id'];
    } else if (scope == 'class' && targetClassId != null) {
      final result = await supabase
          .from('announcements_class')
          .insert({
            'title': title,
            'body': content,
            'class_id': targetClassId,
            'is_pinned': isPinned,
            'is_important': isImportant,
            'created_by': user.id,
            'published_at': DateTime.now().toUtc().toIso8601String(),
            'announcement_type': announcementType,
            'sender_type': senderType,
            'sender_label': senderLabel,
            'sender_avatar_text': senderLabel != null && senderLabel.isNotEmpty
                ? senderLabel[0].toUpperCase()
                : null,
            'payload': payload ?? {},
          })
          .select('id')
          .single();
      insertedId = result['id'];
    } else {
      final result = await supabase
          .from('announcements_global')
          .insert({
            'title': title,
            'body': content,
            'school_id': schoolId,
            'is_pinned': isPinned,
            'is_important': isImportant,
            'created_by': user.id,
            'published_at': DateTime.now().toUtc().toIso8601String(),
            'announcement_type': announcementType,
            'sender_type': senderType,
            'sender_label': senderLabel,
            'sender_avatar_text': senderLabel != null && senderLabel.isNotEmpty
                ? senderLabel[0].toUpperCase()
                : null,
            'payload': payload ?? {},
          })
          .select('id')
          .single();
      insertedId = result['id'];
    }
    ref.invalidateSelf();
    return insertedId;
  }

  Future<void> uploadAttachment({
    required String announcementId,
    required String scope,
    required String fileName,
    required Uint8List fileBytes,
    required String mimeType,
    String? displayName,
  }) async {
    final supabase = SupabaseConfig.client;
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Non connecte');

    final profile = await supabase
        .from('users')
        .select('school_id')
        .eq('id', user.id)
        .single();
    final schoolId = profile['school_id'] as String? ?? 'unknown';

    const bucketName = SupabaseConfig.attachmentsBucket;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath =
        '$schoolId/announcements/$announcementId/${timestamp}_$safeName';

    try {
      await supabase.storage
          .from(bucketName)
          .uploadBinary(
            storagePath,
            fileBytes,
            fileOptions: FileOptions(
              contentType: mimeType,
              upsert: true,
            ),
          );
    } catch (e) {
      throw Exception(
        UserFriendlyError.format(
          e,
          fallback: 'Unable to upload the attachment right now. Please try again.',
        ),
      );
    }

    final publicUrl = supabase.storage
        .from(bucketName)
        .getPublicUrl(storagePath);

    try {
      final insertData = <String, dynamic>{
        'announcement_id': announcementId,
        'scope': (scope == 'student') ? 'class' : scope,
        'file_name': fileName,
        'file_url': publicUrl,
        'file_type': mimeType,
        'file_size': fileBytes.length,
      };

      if (displayName != null &&
          displayName.isNotEmpty &&
          displayName != fileName) {
        insertData['display_name'] = displayName;
      }

      await supabase.from('announcement_attachments').insert(insertData);
    } catch (e) {
      throw Exception(
        UserFriendlyError.format(
          e,
          fallback: 'Unable to save the attachment details. Please try again.',
        ),
      );
    }

    try {
      final table = (scope == 'class' || scope == 'student')
          ? 'announcements_class'
          : 'announcements_global';
      await supabase
          .from(table)
          .update({'has_attachment': true})
          .eq('id', announcementId);
    } catch (e) {
      throw Exception(
        UserFriendlyError.format(
          e,
          fallback: 'Unable to update the announcement attachment status. Please try again.',
        ),
      );
    }
  }

  Future<void> deleteAttachment(String attachmentId) async {
    final supabase = SupabaseConfig.client;

    final att = await supabase
        .from('announcement_attachments')
        .select()
        .eq('id', attachmentId)
        .single();

    final fileUrl = att['file_url'] as String;
    final announcementId = att['announcement_id'] as String;
    final scope = att['scope'] as String;

    const bucketName = SupabaseConfig.attachmentsBucket;
    final urlParts = fileUrl.split('/$bucketName/');
    if (urlParts.length > 1) {
      final storagePath = urlParts[1];
      try {
        await supabase.storage.from(bucketName).remove([storagePath]);
      } catch (e) {
        debugPrint('Storage delete error: $e');
      }
    }

    await supabase
        .from('announcement_attachments')
        .delete()
        .eq('id', attachmentId);

    final remaining = await supabase
        .from('announcement_attachments')
        .select('id')
        .eq('announcement_id', announcementId);

    if ((remaining as List).isEmpty) {
      final table = (scope == 'class' || scope == 'student')
          ? 'announcements_class'
          : 'announcements_global';
      await supabase
          .from(table)
          .update({'has_attachment': false})
          .eq('id', announcementId);
    }
  }

  Future<void> updateAnnouncement({
    required String id,
    required String title,
    required String content,
    String? targetClassId,
    bool isPinned = false,
    bool isImportant = false,
    String scope = 'global',
    String announcementType = 'general',
    String senderType = 'administration',
    String? senderLabel,
    Map<String, dynamic>? payload,
  }) async {
    final supabase = SupabaseConfig.client;

    final updateData = <String, dynamic>{
      'title': title,
      'body': content,
      'is_pinned': isPinned,
      'is_important': isImportant,
      'announcement_type': announcementType,
      'sender_type': senderType,
      'sender_label': senderLabel,
      'sender_avatar_text': senderLabel != null && senderLabel.isNotEmpty
          ? senderLabel[0].toUpperCase()
          : null,
      'payload': payload ?? {},
    };

    if (targetClassId != null && targetClassId.isNotEmpty && scope != 'global') {
      updateData['class_id'] = targetClassId;
    }

    final targetTable = (scope == 'class' || scope == 'student')
        ? 'announcements_class'
        : 'announcements_global';
    final fallbackTable = (targetTable == 'announcements_class')
        ? 'announcements_global'
        : 'announcements_class';

    try {
      final res = await supabase
          .from(targetTable)
          .update(updateData)
          .eq('id', id)
          .select('id');
      if ((res as List).isEmpty) {
        await supabase
            .from(fallbackTable)
            .update(updateData)
            .eq('id', id);
      }
    } catch (_) {
      try {
        await supabase
            .from(fallbackTable)
            .update(updateData)
            .eq('id', id);
      } catch (e) {
        debugPrint('Error updating announcement: $e');
        rethrow;
      }
    }
    ref.invalidateSelf();
  }

  Future<void> delete(String id, {String scope = 'global'}) async {
    state = const AsyncLoading();
    final supabase = SupabaseConfig.client;

    final updateData = {'deleted_at': DateTime.now().toIso8601String()};

    if (scope == 'class' || scope == 'student') {
      await supabase
          .from('announcements_class')
          .update(updateData)
          .eq('id', id);
    } else {
      await supabase
          .from('announcements_global')
          .update(updateData)
          .eq('id', id);
    }
    ref.invalidateSelf();
  }

  Future<void> bulkDelete(List<AnnouncementModel> announcements) async {
    state = const AsyncLoading();
    final supabase = SupabaseConfig.client;
    final now = DateTime.now().toIso8601String();

    final globalIds = announcements
        .where((a) => a.scope == 'global')
        .map((a) => a.id)
        .toList();
    final classOrStudentIds = announcements
        .where((a) => a.scope == 'class' || a.scope == 'student')
        .map((a) => a.id)
        .toList();

    if (globalIds.isNotEmpty) {
      await supabase
          .from('announcements_global')
          .update({'deleted_at': now})
          .inFilter('id', globalIds);
    }
    if (classOrStudentIds.isNotEmpty) {
      await supabase
          .from('announcements_class')
          .update({'deleted_at': now})
          .inFilter('id', classOrStudentIds);
    }
    ref.invalidateSelf();
  }

  Future<void> bulkTogglePin(
    List<AnnouncementModel> announcements,
    bool pinned,
  ) async {
    state = const AsyncLoading();
    final supabase = SupabaseConfig.client;

    final globalIds = announcements
        .where((a) => a.scope == 'global')
        .map((a) => a.id)
        .toList();
    final classOrStudentIds = announcements
        .where((a) => a.scope == 'class' || a.scope == 'student')
        .map((a) => a.id)
        .toList();

    if (globalIds.isNotEmpty) {
      await supabase
          .from('announcements_global')
          .update({'is_pinned': pinned})
          .inFilter('id', globalIds);
    }
    if (classOrStudentIds.isNotEmpty) {
      await supabase
          .from('announcements_class')
          .update({'is_pinned': pinned})
          .inFilter('id', classOrStudentIds);
    }
    ref.invalidateSelf();
  }

  Future<void> bulkToggleImportant(
    List<AnnouncementModel> announcements,
    bool important,
  ) async {
    state = const AsyncLoading();
    final supabase = SupabaseConfig.client;

    final globalIds = announcements
        .where((a) => a.scope == 'global')
        .map((a) => a.id)
        .toList();
    final classOrStudentIds = announcements
        .where((a) => a.scope == 'class' || a.scope == 'student')
        .map((a) => a.id)
        .toList();

    if (globalIds.isNotEmpty) {
      await supabase
          .from('announcements_global')
          .update({'is_important': important})
          .inFilter('id', globalIds);
    }
    if (classOrStudentIds.isNotEmpty) {
      await supabase
          .from('announcements_class')
          .update({'is_important': important})
          .inFilter('id', classOrStudentIds);
    }
    ref.invalidateSelf();
  }

  Future<void> togglePin(
    String id,
    bool pinned, {
    String scope = 'global',
  }) async {
    final supabase = SupabaseConfig.client;

    if (scope == 'class' || scope == 'student') {
      await supabase
          .from('announcements_class')
          .update({'is_pinned': !pinned})
          .eq('id', id);
    } else {
      await supabase
          .from('announcements_global')
          .update({'is_pinned': !pinned})
          .eq('id', id);
    }
    ref.invalidateSelf();
  }
}

final announcementsProvider =
    AsyncNotifierProvider<AnnouncementsNotifier, AnnouncementsState>(
      AnnouncementsNotifier.new,
    );
