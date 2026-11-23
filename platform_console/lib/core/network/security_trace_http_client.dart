import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Callback type for security-driven force disconnects (401/403 kill-switches)
typedef ForceDisconnectCallback = void Function(String reason);

/// Security and observability HTTP client wrapper for Supabase.
///
/// Features:
/// 1. End-to-End Request Correlation (`x-request-id` UUID v4).
/// 2. Device Context & Fingerprinting (`x-device-fingerprint`).
/// 3. App Surface Attribution (`x-app-surface`: 'console_admin', 'school_admin', 'student_portal').
/// 4. Client Request Timestamping (`x-client-timestamp`).
/// 5. Kill-Switch & Revoked Session Interception (triggers instant local logout on 401/403).
class SecurityTraceHttpClient extends http.BaseClient {
  final String appSurface;
  final http.Client _inner;
  final ForceDisconnectCallback? onForceDisconnect;

  static String? _cachedFingerprint;

  SecurityTraceHttpClient({
    required this.appSurface,
    http.Client? innerClient,
    this.onForceDisconnect,
  }) : _inner = innerClient ?? http.Client() {
    _initFingerprint();
  }

  /// Cryptographically secure RFC-4122 compliant UUID v4 generator
  static String generateTraceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant RFC 4122
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static void _initFingerprint() {
    if (_cachedFingerprint != null) return;
    try {
      SharedPreferences.getInstance().then((prefs) {
        String? fp = prefs.getString('pythaone_device_fingerprint');
        if (fp == null || fp.isEmpty) {
          fp = 'dfp_${generateTraceId()}';
          prefs.setString('pythaone_device_fingerprint', fp);
        }
        _cachedFingerprint = fp;
      }).catchError((_) {
        _cachedFingerprint ??= 'dfp_fallback_${generateTraceId()}';
      });
    } catch (_) {
      _cachedFingerprint ??= 'dfp_memory_${generateTraceId()}';
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final requestId = generateTraceId();
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final fingerprint = _cachedFingerprint ?? 'dfp_evaluating';

    // Inject correlated security and observability headers (skip /functions/ to avoid CORS preflight errors)
    final isEdgeFunction = request.url.path.contains('/functions/');
    if (!isEdgeFunction) {
      request.headers['x-request-id'] = requestId;
      request.headers['x-app-surface'] = appSurface;
      request.headers['x-device-fingerprint'] = fingerprint;
      request.headers['x-client-timestamp'] = timestamp;
    }

    final stopwatch = Stopwatch()..start();
    try {
      final response = await _inner.send(request);
      final latencyMs = stopwatch.elapsedMilliseconds;

      if (kDebugMode && latencyMs > 800) {
        debugPrint('⚠️ [Observability] Slow query [${response.statusCode}] $latencyMs ms (${request.method} ${request.url.path}) trace: $requestId');
      }

      // Pillar 1 & 2: Intercept kill-switch 401/403 or session revocation
      if (response.statusCode == 401 || response.statusCode == 403) {
        final reason = 'Server returned ${response.statusCode} (Kill-Switch or Session Revocation) for trace: $requestId';
        debugPrint('🚨 [Security] $reason');
        onForceDisconnect?.call(reason);
      }

      return response;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Observability] Network failure ($e) trace: $requestId');
      }
      rethrow;
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }

  /// Send asynchronous telemetry to Supabase observability pipeline
  static Future<void> logTelemetry({
    required String eventName,
    String severity = 'info',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final client = Supabase.instance.client;
      await client.rpc('log_telemetry', params: {
        'p_event_name': eventName,
        'p_severity': severity,
        'p_component': 'flutter_client',
        'p_metadata': metadata ?? {},
      });
    } catch (_) {
      // Telemetry must never crash the client application
    }
  }
}

