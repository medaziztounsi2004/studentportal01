import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/invoice_pdf_generator.dart';
import '../../core/theme/console_theme.dart';
import '../providers/platform_provider.dart';
import '../widgets/console_invoice_modal.dart';
import '../widgets/console_school_credentials_modal.dart';
import '../widgets/console_sidebar.dart';
import '../widgets/console_skeleton_loader.dart';

// ═══════════════════════════════════════════════════════════════════
// DATA MODEL FOR SCHOOL PROFILE
// ═══════════════════════════════════════════════════════════════════

class SchoolProfileData {
  final Map<String, dynamic> school;
  final Map<String, dynamic>? subscription;
  final Map<String, dynamic>? plan;
  final Map<String, dynamic>? aiQuota;
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> invoices;
  final List<Map<String, dynamic>> aiLogs;
  final List<Map<String, dynamic>> auditLogs;

  final int studentCount;
  final int teacherCount;
  final int staffCount;
  final int maxCapacity;

  final double mrrTnd;
  final double aiSpentUsd;
  final double aiBudgetUsd;
  final int aiTokensMonth;

  final double totalInvoicedTnd;
  final double totalPaidTnd;
  final int pendingInvoicesCount;
  final double pendingAmountTnd;

  SchoolProfileData({
    required this.school,
    this.subscription,
    this.plan,
    this.aiQuota,
    this.users = const [],
    this.invoices = const [],
    this.aiLogs = const [],
    this.auditLogs = const [],
    this.studentCount = 0,
    this.teacherCount = 0,
    this.staffCount = 0,
    this.maxCapacity = 200,
    this.mrrTnd = 0.0,
    this.aiSpentUsd = 0.0,
    this.aiBudgetUsd = 25.0,
    this.aiTokensMonth = 0,
    this.totalInvoicedTnd = 0.0,
    this.totalPaidTnd = 0.0,
    this.pendingInvoicesCount = 0,
    this.pendingAmountTnd = 0.0,
  });
}

// ═══════════════════════════════════════════════════════════════════
// SCHOOL PROFILE PROVIDER
// ═══════════════════════════════════════════════════════════════════

final schoolProfileDataProvider =
    FutureProvider.autoDispose.family<SchoolProfileData?, String>((ref, schoolId) async {
  final supabase = Supabase.instance.client;

  try {
    // 1. School data with subscription and plan
    Map<String, dynamic>? school;
    try {
      final schoolResp = await supabase
          .from('schools')
          .select('''
            id, name, code, logo_url, email, phone, address, is_active, created_at,
            school_subscriptions (
              id, status, billing_cycle, current_period_start, current_period_end, notes,
              plan:subscription_plans(id, code, name, price_tnd_monthly, price_tnd_yearly, max_students, ai_budget_included_usd, features)
            ),
            ai_school_quotas (
              monthly_budget_usd, spent_current_month_usd, tokens_current_month, is_quota_exceeded, kill_switch_enabled
            )
          ''')
          .eq('id', schoolId)
          .maybeSingle();

      if (schoolResp != null) {
        school = Map<String, dynamic>.from(schoolResp);
      }
    } catch (e) {
      debugPrint('SchoolProfile: primary school query error: $e');
    }

    // Fallback: check cached schools in platformProvider
    if (school == null) {
      final cachedSchools = ref.read(platformProvider).schools;
      final match = cachedSchools.where((s) => s['id']?.toString() == schoolId).toList();
      if (match.isNotEmpty) {
        school = Map<String, dynamic>.from(match.first);
      }
    }

    // Fallback 2: simple school query without joins
    if (school == null) {
      try {
        final simpleResp = await supabase
            .from('schools')
            .select('id, name, code, logo_url, email, phone, address, is_active, created_at')
            .eq('id', schoolId)
            .maybeSingle();
        if (simpleResp != null) {
          school = Map<String, dynamic>.from(simpleResp);
        }
      } catch (e) {
        debugPrint('SchoolProfile: fallback school query error: $e');
      }
    }

    if (school == null) return null;


    Map<String, dynamic>? sub;
    final rawSub = school['school_subscriptions'];
    if (rawSub is Map<String, dynamic>) {
      sub = rawSub;
    } else if (rawSub is List && rawSub.isNotEmpty) {
      sub = Map<String, dynamic>.from(rawSub.first);
    }

    Map<String, dynamic>? plan;
    if (sub != null && sub['plan'] != null) {
      final rawPlan = sub['plan'];
      if (rawPlan is Map<String, dynamic>) {
        plan = rawPlan;
      } else if (rawPlan is List && rawPlan.isNotEmpty) {
        plan = Map<String, dynamic>.from(rawPlan.first);
      }
    }

    Map<String, dynamic>? quota;
    final rawQuota = school['ai_school_quotas'];
    if (rawQuota is Map<String, dynamic>) {
      quota = rawQuota;
    } else if (rawQuota is List && rawQuota.isNotEmpty) {
      quota = Map<String, dynamic>.from(rawQuota.first);
    }

    // 2. Users for this school
    List<Map<String, dynamic>> users = [];
    int studentCount = 0;
    int teacherCount = 0;
    int staffCount = 0;
    try {
      final usersResp = await supabase
          .from('users')
          .select('id, full_name, email, role, phone, is_active, initial_password, created_at')
          .eq('school_id', schoolId)
          .order('created_at', ascending: false)
          .limit(100);
      users = List<Map<String, dynamic>>.from(usersResp);
      for (final u in users) {
        final role = (u['role'] as String? ?? '').toLowerCase();
        if (role == 'student') {
          studentCount++;
        } else if (role == 'teacher') {
          teacherCount++;
        } else {
          staffCount++;
        }
      }
    } catch (e) {
      debugPrint('SchoolProfile: users error: $e');
    }

    // 3. Invoices for this school
    List<Map<String, dynamic>> invoices = [];
    double totalInvoiced = 0.0;
    double totalPaid = 0.0;
    int pendingCount = 0;
    double pendingAmount = 0.0;
    try {
      final invResp = await supabase
          .from('invoices')
          .select('*, invoice_payments(*)')
          .eq('school_id', schoolId)
          .order('created_at', ascending: false)
          .limit(50);
      invoices = List<Map<String, dynamic>>.from(invResp);
      for (final inv in invoices) {
        final amt = (inv['amount'] as num?)?.toDouble() ?? 0.0;
        final status = (inv['status'] as String? ?? '').toLowerCase();
        totalInvoiced += amt;
        if (status == 'paid') {
          totalPaid += amt;
        } else {
          pendingCount++;
          pendingAmount += amt;
        }
      }
    } catch (e) {
      debugPrint('SchoolProfile: invoices error: $e');
    }

    // 4. AI usage logs
    List<Map<String, dynamic>> aiLogs = [];
    try {
      final aiResp = await supabase
          .from('ai_usage_logs')
          .select('*')
          .eq('school_id', schoolId)
          .order('created_at', ascending: false)
          .limit(50);
      aiLogs = List<Map<String, dynamic>>.from(aiResp);
    } catch (e) {
      debugPrint('SchoolProfile: aiLogs error: $e');
    }

    // 5. Audit logs
    List<Map<String, dynamic>> auditLogs = [];
    try {
      final auditResp = await supabase
          .from('audit_logs')
          .select('*')
          .eq('school_id', schoolId)
          .order('created_at', ascending: false)
          .limit(40);
      auditLogs = List<Map<String, dynamic>>.from(auditResp);
    } catch (e) {
      debugPrint('SchoolProfile: auditLogs error: $e');
    }

    // MRR & AI spend
    final mrr = (plan?['price_tnd_monthly'] as num?)?.toDouble() ?? 850.0;
    final aiSpent = (quota?['spent_current_month_usd'] as num?)?.toDouble() ?? 0.0;
    final aiBudget = (quota?['monthly_budget_usd'] as num?)?.toDouble() ?? 25.0;
    final aiTokens = (quota?['tokens_current_month'] as num?)?.toInt() ?? 0;

    int maxCap = 200;
    if (plan?['max_students'] != null) {
      maxCap = (plan!['max_students'] as num).toInt();
    } else if (sub?['notes'] != null) {
      try {
        final notes = jsonDecode(sub!['notes'].toString());
        if (notes['max_students'] != null) {
          maxCap = int.parse(notes['max_students'].toString());
        }
      } catch (_) {}
    }

    return SchoolProfileData(
      school: school,
      subscription: sub,
      plan: plan,
      aiQuota: quota,
      users: users,
      invoices: invoices,
      aiLogs: aiLogs,
      auditLogs: auditLogs,
      studentCount: studentCount,
      teacherCount: teacherCount,
      staffCount: staffCount,
      maxCapacity: maxCap,
      mrrTnd: mrr,
      aiSpentUsd: aiSpent,
      aiBudgetUsd: aiBudget,
      aiTokensMonth: aiTokens,
      totalInvoicedTnd: totalInvoiced,
      totalPaidTnd: totalPaid,
      pendingInvoicesCount: pendingCount,
      pendingAmountTnd: pendingAmount,
    );
  } catch (e) {
    debugPrint('SchoolProfile: fetch error: $e');
    return null;
  }
});

// ═══════════════════════════════════════════════════════════════════
// SCHOOL PROFILE SCREEN (CLONED EXACTLY FROM USER PROFILE SCREEN)
// ═══════════════════════════════════════════════════════════════════

class SchoolProfileScreen extends ConsumerStatefulWidget {
  final String schoolId;
  const SchoolProfileScreen({super.key, required this.schoolId});

  @override
  ConsumerState<SchoolProfileScreen> createState() => _SchoolProfileScreenState();
}

class _SchoolProfileScreenState extends ConsumerState<SchoolProfileScreen> {
  int _activeTabIndex = 0; // 0: Facturation, 1: Consommation IA, 2: Utilisateurs, 3: Journal
  bool _isUploadingLogo = false;
  bool _showDirectorPassword = false;
  final Set<String> _unhiddenUserIds = {};

  // Pagination states for all 4 section tables (limited view per page like Users table)
  int _invoicesPage = 0;
  int _invoicesPageSize = 5;

  int _aiLogsPage = 0;
  int _aiLogsPageSize = 5;

  int _usersPage = 0;
  int _usersPageSize = 5;

  int _auditPage = 0;
  int _auditPageSize = 5;

  String _formatTokens(int count) {
    if (count >= 1000000) {
      return "${(count / 1000000).toStringAsFixed(1)}M";
    } else if (count >= 1000) {
      return "${(count / 1000).toStringAsFixed(1)}k";
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(schoolProfileDataProvider(widget.schoolId));

    return Scaffold(
      backgroundColor: ConsoleColors.background,
      body: Row(
        children: [
          const ConsoleSidebar(currentRoute: '/schools'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── TOP HEADER (ALWAYS STATIC, NEVER SKELETON SHIMMER) ──
                  _buildHeader(profileAsync.asData?.value),
                  const SizedBox(height: 28),

                  // ── 2-COLUMN BODY ──
                  profileAsync.when(
                    loading: () => const SchoolProfileSkeleton(),
                    error: (err, _) => _buildErrorView(err),
                    data: (data) {
                      if (data == null) return _buildNotFoundView();
                      return _buildTwoColumnsLayout(context, data);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // TWO COLUMNS LAYOUT
  // ═══════════════════════════════════════════════════
  Widget _buildTwoColumnsLayout(BuildContext context, SchoolProfileData data) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // LEFT COLUMN (360px)
        SizedBox(
          width: 360,
          child: Column(
            children: [
              _buildSchoolIdentityCard(data),
              const SizedBox(height: 24),
              _buildSubscriptionCard(data),
            ],
          ),
        ),
        const SizedBox(width: 28),

        // RIGHT COLUMN (EXPANDED)
        Expanded(
          child: Column(
            children: [
              // 4 Golden Ratio KPI cards (NO badges, NO overflow)
              _buildStatsGrid(data),
              const SizedBox(height: 28),

              // Tab bar + Tab content matching Users screen
              _buildTabbedSection(data),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  // UNIFIED HEADER BUTTON (EXACT SAME HEIGHT, PADDING, SHAPE)
  // ═══════════════════════════════════════════════════
  Widget _buildHeaderActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? backgroundColor,
    Color? foregroundColor,
    BorderSide? side,
  }) {
    final isFilled = backgroundColor != null;
    return SizedBox(
      height: 38,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: foregroundColor ?? (isFilled ? Colors.white : const Color(0xFF475569))),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: foregroundColor ?? (isFilled ? Colors.white : const Color(0xFF334155)),
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ?? Colors.white,
          foregroundColor: foregroundColor ?? const Color(0xFF334155),
          elevation: 0,
          side: side ?? (isFilled ? BorderSide.none : const BorderSide(color: Color(0xFFE2E8F0))),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          minimumSize: const Size(0, 38),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // TOP HEADER (NO ACTIVE PILL, NO CODE PILL, NO ACTUALISER BTN)
  // ═══════════════════════════════════════════════════
  Widget _buildHeader(SchoolProfileData? data) {
    if (data == null) {
      return Container(
        padding: const EdgeInsets.only(bottom: 20),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Row(
          children: [
            // Back button (Always interactive)
            _buildIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Retour aux établissements',
              onTap: () => context.go('/schools'),
            ),
            const SizedBox(width: 16),

            // Shimmer title & static subtitle (like TeacherProfileSkeletonLoader)
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConsoleShimmerLoading(
                    child: ConsoleSkeletonBox(
                      width: 220,
                      height: 22,
                      borderRadius: 6,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Profil établissement',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),

            // Header Action Buttons placeholder wrapped in IgnorePointer
            IgnorePointer(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildHeaderActionButton(
                    icon: Icons.picture_as_pdf_rounded,
                    label: 'Générer Facture',
                    onTap: () {},
                    backgroundColor: const Color(0xFF6D4CF6),
                    foregroundColor: Colors.white,
                  ),
                  _buildHeaderActionButton(
                    icon: Icons.tune_rounded,
                    label: 'Quota IA',
                    onTap: () {},
                  ),
                  _buildHeaderActionButton(
                    icon: Icons.card_membership_rounded,
                    label: 'Changer Forfait',
                    onTap: () {},
                  ),
                  _buildHeaderActionButton(
                    icon: Icons.toggle_on_rounded,
                    label: 'Désactiver',
                    onTap: () {},
                    backgroundColor: const Color(0xFFF1F5F9),
                    foregroundColor: const Color(0xFF64748B),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final school = data.school;
    final name = (school['name'] as String?) ?? 'Établissement';

    String formattedCreated = '—';
    if (school['created_at'] != null) {
      try {
        final dt = DateTime.parse(school['created_at'].toString());
        formattedCreated = DateFormat('dd/MM/yyyy').format(dt);
      } catch (_) {}
    }

    return Container(
      padding: const EdgeInsets.only(bottom: 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          // Back button (Always interactive)
          _buildIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Retour aux établissements',
            onTap: () => context.go('/schools'),
          ),
          const SizedBox(width: 16),

          // Avatar
          _buildSchoolAvatar(school, size: 48),
          const SizedBox(width: 16),

          // Title & Subtitle (Clean, NO pills)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Établissement SaaS • Inscrit le $formattedCreated',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Action Buttons: EXACT SAME SIZE, HEIGHT, AND PROPORTIONS
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 1. Primary Action Button: Générer Facture
              _buildHeaderActionButton(
                icon: Icons.picture_as_pdf_rounded,
                label: 'Générer Facture',
                onTap: () => _openInvoiceModal(data),
                backgroundColor: const Color(0xFF6D4CF6),
                foregroundColor: Colors.white,
              ),
              // 2. Quota IA Button
              _buildHeaderActionButton(
                icon: Icons.tune_rounded,
                label: 'Quota IA',
                onTap: () => _openQuotaDialog(data),
              ),
              // 3. Changer Forfait Button
              _buildHeaderActionButton(
                icon: Icons.card_membership_rounded,
                label: 'Changer Forfait',
                onTap: () => _openPlanDialog(data),
              ),
              // 4. Mot de passe & Identifiants Button
              _buildHeaderActionButton(
                icon: Icons.key_rounded,
                label: 'Mot de passe',
                onTap: () => _openCredentialsModal(data),
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
              ),
              // 5. Suspendre / Réactiver Button
              _buildStatusToggleButton(data),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // LEFT COLUMN: IDENTITY CARD (CONTAINS STATUS & CODE DATA ROWS)
  // ═══════════════════════════════════════════════════
  Widget _buildSchoolIdentityCard(SchoolProfileData data) {
    final school = data.school;
    final name = (school['name'] as String?) ?? 'Établissement';
    final email = (school['email'] as String?) ?? '—';
    final phone = (school['phone'] as String?) ?? '—';
    final address = (school['address'] as String?) ?? 'Non renseignée';
    final rawCode = (school['code'] ?? '—').toString().toUpperCase();
    final isActive = school['is_active'] == true;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo & Change Avatar
          Center(
            child: Stack(
              children: [
                _buildSchoolAvatar(school, size: 76),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: InkWell(
                    onTap: _isUploadingLogo ? null : () => _pickAndUploadLogo(school['id']),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6D4CF6),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: _isUploadingLogo
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.camera_alt_rounded, size: 13, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 20),

          // Statut Row
          _buildInfoRow(
            Icons.shield_outlined,
            'Statut',
            isActive ? 'Actif' : 'Suspendu',
            customValueWidget: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive ? const Color(0xFF059669) : const Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isActive ? 'Actif' : 'Suspendu',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isActive ? const Color(0xFF059669) : const Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Code Établissement Row
          _buildInfoRow(
            Icons.tag_rounded,
            'Code Établissement',
            rawCode,
            copyable: rawCode != '—',
          ),
          const SizedBox(height: 14),

          // Email Directeur
          _buildInfoRow(
            Icons.email_outlined,
            'Email Directeur',
            email,
            copyable: email != '—',
          ),
          const SizedBox(height: 14),

          // Mot de passe Administrateur
          _buildPasswordInfoRow(data),
          const SizedBox(height: 14),

          // Téléphone
          _buildInfoRow(
            Icons.phone_outlined,
            'Téléphone',
            phone,
            copyable: phone != '—',
          ),
          const SizedBox(height: 14),

          // Adresse
          _buildInfoRow(
            Icons.location_on_outlined,
            'Adresse',
            address,
          ),
          const SizedBox(height: 14),

          // Capacité Élèves
          _buildInfoRow(
            Icons.groups_outlined,
            'Capacité Élèves',
            "${data.studentCount} / ${data.maxCapacity} inscrits",
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // LEFT COLUMN: SUBSCRIPTION & LICENSE CARD
  // ═══════════════════════════════════════════════════
  Widget _buildSubscriptionCard(SchoolProfileData data) {
    final plan = data.plan;
    final planName = (plan?['name'] as String?) ?? 'Plan Pro';
    final price = plan?['price_tnd_monthly'] ?? 850;
    final sub = data.subscription;
    final billingCycle = (sub?['billing_cycle'] as String?) ?? 'monthly';

    String periodEnd = 'Renouvellement auto';
    if (sub?['current_period_end'] != null) {
      try {
        final dt = DateTime.parse(sub!['current_period_end'].toString());
        periodEnd = DateFormat('dd/MM/yyyy').format(dt);
      } catch (_) {}
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ABONNEMENT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Color(0xFF94A3B8),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  planName.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7C3AED),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$price TND',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                billingCycle == 'yearly' ? '/ an' : '/ mois',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildCheckItem("Quota IA: \$${data.aiBudgetUsd.toStringAsFixed(0)} USD inclus / mois"),
          _buildCheckItem("Capacité maximale: ${data.maxCapacity} élèves"),
          _buildCheckItem("Accès Espace Direction & Enseignants"),
          _buildCheckItem("Télémétrie IA et Facturation automatisée"),
          const SizedBox(height: 18),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Prochaine échéance',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              Text(
                periodEnd,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _openPlanDialog(data),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6D4CF6),
                side: const BorderSide(color: Color(0xFFDDD6FE)),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Modifier le forfait', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // RIGHT COLUMN: 4 GOLDEN-RATIO METRIC CARDS (NO BADGES, NO OVERFLOW)
  // ═══════════════════════════════════════════════════
  Widget _buildStatsGrid(SchoolProfileData data) {
    return Row(
      children: [
        // 1. MRR
        Expanded(
          child: _buildMetricCard(
            title: 'MRR MENSUEL',
            value: '${data.mrrTnd.toStringAsFixed(0)} TND',
            subtitle: 'Facturation active',
            icon: Icons.trending_up_rounded,
            iconColor: ConsoleColors.success,
          ),
        ),
        const SizedBox(width: 16),

        // 2. AI Spend
        Expanded(
          child: _buildMetricCard(
            title: 'DÉPENSES IA',
            value: "\$${data.aiSpentUsd.toStringAsFixed(2)}",
            subtitle: "${_formatTokens(data.aiTokensMonth)} tokens • Quota \$${data.aiBudgetUsd.toStringAsFixed(0)}",
            icon: Icons.auto_awesome_rounded,
            iconColor: ConsoleColors.brand,
          ),
        ),
        const SizedBox(width: 16),

        // 3. Students
        Expanded(
          child: _buildMetricCard(
            title: 'ÉLÈVES INSCRITS',
            value: '${data.studentCount}',
            subtitle: "Max ${data.maxCapacity} • ${data.teacherCount} profs",
            icon: Icons.school_rounded,
            iconColor: ConsoleColors.primary,
          ),
        ),
        const SizedBox(width: 16),

        // 4. Invoices
        Expanded(
          child: _buildMetricCard(
            title: 'TOTAL RECOUVRÉ',
            value: '${data.totalPaidTnd.toStringAsFixed(0)} TND',
            subtitle: "${data.pendingInvoicesCount} impayée(s) • ${data.pendingAmountTnd.toStringAsFixed(0)} TND",
            icon: Icons.receipt_long_rounded,
            iconColor: ConsoleColors.warning,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // RIGHT COLUMN: TABBED SECTIONS (MATCHING USERS SCREEN)
  // ═══════════════════════════════════════════════════
  Widget _buildTabbedSection(SchoolProfileData data) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Segmented Tab Bar matching Users screen
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      _buildTabPill(0, 'Facturation', data.invoices.length, Icons.receipt_long_outlined),
                      _buildTabPill(1, 'Consommation IA', null, Icons.auto_awesome_outlined),
                      _buildTabPill(2, 'Utilisateurs', data.users.length, Icons.people_outline_rounded),
                      _buildTabPill(3, "Journal d'Activité", data.auditLogs.length, Icons.history_rounded),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          // Tab Content
          IndexedStack(
            index: _activeTabIndex,
            children: [
              _buildInvoicesTab(data),
              _buildAiTelemetryTab(data),
              _buildUsersTab(data),
              _buildAuditTab(data),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabPill(int index, String label, int? count, IconData icon) {
    final isActive = _activeTabIndex == index;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _activeTabIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? const Color(0xFF0F172A) : const Color(0xFF64748B),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0xFFEDE9FE) : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: isActive ? const Color(0xFF6D4CF6) : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // REUSABLE TABLE PAGINATION BAR (MATCHING USERS TABLE EXACTLY)
  // ═══════════════════════════════════════════════════
  Widget _buildTablePaginationBar({
    required int totalItems,
    required int currentPage,
    required int pageSize,
    required ValueChanged<int> onPageChanged,
    required ValueChanged<int> onPageSizeChanged,
  }) {
    final totalPages = (totalItems / pageSize).ceil();
    final startIdx = totalItems == 0 ? 0 : currentPage * pageSize + 1;
    final endIdx = ((currentPage + 1) * pageSize).clamp(0, totalItems);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          const Text('Afficher par ', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: pageSize,
                isDense: true,
                borderRadius: BorderRadius.circular(10),
                dropdownColor: Colors.white,
                items: const [
                  DropdownMenuItem(value: 5, child: Text('5', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)))),
                  DropdownMenuItem(value: 10, child: Text('10', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)))),
                  DropdownMenuItem(value: 20, child: Text('20', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)))),
                  DropdownMenuItem(value: 50, child: Text('50', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)))),
                ],
                onChanged: (v) {
                  if (v != null) onPageSizeChanged(v);
                },
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            totalItems == 0 ? '0 résultat' : '$startIdx–$endIdx sur $totalItems',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const Spacer(),
          Text(
            'Page ${totalPages == 0 ? 1 : currentPage + 1} sur ${totalPages == 0 ? 1 : totalPages}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: currentPage > 0 ? () => onPageChanged(currentPage - 1) : null,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(5)),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(
                      Icons.chevron_left_rounded,
                      size: 18,
                      color: currentPage > 0 ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                    ),
                  ),
                ),
                Container(width: 1, height: 22, color: const Color(0xFFE2E8F0)),
                InkWell(
                  onTap: (currentPage + 1) < totalPages ? () => onPageChanged(currentPage + 1) : null,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(5)),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: (currentPage + 1) < totalPages ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── TAB 1: FACTURATION (FULL BLOCK WIDTH, PERFECTLY CENTERED & PAGINATED) ──
  Widget _buildInvoicesTab(SchoolProfileData data) {
    final totalItems = data.invoices.length;
    if (_invoicesPage * _invoicesPageSize >= totalItems && totalItems > 0) {
      _invoicesPage = max(0, (totalItems - 1) ~/ _invoicesPageSize);
    }
    final startIdx = _invoicesPage * _invoicesPageSize;
    final endIdx = (startIdx + _invoicesPageSize).clamp(0, totalItems);
    final pageInvoices = totalItems == 0 ? <Map<String, dynamic>>[] : data.invoices.sublist(startIdx, endIdx);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Factures de l'établissement ($totalItems)",
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
              ),
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: () => _openInvoiceModal(data),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Générer une facture', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6D4CF6),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFF1F5F9)),

        if (totalItems == 0)
          _buildEmptyState(
            Icons.receipt_long_outlined,
            'Aucune facture émise pour cet établissement.',
            actionLabel: 'Générer une facture',
            onAction: () => _openInvoiceModal(data),
          )
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final tableWidth = max(availableWidth, 760.0);

              final invoiceNumW = tableWidth * 0.22;
              final issueDateW = tableWidth * 0.16;
              final dueDateW = tableWidth * 0.16;
              final amountW = tableWidth * 0.18;
              final statusW = tableWidth * 0.15;
              final actionW = tableWidth - (invoiceNumW + issueDateW + dueDateW + amountW + statusW);

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: availableWidth),
                  child: DataTable(
                    columnSpacing: 0,
                    horizontalMargin: 0,
                    headingRowHeight: 44,
                    dataRowMinHeight: 56,
                    dataRowMaxHeight: 60,
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
                    headingTextStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.5,
                    ),
                    border: TableBorder(
                      horizontalInside: BorderSide(
                        color: const Color(0xFFE2E8F0).withValues(alpha: 0.6),
                        width: 1,
                      ),
                    ),
                    dividerThickness: 0.0001,
                    columns: [
                      DataColumn(
                        label: SizedBox(
                          width: invoiceNumW,
                          child: const Padding(
                            padding: EdgeInsets.only(left: 24),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text('FACTURE N°'),
                            ),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: issueDateW,
                          child: const Center(child: Text('DATE ÉMISSION')),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: dueDateW,
                          child: const Center(child: Text('ÉCHÉANCE')),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: amountW,
                          child: const Center(child: Text('MONTANT NET')),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: statusW,
                          child: const Center(child: Text('STATUT')),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: actionW,
                          child: const Padding(
                            padding: EdgeInsets.only(right: 24),
                            child: Center(child: Text('ACTION')),
                          ),
                        ),
                      ),
                    ],
                    rows: pageInvoices.map((inv) {
                      final number = (inv['invoice_number'] ?? '—').toString();
                      final amount = (inv['amount'] as num?)?.toDouble() ?? 0.0;
                      final status = (inv['status'] as String? ?? 'pending').toLowerCase();
                      final isPaid = status == 'paid';
                      final issueDate = inv['issue_date'] ?? '—';
                      final dueDate = inv['due_date'] ?? '—';

                      return DataRow(
                        cells: [
                          DataCell(
                            SizedBox(
                              width: invoiceNumW,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 24),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    number,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: issueDateW,
                              child: Center(
                                child: Text(issueDate, style: const TextStyle(fontSize: 12, color: Color(0xFF334155))),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: dueDateW,
                              child: Center(
                                child: Text(dueDate, style: const TextStyle(fontSize: 12, color: Color(0xFF334155))),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: amountW,
                              child: Center(
                                child: Text(
                                  "${amount.toStringAsFixed(2)} TND",
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: statusW,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isPaid ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isPaid ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A),
                                    ),
                                  ),
                                  child: Text(
                                    isPaid ? 'Payée' : 'En attente',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: isPaid ? const Color(0xFF059669) : const Color(0xFFD97706),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: actionW,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 24),
                                child: Center(
                                  child: IconButton(
                                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18, color: Color(0xFF6D4CF6)),
                                    tooltip: 'Télécharger / Imprimer la facture',
                                    splashRadius: 18,
                                    onPressed: () async {
                                      final invData = InvoiceDataModel(
                                        invoiceNumber: number,
                                        date: DateTime.tryParse(issueDate) ?? DateTime.now(),
                                        issuerName: inv['issuer_name'] ?? 'PythaOne SaaS Technologies',
                                        matriculeFiscale: inv['matricule_fiscale'] ?? '2007778S/A/M/000',
                                        clientName: data.school['name'] ?? 'Établissement',
                                        timbreFiscal: (inv['timbre_fiscal'] as num?)?.toDouble() ?? 1.0,
                                        items: [
                                          InvoiceItemModel(
                                            index: 1,
                                            ref: 'P-0001',
                                            designation: 'Abonnement SaaS PythaOne',
                                            quantity: 1,
                                            unitPriceHt: amount,
                                            tvaPercent: 0.0,
                                          ),
                                        ],
                                      );
                                      await InvoicePdfGenerator.downloadOrPrintInvoice(invData);
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
          _buildTablePaginationBar(
            totalItems: totalItems,
            currentPage: _invoicesPage,
            pageSize: _invoicesPageSize,
            onPageChanged: (p) => setState(() => _invoicesPage = p),
            onPageSizeChanged: (s) => setState(() {
              _invoicesPageSize = s;
              _invoicesPage = 0;
            }),
          ),
        ],
      ],
    );
  }

  // ── TAB 2: CONSOMMATION IA (FULL BLOCK WIDTH, PERFECTLY CENTERED & PAGINATED) ──
  Widget _buildAiTelemetryTab(SchoolProfileData data) {
    final spent = data.aiSpentUsd;
    final budget = max(1.0, data.aiBudgetUsd);
    final ratio = (spent / budget).clamp(0.0, 1.0);

    final totalItems = data.aiLogs.length;
    if (_aiLogsPage * _aiLogsPageSize >= totalItems && totalItems > 0) {
      _aiLogsPage = max(0, (totalItems - 1) ~/ _aiLogsPageSize);
    }
    final startIdx = _aiLogsPage * _aiLogsPageSize;
    final endIdx = (startIdx + _aiLogsPageSize).clamp(0, totalItems);
    final pageLogs = totalItems == 0 ? <Map<String, dynamic>>[] : data.aiLogs.sublist(startIdx, endIdx);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Budget & Quota Mensuel',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "\$${spent.toStringAsFixed(2)} consommés sur un budget de \$${budget.toStringAsFixed(0)} USD (${_formatTokens(data.aiTokensMonth)} tokens)",
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 36,
                    child: OutlinedButton.icon(
                      onPressed: () => _openQuotaDialog(data),
                      icon: const Icon(Icons.tune_rounded, size: 15),
                      label: const Text('Ajuster le quota', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6D4CF6),
                        side: const BorderSide(color: Color(0xFFDDD6FE)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 10,
                  backgroundColor: const Color(0xFFF1F5F9),
                  valueColor: AlwaysStoppedAnimation(
                    ratio >= 0.9 ? const Color(0xFFDC2626) : const Color(0xFF6D4CF6),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFF1F5F9)),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Text(
            'Dernières requêtes IA enregistrées ($totalItems)',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
          ),
        ),

        if (totalItems == 0)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Center(
              child: Text('Aucune requête IA enregistrée pour le moment.', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
          )
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final tableWidth = max(availableWidth, 680.0);

              final modelW = tableWidth * 0.38;
              final tokensW = tableWidth * 0.18;
              final costW = tableWidth * 0.22;
              final dateW = tableWidth - (modelW + tokensW + costW);

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: availableWidth),
                  child: DataTable(
                    columnSpacing: 0,
                    horizontalMargin: 0,
                    headingRowHeight: 44,
                    dataRowMinHeight: 52,
                    dataRowMaxHeight: 56,
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
                    headingTextStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.5,
                    ),
                    border: TableBorder(
                      horizontalInside: BorderSide(
                        color: const Color(0xFFE2E8F0).withValues(alpha: 0.6),
                        width: 1,
                      ),
                    ),
                    dividerThickness: 0.0001,
                    columns: [
                      DataColumn(
                        label: SizedBox(
                          width: modelW,
                          child: const Padding(
                            padding: EdgeInsets.only(left: 24),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text('MODÈLE'),
                            ),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: tokensW,
                          child: const Center(child: Text('TOKENS')),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: costW,
                          child: const Center(child: Text('COÛT ESTIMÉ (USD)')),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: dateW,
                          child: const Padding(
                            padding: EdgeInsets.only(right: 24),
                            child: Center(child: Text('DATE')),
                          ),
                        ),
                      ),
                    ],
                    rows: pageLogs.map((log) {
                      final model = log['model'] ?? 'gemini-1.5-flash';
                      final tokens = (log['total_tokens'] as num?)?.toInt() ?? 0;
                      final cost = (log['cost_usd'] as num?)?.toDouble() ?? 0.0;
                      final dt = log['created_at']?.toString().split('.')[0] ?? '—';

                      return DataRow(
                        cells: [
                          DataCell(
                            SizedBox(
                              width: modelW,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 24),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.auto_awesome_rounded, size: 15, color: Color(0xFF6D4CF6)),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        model,
                                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: tokensW,
                              child: Center(
                                child: Text(
                                  _formatTokens(tokens),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: costW,
                              child: Center(
                                child: Text(
                                  "\$${cost.toStringAsFixed(4)}",
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: dateW,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 24),
                                child: Center(
                                  child: Text(dt, style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
          _buildTablePaginationBar(
            totalItems: totalItems,
            currentPage: _aiLogsPage,
            pageSize: _aiLogsPageSize,
            onPageChanged: (p) => setState(() => _aiLogsPage = p),
            onPageSizeChanged: (s) => setState(() {
              _aiLogsPageSize = s;
              _aiLogsPage = 0;
            }),
          ),
        ],
      ],
    );
  }

  // ── TAB 3: UTILISATEURS (FULL BLOCK WIDTH, PERFECTLY CENTERED & PAGINATED) ──
  Widget _buildUsersTab(SchoolProfileData data) {
    final totalItems = data.users.length;
    if (_usersPage * _usersPageSize >= totalItems && totalItems > 0) {
      _usersPage = max(0, (totalItems - 1) ~/ _usersPageSize);
    }
    final startIdx = _usersPage * _usersPageSize;
    final endIdx = (startIdx + _usersPageSize).clamp(0, totalItems);
    final pageUsers = totalItems == 0 ? <Map<String, dynamic>>[] : data.users.sublist(startIdx, endIdx);

    if (totalItems == 0) {
      return _buildEmptyState(
        Icons.group_off_outlined,
        'Aucun utilisateur rattaché à cet établissement.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final tableWidth = max(availableWidth, 860.0);

            final userW = tableWidth * 0.22;
            final roleW = tableWidth * 0.13;
            final emailW = tableWidth * 0.21;
            final phoneW = tableWidth * 0.14;
            final statusW = tableWidth * 0.11;
            final passW = tableWidth - (userW + roleW + emailW + phoneW + statusW);

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: availableWidth),
                child: DataTable(
                  columnSpacing: 0,
                  horizontalMargin: 0,
                  headingRowHeight: 44,
                  dataRowMinHeight: 56,
                  dataRowMaxHeight: 60,
                  headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
                  headingTextStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                  border: TableBorder(
                    horizontalInside: BorderSide(
                      color: const Color(0xFFE2E8F0).withValues(alpha: 0.6),
                      width: 1,
                    ),
                  ),
                  dividerThickness: 0.0001,
                  columns: [
                    DataColumn(
                      label: SizedBox(
                        width: userW,
                        child: const Padding(
                          padding: EdgeInsets.only(left: 24),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('UTILISATEUR'),
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: roleW,
                        child: const Center(child: Text('RÔLE')),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: emailW,
                        child: const Center(child: Text('EMAIL')),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: phoneW,
                        child: const Center(child: Text('TÉLÉPHONE')),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: statusW,
                        child: const Center(child: Text('STATUT')),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: passW,
                        child: const Padding(
                          padding: EdgeInsets.only(right: 20),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('MOT DE PASSE'),
                          ),
                        ),
                      ),
                    ),
                  ],
                  rows: pageUsers.map((u) {
                    final fullName = u['full_name'] ?? 'Utilisateur';
                    final email = u['email'] ?? '—';
                    final phone = u['phone'] ?? '—';
                    final role = (u['role'] as String? ?? 'student').toLowerCase();
                    final isActive = u['is_active'] == true;
                    final uId = u['id']?.toString() ?? '';
                    final rawPass = (u['initial_password'] as String?)?.trim() ?? '';
                    final isUnhidden = _unhiddenUserIds.contains(uId);

                    String roleLabel = 'Élève';
                    Color roleColor = const Color(0xFF2563EB);
                    Color roleBg = const Color(0xFFEFF6FF);
                    if (role == 'teacher') {
                      roleLabel = 'Professeur';
                      roleColor = const Color(0xFF7C3AED);
                      roleBg = const Color(0xFFF5F3FF);
                    } else if (role == 'admin' || role == 'director') {
                      roleLabel = 'Direction';
                      roleColor = const Color(0xFF059669);
                      roleBg = const Color(0xFFECFDF5);
                    } else if (role == 'staff') {
                      roleLabel = 'Manager';
                      roleColor = const Color(0xFFD97706);
                      roleBg = const Color(0xFFFFFBEB);
                    }

                    return DataRow(
                      cells: [
                        DataCell(
                          SizedBox(
                            width: userW,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 24),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: roleBg,
                                    child: Text(
                                      fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: roleColor),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      fullName,
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: roleW,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: roleBg, borderRadius: BorderRadius.circular(6)),
                                child: Text(
                                  roleLabel,
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: roleColor),
                                ),
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: emailW,
                            child: Center(
                              child: Text(
                                email,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: phoneW,
                            child: Center(
                              child: Text(phone, style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: Color(0xFF64748B))),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: statusW,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isActive ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isActive ? 'Actif' : 'Bloqué',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: isActive ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: passW,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 16),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Expanded(
                                    child: Text(
                                      rawPass.isNotEmpty
                                          ? (isUnhidden ? rawPass : '••••••••')
                                          : 'Non défini',
                                      style: TextStyle(
                                        fontSize: isUnhidden && rawPass.isNotEmpty ? 11.5 : 12,
                                        fontFamily: isUnhidden && rawPass.isNotEmpty ? 'monospace' : null,
                                        fontWeight: FontWeight.w600,
                                        color: rawPass.isNotEmpty
                                            ? (isUnhidden ? const Color(0xFF0F172A) : const Color(0xFF64748B))
                                            : const Color(0xFF94A3B8),
                                        letterSpacing: isUnhidden || rawPass.isEmpty ? 0.2 : 2.0,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (rawPass.isNotEmpty) ...[
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          if (isUnhidden) {
                                            _unhiddenUserIds.remove(uId);
                                          } else {
                                            _unhiddenUserIds.add(uId);
                                          }
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: Icon(
                                          isUnhidden
                                              ? Icons.visibility_off_rounded
                                              : Icons.visibility_rounded,
                                          size: 15,
                                          color: const Color(0xFF6D4CF6),
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () {
                                        Clipboard.setData(ClipboardData(text: rawPass));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Mot de passe copié !'),
                                            duration: Duration(seconds: 1),
                                            backgroundColor: Color(0xFF059669),
                                          ),
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(4),
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(Icons.copy_rounded, size: 13, color: Color(0xFF94A3B8)),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 2),
                                  InkWell(
                                    onTap: () => _openCredentialsModal(data, preselectedUser: u),
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF5F3FF),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFDDD6FE)),
                                      ),
                                      child: const Text(
                                        'Modifier',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF7C3AED),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
        _buildTablePaginationBar(
          totalItems: totalItems,
          currentPage: _usersPage,
          pageSize: _usersPageSize,
          onPageChanged: (p) => setState(() => _usersPage = p),
          onPageSizeChanged: (s) => setState(() {
            _usersPageSize = s;
            _usersPage = 0;
          }),
        ),
      ],
    );
  }

  // ── TAB 4: JOURNAL D'ACTIVITÉ (FULL BLOCK WIDTH, PERFECTLY CENTERED & PAGINATED) ──
  Widget _buildAuditTab(SchoolProfileData data) {
    final totalItems = data.auditLogs.length;
    if (_auditPage * _auditPageSize >= totalItems && totalItems > 0) {
      _auditPage = max(0, (totalItems - 1) ~/ _auditPageSize);
    }
    final startIdx = _auditPage * _auditPageSize;
    final endIdx = (startIdx + _auditPageSize).clamp(0, totalItems);
    final pageLogs = totalItems == 0 ? <Map<String, dynamic>>[] : data.auditLogs.sublist(startIdx, endIdx);

    if (totalItems == 0) {
      return _buildEmptyState(
        Icons.history_rounded,
        "Aucun événement d'audit enregistré pour cet établissement.",
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final tableWidth = max(availableWidth, 700.0);

            final actionW = tableWidth * 0.28;
            final dateW = tableWidth * 0.22;
            final detailsW = tableWidth - (actionW + dateW);

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: availableWidth),
                child: DataTable(
                  columnSpacing: 0,
                  horizontalMargin: 0,
                  headingRowHeight: 44,
                  dataRowMinHeight: 52,
                  dataRowMaxHeight: 56,
                  headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
                  headingTextStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                  border: TableBorder(
                    horizontalInside: BorderSide(
                      color: const Color(0xFFE2E8F0).withValues(alpha: 0.6),
                      width: 1,
                    ),
                  ),
                  dividerThickness: 0.0001,
                  columns: [
                    DataColumn(
                      label: SizedBox(
                        width: actionW,
                        child: const Padding(
                          padding: EdgeInsets.only(left: 24),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('ACTION'),
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: detailsW,
                        child: const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('DÉTAILS'),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: dateW,
                        child: const Padding(
                          padding: EdgeInsets.only(right: 24),
                          child: Center(child: Text('DATE')),
                        ),
                      ),
                    ),
                  ],
                  rows: pageLogs.map((log) {
                    final action = (log['action'] ?? 'ACTION').toString().toUpperCase();
                    final details = log['details']?.toString() ?? '—';
                    final dt = log['created_at']?.toString().split('.')[0] ?? '—';

                    return DataRow(
                      cells: [
                        DataCell(
                          SizedBox(
                            width: actionW,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 24),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(Icons.history_rounded, size: 14, color: Color(0xFF64748B)),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      action,
                                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: detailsW,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                details,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: dateW,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 24),
                              child: Center(
                                child: Text(dt, style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8))),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
        _buildTablePaginationBar(
          totalItems: totalItems,
          currentPage: _auditPage,
          pageSize: _auditPageSize,
          onPageChanged: (p) => setState(() => _auditPage = p),
          onPageSizeChanged: (s) => setState(() {
            _auditPageSize = s;
            _auditPage = 0;
          }),
        ),
      ],
    );
  }
  // ═══════════════════════════════════════════════════
  // REUSABLE ATOMS & DIALOGS
  // ═══════════════════════════════════════════════════
  Widget _buildSchoolAvatar(Map<String, dynamic> school, {double size = 48}) {
    final logoUrl = (school['logo_url'] as String?)?.trim();
    final name = (school['name'] as String?) ?? 'École';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'E';

    if (logoUrl != null && logoUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.25),
        child: Image.network(
          logoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallbackAvatar(initial, size),
        ),
      );
    }
    return _fallbackAvatar(initial, size);
  }

  Widget _fallbackAvatar(String initial, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFEDE9FE),
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: size * 0.42,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF6D4CF6),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({required IconData icon, required String tooltip, required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: IconButton(
        icon: Icon(icon, size: 18, color: const Color(0xFF475569)),
        tooltip: tooltip,
        onPressed: onTap,
        splashRadius: 20,
      ),
    );
  }

  Widget _buildStatusToggleButton(SchoolProfileData data) {
    final isActive = data.school['is_active'] == true;
    return _buildHeaderActionButton(
      icon: isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded,
      label: isActive ? 'Suspendre' : 'Réactiver',
      backgroundColor: isActive ? const Color(0xFFDC2626) : const Color(0xFF059669),
      foregroundColor: Colors.white,
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        final ok = await ref.read(platformProvider.notifier).toggleSchoolStatus(data.school['id'], !isActive);
        if (!mounted) return;
        if (ok) {
          ref.invalidate(schoolProfileDataProvider(widget.schoolId));
          messenger.showSnackBar(
            SnackBar(
              content: Text(isActive ? 'Établissement suspendu.' : 'Établissement réactivé !'),
              backgroundColor: isActive ? ConsoleColors.warning : ConsoleColors.success,
            ),
          );
        }
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {bool copyable = false, Widget? customValueWidget}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
              const SizedBox(height: 2),
              if (customValueWidget != null)
                customValueWidget
              else
                Text(
                  value,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                ),
            ],
          ),
        ),
        if (copyable)
          IconButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copié dans le presse-papier'), duration: Duration(seconds: 1)),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF94A3B8)),
            splashRadius: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
      ],
    );
  }

  Widget _buildPasswordInfoRow(SchoolProfileData data) {
    final directorUser = data.users.firstWhere(
      (u) {
        final r = (u['role'] as String? ?? '').toLowerCase();
        return r == 'owner' || r == 'admin' || r == 'director';
      },
      orElse: () => data.users.isNotEmpty ? data.users.first : <String, dynamic>{},
    );

    final rawPassword = (directorUser['initial_password'] as String?)?.trim() ?? '';
    final hasPassword = rawPassword.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_outline_rounded, size: 16, color: Color(0xFF94A3B8)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Mot de passe Admin', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hasPassword
                          ? (_showDirectorPassword ? rawPassword : '••••••••••••')
                          : 'Non archivé',
                      style: TextStyle(
                        fontSize: _showDirectorPassword && hasPassword ? 12.5 : 13,
                        fontFamily: _showDirectorPassword && hasPassword ? 'monospace' : null,
                        fontWeight: FontWeight.w600,
                        color: hasPassword
                            ? (_showDirectorPassword ? const Color(0xFF0F172A) : const Color(0xFF64748B))
                            : const Color(0xFF94A3B8),
                        letterSpacing: _showDirectorPassword || !hasPassword ? 0.2 : 2.0,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasPassword) ...[
                    InkWell(
                      onTap: () => setState(() => _showDirectorPassword = !_showDirectorPassword),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Icon(
                          _showDirectorPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          size: 16,
                          color: const Color(0xFF6D4CF6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: rawPassword));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Mot de passe copié !'),
                            duration: Duration(seconds: 1),
                            backgroundColor: Color(0xFF059669),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Icon(Icons.copy_rounded, size: 14, color: Color(0xFF94A3B8)),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  InkWell(
                    onTap: () => _openCredentialsModal(data, preselectedUser: directorUser.isNotEmpty ? directorUser : null),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F3FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFDDD6FE)),
                      ),
                      child: const Text(
                        'Modifier',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF7C3AED),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openCredentialsModal(SchoolProfileData data, {Map<String, dynamic>? preselectedUser}) {
    showConsoleSchoolCredentialsModal(
      context: context,
      school: data.school,
      preselectedUser: preselectedUser,
      onPasswordChanged: () {
        ref.invalidate(schoolProfileDataProvider(widget.schoolId));
        ref.read(platformProvider.notifier).loadAll();
      },
    );
  }

  Widget _buildCheckItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_rounded, size: 15, color: Color(0xFF059669)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF334155))),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String message, {String? actionLabel, VoidCallback? onAction}) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: const Color(0xFFCBD5E1)),
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6D4CF6),
                  side: const BorderSide(color: Color(0xFFDDD6FE)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(Object error) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFFDC2626)),
            const SizedBox(height: 16),
            Text('Erreur de chargement: $error', style: const TextStyle(color: Color(0xFFDC2626))),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.invalidate(schoolProfileDataProvider(widget.schoolId)),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6D4CF6)),
              child: const Text('Réessayer', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotFoundView() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.domain_disabled_rounded, size: 48, color: Color(0xFF94A3B8)),
            const SizedBox(height: 16),
            const Text(
              'Établissement introuvable',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 8),
            const Text(
              "Cet établissement a peut-être été supprimé ou l'identifiant est invalide.",
              style: TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => context.go('/schools'),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Retour à la liste'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6D4CF6),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // MODAL ACTIONS
  // ═══════════════════════════════════════════════════
  Future<void> _pickAndUploadLogo(String schoolId) async {
    setState(() => _isUploadingLogo = true);
    final url = await ref.read(platformProvider.notifier).pickAndUploadSchoolLogo(schoolId: schoolId);
    if (mounted) {
      setState(() => _isUploadingLogo = false);
      if (url != null) {
        ref.invalidate(schoolProfileDataProvider(widget.schoolId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logo mis à jour avec succès!'), backgroundColor: ConsoleColors.success),
        );
      }
    }
  }

  void _openInvoiceModal(SchoolProfileData data) {
    showConsoleInvoiceGeneratorModal(
      context: context,
      ref: ref,
      schools: [data.school],
      preselectedSchoolId: data.school['id'],
      onSaved: () => ref.invalidate(schoolProfileDataProvider(widget.schoolId)),
    );
  }

  void _openQuotaDialog(SchoolProfileData data) {
    final budgetCtrl = TextEditingController(text: data.aiBudgetUsd.toStringAsFixed(0));
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: StatefulBuilder(
          builder: (ctx, setDlgState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Modifier Quota IA & Budget', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Budget mensuel USD alloué aux requêtes IA de l'école :", style: TextStyle(fontSize: 13, color: Color(0xFF334155))),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: budgetCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                    decoration: InputDecoration(
                      prefixText: '\$ ',
                      suffixText: 'USD / mois',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                    ),
                  ),
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            actions: [
              SizedBox(
                height: 40,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Annuler', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: isSaving ? null : () async {
                    if (!formKey.currentState!.validate()) return;
                    setDlgState(() => isSaving = true);
                    final budgetVal = double.tryParse(budgetCtrl.text.trim()) ?? 25.0;
                    final ok = await ref.read(platformProvider.notifier).updateSchoolAiQuota(
                      schoolId: data.school['id'],
                      monthlyBudgetUsd: budgetVal,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted && ok) {
                      ref.invalidate(schoolProfileDataProvider(widget.schoolId));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Quota IA mis à jour !'), backgroundColor: ConsoleColors.success),
                      );
                    }
                  },
                  icon: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Enregistrer', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6D4CF6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPlanDialog(SchoolProfileData data) {
    final platformState = ref.read(platformProvider);
    final plans = platformState.plans;
    String selectedPlanId = data.plan?['id'] ?? (plans.isNotEmpty ? plans.first['id'] : '');
    bool isSaving = false;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: StatefulBuilder(
          builder: (ctx, setDlgState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Changer de Forfait', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Sélectionnez la formule d'abonnement :", style: TextStyle(fontSize: 13, color: Color(0xFF334155))),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedPlanId,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(10),
                  items: plans.map((p) {
                    return DropdownMenuItem<String>(
                      value: p['id'] as String,
                      child: Text("${p['name']} — ${p['price_tnd_monthly']} TND/m"),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => selectedPlanId = v);
                  },
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                  ),
                ),
              ],
            ),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            actions: [
              SizedBox(
                height: 40,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Annuler', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: isSaving ? null : () async {
                    setDlgState(() => isSaving = true);
                    final ok = await ref.read(platformProvider.notifier).updateSchoolSubscriptionPlan(
                      schoolId: data.school['id'],
                      planId: selectedPlanId,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted && ok) {
                      ref.invalidate(schoolProfileDataProvider(widget.schoolId));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Forfait modifié avec succès !'), backgroundColor: ConsoleColors.success),
                      );
                    }
                  },
                  icon: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Appliquer', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6D4CF6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
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
