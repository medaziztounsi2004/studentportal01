import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Offline Persistent Cache Service
/// Caches user data, schedules, results, absences, messages and announcements
/// so the app functions seamlessly with previous data even when offline or server is down.
class OfflineCacheService {
  static OfflineCacheService? _instance;
  SharedPreferences? _prefs;

  OfflineCacheService._();

  static OfflineCacheService get instance => _instance ??= OfflineCacheService._();

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  SharedPreferences? get prefs => _prefs;

  /// Saves a JSON-serializable Map or List to local storage
  Future<bool> setJson(String key, dynamic data) async {
    try {
      final p = _prefs ?? await SharedPreferences.getInstance();
      _prefs = p;
      final encoded = jsonEncode(data);
      return await p.setString('cache_$key', encoded);
    } catch (e) {
      debugPrint('OfflineCacheService.setJson error for key $key: $e');
      return false;
    }
  }

  /// Retrieves a Map from local storage
  Map<String, dynamic>? getMap(String key) {
    try {
      final p = _prefs;
      if (p == null) return null;
      final raw = p.getString('cache_$key');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (e) {
      debugPrint('OfflineCacheService.getMap error for key $key: $e');
      return null;
    }
  }

  /// Retrieves a List of dynamic items from local storage
  List<dynamic>? getList(String key) {
    try {
      final p = _prefs;
      if (p == null) return null;
      final raw = p.getString('cache_$key');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded;
      return null;
    } catch (e) {
      debugPrint('OfflineCacheService.getList error for key $key: $e');
      return null;
    }
  }

  /// Retrieves a List of Maps from local storage
  List<Map<String, dynamic>>? getListOfMaps(String key) {
    try {
      final list = getList(key);
      if (list == null) return null;
      return list
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (e) {
      debugPrint('OfflineCacheService.getListOfMaps error for key $key: $e');
      return null;
    }
  }

  /// Saves a boolean to local storage
  Future<bool> setBool(String key, bool value) async {
    try {
      final p = _prefs ?? await SharedPreferences.getInstance();
      _prefs = p;
      return await p.setBool('cache_$key', value);
    } catch (e) {
      debugPrint('OfflineCacheService.setBool error for key $key: $e');
      return false;
    }
  }

  /// Retrieves a boolean from local storage
  bool? getBool(String key) {
    try {
      final p = _prefs;
      if (p == null) return null;
      return p.getBool('cache_$key');
    } catch (e) {
      debugPrint('OfflineCacheService.getBool error for key $key: $e');
      return null;
    }
  }

  /// Checks if a key exists in cache
  bool has(String key) {
    return _prefs?.containsKey('cache_$key') ?? false;
  }

  /// Removes a specific cached entry
  Future<bool> remove(String key) async {
    final p = _prefs ?? await SharedPreferences.getInstance();
    return await p.remove('cache_$key');
  }

  /// Clears all cached app data
  Future<void> clearAll() async {
    final p = _prefs ?? await SharedPreferences.getInstance();
    final keys = p.getKeys().where((k) => k.startsWith('cache_')).toList();
    for (final k in keys) {
      await p.remove(k);
    }
  }
}
