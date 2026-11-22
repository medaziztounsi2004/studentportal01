import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/services/offline_cache_service.dart';
import '../../data/services/student_seen_service.dart';
import '../../core/services/connectivity_service.dart';
import 'auth_provider.dart';

/// Model for suggestion attachment
class SuggestionAttachment {
  final String id;
  final String fileUrl;
  final String fileName;
  final String? fileType;
  final int? fileSize;

  SuggestionAttachment({
    required this.id,
    required this.fileUrl,
    required this.fileName,
    this.fileType,
    this.fileSize,
  });

  factory SuggestionAttachment.fromJson(Map<String, dynamic> json) {
    return SuggestionAttachment(
      id: json['id']?.toString() ?? '',
      fileUrl: json['file_url']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? '',
      fileType: json['file_type']?.toString(),
      fileSize: json['file_size'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'file_url': fileUrl,
      'file_name': fileName,
      'file_type': fileType,
      'file_size': fileSize,
    };
  }
}

/// Model for admin reply
class SuggestionReply {
  final String id;
  final String replyText;
  final DateTime createdAt;

  SuggestionReply({
    required this.id,
    required this.replyText,
    required this.createdAt,
  });

  factory SuggestionReply.fromJson(Map<String, dynamic> json) {
    return SuggestionReply(
      id: json['id']?.toString() ?? '',
      replyText: json['reply_text']?.toString() ?? json['body']?.toString() ?? json['message']?.toString() ?? '',
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'].toString()) : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reply_text': replyText,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// Model for student suggestion
class Suggestion {
  final String id;
  final String title;
  final String body;
  final String suggestionType;
  final String status;
  final bool isRead;
  final bool hasAttachment;
  final DateTime createdAt;
  final DateTime? readAt;
  final List<SuggestionAttachment> attachments;
  final List<SuggestionReply> replies;

  Suggestion({
    required this.id,
    required this.title,
    required this.body,
    this.suggestionType = 'general',
    this.status = 'pending',
    this.isRead = false,
    this.hasAttachment = false,
    required this.createdAt,
    this.readAt,
    this.attachments = const [],
    this.replies = const [],
  });

  factory Suggestion.fromJson(
    Map<String, dynamic> json, {
    List<SuggestionAttachment> attachments = const [],
    List<SuggestionReply> replies = const [],
  }) {
    return Suggestion(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? json['subject']?.toString() ?? '',
      body: json['body']?.toString() ?? json['content']?.toString() ?? json['message']?.toString() ?? '',
      suggestionType: json['suggestion_type']?.toString() ?? 'general',
      status: json['status']?.toString() ?? 'pending',
      isRead: json['is_read'] as bool? ?? false,
      hasAttachment: json['has_attachment'] as bool? ?? false,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'].toString()) : DateTime.now(),
      readAt: json['read_at'] != null ? DateTime.tryParse(json['read_at'].toString()) : null,
      attachments: attachments,
      replies: replies,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'suggestion_type': suggestionType,
      'status': status,
      'is_read': isRead,
      'has_attachment': hasAttachment,
      'created_at': createdAt.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
      'attachments': attachments.map((a) => a.toJson()).toList(),
      'replies': replies.map((r) => r.toJson()).toList(),
    };
  }

  factory Suggestion.fromCachedJson(Map<String, dynamic> json) {
    final atts = (json['attachments'] as List?)
        ?.map((a) => SuggestionAttachment.fromJson(Map<String, dynamic>.from(a as Map)))
        .toList() ?? [];
    final reps = (json['replies'] as List?)
        ?.map((r) => SuggestionReply.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList() ?? [];
    return Suggestion.fromJson(json, attachments: atts, replies: reps);
  }
}

/// Loading state for suggestions refresh
final suggestionsRefreshingProvider = StateProvider<bool>((ref) => false);

/// Provider for user's suggestions with resilient offline cache
final suggestionsProvider = FutureProvider.autoDispose<List<Suggestion>>((ref) async {
  final supabase = Supabase.instance.client;
  final authState = ref.watch(authProvider);

  final userId = authState.user?.id 
      ?? supabase.auth.currentUser?.id 
      ?? OfflineCacheService.instance.getMap('cached_user')?['id'] as String?;

  if (userId == null) {
    return [];
  }

  final cacheKey = 'suggestions_$userId';

  try {
    // Fetch suggestions
    final response = await supabase
        .from('suggestions')
        .select()
        .eq('student_id', userId)
        .order('created_at', ascending: false);

    final suggestions = response as List;
    final suggestionIds = suggestions.map((s) => s['id']?.toString() ?? '').where((id) => id.isNotEmpty).toList();

    if (suggestionIds.isEmpty) {
      await OfflineCacheService.instance.setJson(cacheKey, []);
      ConnectivityService.instance.reportNetworkSuccess();
      return [];
    }

    // Fetch attachments
    final attachmentsResponse = await supabase
        .from('suggestion_attachments')
        .select()
        .inFilter('suggestion_id', suggestionIds);

    final Map<String, List<SuggestionAttachment>> attachmentsMap = {};
    for (final att in (attachmentsResponse as List)) {
      final suggestionId = att['suggestion_id']?.toString() ?? '';
      if (suggestionId.isEmpty) continue;
      final attachment = SuggestionAttachment.fromJson(att);
      attachmentsMap.putIfAbsent(suggestionId, () => []).add(attachment);
    }

    // Fetch replies
    final repliesResponse = await supabase
        .from('suggestion_replies')
        .select()
        .inFilter('suggestion_id', suggestionIds)
        .order('created_at', ascending: true);

    final Map<String, List<SuggestionReply>> repliesMap = {};
    for (final reply in (repliesResponse as List)) {
      final suggestionId = reply['suggestion_id']?.toString() ?? '';
      if (suggestionId.isEmpty) continue;
      final replyObj = SuggestionReply.fromJson(reply);
      repliesMap.putIfAbsent(suggestionId, () => []).add(replyObj);
    }

    final results = suggestions
        .where((json) {
          final type = json['suggestion_type']?.toString().toLowerCase() ?? '';
          final title = (json['title'] ?? json['subject'] ?? '').toString();
          final body = (json['body'] ?? json['content'] ?? json['message'] ?? '').toString();
          if (type == 'bug_report' || type == 'bug') return false;
          if (title.contains('[BUG REPORT') || body.contains('[BUG REPORT')) return false;
          return true;
        })
        .map(
          (json) => Suggestion.fromJson(
            json,
            attachments: attachmentsMap[json['id']] ?? [],
            replies: repliesMap[json['id']] ?? [],
          ),
        )
        .toList();

    // Persist to offline cache
    await OfflineCacheService.instance.setJson(
      cacheKey,
      results.map((s) => s.toJson()).toList(),
    );
    await OfflineCacheService.instance.setJson(
      'suggestions_latest',
      results.map((s) => s.toJson()).toList(),
    );
    // Realtime subscription for suggestions and replies
    RealtimeChannel? channel;
    try {
      channel = supabase
          .channel('suggestions_realtime_$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'suggestions',
            callback: (_) {
              debugPrint('Realtime: suggestions table changed -> refreshing');
              ref.invalidateSelf();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'suggestion_replies',
            callback: (_) {
              debugPrint('Realtime: suggestion_replies table changed -> refreshing');
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

    ConnectivityService.instance.reportNetworkSuccess();
    return results;
  } catch (e) {
    debugPrint('suggestionsProvider error (offline?): $e');
    ConnectivityService.instance.reportNetworkError(e);

    // Offline fallback from cache
    final cached = OfflineCacheService.instance.getList(cacheKey) 
        ?? OfflineCacheService.instance.getList('suggestions_latest');
    if (cached != null && cached.isNotEmpty) {
      return cached
          .map((item) => Suggestion.fromCachedJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    }
    return [];
  }
});

/// Provider for creating a suggestion
final suggestionRepositoryProvider = Provider((ref) => SuggestionRepository(ref));

class SuggestionRepository {
  final Ref ref;
  
  SuggestionRepository(this.ref);

  Future<String> createSuggestion({
    required String title,
    required String body,
    String suggestionType = 'general',
    List<String>? attachmentUrls,
    List<String>? attachmentNames,
    List<String>? attachmentTypes,
    List<int>? attachmentSizes,
  }) async {
    final supabase = Supabase.instance.client;
    final authState = ref.read(authProvider);
    final session = supabase.auth.currentSession;

    // Check both authState and session directly
    if (!authState.isAuthenticated && session == null) {
      throw Exception('User not authenticated');
    }

    // Get userId from authState or directly from session
    final userId = authState.user?.id ?? session?.user.id;
    if (userId == null) {
      throw Exception('User ID not available');
    }
    
    final enrollment = authState.enrollment;

    // Create suggestion
    final suggestionData = {
      'student_id': userId,
      'subject': title, // Old field name for backward compatibility
      'title': title,   // New field name
      'message': body,  // Old field name for backward compatibility
      'body': body,     // New field name
      'suggestion_type': suggestionType,
      'status': 'sent',  // Database enum: sent, read, replied
      'has_attachment': attachmentUrls != null && attachmentUrls.isNotEmpty,
      'student_name': authState.user?.fullName,
      'student_code': authState.user?.studentCode,
      'class_id': enrollment?.classId,
      'class_name': enrollment?.classInfo?.name,
      'group_id': enrollment?.groupId,
      'enrollment_id': enrollment?.id,
      'school_id': authState.user?.schoolId,
    };

    final response = await supabase
        .from('suggestions')
        .insert(suggestionData)
        .select()
        .single();

    final suggestionId = response['id'] as String;

    // Add attachments if any
    if (attachmentUrls != null && attachmentUrls.isNotEmpty) {
      for (int i = 0; i < attachmentUrls.length; i++) {
        await supabase.from('suggestion_attachments').insert({
          'suggestion_id': suggestionId,
          'file_url': attachmentUrls[i],
          'file_name': attachmentNames?[i] ?? 'attachment_$i',
          'file_type': attachmentTypes?[i],
          'file_size': attachmentSizes?[i],
        });
      }
    }

    return suggestionId;
  }

  Future<String> uploadFile(String filePath, String fileName) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser!.id;
    
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storePath = '$userId/${timestamp}_$fileName';
    
    await supabase.storage
        .from('suggestions')
        .uploadBinary(storePath, Uint8List.fromList(await _readFileBytes(filePath)));
    
    return supabase.storage.from('suggestions').getPublicUrl(storePath);
  }

  Future<List<int>> _readFileBytes(String filePath) async {
    // This would use dart:io File.readAsBytes() in a real implementation
    // For web, you'd handle it differently with html.File
    throw UnimplementedError('File reading not implemented for this platform');
  }
}

// Count providers for suggestions
final pendingSuggestionsCountProvider = Provider<int>((ref) {
  final suggestions = ref.watch(suggestionsProvider);
  return suggestions.when(
    data: (list) => list.where((s) => s.status == 'pending' && !s.isRead).length,
    loading: () => 0,
    error: (_, _) => 0,
  );
});

final readSuggestionsCountProvider = Provider<int>((ref) {
  final suggestions = ref.watch(suggestionsProvider);
  return suggestions.when(
    data: (list) => list.where((s) => s.isRead).length,
    loading: () => 0,
    error: (_, _) => 0,
  );
});

/// Set of suggestion IDs whose replies have been seen/read by the student
final readRepliedSuggestionsProvider =
    StateNotifierProvider<ReadRepliedSuggestionsNotifier, Set<String>>((ref) {
  final authState = ref.watch(authProvider);
  final userId = authState.user?.id ?? 'default_user';
  return ReadRepliedSuggestionsNotifier(userId);
});

class ReadRepliedSuggestionsNotifier extends StateNotifier<Set<String>> {
  final String userId;
  static const _storagePrefix = 'read_replied_suggestions_';

  ReadRepliedSuggestionsNotifier(this.userId) : super({}) {
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
      debugPrint('ReadRepliedSuggestionsNotifier load error: $e');
    }
  }

  Future<void> _syncRemote() async {
    if (userId.isEmpty || userId == 'default_user') return;
    try {
      final remoteIds = await StudentSeenService.fetchSeenIds(
        userId,
        [StudentSeenService.typeSuggestionReply],
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
      debugPrint('ReadRepliedSuggestionsNotifier _syncRemote error: $e');
    }
  }

  Future<void> syncRemote() => _syncRemote();

  Future<void> markAsRead(String id) async {
    if (state.contains(id)) return;
    final updated = Set<String>.from(state)..add(id);
    state = updated;
    await OfflineCacheService.instance.setJson('$_storagePrefix$userId', updated.toList());
    if (userId.isNotEmpty && userId != 'default_user') {
      unawaited(StudentSeenService.markItemSeen(userId, StudentSeenService.typeSuggestionReply, id));
    }
  }

  bool isRead(String id) => state.contains(id);
}

final repliedSuggestionsCountProvider = Provider<int>((ref) {
  final suggestions = ref.watch(suggestionsProvider);
  final readRepliedIds = ref.watch(readRepliedSuggestionsProvider);
  return suggestions.when(
    data: (list) => list.where((s) => s.replies.isNotEmpty && !readRepliedIds.contains(s.id)).length,
    loading: () => 0,
    error: (_, _) => 0,
  );
});

/// Count of suggestions that have been replied to OR marked as seen by admin
final repliedOrSeenSuggestionsCountProvider = Provider<int>((ref) {
  final suggestions = ref.watch(suggestionsProvider);
  final readRepliedIds = ref.watch(readRepliedSuggestionsProvider);
  return suggestions.when(
    data: (list) => list.where((s) => (s.replies.isNotEmpty || s.isRead) && !readRepliedIds.contains(s.id)).length,
    loading: () => 0,
    error: (_, _) => 0,
  );
});

final allSuggestionsCountProvider = Provider<int>((ref) {
  final suggestions = ref.watch(suggestionsProvider);
  return suggestions.when(
    data: (list) => list.length,
    loading: () => 0,
    error: (_, _) => 0,
  );
});

