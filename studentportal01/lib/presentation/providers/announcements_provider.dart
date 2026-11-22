import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/connectivity_service.dart';
import '../../data/services/offline_cache_service.dart';
import '../../data/services/student_seen_service.dart';
import 'auth_provider.dart';

/// Model for attachment
class AnnouncementAttachment {
  final String id;
  final String fileUrl;
  final String fileName;
  final String? fileType;
  final String? displayName; // Custom display name

  AnnouncementAttachment({
    required this.id,
    required this.fileUrl,
    required this.fileName,
    this.fileType,
    this.displayName,
  });

  /// Returns the display name if available, otherwise the file name
  String get effectiveName => displayName ?? fileName;

  factory AnnouncementAttachment.fromJson(Map<String, dynamic> json) {
    return AnnouncementAttachment(
      id: json['id'] as String,
      fileUrl: json['file_url'] as String,
      fileName: json['file_name'] as String,
      fileType: json['file_type'] as String?,
      displayName: json['display_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'file_url': fileUrl,
      'file_name': fileName,
      'file_type': fileType,
      'display_name': displayName,
    };
  }
}

/// Model for announcements in student app
class StudentAnnouncement {
  final String id;
  final String title;
  final String body;
  final String? announcementType;
  final bool isImportant;
  final bool isPinned;
  final bool hasAttachment;
  final String? attachmentUrl;
  final String? attachmentName;
  final List<AnnouncementAttachment> attachments;
  final String? senderLabel;
  final String? senderType;
  final DateTime publishedAt;
  final DateTime createdAt;
  final Map<String, dynamic> payload;

  StudentAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    this.announcementType,
    this.isImportant = false,
    this.isPinned = false,
    this.hasAttachment = false,
    this.attachmentUrl,
    this.attachmentName,
    this.attachments = const [],
    this.senderLabel,
    this.senderType,
    required this.publishedAt,
    required this.createdAt,
    this.payload = const {},
  });

  factory StudentAnnouncement.fromJson(
    Map<String, dynamic> json, {
    List<AnnouncementAttachment> attachments = const [],
  }) {
    List<AnnouncementAttachment> effectiveAttachments = attachments;
    if (effectiveAttachments.isEmpty && json['attachments'] is List) {
      effectiveAttachments = (json['attachments'] as List)
          .map((a) => AnnouncementAttachment.fromJson(a as Map<String, dynamic>))
          .toList();
    }

    // Get first attachment URL if available
    String? attachmentUrl = json['attachment_url'] as String?;
    String? attachmentName = json['attachment_name'] as String?;
    if (effectiveAttachments.isNotEmpty) {
      attachmentUrl ??= effectiveAttachments.first.fileUrl;
      attachmentName ??= effectiveAttachments.first.fileName;
    }

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

    final rawType = json['announcement_type']?.toString() ??
        json['type']?.toString() ??
        payload['announcement_type']?.toString() ??
        payload['type']?.toString() ??
        'general';

    final hasAtt = (json['has_attachment'] as bool? ?? false) ||
        effectiveAttachments.isNotEmpty ||
        (attachmentUrl != null && attachmentUrl.isNotEmpty);

    return StudentAnnouncement(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      announcementType: rawType,
      isImportant: json['is_important'] as bool? ?? false,
      isPinned: json['is_pinned'] as bool? ?? false,
      hasAttachment: hasAtt,
      attachmentUrl: attachmentUrl,
      attachmentName: attachmentName,
      attachments: effectiveAttachments,
      senderLabel: json['sender_label'] as String?,
      senderType: json['sender_type'] as String?,
      publishedAt: DateTime.parse(
        json['published_at'] as String? ?? json['created_at'] as String,
      ).toLocal(),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      payload: payload,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'announcement_type': announcementType,
      'is_important': isImportant,
      'is_pinned': isPinned,
      'has_attachment': hasAttachment,
      'attachment_url': attachmentUrl,
      'attachment_name': attachmentName,
      'attachments': attachments.map((a) => a.toJson()).toList(),
      'sender_label': senderLabel,
      'sender_type': senderType,
      'published_at': publishedAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'payload': payload,
    };
  }
}

/// Helper to fetch attachments for announcements
Future<Map<String, List<AnnouncementAttachment>>> _fetchAttachments(
  SupabaseClient supabase,
  List<String> announcementIds, [
  String? scope,
]) async {
  if (announcementIds.isEmpty) return {};

  final response = await supabase
      .from('announcement_attachments')
      .select()
      .inFilter('announcement_id', announcementIds);

  final Map<String, List<AnnouncementAttachment>> attachmentsMap = {};

  for (final att in response as List) {
    final announcementId = att['announcement_id'] as String;
    final attachment = AnnouncementAttachment.fromJson(att);
    attachmentsMap.putIfAbsent(announcementId, () => []).add(attachment);
  }

  return attachmentsMap;
}

/// Loading state for notifications refresh
final notificationsRefreshingProvider = StateProvider<bool>((ref) => false);

/// Provider for global announcements (Notifications)
final globalAnnouncementsProvider = FutureProvider<List<StudentAnnouncement>>((
  ref,
) async {
  final supabase = Supabase.instance.client;
  final authState = ref.watch(authProvider);

  // Check if still loading - wait for auth to complete
  if (authState.isLoading) {
    debugPrint('globalAnnouncementsProvider: Auth still loading, waiting...');
    // Return empty for now, will be re-triggered when auth state changes
    return [];
  }

  // Check authentication - also check Supabase session directly as fallback
  final session = supabase.auth.currentSession;
  if (!authState.isAuthenticated && session == null) {
    debugPrint('globalAnnouncementsProvider: Not authenticated (no session)');
    return [];
  }

  // If we have a session but auth state not loaded yet, fetch school_id directly
  String? schoolId = authState.user?.schoolId;
  
  // Fallback: get school_id from enrollment's class
  if (schoolId == null && authState.enrollment?.classInfo != null) {
    schoolId = authState.enrollment!.classInfo!.schoolId;
    debugPrint('globalAnnouncementsProvider: Got schoolId from enrollment class: $schoolId');
  }
  
  // Last resort: use RPC to bypass RLS
  if (schoolId == null && session != null) {
    debugPrint('globalAnnouncementsProvider: Using RPC to fetch school_id...');
    try {
      // Try get_my_school_id RPC first
      final rpcResult = await supabase.rpc('get_my_school_id');
      if (rpcResult != null) {
        schoolId = rpcResult as String;
        debugPrint('globalAnnouncementsProvider: Got schoolId from RPC: $schoolId');
      }
    } catch (e) {
      debugPrint('globalAnnouncementsProvider: RPC get_my_school_id failed: $e');
    }
    
    // Fallback: try get_my_enrollment_data RPC
    if (schoolId == null) {
      try {
        final enrollmentData = await supabase.rpc('get_my_enrollment_data');
        if (enrollmentData != null) {
          schoolId = enrollmentData['classes']?['school_id'] as String?;
          debugPrint('globalAnnouncementsProvider: Got schoolId from enrollment RPC: $schoolId');
        }
      } catch (e) {
        debugPrint('globalAnnouncementsProvider: RPC get_my_enrollment_data failed: $e');
      }
    }
  }
  
  final cacheKey = 'global_announcements_${schoolId ?? 'default'}';
  if (schoolId == null) {
    debugPrint('globalAnnouncementsProvider: No school_id available, checking cache');
    final cached = OfflineCacheService.instance.getListOfMaps('global_announcements_default') ??
        OfflineCacheService.instance.getListOfMaps(cacheKey);
    if (cached != null) {
      return cached.map((e) => StudentAnnouncement.fromJson(e)).toList();
    }
    return [];
  }

  debugPrint('globalAnnouncementsProvider: Fetching for school_id=$schoolId');

  try {
    final response = await supabase
        .from('announcements_global')
        .select()
        .eq('school_id', schoolId)
        .isFilter('deleted_at', null)
        .order('is_pinned', ascending: false)
        .order('published_at', ascending: false)
        .limit(50);

    final announcements = response as List;
    debugPrint('globalAnnouncementsProvider: Fetched ${announcements.length} global announcements');
    
    final announcementIds = announcements.map((a) => a['id'] as String).toList();

    // Fetch attachments for all announcements
    Map<String, List<AnnouncementAttachment>> attachmentsMap = {};
    if (announcementIds.isNotEmpty) {
      try {
        attachmentsMap = await _fetchAttachments(
          supabase,
          announcementIds,
          'global',
        );
      } catch (e) {
        debugPrint('globalAnnouncementsProvider: Error fetching attachments: $e');
      }
    }

    final list = announcements
        .map(
          (json) => StudentAnnouncement.fromJson(
            json,
            attachments: attachmentsMap[json['id']] ?? [],
          ),
        )
        .toList();

    // Realtime subscription for global announcements
    RealtimeChannel? channel;
    try {
      channel = supabase
          .channel('announcements_global_realtime_$schoolId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'announcements_global',
            callback: (_) {
              debugPrint('Realtime: announcements_global changed -> refreshing');
              ref.invalidateSelf();
            },
          )
          .subscribe();
      ref.onDispose(() {
        if (channel != null) {
          try {
            supabase.removeChannel(channel);
          } catch (_) {}
        }
      });
    } catch (_) {}

    OfflineCacheService.instance.setJson(cacheKey, list.map((a) => a.toJson()).toList());
    OfflineCacheService.instance.setJson('global_announcements_default', list.map((a) => a.toJson()).toList());
    ConnectivityService.instance.reportNetworkSuccess();
    return list;
  } catch (e) {
    debugPrint('globalAnnouncementsProvider error: $e');
    ConnectivityService.instance.reportNetworkError(e);

    final cached = OfflineCacheService.instance.getListOfMaps(cacheKey) ??
        OfflineCacheService.instance.getListOfMaps('global_announcements_default');
    if (cached != null && cached.isNotEmpty) {
      return cached.map((e) => StudentAnnouncement.fromJson(e)).toList();
    }

    return [];
  }
});

/// Loading state for messages refresh
final messagesRefreshingProvider = StateProvider<bool>((ref) => false);

/// Provider for class messages
final classMessagesProvider = FutureProvider<List<StudentAnnouncement>>((
  ref,
) async {
  final supabase = Supabase.instance.client;
  final authState = ref.watch(authProvider);

  // Check if still loading - wait for auth to complete
  if (authState.isLoading) {
    debugPrint('classMessagesProvider: Auth still loading, waiting...');
    return [];
  }

  // Check authentication - also check Supabase session directly as fallback
  final session = supabase.auth.currentSession;
  if (!authState.isAuthenticated && session == null) {
    debugPrint('classMessagesProvider: Not authenticated (no session)');
    return [];
  }

  // Get class_id and group_id from enrollment or fetch directly
  String? classId = authState.enrollment?.classId;
  String? groupId = authState.enrollment?.groupId;
  
  // Fallback: use RPC to bypass RLS
  if (classId == null && session != null) {
    debugPrint('classMessagesProvider: Using RPC to fetch enrollment...');
    try {
      // Try get_my_class_id RPC first
      final rpcResult = await supabase.rpc('get_my_class_id');
      if (rpcResult != null) {
        classId = rpcResult as String;
        debugPrint('classMessagesProvider: Got classId from RPC: $classId');
      }
    } catch (e) {
      debugPrint('classMessagesProvider: RPC get_my_class_id failed: $e');
    }
    
    // Fallback: try get_my_enrollment_data RPC
    if (classId == null) {
      try {
        final enrollmentData = await supabase.rpc('get_my_enrollment_data');
        if (enrollmentData != null) {
          classId = enrollmentData['class_id'] as String?;
          groupId = enrollmentData['group_id'] as String?;
          debugPrint('classMessagesProvider: Got classId from enrollment RPC: $classId');
        }
      } catch (e) {
        debugPrint('classMessagesProvider: RPC get_my_enrollment_data failed: $e');
      }
    }
  }
  
  final cacheKey = 'class_messages_${classId ?? 'default'}_$groupId';
  if (classId == null) {
    debugPrint('classMessagesProvider: No class_id available, checking cache');
    final cached = OfflineCacheService.instance.getListOfMaps('class_messages_default') ??
        OfflineCacheService.instance.getListOfMaps(cacheKey);
    if (cached != null) {
      return cached.map((e) => StudentAnnouncement.fromJson(e)).toList();
    }
    return [];
  }

  debugPrint('classMessagesProvider: Fetching for class_id=$classId, group_id=$groupId');

  try {
    // Build query - get messages for user's class
    var query = supabase
        .from('announcements_class')
        .select()
        .eq('class_id', classId)
        .isFilter('deleted_at', null);

    // Also filter by group if specified, or get class-wide messages (null group_id)
    if (groupId != null) {
      query = query.or('group_id.eq.$groupId,group_id.is.null');
    }

    final response = await query
        .order('is_pinned', ascending: false)
        .order('published_at', ascending: false)
        .limit(50);

    final announcements = response as List;
    final currentUserId = authState.user?.id ?? session?.user.id;
    final List<dynamic> allRows = [...announcements];

    if (currentUserId != null) {
      try {
        final targetedRes = await supabase
            .from('announcements_class')
            .select()
            .contains('payload', {'target_student_id': currentUserId})
            .isFilter('deleted_at', null)
            .limit(30);
        for (final t in targetedRes as List) {
          if (!allRows.any((a) => a['id'] == t['id'])) {
            allRows.add(t);
          }
        }
      } catch (_) {}
    }

    final visibleRows = allRows.where((a) {
      final payload = a['payload'] is Map ? (a['payload'] as Map) : null;
      final targetStudentId = payload?['target_student_id']?.toString() ?? a['target_student_id']?.toString();
      if (targetStudentId != null && targetStudentId.isNotEmpty) {
        return currentUserId != null && targetStudentId == currentUserId;
      }
      return true;
    }).toList();

    debugPrint('classMessagesProvider: Fetched ${visibleRows.length} visible class/student messages');
    
    final announcementIds = visibleRows.map((a) => a['id'] as String).toList();

    // Fetch attachments for all announcements
    Map<String, List<AnnouncementAttachment>> attachmentsMap = {};
    if (announcementIds.isNotEmpty) {
      try {
        attachmentsMap = await _fetchAttachments(
          supabase,
          announcementIds,
          'class',
        );
      } catch (e) {
        debugPrint('classMessagesProvider: Error fetching attachments: $e');
      }
    }

    final list = visibleRows
        .map(
          (json) => StudentAnnouncement.fromJson(
            json,
            attachments: attachmentsMap[json['id']] ?? [],
          ),
        )
        .toList();

    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.publishedAt.compareTo(a.publishedAt);
    });

    // Realtime subscription for class messages
    RealtimeChannel? channel;
    try {
      channel = supabase
          .channel('announcements_class_realtime_$classId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'announcements_class',
            callback: (_) {
              debugPrint('Realtime: announcements_class changed -> refreshing');
              ref.invalidateSelf();
            },
          )
          .subscribe();
      ref.onDispose(() {
        if (channel != null) {
          try {
            supabase.removeChannel(channel);
          } catch (_) {}
        }
      });
    } catch (_) {}

    OfflineCacheService.instance.setJson(cacheKey, list.map((a) => a.toJson()).toList());
    OfflineCacheService.instance.setJson('class_messages_default', list.map((a) => a.toJson()).toList());
    ConnectivityService.instance.reportNetworkSuccess();
    return list;
  } catch (e) {
    debugPrint('classMessagesProvider error: $e');
    ConnectivityService.instance.reportNetworkError(e);

    final cached = OfflineCacheService.instance.getListOfMaps(cacheKey) ??
        OfflineCacheService.instance.getListOfMaps('class_messages_default');
    if (cached != null && cached.isNotEmpty) {
      return cached.map((e) => StudentAnnouncement.fromJson(e)).toList();
    }

    return [];
  }
});

/// Combined provider for all announcements (for unified feed if needed)
final allAnnouncementsProvider = FutureProvider<List<StudentAnnouncement>>((
  ref,
) async {
  final global = await ref.watch(globalAnnouncementsProvider.future);
  final classMessages = await ref.watch(classMessagesProvider.future);

  final all = [...global, ...classMessages];
  all.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

  return all;
});

/// Set of announcement IDs that have been opened/read by the current user
final readAnnouncementsProvider =
    StateNotifierProvider<ReadAnnouncementsNotifier, Set<String>>((ref) {
  final authState = ref.watch(authProvider);
  final userId = authState.user?.id ?? 'default_user';
  return ReadAnnouncementsNotifier(userId);
});

class ReadAnnouncementsNotifier extends StateNotifier<Set<String>> {
  final String userId;
  static const _storagePrefix = 'read_announcements_ids_';

  ReadAnnouncementsNotifier(this.userId) : super({}) {
    _loadFromCache();
    if (userId.isNotEmpty && userId != 'default_user') {
      _syncRemote();
    }
  }

  void _loadFromCache() {
    try {
      final cachedList = OfflineCacheService.instance.getList('$_storagePrefix$userId');
      if (cachedList != null) {
        state = cachedList.map((e) => e.toString()).toSet();
      }
    } catch (e) {
      debugPrint('ReadAnnouncementsNotifier load error: $e');
    }
  }

  Future<void> _syncRemote() async {
    if (userId.isEmpty || userId == 'default_user') return;
    try {
      final remoteIds = await StudentSeenService.fetchSeenIds(
        userId,
        [StudentSeenService.typeAnnouncement, StudentSeenService.typeMessage],
      );
      if (remoteIds.isNotEmpty) {
        final merged = Set<String>.from(state)..addAll(remoteIds);
        if (merged.length != state.length) {
          state = merged;
          await OfflineCacheService.instance.setJson('$_storagePrefix$userId', merged.toList());
        }
      }
      unawaited(StudentSeenService.syncPendingQueue());
    } catch (e) {
      debugPrint('ReadAnnouncementsNotifier _syncRemote error: $e');
    }
  }

  Future<void> syncRemote() => _syncRemote();

  Future<void> markAsRead(String id, {String itemType = StudentSeenService.typeAnnouncement}) async {
    if (state.contains(id)) return;
    final updated = Set<String>.from(state)..add(id);
    state = updated;
    await OfflineCacheService.instance.setJson('$_storagePrefix$userId', updated.toList());
    if (userId.isNotEmpty && userId != 'default_user') {
      unawaited(StudentSeenService.markItemSeen(userId, itemType, id));
    }
  }

  Future<void> markAllAsRead(List<String> ids, {String itemType = StudentSeenService.typeAnnouncement}) async {
    final updated = Set<String>.from(state)..addAll(ids);
    state = updated;
    await OfflineCacheService.instance.setJson('$_storagePrefix$userId', updated.toList());
    if (userId.isNotEmpty && userId != 'default_user') {
      unawaited(StudentSeenService.markItemsSeen(userId, itemType, ids));
    }
  }

  bool isRead(String id) => state.contains(id);
}

/// Provider for global announcements unread count (Notifications badge)
final globalAnnouncementsCountProvider = Provider<int>((ref) {
  final announcements = ref.watch(globalAnnouncementsProvider);
  final readIds = ref.watch(readAnnouncementsProvider);

  return announcements.when(
    data: (list) => list.where((a) => !readIds.contains(a.id)).length,
    loading: () => 0,
    error: (_, _) => 0,
  );
});

/// Provider for class messages unread count (Messages badge)
final classMessagesCountProvider = Provider<int>((ref) {
  final messages = ref.watch(classMessagesProvider);
  final readIds = ref.watch(readAnnouncementsProvider);

  return messages.when(
    data: (list) => list.where((a) => !readIds.contains(a.id)).length,
    loading: () => 0,
    error: (_, _) => 0,
  );
});
