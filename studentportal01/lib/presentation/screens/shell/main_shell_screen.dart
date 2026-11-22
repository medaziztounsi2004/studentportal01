import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../../providers/announcements_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/school_provider.dart';
import '../../providers/student_context_provider.dart';
import '../../providers/suggestions_provider.dart';
import '../../widgets/bubble_nav_bar.dart';
import '../../../core/services/notification_service.dart';
import '../../../data/services/offline_cache_service.dart';
import '../../../data/services/student_seen_service.dart';
import '../documents/documents_screen.dart';

/// Wraps authenticated app shell to manage FCM token sync and Supabase Realtime
/// provider refreshes plus deduplicated native OS notifications.
class RealtimeNotificationWrapper extends ConsumerStatefulWidget {
  final Widget child;

  const RealtimeNotificationWrapper({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<RealtimeNotificationWrapper> createState() =>
      _RealtimeNotificationWrapperState();
}

class _RealtimeNotificationWrapperState
    extends ConsumerState<RealtimeNotificationWrapper>
    with WidgetsBindingObserver {
  DateTime? _lastResumeSync;
  RealtimeChannel? _globalRealtimeChannel;
  String? _subscribedUserId;
  Timer? _periodicCatchUpTimer;
  final Set<String> _alertedNotificationIds = {};

  void _loadAlertedIds(String userId) {
    try {
      final cached = OfflineCacheService.instance.getList('alerted_notification_ids_$userId');
      if (cached != null) {
        _alertedNotificationIds.addAll(cached.map((e) => e.toString()));
      }
    } catch (_) {}
  }

  void _markAsAlerted(String userId, String id) {
    _alertedNotificationIds.add(id);
    if (_alertedNotificationIds.length > 200) {
      _alertedNotificationIds.removeAll(_alertedNotificationIds.take(50).toList());
    }
    unawaited(OfflineCacheService.instance.setJson(
      'alerted_notification_ids_$userId',
      _alertedNotificationIds.toList(),
    ));
  }

  void _syncExistingNotificationIdsAsAlerted() {
    if (!mounted) return;
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    final userId = session.user.id;
    if (_alertedNotificationIds.isEmpty) {
      _loadAlertedIds(userId);
    }
    try {
      final globalList = ref.read(globalAnnouncementsProvider).valueOrNull ?? [];
      final classList = ref.read(classMessagesProvider).valueOrNull ?? [];
      for (final a in globalList) {
        _alertedNotificationIds.add(a.id);
      }
      for (final m in classList) {
        _alertedNotificationIds.add(m.id);
      }
      unawaited(OfflineCacheService.instance.setJson(
        'alerted_notification_ids_$userId',
        _alertedNotificationIds.toList(),
      ));
    } catch (e) {
      debugPrint('Sync existing notification IDs error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _setupRealtime();
      await LocalNotificationService.requestPermissions();
      if (!mounted) return;
      final userId = Supabase.instance.client.auth.currentSession?.user.id;
      if (userId != null) {
        _loadAlertedIds(userId);
        unawaited(StudentSeenService.preloadAll(userId));
        unawaited(LocalNotificationService.syncDeviceToken(userId).catchError((_) {}));
      }
      await Future.delayed(const Duration(milliseconds: 1000));
      if (mounted) {
        _syncExistingNotificationIdsAsAlerted();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodicCatchUpTimer?.cancel();
    _tearDownRealtime();
    super.dispose();
  }

  void _tearDownRealtime() {
    if (_globalRealtimeChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_globalRealtimeChannel!);
      } catch (_) {}
      _globalRealtimeChannel = null;
      _subscribedUserId = null;
    }
  }

  String? get _currentSchoolId {
    final auth = ref.read(authProvider);
    final ctx = ref.read(studentContextProvider).valueOrNull;
    return ctx?.schoolId ?? auth.user?.schoolId ?? auth.enrollment?.classInfo?.schoolId;
  }

  String? get _currentClassId {
    final auth = ref.read(authProvider);
    final ctx = ref.read(studentContextProvider).valueOrNull;
    return ctx?.classId ?? auth.enrollment?.classId;
  }

  void _setupRealtime() {
    try {
      if (!mounted) return;
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;
      if (session == null) return;
      final userId = session.user.id;

      // Sync FCM device token for background push notifications
      unawaited(LocalNotificationService.syncDeviceToken(userId).catchError((_) {}));

      if (_subscribedUserId == userId && _globalRealtimeChannel != null) {
        return; // already subscribed for this user
      }

      _tearDownRealtime();
      _subscribedUserId = userId;

      _globalRealtimeChannel =
          supabase.channel('student_portal_realtime_shell_$userId');

      // 1. Global announcements (Notifications)
      _globalRealtimeChannel?.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'announcements_global',
        callback: (payload) {
          if (!mounted) return;
          final record = payload.newRecord;
          final mySchoolId = _currentSchoolId;
          final recSchoolId = record['school_id']?.toString();
          if (mySchoolId != null &&
              recSchoolId != null &&
              recSchoolId.isNotEmpty &&
              recSchoolId != mySchoolId) {
            return;
          }

          debugPrint('Realtime Shell: announcements_global updated -> refreshing');
          ref.invalidate(globalAnnouncementsProvider);

          if (payload.eventType == PostgresChangeEvent.insert) {
            final title =
                record['title']?.toString().trim().isNotEmpty == true
                    ? record['title']!.toString().trim()
                    : 'Nouvelle notification';
            final body = record['body']?.toString().trim() ?? '';
            final message =
                body.isNotEmpty ? body : 'Nouvelle notification disponible';
            final recId = record['id']?.toString();
            final route = recId != null && recId.isNotEmpty
                ? '/notifications?id=$recId'
                : '/notifications';
            final dedupKey = recId != null && recId.isNotEmpty
                ? 'announcements_global:$recId'
                : null;

            if (recId != null) _markAsAlerted(userId, recId);

            LocalNotificationService.showNotification(
              id: LocalNotificationService.stableNotificationId(
                  dedupKey ?? '$title|$message|$route'),
              title: title,
              body: message,
              routePayload: route,
              dedupKey: dedupKey,
            );
          }
        },
      );

      // 2. Class messages (Messages)
      _globalRealtimeChannel?.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'announcements_class',
        callback: (payload) {
          if (!mounted) return;
          final record = payload.newRecord;
          final mySchoolId = _currentSchoolId;
          final recSchoolId = record['school_id']?.toString();
          if (mySchoolId != null &&
              recSchoolId != null &&
              recSchoolId.isNotEmpty &&
              recSchoolId != mySchoolId) {
            return;
          }

          final myClassId = _currentClassId;
          final recClassId = record['class_id']?.toString();
          if (myClassId != null &&
              recClassId != null &&
              recClassId.isNotEmpty &&
              recClassId != myClassId) {
            return;
          }

          final recPayload = record['payload'];
          String? targetStudentId;
          if (recPayload is Map) {
            targetStudentId = recPayload['target_student_id']?.toString();
            if (targetStudentId != null &&
                targetStudentId.isNotEmpty &&
                targetStudentId != userId) {
              return;
            }
          }

          debugPrint('Realtime Shell: announcements_class updated -> refreshing');
          ref.invalidate(classMessagesProvider);

          if (payload.eventType == PostgresChangeEvent.insert) {
            final rawTitle = record['title']?.toString().trim() ?? '';
            final title = rawTitle.isNotEmpty
                ? rawTitle
                : (targetStudentId != null && targetStudentId.isNotEmpty
                    ? 'Nouveau message'
                    : 'Nouveau message de classe');
            final cleanBody = (record['body']?.toString() ?? '')
                .replaceFirst(RegExp(r'^\*\*@[^*]+\*\*\s*'), '')
                .trim();
            final message = cleanBody.isNotEmpty
                ? cleanBody
                : 'Nouveau message disponible';
            final recId = record['id']?.toString();
            final route = recId != null && recId.isNotEmpty
                ? '/messages?id=$recId'
                : '/messages';
            final dedupKey = recId != null && recId.isNotEmpty
                ? 'announcements_class:$recId'
                : null;

            if (recId != null) _markAsAlerted(userId, recId);

            LocalNotificationService.showNotification(
              id: LocalNotificationService.stableNotificationId(
                  dedupKey ?? '$title|$message|$route'),
              title: title,
              body: message,
              routePayload: route,
              dedupKey: dedupKey,
            );
          }
        },
      );

      // 3. Student personal announcements (Messages ciblés)
      _globalRealtimeChannel?.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'announcements_student',
        callback: (payload) {
          if (!mounted) return;
          final record = payload.newRecord;
          final recStudentId = record['student_id']?.toString() ??
              (record['payload'] is Map ? record['payload']['target_student_id']?.toString() : null);
          if (recStudentId != null && recStudentId.isNotEmpty && recStudentId != userId) {
            return;
          }

          debugPrint('Realtime Shell: announcements_student updated -> refreshing');
          ref.invalidate(classMessagesProvider);
          ref.invalidate(globalAnnouncementsProvider);

          if (payload.eventType == PostgresChangeEvent.insert) {
            final title = record['title']?.toString().trim().isNotEmpty == true
                ? record['title']!.toString().trim()
                : 'Nouveau message personnel';
            final body = record['body']?.toString().trim() ?? '';
            final message = body.isNotEmpty ? body : 'Nouveau message disponible';
            final recId = record['id']?.toString();
            final route = recId != null && recId.isNotEmpty ? '/messages?id=$recId' : '/messages';
            final dedupKey = recId != null && recId.isNotEmpty ? 'announcements_student:$recId' : null;

            if (recId != null) _markAsAlerted(userId, recId);

            LocalNotificationService.showNotification(
              id: LocalNotificationService.stableNotificationId(
                  dedupKey ?? '$title|$message|$route'),
              title: title,
              body: message,
              routePayload: route,
              dedupKey: dedupKey,
            );
          }
        },
      );

      // 4. Suggestions & Replies
      _globalRealtimeChannel?.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'suggestions',
        callback: (payload) {
          if (!mounted) return;
          final studentId = payload.newRecord['student_id']?.toString() ??
              payload.oldRecord['student_id']?.toString();
          if (studentId != null && studentId.isNotEmpty && studentId != userId) {
            return;
          }
          debugPrint('Realtime Shell: suggestions updated -> refreshing');
          ref.invalidate(suggestionsProvider);
        },
      );

      _globalRealtimeChannel?.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'suggestion_replies',
        callback: (payload) async {
          if (!mounted) return;
          final record = payload.newRecord;
          final suggestionId = record['suggestion_id']?.toString();

          if (suggestionId != null && suggestionId.isNotEmpty) {
            try {
              final suggestion = await supabase
                  .from('suggestions')
                  .select('student_id')
                  .eq('id', suggestionId)
                  .maybeSingle();
              if (!mounted) return;
              if (suggestion == null ||
                  suggestion['student_id']?.toString() != userId) {
                return;
              }
            } catch (_) {
              // If verification fails, still refresh provider quietly without popping another user's alert
              if (mounted) ref.invalidate(suggestionsProvider);
              return;
            }
          }

          if (!mounted) return;
          debugPrint('Realtime Shell: suggestion_replies updated -> refreshing');
          ref.invalidate(suggestionsProvider);

          if (payload.eventType == PostgresChangeEvent.insert) {
            final text = (record['reply_text'] ??
                    record['body'] ??
                    record['message'] ??
                    '')
                .toString()
                .trim();
            final message = text.isNotEmpty
                ? text
                : 'L\'administration a répondu à votre suggestion.';
            final recId = record['id']?.toString();
            final dedupKey = recId != null && recId.isNotEmpty
                ? 'suggestion_replies:$recId'
                : null;

            LocalNotificationService.showNotification(
              id: LocalNotificationService.stableNotificationId(
                  dedupKey ?? 'Réponse à votre suggestion|$message|/suggestions'),
              title: 'Réponse à votre suggestion',
              body: message,
              routePayload: '/suggestions',
              dedupKey: dedupKey,
            );
          }
        },
      );

      // 5. Documents
      _globalRealtimeChannel?.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'documents',
        callback: (payload) {
          if (!mounted) return;
          final record = payload.newRecord;
          final mySchoolId = _currentSchoolId;
          final recSchoolId = record['school_id']?.toString();
          if (mySchoolId != null &&
              recSchoolId != null &&
              recSchoolId.isNotEmpty &&
              recSchoolId != mySchoolId) {
            return;
          }

          final myClassId = _currentClassId;
          final recClassId = record['class_id']?.toString();
          if (myClassId != null &&
              recClassId != null &&
              recClassId.isNotEmpty &&
              recClassId != myClassId) {
            return;
          }

          final desc = record['description']?.toString() ?? '';
          final studentMatch =
              RegExp(r'\[Student:\s*([^|\]]+)').firstMatch(desc);
          if (studentMatch != null) {
            final targetStudentId = studentMatch.group(1)?.trim();
            if (targetStudentId != null &&
                targetStudentId.isNotEmpty &&
                targetStudentId != userId) {
              return;
            }
          }

          debugPrint('Realtime Shell: documents updated -> refreshing');
          ref.invalidate(allStudentDocumentsProvider);

          if (payload.eventType == PostgresChangeEvent.insert &&
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed) {
            final rawTitle = record['title']?.toString().trim() ?? '';
            final title =
                'Nouveau document : ${rawTitle.isNotEmpty ? rawTitle : 'Document'}';
            final cleanDesc = desc
                .replaceAll(RegExp(r'\[Semestre:\s*\d+\]'), '')
                .replaceAll(RegExp(r'\[Student:\s*[^\]]+\]'), '')
                .replaceAll(RegExp(r'\[Type:\s*[^\]]+\]'), '')
                .trim();
            final message = cleanDesc.isNotEmpty
                ? cleanDesc
                : 'Un nouveau document a été partagé.';
            final recId = record['id']?.toString();
            final route = recId != null && recId.isNotEmpty
                ? '/documents?id=$recId'
                : '/documents';
            final dedupKey =
                recId != null && recId.isNotEmpty ? 'documents:$recId' : null;

            if (recId != null) _markAsAlerted(userId, recId);

            LocalNotificationService.showNotification(
              id: LocalNotificationService.stableNotificationId(
                  dedupKey ?? '$title|$message|$route'),
              title: title,
              body: message,
              routePayload: route,
              dedupKey: dedupKey,
            );
          }
        },
      );

      // 5. School branding updates (logo_url, name)
      _globalRealtimeChannel?.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'schools',
        callback: (payload) {
          if (!mounted) return;
          final mySchoolId = _currentSchoolId;
          final recSchoolId = payload.newRecord['id']?.toString();
          if (mySchoolId != null &&
              recSchoolId != null &&
              recSchoolId.isNotEmpty &&
              recSchoolId != mySchoolId) {
            return;
          }
          debugPrint('Realtime Shell: school branding updated -> refreshing');
          ref.invalidate(schoolProvider);
        },
      );

      _globalRealtimeChannel?.subscribe((status, error) async {
        debugPrint(
          'Realtime Shell subscription status: $status, error: $error',
        );
        if (status == RealtimeSubscribeStatus.channelError && error != null) {
          final errStr = error.toString().toLowerCase();
          if (errStr.contains('jwt') || errStr.contains('expired') || errStr.contains('token')) {
            debugPrint('Realtime Shell: Token expired, refreshing session...');
            try {
              final response = await Supabase.instance.client.auth.refreshSession();
              if (response.session != null && mounted) {
                debugPrint('Realtime Shell: Session refreshed successfully');
              }
            } catch (e) {
              debugPrint('Realtime Shell: Failed to refresh session: $e');
            }
          }
        }
      });
    } catch (e) {
      debugPrint('Realtime shell setup error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      if (_lastResumeSync == null ||
          now.difference(_lastResumeSync!) > const Duration(seconds: 3)) {
        _lastResumeSync = now;
        final userId = Supabase.instance.client.auth.currentSession?.user.id;
        if (userId != null) {
          LocalNotificationService.syncDeviceToken(userId);
        }
        if (!mounted) return;
        ref.invalidate(semestersProvider);
        ref.invalidate(schoolProvider);
        ref.invalidate(globalAnnouncementsProvider);
        ref.invalidate(classMessagesProvider);
        ref.invalidate(allStudentDocumentsProvider);
        ref.invalidate(suggestionsProvider);
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) {
            _syncExistingNotificationIdsAsAlerted();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for auth state changes to connect/disconnect realtime
    ref.listen<AuthState>(authProvider, (_, next) {
      if (next.isAuthenticated) {
        _setupRealtime();
      } else {
        _tearDownRealtime();
      }
    });

    return widget.child;
  }
}

class MainShellScreen extends StatelessWidget {
  final Widget child;
  final int currentIndex;

  const MainShellScreen({
    super.key,
    required this.child,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return RealtimeNotificationWrapper(
      child: Scaffold(
        extendBody: true,
        body: child,
        bottomNavigationBar: BubbleNavBar(currentIndex: currentIndex),
      ),
    );
  }
}


