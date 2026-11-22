import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  BiometricService._();
  static final BiometricService instance = BiometricService._();

  final LocalAuthentication _auth = LocalAuthentication();
  static const String _prefKey = 'biometric_lock_enabled';
  static const MethodChannel _deviceLockChannel = MethodChannel('com.studentportal.device_lock');

  /// Tracks if the app has launched an external intent (camera, photo picker, file chooser)
  /// to suppress lifecycle-triggered biometric authentication on resume.
  bool _isExternalIntentActive = false;
  DateTime? _intentEndTime;

  bool get isExternalIntentActive => _isExternalIntentActive;

  bool get isInIntentGracePeriod {
    if (_isExternalIntentActive) return true;
    if (_intentEndTime != null &&
        DateTime.now().difference(_intentEndTime!).inMilliseconds < 3000) {
      return true;
    }
    return false;
  }

  void setExternalIntentActive(bool active) {
    _isExternalIntentActive = active;
    if (!active) {
      _intentEndTime = DateTime.now();
    }
  }

  /// Check if the device was locked (screen turned off / locked with PIN or biometrics)
  /// while the app was backgrounded. Resets the native lock flag.
  Future<bool> checkAndResetDeviceLocked() async {
    try {
      final bool? isLocked = await _deviceLockChannel.invokeMethod<bool>('checkAndResetDeviceLocked');
      return isLocked ?? false;
    } on MissingPluginException {
      return false;
    } catch (e) {
      debugPrint('[BiometricService] checkAndResetDeviceLocked error: $e');
      return false;
    }
  }

  /// Check if the device hardware supports biometrics (Face ID, Touch ID, Fingerprint)
  Future<bool> isBiometricsAvailable() async {
    try {
      final isSupported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      final biometrics = await _auth.getAvailableBiometrics();
      return isSupported || canCheck || biometrics.isNotEmpty;
    } on PlatformException catch (e) {
      debugPrint('[BiometricService] isBiometricsAvailable error: $e');
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Get list of available biometric types on device
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } on PlatformException catch (e) {
      debugPrint('[BiometricService] getAvailableBiometrics error: $e');
      return [];
    }
  }

  /// Check if biometric lock is enabled in user settings
  Future<bool> isBiometricLockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  /// Save biometric lock setting
  Future<void> setBiometricLockEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);
  }

  /// Trigger real biometric prompt (Face ID / Touch ID / Fingerprint)
  Future<bool> authenticate({String? reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason ?? 'Authentifiez-vous pour accéder à votre espace élève',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } on PlatformException catch (e) {
      debugPrint('[BiometricService] Authentication error: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[BiometricService] Unknown authentication error: $e');
      return false;
    }
  }
}
