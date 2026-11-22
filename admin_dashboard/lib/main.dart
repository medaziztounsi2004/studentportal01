import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/config/supabase_config.dart';
import 'core/network/security_trace_http_client.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'presentation/providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    debugPrint('[ADMIN DASHBOARD] FlutterError: ${details.exceptionAsString()}');
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
    debugPrint('[ADMIN DASHBOARD] PlatformDispatcher error: $error');
    SecurityTraceHttpClient.logTelemetry(
      eventName: 'platform_dispatcher_error',
      severity: 'critical',
      metadata: {'error': error.toString()},
    );
    return true;
  };

  await initializeDateFormatting('fr_FR', null);
  await SupabaseConfig.initialize();
  runApp(const ProviderScope(child: AdminApp()));
}

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    return MaterialApp.router(
      title: 'Admin Dashboard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('fr', 'FR'),
        Locale('en', 'US'),
      ],
      locale: const Locale('fr', 'FR'),
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        if (!authState.isAuthenticated) return content;

        // When school is suspended by the super admin:
        // The entire admin dashboard is completely gone and replaced by the centered suspension screen
        if (authState.isSchoolSuspended && authState.user?.role != 'super_admin') {
          return const _AdminSchoolSuspendedScreen();
        }

        // First-login forced permanent password setup
        if (authState.user?.forcePasswordChange == true) {
          return _ForcedPasswordChangeScreen(
            userName: authState.user?.fullName ?? 'Administrateur',
          );
        }

        // Past-due subscription warning banner
        if (authState.schoolSubscriptionStatus == 'past_due') {
          return Column(
            children: [
              Material(
                color: const Color(0xFFFEF3C7),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFF59E0B)),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: Color(0xFFB45309),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Abonnement en retard de paiement (past_due) — Veuillez régulariser avec l\'administrateur de la plateforme avant suspension.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(child: content),
            ],
          );
        }

        return content;
      },
    );
  }
}

class _ForcedPasswordChangeScreen extends ConsumerStatefulWidget {
  final String userName;
  const _ForcedPasswordChangeScreen({required this.userName});

  @override
  ConsumerState<_ForcedPasswordChangeScreen> createState() =>
      _ForcedPasswordChangeScreenState();
}

class _ForcedPasswordChangeScreenState
    extends ConsumerState<_ForcedPasswordChangeScreen> {
  final _newCtrl = TextEditingController();
  final _confCtrl = TextEditingController();
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _newCtrl.dispose();
    _confCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final p1 = _newCtrl.text.trim();
    final p2 = _confCtrl.text.trim();
    if (p1.length < 8) {
      setState(() => _error = 'Minimum 8 caractères requis.');
      return;
    }
    if (p1 != p2) {
      setState(() => _error = 'Les mots de passe ne correspondent pas.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final err = await ref
        .read(authProvider.notifier)
        .completeForcedPasswordChange(p1);
    if (err != null && mounted) {
      setState(() {
        _saving = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Première connexion',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Bienvenue ${widget.userName}. Veuillez définir votre mot de passe permanent avant d\'accéder au tableau de bord.',
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 18),
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFB91C1C),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              TextField(
                controller: _newCtrl,
                obscureText: _obscure1,
                decoration: InputDecoration(
                  labelText: 'Nouveau mot de passe',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure1
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () => setState(() => _obscure1 = !_obscure1),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confCtrl,
                obscureText: _obscure2,
                decoration: InputDecoration(
                  labelText: 'Confirmer le mot de passe',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure2
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () => setState(() => _obscure2 = !_obscure2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6D4CF6),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    _saving
                        ? 'Enregistrement...'
                        : 'Enregistrer et continuer',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminSchoolSuspendedScreen extends StatelessWidget {
  const _AdminSchoolSuspendedScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: const _SuspendedSchoolCard(),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuspendedSchoolCard extends StatelessWidget {
  const _SuspendedSchoolCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Flat soft red icon container (no gradients)
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.shield_outlined,
              size: 28,
              color: Color(0xFFDC2626),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Établissement suspendu',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'L\'accès à la plateforme pour cet établissement est actuellement suspendu par l\'administration centrale. Pour toute information ou réactivation, veuillez contacter le support de la plateforme.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 20),
          // Clean status indicator (no action button)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFEE2E2)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 13,
                  color: Color(0xFFDC2626),
                ),
                SizedBox(width: 6),
                Text(
                  'Accès restreint',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

