import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/services/biometric_service.dart';
import 'bouncing_wrapper.dart';

class BiometricLockOverlay extends StatefulWidget {
  final Widget child;

  const BiometricLockOverlay({super.key, required this.child});

  @override
  State<BiometricLockOverlay> createState() => _BiometricLockOverlayState();
}

class _BiometricLockOverlayState extends State<BiometricLockOverlay>
    with WidgetsBindingObserver {
  bool _isLocked = false;
  bool _isAuthenticating = false;
  bool _hasUnlockedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInitialLock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleAppResumed();
    }
  }

  /// Initial cold-start check: if biometric lock is enabled, lock and prompt once.
  Future<void> _checkInitialLock() async {
    final enabled = await BiometricService.instance.isBiometricLockEnabled();
    if (enabled && mounted) {
      setState(() => _isLocked = true);
      _triggerBiometricAuth();
    }
  }

  /// App resume handler:
  /// - If authentication dialog is currently showing, ignore.
  /// - Only re-lock if the device itself was locked while backgrounded,
  ///   or if the app was never unlocked in this session.
  /// - If the app was just backgrounded without locking the phone, DO NOT prompt.
  Future<void> _handleAppResumed() async {
    if (_isAuthenticating) return;

    final enabled = await BiometricService.instance.isBiometricLockEnabled();
    if (!enabled || !mounted) return;

    final wasDeviceLocked =
        await BiometricService.instance.checkAndResetDeviceLocked();

    if (wasDeviceLocked || !_hasUnlockedOnce) {
      if (!_isLocked && mounted) {
        setState(() => _isLocked = true);
      }
      _triggerBiometricAuth();
    }
  }

  Future<void> _triggerBiometricAuth() async {
    if (_isAuthenticating) return;
    _isAuthenticating = true;

    try {
      final success = await BiometricService.instance.authenticate(
        reason: 'Déverrouillez pour accéder à votre espace élève',
      );

      if (success && mounted) {
        _hasUnlockedOnce = true;
        setState(() => _isLocked = false);
      }
    } finally {
      _isAuthenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_isLocked)
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  color: Colors.white.withValues(alpha: 0.95),
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.fingerprint_rounded,
                            size: 42,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Espace Élève Sécurisé',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E293B),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Verrouillage biométrique actif.\nVeuillez vous authentifier pour continuer.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade600,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 32),
                        BouncingWrapper(
                          shrinkScale: 0.94,
                          onTap: _triggerBiometricAuth,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_open_rounded, color: Colors.white, size: 20),
                                SizedBox(width: 10),
                                Text(
                                  'Déverrouiller',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
