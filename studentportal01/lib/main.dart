import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:intl/date_symbol_data_local.dart';

import 'dart:ui';
import 'core/config/supabase_config.dart';
import 'core/network/security_trace_http_client.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/l10n/app_localizations.dart';
import 'core/services/notification_service.dart';
import 'data/services/offline_cache_service.dart';
import 'presentation/providers/auth_provider.dart';
import 'presentation/providers/locale_provider.dart';
import 'presentation/widgets/offline_indicator_banner.dart';
import 'presentation/widgets/biometric_lock_overlay.dart';

void main() {
  // runZonedGuarded must wrap EVERYTHING including ensureInitialized so that
  // the binding and runApp are in the same zone (prevents "Zone mismatch" crash).
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await initializeDateFormatting();

      // Catch all unhandled Flutter framework errors (prevent crashes and correlate telemetry)
      FlutterError.onError = (details) {
        debugPrint('[STUDENT PORTAL] FlutterError caught: ${details.exceptionAsString()}');
        SecurityTraceHttpClient.logTelemetry(
          eventName: 'flutter_framework_error',
          severity: 'error',
          metadata: {
            'exception': details.exceptionAsString(),
            'library': details.library,
          },
        );
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        debugPrint('[STUDENT PORTAL] PlatformDispatcher error: $error');
        SecurityTraceHttpClient.logTelemetry(
          eventName: 'platform_dispatcher_error',
          severity: 'critical',
          metadata: {'error': error.toString()},
        );
        return true;
      };

      // Initialize persistent offline cache
      await OfflineCacheService.instance.init();

      // Initialize Supabase with correlated security & tracing client
      await Supabase.initialize(
        url: SupabaseConfig.url,
        // ignore: deprecated_member_use
        anonKey: SupabaseConfig.anonKey,
        httpClient: SecurityTraceHttpClient(
          appSurface: 'student_portal',
          onForceDisconnect: (reason) {
            debugPrint('[SECURITY] Student Portal forced disconnect: $reason');
          },
        ),
      );

      // Initialize native local notifications for system alerts
      await LocalNotificationService.init();

      // Set system UI overlay style
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      );

      // Set preferred orientations
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      runApp(
        const ProviderScope(
          child: StudentPortalApp(),
        ),
      );
    },
    (error, stack) {
      // Log but do NOT rethrow — prevents "Lost connection to device" crashes
      // caused by AuthRetryableFetchException from GoTrue auto-refresh.
      debugPrint('Unhandled async error (zone): $error');
    },
  );
}



class StudentPortalApp extends ConsumerWidget {
  const StudentPortalApp({super.key});

  ThemeData _applyLocaleFont(ThemeData theme, Locale? locale) {
    if (locale?.languageCode == 'ar') {
      final isDark = theme.brightness == Brightness.dark;
      final pColor = isDark ? Colors.white : AppColors.textPrimary;
      final sColor = isDark ? Colors.grey[400]! : AppColors.textSecondary;

      final arabicText = AppTheme.arabicTextTheme(
        theme.textTheme,
        primaryColor: pColor,
        secondaryColor: sColor,
      );

      return theme.copyWith(
        textTheme: arabicText,
        appBarTheme: theme.appBarTheme.copyWith(
          titleTextStyle: GoogleFonts.cairo(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: pColor,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            textStyle: GoogleFonts.tajawal(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            textStyle: GoogleFonts.tajawal(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            textStyle: GoogleFonts.tajawal(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          labelStyle: GoogleFonts.tajawal(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: sColor,
          ),
          hintStyle: GoogleFonts.tajawal(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
        ),
        dialogTheme: theme.dialogTheme.copyWith(
          titleTextStyle: GoogleFonts.cairo(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: pColor,
          ),
          contentTextStyle: GoogleFonts.tajawal(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: sColor,
          ),
        ),
      );
    }
    return theme;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(localeProvider);

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: MaterialApp.router(
        title: 'PythaOne',
        debugShowCheckedModeBanner: false,
        theme: _applyLocaleFont(AppTheme.lightTheme, locale),
        darkTheme: _applyLocaleFont(AppTheme.lightTheme, locale),
        themeMode: ThemeMode.light,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: router,
        builder: (context, child) {
          final authState = ref.watch(authProvider);
          final mediaQuery = MediaQuery.of(context);
          final clampedTextScaler = mediaQuery.textScaler.clamp(
            minScaleFactor: 0.85,
            maxScaleFactor: 1.10,
          );

          Widget body = child ?? const SizedBox.shrink();
          final isAccessLocked = authState.isAuthenticated && authState.isAccessLocked;
          if (isAccessLocked) {
            body = _AccessLockedScreen(
              isSchoolSuspended: authState.schoolSuspended,
              onRefresh: () => ref.read(authProvider.notifier).refreshUserData(),
            );
          }

          return MediaQuery(
            data: mediaQuery.copyWith(textScaler: clampedTextScaler),
            child: BiometricLockOverlay(
              child: Stack(
                children: [
                  body,
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: OfflineIndicatorBanner(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AccessLockedScreen extends StatefulWidget {
  final bool isSchoolSuspended;
  final Future<bool> Function() onRefresh;

  const _AccessLockedScreen({
    required this.isSchoolSuspended,
    required this.onRefresh,
  });

  @override
  State<_AccessLockedScreen> createState() => _AccessLockedScreenState();
}

class _AccessLockedScreenState extends State<_AccessLockedScreen> {
  bool _isChecking = false;
  String? _feedbackMessage;
  bool _isError = false;

  Future<void> _handleRefresh() async {
    if (_isChecking) return;
    setState(() {
      _isChecking = true;
      _feedbackMessage = null;
    });

    try {
      final isUnlocked = await widget.onRefresh();
      if (mounted) {
        if (!isUnlocked) {
          setState(() {
            _isChecking = false;
            _isError = true;
            _feedbackMessage = widget.isSchoolSuspended
                ? 'L\'application est toujours hors service pour votre établissement.'
                : 'Votre compte est toujours suspendu par l\'administration.';
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _isError = true;
          _feedbackMessage = 'Connexion impossible. Vérifiez votre réseau.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      widget.isSchoolSuspended
                          ? Icons.domain_disabled_rounded
                          : Icons.lock_person_rounded,
                      size: 32,
                      color: const Color(0xFFDC2626),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.isSchoolSuspended
                        ? 'Application hors service'
                        : 'Accès temporairement suspendu',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.isSchoolSuspended
                        ? 'L\'application est actuellement hors service pour votre établissement. Veuillez contacter la direction de votre école.'
                        : 'Votre compte est temporairement suspendu. Veuillez contacter l\'administration.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isChecking ? null : _handleRefresh,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6D4CF6),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF8B5CF6),
                        disabledForegroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isChecking) ...[
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Vérification en cours...',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ] else ...[
                            const Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
                            const SizedBox(width: 8),
                            const Text(
                              'Vérifier mon accès',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_feedbackMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _feedbackMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: _isError ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
