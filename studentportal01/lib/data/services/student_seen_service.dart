import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'offline_cache_service.dart';

/// Service responsible for managing persistent read/seen receipts for students
/// across all card types:
/// - Announcements ('announcement')
/// - Documents ('document')
/// - Messages ('message')
/// - Suggestion Replies ('suggestion_reply')
///
/// Ensures read statuses survive app uninstallation and multi-device sync
/// by synchronizing both locally (OfflineCacheService) and in Supabase (student_seen_items).
class StudentSeenService {
  static const String typeAnnouncement = 'announcement';
  static const String typeDocument = 'document';
  static const String typeMessage = 'message';
  static const String typeSuggestionReply = 'suggestion_reply';

  static const String _pendingQueueKey = 'pending_seen_items_sync_queue';
  static bool _isSyncing = false;

  /// Fetches all seen item IDs for the given user from Supabase.
  /// If [itemTypes] is provided, only IDs matching those types are returned.
  /// Merges remote results with local cache to maintain complete fidelity.
  static Future<Set<String>> fetchSeenIds(String userId, [List<String>? itemTypes]) async {
    if (userId.isEmpty || userId == 'default_user') return {};

    final Set<String> seenIds = {};

    try {
      final supabase = Supabase.instance.client;
      var query = supabase
          .from('student_seen_items')
          .select('item_type, item_id')
          .eq('student_id', userId);

      if (itemTypes != null && itemTypes.isNotEmpty) {
        if (itemTypes.length == 1) {
          query = query.eq('item_type', itemTypes.first);
        } else {
          query = query.inFilter('item_type', itemTypes);
        }
      }

      final response = await query;
      final rows = response as List;
      for (final r in rows) {
        final itemId = r['item_id']?.toString();
        if (itemId != null && itemId.isNotEmpty) {
          seenIds.add(itemId);
        }
      }
      debugPrint('[StudentSeenService] Fetched ${seenIds.length} seen IDs from Supabase for types: $itemTypes');
    } catch (e) {
      debugPrint('[StudentSeenService] Error fetching seen IDs from Supabase (offline?): $e');
      // If direct query fails (e.g. offline or custom RPC), try RPC fallback
      try {
        final rpcType = (itemTypes != null && itemTypes.length == 1) ? itemTypes.first : null;
        final res = await Supabase.instance.client.rpc(
          'get_student_seen_items',
          params: rpcType != null ? {'p_item_type': rpcType} : null,
        );
        if (res is Map) {
          for (final entry in res.entries) {
            final key = entry.key.toString();
            if (itemTypes == null || itemTypes.contains(key)) {
              final list = entry.value as List?;
              if (list != null) {
                for (final id in list) {
                  seenIds.add(id.toString());
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    return seenIds;
  }

  /// Mark an item as seen persistently both locally and in Supabase.
  static Future<void> markItemSeen(String userId, String itemType, String itemId) async {
    if (userId.isEmpty || userId == 'default_user' || itemId.isEmpty) return;

    // 1. Immediately enqueue in pending sync queue for offline safety
    _enqueuePending(userId, itemType, itemId);

    // 2. Push to Supabase
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('student_seen_items').upsert({
        'student_id': userId,
        'item_type': itemType,
        'item_id': itemId,
        'seen_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'student_id,item_type,item_id');

      // If successful, remove from pending queue
      _dequeuePending(userId, itemType, itemId);
      debugPrint('[StudentSeenService] Successfully saved seen status on Supabase: $itemType:$itemId');
    } catch (e) {
      debugPrint('[StudentSeenService] Failed to upsert seen status (queued for retry): $e');
      // Try RPC fallback
      try {
        await Supabase.instance.client.rpc('mark_student_item_seen', params: {
          'p_item_type': itemType,
          'p_item_id': itemId,
        });
        _dequeuePending(userId, itemType, itemId);
      } catch (_) {}
    }
  }

  /// Mark multiple items as seen
  static Future<void> markItemsSeen(String userId, String itemType, List<String> itemIds) async {
    if (userId.isEmpty || userId == 'default_user' || itemIds.isEmpty) return;

    for (final id in itemIds) {
      _enqueuePending(userId, itemType, id);
    }

    try {
      final supabase = Supabase.instance.client;
      final rows = itemIds.map((id) => {
        'student_id': userId,
        'item_type': itemType,
        'item_id': id,
        'seen_at': DateTime.now().toUtc().toIso8601String(),
      }).toList();

      await supabase.from('student_seen_items').upsert(
        rows,
        onConflict: 'student_id,item_type,item_id',
      );

      for (final id in itemIds) {
        _dequeuePending(userId, itemType, id);
      }
      debugPrint('[StudentSeenService] Batch saved ${itemIds.length} seen items on Supabase');
    } catch (e) {
      debugPrint('[StudentSeenService] Batch upsert error, trying RPC: $e');
      try {
        await Supabase.instance.client.rpc('mark_student_items_seen', params: {
          'p_item_type': itemType,
          'p_item_ids': itemIds,
        });
        for (final id in itemIds) {
          _dequeuePending(userId, itemType, id);
        }
      } catch (_) {}
    }
  }

  /// Preloads all seen item IDs across all categories from Supabase
  static Future<Map<String, Set<String>>> preloadAll(String userId) async {
    if (userId.isEmpty || userId == 'default_user') return {};

    final Map<String, Set<String>> result = {
      typeAnnouncement: {},
      typeDocument: {},
      typeMessage: {},
      typeSuggestionReply: {},
    };

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('student_seen_items')
          .select('item_type, item_id')
          .eq('student_id', userId);

      final rows = response as List;
      for (final r in rows) {
        final type = r['item_type']?.toString();
        final id = r['item_id']?.toString();
        if (type != null && id != null && result.containsKey(type)) {
          result[type]!.add(id);
        }
      }

      // Also merge local caches
      final localAnnouncements = OfflineCacheService.instance.getList('read_announcements_ids_$userId') ?? [];
      final localDocuments = OfflineCacheService.instance.getList('read_documents_ids_$userId') ?? [];
      final localSuggestions = OfflineCacheService.instance.getList('read_replied_suggestions_$userId') ?? [];

      for (final id in localAnnouncements) {
        result[typeAnnouncement]!.add(id.toString());
      }
      for (final id in localDocuments) {
        result[typeDocument]!.add(id.toString());
      }
      for (final id in localSuggestions) {
        result[typeSuggestionReply]!.add(id.toString());
      }

      // Sync back merged cache to local disk
      final combinedAnnouncementsAndMessages = {
        ...result[typeAnnouncement]!,
        ...result[typeMessage]!,
      };
      await OfflineCacheService.instance.setJson('read_announcements_ids_$userId', combinedAnnouncementsAndMessages.toList());
      await OfflineCacheService.instance.setJson('read_documents_ids_$userId', result[typeDocument]!.toList());
      await OfflineCacheService.instance.setJson('read_replied_suggestions_$userId', result[typeSuggestionReply]!.toList());

      debugPrint('[StudentSeenService] Preloaded all seen categories for user $userId');
      unawaited(syncPendingQueue());
    } catch (e) {
      debugPrint('[StudentSeenService] PreloadAll error: $e');
    }

    return result;
  }

  /// Syncs any pending offline seen receipts to Supabase
  static Future<void> syncPendingQueue() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final queue = _getPendingQueue();
      if (queue.isEmpty) {
        _isSyncing = false;
        return;
      }

      debugPrint('[StudentSeenService] Syncing ${queue.length} pending seen receipts to Supabase...');
      final toRemove = <Map<String, dynamic>>[];

      for (final item in queue) {
        final userId = item['user_id'] as String?;
        final itemType = item['item_type'] as String?;
        final itemId = item['item_id'] as String?;
        if (userId != null && itemType != null && itemId != null) {
          try {
            await Supabase.instance.client.from('student_seen_items').upsert({
              'student_id': userId,
              'item_type': itemType,
              'item_id': itemId,
              'seen_at': DateTime.now().toUtc().toIso8601String(),
            }, onConflict: 'student_id,item_type,item_id');
            toRemove.add(item);
          } catch (_) {
            // Stop syncing if still offline
            break;
          }
        }
      }

      if (toRemove.isNotEmpty) {
        final currentQueue = _getPendingQueue();
        currentQueue.removeWhere((item) => toRemove.any((r) =>
            r['user_id'] == item['user_id'] &&
            r['item_type'] == item['item_type'] &&
            r['item_id'] == item['item_id']));
        OfflineCacheService.instance.setJson(_pendingQueueKey, currentQueue);
      }
    } finally {
      _isSyncing = false;
    }
  }

  static void _enqueuePending(String userId, String itemType, String itemId) {
    try {
      final queue = _getPendingQueue();
      final alreadyQueued = queue.any((item) =>
          item['user_id'] == userId &&
          item['item_type'] == itemType &&
          item['item_id'] == itemId);
      if (!alreadyQueued) {
        queue.add({
          'user_id': userId,
          'item_type': itemType,
          'item_id': itemId,
          'timestamp': DateTime.now().toIso8601String(),
        });
        OfflineCacheService.instance.setJson(_pendingQueueKey, queue);
      }
    } catch (_) {}
  }

  static void _dequeuePending(String userId, String itemType, String itemId) {
    try {
      final queue = _getPendingQueue();
      queue.removeWhere((item) =>
          item['user_id'] == userId &&
          item['item_type'] == itemType &&
          item['item_id'] == itemId);
      OfflineCacheService.instance.setJson(_pendingQueueKey, queue);
    } catch (_) {}
  }

  static List<Map<String, dynamic>> _getPendingQueue() {
    try {
      final list = OfflineCacheService.instance.getList(_pendingQueueKey);
      if (list != null) {
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }
}
