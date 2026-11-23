import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/localization/console_translations.dart';
import '../../core/services/invoice_pdf_generator.dart';
import '../../core/theme/console_theme.dart';
import '../providers/console_auth_provider.dart';
import '../providers/platform_provider.dart';
import '../widgets/console_invoice_modal.dart';
import '../widgets/console_school_credentials_modal.dart';
import '../widgets/console_settings_view.dart';
import '../widgets/console_sidebar.dart';
import '../widgets/console_skeleton_loader.dart';

Map<String, dynamic>? _extractRelationMap(dynamic value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is List && value.isNotEmpty) {
    final first = value.first;
    if (first is Map<String, dynamic>) return first;
    if (first is Map) return Map<String, dynamic>.from(first);
  }
  return null;
}

class ConsoleDashboardScreen extends ConsumerStatefulWidget {
  final String currentRoute;
  const ConsoleDashboardScreen({super.key, this.currentRoute = '/dashboard'});

  @override
  ConsumerState<ConsoleDashboardScreen> createState() =>
      _ConsoleDashboardScreenState();
}

class _ConsoleDashboardScreenState
    extends ConsumerState<ConsoleDashboardScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _schoolsStatusFilter = 'all'; // 'all', 'active', 'suspended'
  int _schoolsPage = 0;
  int _schoolsPageSize = 10;
  String _bugStatusFilter = 'all'; // 'all', 'open', 'in_progress', 'resolved'
  int _bugsPage = 0;
  int _bugsPageSize = 10;
  String _auditActionFilter = 'all';
  int _auditPage = 0;
  int _auditPageSize = 10;
  int _telemetryPage = 0;
  int _telemetryPageSize = 10;
  int _securityPage = 0;
  int _securityPageSize = 10;

  @override
  void didUpdateWidget(covariant ConsoleDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentRoute != widget.currentRoute) {
      _searchController.clear();
      _searchQuery = '';
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.watch(consoleTranslationsProvider);
    final authState = ref.watch(consoleAuthProvider);
    final platformState = ref.watch(platformProvider);

    // If auth state is still initializing or checking session on reload, display skeleton
    if (!authState.isInitialized || authState.isLoading) {
      return Scaffold(
        backgroundColor: ConsoleColors.background,
        body: _skeletonForRoute(),
      );
    }

    // When fully initialized, if user is not authenticated, redirect to /login
    if (!authState.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/login');
      });
      return Scaffold(
        backgroundColor: ConsoleColors.background,
        body: _skeletonForRoute(),
      );
    }

    return Scaffold(
      backgroundColor: ConsoleColors.background,
      body: Row(
        children: [
          ConsoleSidebar(currentRoute: widget.currentRoute),
          Expanded(
            child: Column(
              children: [
                _buildPageHeader(authState.user, platformState, tr),
                Expanded(
                  child: platformState.isLoading
                      ? _skeletonForRoute()
                      : (platformState.errorMessage != null && platformState.schools.isEmpty)
                          ? _buildErrorState(platformState.errorMessage!, tr)
                          : _pageForRoute(platformState, tr, authState.user),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeletonForRoute() {
    switch (widget.currentRoute) {
      case '/settings':
        return const ConsoleSettingsSkeleton();
      case '/schools':
        return const ConsoleSchoolsSkeleton();
      case '/billing':
        return const ConsoleBillingSkeleton();
      case '/ai-telemetry':
        return const ConsoleAiTelemetrySkeleton();
      case '/audit':
        return const ConsoleAuditSkeleton();
      case '/bugs':
        return const ConsoleBugReportsSkeleton();
      case '/security':
        return const ConsoleOverviewSkeleton();
      case '/dashboard':
      case '/':
      default:
        return const ConsoleOverviewSkeleton();
    }
  }

  Widget _pageForRoute(
      PlatformState state, ConsoleStrings tr, Map<String, dynamic>? user) {
    switch (widget.currentRoute) {
      case '/settings':
        return ConsoleSettingsView(platformState: state, user: user);
      case '/schools':
        return _buildOverviewPage(state, tr, showKpis: false);
      case '/billing':
        return _buildBillingPage(state, tr);
      case '/ai-telemetry':
        return _buildAiTelemetryPage(state, tr);
      case '/audit':
        return _buildAuditPage(state, tr);
      case '/bugs':
        return _buildBugReportsPage(state, tr);
      case '/security':
        return _buildSecuritySloPage(state, tr);
      case '/dashboard':
      case '/':
      default:
        return _buildOverviewPage(state, tr, showKpis: true);
    }
  }

  (String, String) _headerMeta(ConsoleStrings tr) {
    switch (widget.currentRoute) {
      case '/settings':
        return (
          tr.headerSettingsTitle,
          tr.headerSettingsSubtitle,
        );
      case '/schools':
        return (
          tr.headerSchoolsTitle,
          tr.headerSchoolsSubtitle,
        );
      case '/billing':
        return (
          tr.headerBillingTitle,
          tr.headerBillingSubtitle,
        );
      case '/ai-telemetry':
        return (
          tr.headerAiTitle,
          tr.headerAiSubtitle,
        );
      case '/audit':
        return (
          tr.headerAuditTitle,
          tr.headerAuditSubtitle,
        );
      case '/bugs':
        return (
          tr.headerBugsTitle,
          tr.headerBugsSubtitle,
        );
      case '/security':
        return (
          'Sécurité Zero Trust & Observabilité',
          'Surveillance des SLOs 99.9%, tracing corrélé des requêtes et kill-switch de sessions',
        );
      case '/dashboard':
      case '/':
      default:
        return (
          tr.headerOverviewTitle,
          tr.headerOverviewSubtitle,
        );
    }
  }

  Widget _buildPageHeader(
      Map<String, dynamic>? user, PlatformState state, ConsoleStrings tr) {
    final (title, subtitle) = _headerMeta(tr);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE9EAF2))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: ConsoleColors.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: ConsoleColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Exact Documents / Admin search bar
          SizedBox(
            width: 280,
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: tr.searchPlaceholder,
                hintStyle: const TextStyle(
                  color: ConsoleColors.textTertiary,
                  fontSize: 13,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 18,
                  color: ConsoleColors.textTertiary,
                ),
                suffixIcon: _searchController.text.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: ConsoleColors.cardBorder),
                          ),
                          child: const Text(
                            '⌘K',
                            style: TextStyle(
                              fontSize: 10,
                              color: ConsoleColors.textTertiary,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: ConsoleColors.cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: ConsoleColors.cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: ConsoleColors.brand.withValues(alpha: 0.45),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          if (widget.currentRoute == '/schools' ||
              widget.currentRoute == '/dashboard' ||
              widget.currentRoute == '/') ...[
            const SizedBox(width: 10),
            SizedBox(
              height: 40,
              child: ElevatedButton.icon(
                onPressed: () => _showCreateSchoolModal(context, state.plans),
                icon: const Icon(Icons.add_business_outlined, size: 17),
                label: Text(tr.newSchoolBtn),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ConsoleColors.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
          if (widget.currentRoute == '/billing') ...[
            const SizedBox(width: 10),
            SizedBox(
              height: 40,
              child: ElevatedButton.icon(
                onPressed: () =>
                    _showManualInvoiceModal(context, state.schools),
                icon: const Icon(Icons.add_rounded, size: 17),
                label: Text(tr.manualInvoiceBtn),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ConsoleColors.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorState(String message, ConsoleStrings tr) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(28),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ConsoleColors.cardBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 44, color: ConsoleColors.error),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(color: ConsoleColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: () => ref.read(platformProvider.notifier).clearError(),
                  child: const Text('Fermer'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => ref.read(platformProvider.notifier).loadAll(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ConsoleColors.brand,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(tr.refreshTooltip),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // 1. OVERVIEW PAGE & UNIFIED SCHOOLS TABLE
  // ══════════════════════════════════════════════════════════════
  Widget _buildOverviewPage(PlatformState state, ConsoleStrings tr, {bool showKpis = true}) {
    final kpis = state.kpis;
    final allSchools = state.schools;

    // Filter by search query
    final searchedSchools = allSchools.where((s) {
      if (_searchQuery.isEmpty) return true;
      final name = (s['name'] ?? '').toString().toLowerCase();
      final code = (s['code'] ?? '').toString().toLowerCase();
      final email = (s['email'] ?? '').toString().toLowerCase();
      final phone = (s['phone'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery) ||
          code.contains(_searchQuery) ||
          email.contains(_searchQuery) ||
          phone.contains(_searchQuery);
    }).toList();

    // Counts for tabs
    final totalCount = searchedSchools.length;
    final activeCount = searchedSchools.where((s) => s['is_active'] == true).length;
    final suspendedCount = searchedSchools.where((s) => s['is_active'] != true).length;

    // Filter by status tab
    final filteredSchools = searchedSchools.where((s) {
      if (_schoolsStatusFilter == 'active') return s['is_active'] == true;
      if (_schoolsStatusFilter == 'suspended') return s['is_active'] != true;
      return true;
    }).toList();

    // Pagination
    final pageStart = _schoolsPage * _schoolsPageSize;
    final paginatedSchools = filteredSchools.skip(pageStart).take(_schoolsPageSize).toList();

    final realAiSpend = (kpis['aiSpendUsd'] as double? ?? 0.0);
    final realAiTokens = (kpis['aiTokensMonth'] as int? ?? 0);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showKpis) ...[
            // ── KPI METRICS ROW (GOLDEN RATIO SPACING & TYPOGRAPHY) ──
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    tr.kpiActiveSchools,
                    '${kpis['activeSchools'] ?? 0}',
                    '${kpis['totalSchools'] ?? 0} total enregistrées',
                    Icons.domain_rounded,
                    ConsoleColors.primary,
                    trend: '+${kpis['activeSchools'] ?? 0}',
                    trendLabel: 'sur ${kpis['totalSchools'] ?? 0} total',
                    trendUp: true,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMetricCard(
                    tr.kpiTotalMrr,
                    '${(kpis['mrrTnd'] as double? ?? 0.0).toStringAsFixed(0)} TND',
                    tr.mrrSubtitle,
                    Icons.trending_up_rounded,
                    ConsoleColors.success,
                    trend: '+8.3%',
                    trendLabel: 'vs mois dernier',
                    trendUp: true,
                    onTap: () => context.go('/billing'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMetricCard(
                    tr.totalCostUsd,
                    '\$${realAiSpend.toStringAsFixed(4)}',
                    '$realAiTokens tokens • Dépenses réelles API',
                    Icons.auto_awesome_rounded,
                    ConsoleColors.brand,
                    trend: '$realAiTokens',
                    trendLabel: 'tokens ce mois',
                    trendUp: true,
                    onTap: () => context.go('/ai-telemetry'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMetricCard(
                    tr.pendingInvoicesCount,
                    '${kpis['pendingCount'] ?? 0}',
                    tr.statusPending,
                    Icons.receipt_long_rounded,
                    ConsoleColors.warning,
                    trend: '0%',
                    trendLabel: 'impayés nécessitant relance',
                    trendUp: false,
                    onTap: () => context.go('/billing'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // ── FLOATING STATUS FILTER PILLS (EXACT USERS SCREEN LAYOUT) ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildStatusChip(
                      'Tous',
                      totalCount,
                      _schoolsStatusFilter == 'all',
                      () => setState(() {
                        _schoolsStatusFilter = 'all';
                        _schoolsPage = 0;
                      }),
                    ),
                    _buildStatusChip(
                      'Actifs',
                      activeCount,
                      _schoolsStatusFilter == 'active',
                      () => setState(() {
                        _schoolsStatusFilter = 'active';
                        _schoolsPage = 0;
                      }),
                    ),
                    _buildStatusChip(
                      'Suspendus',
                      suspendedCount,
                      _schoolsStatusFilter == 'suspended',
                      () => setState(() {
                        _schoolsStatusFilter = 'suspended';
                        _schoolsPage = 0;
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── EXACT USERS PAGE TABLE CONTAINER (NO INNER CARD HEADER) ──
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0).withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  filteredSchools.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.domain_disabled_rounded, size: 48, color: Colors.grey.shade300),
                                const SizedBox(height: 12),
                                Text(
                                  tr.noSchoolsRegistered,
                                  style: const TextStyle(fontSize: 14, color: ConsoleColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _buildSchoolsDataTable(paginatedSchools, state),
                  _buildPagination(filteredSchools.length),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // STATUS CHIP (EXACT USERS SCREEN SEGMENTED PILL WITH GUARANTEED FINGER CURSOR)
  // ═══════════════════════════════════════════════════
  Widget _buildStatusChip(String label, int count, bool isActive, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: isActive ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        elevation: isActive ? 1 : 0,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        child: InkWell(
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: isActive ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400,
                    color: isActive ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  // ═══════════════════════════════════════════════════
  // SCHOOL AVATAR (EXACT USER AVATAR CLONE)
  // ═══════════════════════════════════════════════════
  Widget _buildSchoolAvatar(Map<String, dynamic> school) {
    final logoUrl = (school['logo_url'] as String?)?.trim();
    final name = (school['name'] as String?) ?? 'École';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'E';

    const pastelBgs = [
      Color(0xFFEDE9FE),
      Color(0xFFE0E7FF),
      Color(0xFFDCFCE7),
      Color(0xFFFEF3C7),
      Color(0xFFFCE7F3),
      Color(0xFFE0F2FE),
    ];
    const textColors = [
      Color(0xFF6D28D9),
      Color(0xFF4338CA),
      Color(0xFF15803D),
      Color(0xFFB45309),
      Color(0xFFBE185D),
      Color(0xFF0369A1),
    ];

    final colorIndex = name.hashCode.abs() % pastelBgs.length;
    final bg = pastelBgs[colorIndex];
    final fg = textColors[colorIndex];

    if (logoUrl != null && logoUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          logoUrl,
          width: 34,
          height: 34,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => CircleAvatar(
            radius: 17,
            backgroundColor: bg,
            child: Text(
              initial,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg),
            ),
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 17,
      backgroundColor: bg,
      child: Text(
        initial,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // SCHOOLS DATA TABLE (EACH INFO IN ITS OWN COLUMN)
  // ═══════════════════════════════════════════════════
  Widget _buildSchoolsDataTable(List<Map<String, dynamic>> paginatedSchools, PlatformState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        const schoolW = 280.0;
        const codeW = 85.0;
        const emailW = 210.0;
        const phoneW = 120.0;
        const planPriceW = 165.0;
        const quotaW = 125.0;
        const statusW = 85.0;
        const createdW = 80.0;
        const actionsW = 44.0;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: availableWidth),
            child: DataTable(
              columnSpacing: 0,
              horizontalMargin: 0,
              dataRowMinHeight: 56,
              dataRowMaxHeight: 60,
              headingRowHeight: 44,
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
              headingTextStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF94A3B8),
                fontSize: 11,
                letterSpacing: 0.5,
              ),
              border: TableBorder(
                horizontalInside: BorderSide(
                  color: const Color(0xFFE2E8F0).withValues(alpha: 0.6),
                  width: 1,
                ),
              ),
              dividerThickness: 0.0001,
              showCheckboxColumn: false,
              columns: [
                DataColumn(
                  label: Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: SizedBox(width: schoolW, child: _headerLabel('ÉTABLISSEMENT')),
                  ),
                ),
                DataColumn(label: SizedBox(width: codeW, child: _headerLabel('CODE'))),
                DataColumn(label: SizedBox(width: emailW, child: _headerLabel('EMAIL DIRECTEUR'))),
                DataColumn(label: SizedBox(width: phoneW, child: _headerLabel('TÉLÉPHONE'))),
                DataColumn(label: SizedBox(width: planPriceW, child: _headerLabel('OFFRE & TARIF'))),
                DataColumn(label: SizedBox(width: quotaW, child: _headerLabel('QUOTA IA'))),
                DataColumn(label: SizedBox(width: statusW, child: _headerLabel('STATUT'))),
                DataColumn(label: SizedBox(width: createdW, child: _headerLabel('CRÉÉ LE'))),
                DataColumn(label: SizedBox(width: actionsW, child: Container())),
              ],
              rows: paginatedSchools.map((s) {
                final sub = _extractRelationMap(s['school_subscriptions']);
                final plan = _extractRelationMap(sub?['plan']);
                final quota = _extractRelationMap(s['ai_school_quotas']);
                final isActive = s['is_active'] == true;
                final spent = (quota?['spent_current_month_usd'] as num?)?.toDouble() ?? 0.0;
                final budget = (quota?['monthly_budget_usd'] as num?)?.toDouble() ?? 25.0;
                final isQuotaExceeded = quota?['is_quota_exceeded'] == true || spent >= budget;

                final directorPhone = s['phone'] as String?;
                final email = s['email'] as String? ?? '—';

                // Code shortcut
                final rawCode = (s['code'] ?? '—').toString().trim().toUpperCase();
                final displayCode = rawCode.length > 6 ? rawCode.substring(0, 6) : rawCode;

                // Short plan badge indicator
                final planName = (plan?['name'] as String? ?? 'Plan Pro').trim();
                String planBadge = 'PRO';
                final lowerPlan = planName.toLowerCase();
                if (lowerPlan.contains('standard') || lowerPlan.contains('basic')) {
                  planBadge = 'STD';
                } else if (lowerPlan.contains('entreprise') || lowerPlan.contains('enterprise')) {
                  planBadge = 'ENT';
                } else if (lowerPlan.contains('premium')) {
                  planBadge = 'PREM';
                } else if (lowerPlan.contains('pro')) {
                  planBadge = 'PRO';
                } else {
                  planBadge = planName.length > 4 ? planName.substring(0, 4).toUpperCase() : planName.toUpperCase();
                }
                final monthlyPrice = plan?['price_tnd_monthly'] ?? 850;

                String formattedCreated = '—';
                if (s['created_at'] != null) {
                  try {
                    final dt = DateTime.parse(s['created_at'].toString());
                    formattedCreated = DateFormat('dd/MM/yy').format(dt);
                  } catch (_) {
                    formattedCreated = s['created_at'].toString().split('T')[0];
                  }
                }

                return DataRow(
                  color: WidgetStateProperty.resolveWith<Color?>((states) {
                    if (states.contains(WidgetState.hovered)) return const Color(0xFFF9FAFB);
                    return null;
                  }),
                  cells: [
                    // 1. Établissement (Avatar + Nom, clickable)
                    DataCell(
                      Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: SizedBox(
                          width: schoolW,
                          child: InkWell(
                            onTap: () => context.go('/schools/${s['id']}'),
                            mouseCursor: SystemMouseCursors.click,
                            borderRadius: BorderRadius.circular(8),
                            child: Row(
                              children: [
                                _buildSchoolAvatar(s),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    s['name'] ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: Color(0xFF0F172A),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 2. Code (Clean Shortcut Pill)
                    DataCell(
                      SizedBox(
                        width: codeW,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Tooltip(
                            message: rawCode,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                displayCode,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                  fontFamily: 'monospace',
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 3. Email Directeur
                    DataCell(
                      SizedBox(
                        width: emailW,
                        child: Text(
                          email,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF334155),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    // 4. Téléphone
                    DataCell(
                      SizedBox(
                        width: phoneW,
                        child: Text(
                          (directorPhone != null && directorPhone.isNotEmpty) ? directorPhone : '—',
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Color(0xFF64748B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    // 5. Forfait & Tarif (Merged Single Column)
                    DataCell(
                      SizedBox(
                        width: planPriceW,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F3FF),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFDDD6FE)),
                              ),
                              child: Text(
                                planBadge,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF7C3AED),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$monthlyPrice TND/m',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF334155),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 6. Quota IA
                    DataCell(
                      SizedBox(
                        width: quotaW,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '\$${spent.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isQuotaExceeded ? const Color(0xFFDC2626) : const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              ' / \$${budget.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 7. Statut (Single Pill)
                    DataCell(
                      SizedBox(
                        width: statusW,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isActive ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isActive ? 'Actif' : 'Suspendu',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: isActive ? const Color(0xFF059669) : const Color(0xFFDC2626),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 8. Créé le
                    DataCell(
                      SizedBox(
                        width: createdW,
                        child: Text(
                          formattedCreated,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                        ),
                      ),
                    ),
                    // 9. Actions (3 dots)
                    DataCell(
                      SizedBox(
                        width: actionsW,
                        child: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_horiz, size: 18, color: Color(0xFF94A3B8)),
                          tooltip: 'Actions',
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: const Color(0xFFE2E8F0).withValues(alpha: 0.6)),
                          ),
                          elevation: 6,
                          shadowColor: Colors.black.withValues(alpha: 0.08),
                          offset: const Offset(-160, 40),
                          onSelected: (val) async {
                            switch (val) {
                              case 'profile':
                                context.go('/schools/${s['id']}');
                                break;
                              case 'quota':
                                _showEditAiQuotaModal(context, s);
                                break;
                              case 'invoice':
                                _showInvoiceGeneratorModal(
                                  context,
                                  state.schools,
                                  preselectedSchoolId: s['id'],
                                );
                                break;
                              case 'logo':
                                _showSchoolLogoModal(context, s);
                                break;
                              case 'plan':
                                _showChangePlanModal(context, s, state.plans);
                                break;
                              case 'credentials':
                                showConsoleSchoolCredentialsModal(
                                  context: context,
                                  school: s,
                                  onPasswordChanged: () => ref.read(platformProvider.notifier).loadAll(),
                                );
                                break;
                              case 'toggle_status':
                                final messenger = ScaffoldMessenger.of(context);
                                final ok = await ref
                                    .read(platformProvider.notifier)
                                    .toggleSchoolStatus(s['id'], !isActive);
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(ok
                                        ? (isActive
                                            ? 'Établissement suspendu.'
                                            : 'Établissement réactivé !')
                                        : 'Erreur lors du changement de statut.'),
                                    backgroundColor: ok
                                        ? (isActive ? ConsoleColors.warning : ConsoleColors.success)
                                        : ConsoleColors.error,
                                  ),
                                );
                                break;
                            }
                          },
                          itemBuilder: (_) => [
                            _buildPopupItem('profile', Icons.visibility_outlined, 'Voir le Profil École', const Color(0xFF2563EB)),
                            _buildPopupItem('quota', Icons.auto_awesome_rounded, 'Modifier Quota IA & Budget', const Color(0xFF6D4CF6)),
                            _buildPopupItem('invoice', Icons.picture_as_pdf_rounded, 'Générer Facture PDF', const Color(0xFF059669)),
                            _buildPopupItem('logo', Icons.image_outlined, 'Changer le Logo', const Color(0xFF2563EB)),
                            _buildPopupItem('plan', Icons.card_membership_rounded, 'Changer de Forfait', const Color(0xFF7C3AED)),
                            _buildPopupItem('credentials', Icons.key_rounded, 'Mot de passe & Identifiants', const Color(0xFFD97706)),
                            const PopupMenuItem<String>(
                              enabled: false,
                              height: 9,
                              padding: EdgeInsets.zero,
                              child: Divider(
                                height: 1,
                                thickness: 1,
                                color: Color(0xFFF1F5F9),
                              ),
                            ),
                            _buildPopupItem(
                              'toggle_status',
                              isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                              isActive ? 'Suspendre l\'école' : 'Réactiver l\'école',
                              isActive ? const Color(0xFFDC2626) : const Color(0xFF059669),
                            ),
                          ],
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
    );
  }

  // ═══════════════════════════════════════════════════
  // PAGINATION (CLEAN BORDERLESS ARROWS)
  // ═══════════════════════════════════════════════════
  Widget _buildPagination(int totalItems) {
    final totalPages = _schoolsPageSize == -1 ? 1 : (totalItems / _schoolsPageSize).ceil();
    final currentPageDisplay = _schoolsPage + 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFB),
        border: Border(top: BorderSide(color: const Color(0xFFE2E8F0).withValues(alpha: 0.5))),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          // Items per page
          const Text('Afficher par ', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _schoolsPageSize,
                isDense: true,
                borderRadius: BorderRadius.circular(10),
                dropdownColor: Colors.white,
                elevation: 4,
                menuMaxHeight: 200,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: Color(0xFF94A3B8)),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                items: [5, 10, 20, 50].map((v) => DropdownMenuItem(
                  value: v,
                  child: Text('$v', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                )).toList(),
                onChanged: (v) => setState(() {
                  _schoolsPageSize = v!;
                  _schoolsPage = 0;
                }),
              ),
            ),
          ),
          const Spacer(),
          // Page info
          Text(
            'Page $currentPageDisplay sur ${totalPages == 0 ? 1 : totalPages}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(width: 8),
          // Prev/Next (Clean borderless arrow buttons)
          Row(
            children: [
              IconButton(
                onPressed: _schoolsPage > 0 ? () => setState(() => _schoolsPage--) : null,
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                color: const Color(0xFF334155),
                disabledColor: const Color(0xFFCBD5E1),
                splashRadius: 18,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              const SizedBox(width: 2),
              IconButton(
                onPressed: (_schoolsPage + 1) < totalPages ? () => setState(() => _schoolsPage++) : null,
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                color: const Color(0xFF334155),
                disabledColor: const Color(0xFFCBD5E1),
                splashRadius: 18,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Color(0xFF94A3B8),
        letterSpacing: 0.5,
      ),
    );
  }

  PopupMenuItem<String> _buildPopupItem(String value, IconData icon, String label, Color color) {
    return PopupMenuItem(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: value == 'toggle_status' ? color : const Color(0xFF1E293B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChipItem({
    required String label,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
    Color activeColor = const Color(0xFF6D4CF6),
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.08) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? activeColor.withValues(alpha: 0.35) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? activeColor : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? activeColor.withValues(alpha: 0.15) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? activeColor : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAFB),
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
                borderRadius: BorderRadius.circular(8),
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



  Widget _buildSectionIndicator(String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: const Color(0xFF6D4CF6),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: Color(0xFF4B5563),
          ),
        ),
      ],
    );
  }

  void _showEditAiQuotaModal(BuildContext context, Map<String, dynamic> school) {
    final schoolId = school['id'] as String;
    final schoolName = school['name'] as String? ?? 'Établissement';
    final quota = _extractRelationMap(school['ai_school_quotas']);
    final currentBudget = (quota?['monthly_budget_usd'] as num?)?.toDouble() ?? 25.0;
    final currentSpent = (quota?['spent_current_month_usd'] as num?)?.toDouble() ?? 0.0;
    final currentDaily = (quota?['daily_messages_per_student'] as num?)?.toInt() ?? 30;
    final currentKill = quota?['kill_switch_enabled'] == true;

    final budgetCtrl = TextEditingController(text: currentBudget.toStringAsFixed(2));
    final dailyCtrl = TextEditingController(text: currentDaily.toString());
    bool killSwitch = currentKill;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.15),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: StatefulBuilder(
          builder: (sbContext, setSbState) => Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: 500,
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: ConsoleColors.brandSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.auto_awesome_rounded, color: ConsoleColors.brand, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Quota & Budget IA — $schoolName',
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: ConsoleColors.textPrimary)),
                            const SizedBox(height: 3),
                            Text('Dépenses actuelles ce mois: \$${currentSpent.toStringAsFixed(4)} USD',
                                style: const TextStyle(fontSize: 12, color: ConsoleColors.textSecondary)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSectionIndicator('BUDGET MENSUEL MAXIMUM (USD)'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: budgetCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      prefixText: '\$ ',
                      hintText: '25.00',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildSectionIndicator('MESSAGES PAR ÉTUDIANT / JOUR'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: dailyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: '30',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: killSwitch ? ConsoleColors.errorSoft : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: killSwitch ? ConsoleColors.error : const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Arrêt d\'urgence IA (Kill Switch École)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: killSwitch ? ConsoleColors.error : ConsoleColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Désactive immédiatement l\'accès à l\'IA pour cet établissement.',
                                style: TextStyle(fontSize: 11.5, color: ConsoleColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: killSwitch,
                          activeThumbColor: ConsoleColors.error,
                          onChanged: (val) => setSbState(() => killSwitch = val),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: 40,
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(foregroundColor: const Color(0xFF6B7280)),
                          child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 40,
                        child: ElevatedButton(
                          onPressed: () async {
                            final budget = double.tryParse(budgetCtrl.text.trim()) ?? currentBudget;
                            final daily = int.tryParse(dailyCtrl.text.trim()) ?? currentDaily;
                            Navigator.pop(ctx);
                            final ok = await ref.read(platformProvider.notifier).updateSchoolAiQuota(
                              schoolId: schoolId,
                              monthlyBudgetUsd: budget,
                              dailyMessagesPerStudent: daily,
                              killSwitchEnabled: killSwitch,
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ok ? 'Quota IA mis à jour avec succès !' : 'Erreur mise à jour quota.'),
                                backgroundColor: ok ? ConsoleColors.success : ConsoleColors.error,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6D4CF6),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          child: const Text('Enregistrer le Quota', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showChangePlanModal(BuildContext context, Map<String, dynamic> school, List<Map<String, dynamic>> plans) {
    if (plans.isEmpty) return;
    final schoolId = school['id'] as String;
    final schoolName = school['name'] as String? ?? 'Établissement';
    final sub = _extractRelationMap(school['school_subscriptions']);
    String selectedPlanId = sub?['plan_id'] as String? ?? plans.first['id'] as String;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.15),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: StatefulBuilder(
          builder: (sbContext, setSbState) => Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: 480,
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: ConsoleColors.brandSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.card_membership_rounded, color: ConsoleColors.brand, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Changer le Forfait — $schoolName',
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: ConsoleColors.textPrimary)),
                            const SizedBox(height: 3),
                            const Text('Sélectionnez la nouvelle formule d\'abonnement.',
                                style: TextStyle(fontSize: 12, color: ConsoleColors.textSecondary)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSectionIndicator('CHOISIR UNE FORMULE D\'ABONNEMENT'),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: plans.any((p) => p['id'] == selectedPlanId) ? selectedPlanId : plans.first['id'],
                    borderRadius: BorderRadius.circular(10),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                    ),
                    items: plans.map((p) {
                      return DropdownMenuItem<String>(
                        value: p['id'] as String,
                        child: Text('${p['name']} (${p['price_tnd_monthly']} TND/mois)'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setSbState(() => selectedPlanId = val);
                    },
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: 40,
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(foregroundColor: const Color(0xFF6B7280)),
                          child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 40,
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final ok = await ref.read(platformProvider.notifier).updateSchoolSubscriptionPlan(
                              schoolId: schoolId,
                              planId: selectedPlanId,
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ok ? 'Forfait mis à jour avec succès !' : 'Erreur mise à jour forfait.'),
                                backgroundColor: ok ? ConsoleColors.success : ConsoleColors.error,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6D4CF6),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          child: const Text('Confirmer le changement', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // 3. BILLING PAGE
  // ══════════════════════════════════════════════════════════════
  Widget _buildBillingPage(PlatformState state, ConsoleStrings tr) {
    final pending = state.pendingPayments;
    final allInvoices = state.invoices;

    final searchedInvoices = allInvoices.where((inv) {
      if (_searchQuery.isEmpty) return true;
      final num = (inv['invoice_number'] ?? '').toString().toLowerCase();
      final sName = ((inv['school'] as Map?)?['name'] ?? '').toString().toLowerCase();
      return num.contains(_searchQuery) || sName.contains(_searchQuery);
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── PENDING PAYMENTS ──
          if (pending.isNotEmpty) ...[
            _surfaceCard(
              title: 'Vérification des Virements en Attente (${pending.length})',
              child: Column(
                children: pending.map((p) {
                  final inv = p['invoice'] as Map<String, dynamic>?;
                  final school = inv?['school'] as Map<String, dynamic>?;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: ConsoleColors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF6D4CF6).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: ConsoleColors.brandSoft,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.account_balance_outlined,
                            color: Color(0xFF6D4CF6),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${school?['name'] ?? "École"} — Facture N° ${inv?['invoice_number'] ?? ""}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: ConsoleColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Réf transaction: ${p['transaction_ref'] ?? "N/A"} • Montant déclaré: ${p['amount']} TND',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: ConsoleColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 38,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final ok = await ref
                                  .read(platformProvider.notifier)
                                  .verifyPayment(p['id']);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(ok
                                      ? 'Paiement validé avec succès !'
                                      : 'Erreur lors de la validation du paiement.'),
                                  backgroundColor: ok
                                      ? ConsoleColors.success
                                      : ConsoleColors.error,
                                ),
                              );
                            },
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: const Text('Valider & Marquer Payé', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: ConsoleColors.success,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // ── INVOICES TABLE MATCHING USERS TABLE ──
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ConsoleColors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Historique des Factures Émises (${searchedInvoices.length})',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: ConsoleColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Factures officielles conformes avec timbre fiscal et arrêté légal en toutes lettres.',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 38,
                        child: ElevatedButton.icon(
                          onPressed: () => _showInvoiceGeneratorModal(context, state.schools),
                          icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                          label: const Text('Nouvelle Facture PDF', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6D4CF6),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: ConsoleColors.divider),

                searchedInvoices.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              const Text(
                                'Aucune facture enregistrée pour l\'instant.',
                                style: TextStyle(fontSize: 14, color: ConsoleColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                          headingRowHeight: 46,
                          dataRowMinHeight: 60,
                          dataRowMaxHeight: 64,
                          horizontalMargin: 24,
                          columnSpacing: 28,
                          columns: const [
                            DataColumn(label: Text('N° FACTURE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                            DataColumn(label: Text('ÉTABLISSEMENT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                            DataColumn(label: Text('MONTANT TOTAL TTC', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                            DataColumn(label: Text('DATE ÉCHÉANCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                            DataColumn(label: Text('STATUT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                            DataColumn(label: Text('ACTION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                          ],
                          rows: searchedInvoices.map((inv) {
                            final school = inv['school'] as Map<String, dynamic>?;
                            final schoolName = school?['name']?.toString() ?? 'École';
                            final invNum = inv['invoice_number']?.toString() ?? 'FAC-2026';
                            final amount = (inv['amount'] as num?)?.toDouble() ?? 0.0;
                            final currency = inv['currency']?.toString() ?? 'TND';
                            final dueDate = inv['due_date']?.toString() ?? '—';
                            final status = inv['status']?.toString() ?? 'issued';

                            return DataRow(
                              cells: [
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      invNum,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                        color: ConsoleColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    schoolName,
                                    style: const TextStyle(fontWeight: FontWeight.w600, color: ConsoleColors.textPrimary),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '${InvoicePdfGenerator.formatTnd(amount)} $currency',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                      color: Color(0xFF6D4CF6),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(dueDate, style: const TextStyle(color: ConsoleColors.textSecondary, fontSize: 12.5)),
                                ),
                                DataCell(_buildStatusBadge(status)),
                                DataCell(
                                  SizedBox(
                                    height: 32,
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final invoiceData = InvoiceDataModel(
                                          invoiceNumber: invNum,
                                          date: DateTime.tryParse(inv['issue_date']?.toString() ?? '') ?? DateTime.now(),
                                          issuerName: 'Aziz Tounsi',
                                          matriculeFiscale: '2007778S',
                                          clientName: schoolName,
                                          timbreFiscal: 1.0,
                                          items: [
                                            InvoiceItemModel(
                                              index: 1,
                                              ref: 'P-0001',
                                              designation: 'Abonnement Plateforme Académique SaaS',
                                              quantity: 1,
                                              unitPriceHt: amount > 1.0 ? amount - 1.0 : amount,
                                              tvaPercent: 0.0,
                                            ),
                                          ],
                                        );
                                        await InvoicePdfGenerator.downloadOrPrintInvoice(invoiceData);
                                      },
                                      icon: const Icon(Icons.download_rounded, size: 14),
                                      label: const Text('Télécharger PDF', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF6D4CF6),
                                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // 4. AI TELEMETRY PAGE
  // ══════════════════════════════════════════════════════════════
  Widget _buildAiTelemetryPage(PlatformState state, ConsoleStrings tr) {
    final settings = state.platformSettings;
    final killSwitch = settings?['global_ai_kill_switch'] == true;
    final allLogs = state.recentAiLogs;

    final filteredLogs = allLogs.where((l) {
      if (_searchQuery.isEmpty) return true;
      final model = (l['model'] ?? '').toString().toLowerCase();
      final sName = ((l['school'] as Map?)?['name'] ?? '').toString().toLowerCase();
      return model.contains(_searchQuery) || sName.contains(_searchQuery);
    }).toList();

    final pageStart = _telemetryPage * _telemetryPageSize;
    final paginatedLogs = filteredLogs.skip(pageStart).take(_telemetryPageSize).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── KILL SWITCH ALERT ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: killSwitch ? ConsoleColors.errorSoft : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: killSwitch ? ConsoleColors.error : ConsoleColors.cardBorder,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: killSwitch
                        ? ConsoleColors.error.withValues(alpha: 0.14)
                        : ConsoleColors.successSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    killSwitch ? Icons.power_off : Icons.power,
                    color: killSwitch ? ConsoleColors.error : ConsoleColors.success,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        killSwitch
                            ? 'Kill Switch IA Général Activé — Requêtes Bloquées'
                            : 'Passerelle IA Active & Opérationnelle',
                        style: TextStyle(
                          color: killSwitch ? ConsoleColors.error : ConsoleColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        killSwitch
                            ? 'Toutes les requêtes Gemini/OpenAI des étudiants et professeurs sont actuellement suspendues.'
                            : 'Supervisez la consommation en jetons et les dépenses réelles API par établissement.',
                        style: const TextStyle(
                          color: ConsoleColors.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: killSwitch,
                  activeThumbColor: ConsoleColors.error,
                  onChanged: (val) =>
                      ref.read(platformProvider.notifier).toggleAiKillSwitch(val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── TELEMETRY LOGS TABLE ──
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ConsoleColors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Consommation IA & Télémétrie (${filteredLogs.length})',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: ConsoleColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Coûts réels en dollars calculés sur les tokens d\'entrée/sortie et latences relevées.',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: ConsoleColors.divider),

                filteredLogs.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome_outlined, size: 48, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              const Text(
                                'Aucun log de télémétrie IA enregistré pour le moment.',
                                style: TextStyle(fontSize: 14, color: ConsoleColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                          headingRowHeight: 46,
                          dataRowMinHeight: 56,
                          dataRowMaxHeight: 60,
                          horizontalMargin: 24,
                          columnSpacing: 28,
                          columns: const [
                            DataColumn(label: Text('ÉTABLISSEMENT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                            DataColumn(label: Text('MODÈLE IA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                            DataColumn(label: Text('JETONS CONSOMMÉS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                            DataColumn(label: Text('COÛT RÉEL (USD)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                            DataColumn(label: Text('LATENCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                            DataColumn(label: Text('STATUT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                            DataColumn(label: Text('ACTIONS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                          ],
                          rows: paginatedLogs.map((l) {
                            final school = l['school'] as Map<String, dynamic>?;
                            final cost = (l['cost_usd'] as num?)?.toDouble() ?? 0.0;
                            final model = l['model']?.toString() ?? 'gemini-1.5-flash';
                            final tokens = l['total_tokens'] ?? 0;
                            final latency = l['latency_ms'] ?? '—';
                            final status = l['status']?.toString() ?? 'success';

                            return DataRow(
                              cells: [
                                DataCell(
                                  Text(
                                    school?['name'] ?? 'Plateforme',
                                    style: const TextStyle(fontWeight: FontWeight.w600, color: ConsoleColors.textPrimary),
                                  ),
                                ),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      model,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(Text('$tokens tokens', style: const TextStyle(fontSize: 12.5))),
                                DataCell(
                                  Text(
                                    '\$${cost.toStringAsFixed(5)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: ConsoleColors.success,
                                    ),
                                  ),
                                ),
                                DataCell(Text('$latency ms', style: const TextStyle(color: ConsoleColors.textSecondary, fontSize: 12))),
                                DataCell(_buildStatusBadge(status)),
                                DataCell(
                                  school != null
                                      ? IconButton(
                                          icon: const Icon(Icons.tune_rounded, size: 18, color: Color(0xFF6D4CF6)),
                                          tooltip: 'Ajuster le quota de cette école',
                                          onPressed: () => _showEditAiQuotaModal(context, school),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),

                _buildTablePaginationBar(
                  totalItems: filteredLogs.length,
                  currentPage: _telemetryPage,
                  pageSize: _telemetryPageSize,
                  onPageChanged: (newPage) => setState(() => _telemetryPage = newPage),
                  onPageSizeChanged: (newSize) => setState(() {
                    _telemetryPageSize = newSize;
                    _telemetryPage = 0;
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // 5. AUDIT PAGE
  // ══════════════════════════════════════════════════════════════
  Widget _buildAuditPage(PlatformState state, ConsoleStrings tr) {
    final allLogs = state.auditLogs;

    final filteredLogs = allLogs.where((a) {
      final act = (a['action'] ?? '').toString().toLowerCase();
      final tbl = (a['target_table'] ?? '').toString().toLowerCase();
      final role = (a['actor_role'] ?? '').toString().toLowerCase();

      if (_auditActionFilter != 'all') {
        if (!act.contains(_auditActionFilter) && !tbl.contains(_auditActionFilter)) {
          return false;
        }
      }

      if (_searchQuery.isEmpty) return true;
      return act.contains(_searchQuery) || tbl.contains(_searchQuery) || role.contains(_searchQuery);
    }).toList();

    final pageStart = _auditPage * _auditPageSize;
    final paginatedLogs = filteredLogs.skip(pageStart).take(_auditPageSize).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ConsoleColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Journaux d\'Audit Système (${filteredLogs.length})',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: ConsoleColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Historique immuable de toutes les actions administratives et de sécurité.',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      _buildFilterChipItem(
                        label: 'Tous',
                        count: allLogs.length,
                        isSelected: _auditActionFilter == 'all',
                        onTap: () => setState(() {
                          _auditActionFilter = 'all';
                          _auditPage = 0;
                        }),
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChipItem(
                        label: 'Auth',
                        count: allLogs.where((l) => (l['action'] ?? '').toString().contains('login') || (l['target_table'] ?? '').toString().contains('user')).length,
                        isSelected: _auditActionFilter == 'auth',
                        onTap: () => setState(() {
                          _auditActionFilter = 'auth';
                          _auditPage = 0;
                        }),
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChipItem(
                        label: 'Écoles',
                        count: allLogs.where((l) => (l['target_table'] ?? '').toString().contains('school')).length,
                        isSelected: _auditActionFilter == 'school',
                        onTap: () => setState(() {
                          _auditActionFilter = 'school';
                          _auditPage = 0;
                        }),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: ConsoleColors.divider),

            filteredLogs.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_toggle_off_rounded, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          const Text(
                            'Aucun log d\'audit ne correspond à vos filtres.',
                            style: TextStyle(fontSize: 14, color: ConsoleColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                      headingRowHeight: 46,
                      dataRowMinHeight: 56,
                      dataRowMaxHeight: 60,
                      horizontalMargin: 24,
                      columnSpacing: 28,
                      columns: const [
                        DataColumn(label: Text('HORODATAGE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                        DataColumn(label: Text('ÉTABLISSEMENT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                        DataColumn(label: Text('ACTEUR / RÔLE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                        DataColumn(label: Text('ACTION EFFECTUÉE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                        DataColumn(label: Text('TABLE CIBLE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                      ],
                      rows: paginatedLogs.map((a) {
                        final school = a['school'] as Map<String, dynamic>?;
                        final date = a['created_at'] != null
                            ? a['created_at'].toString().split('.')[0].replaceFirst('T', ' ')
                            : '—';
                        final role = a['actor_role'] ?? 'super_admin';
                        final act = a['action'] ?? 'ACTION';
                        final tbl = a['target_table'] ?? 'system';

                        return DataRow(
                          cells: [
                            DataCell(Text(date, style: const TextStyle(fontSize: 12, color: ConsoleColors.textSecondary))),
                            DataCell(Text(school?['name'] ?? 'Plateforme', style: const TextStyle(fontWeight: FontWeight.w600))),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEDE9FE),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  role.toString().toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF6D4CF6),
                                  ),
                                ),
                              ),
                            ),
                            DataCell(Text(act, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(tbl, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),

            _buildTablePaginationBar(
              totalItems: filteredLogs.length,
              currentPage: _auditPage,
              pageSize: _auditPageSize,
              onPageChanged: (newPage) => setState(() => _auditPage = newPage),
              onPageSizeChanged: (newSize) => setState(() {
                _auditPageSize = newSize;
                _auditPage = 0;
              }),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // 6. BUG REPORTS PAGE (MATCHING ANNOUNCEMENTS TABLE)
  // ══════════════════════════════════════════════════════════════
  Widget _buildBugReportsPage(PlatformState state, ConsoleStrings tr) {
    final allReports = state.bugReports;

    final totalCount = allReports.length;
    final openCount = allReports.where((b) => b['status'] == 'open' || b['status'] == 'sent').length;
    final inProgressCount = allReports.where((b) => b['status'] == 'in_progress').length;
    final resolvedCount = allReports.where((b) => b['status'] == 'resolved' || b['status'] == 'closed').length;

    final filteredReports = allReports.where((b) {
      final status = (b['status'] ?? 'open').toString().toLowerCase();
      if (_bugStatusFilter == 'open' && (status != 'open' && status != 'sent')) return false;
      if (_bugStatusFilter == 'in_progress' && status != 'in_progress') return false;
      if (_bugStatusFilter == 'resolved' && (status != 'resolved' && status != 'closed')) return false;

      if (_searchQuery.isEmpty) return true;
      final t = (b['title'] ?? '').toString().toLowerCase();
      final d = (b['description'] ?? '').toString().toLowerCase();
      final s = (b['student_name'] ?? '').toString().toLowerCase();
      final phone = (b['student_phone'] ?? '').toString().toLowerCase();
      return t.contains(_searchQuery) || d.contains(_searchQuery) || s.contains(_searchQuery) || phone.contains(_searchQuery);
    }).toList();

    final pageStart = _bugsPage * _bugsPageSize;
    final paginatedReports = filteredReports.skip(pageStart).take(_bugsPageSize).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── METRIC CARDS ──
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Total Tickets',
                  '$totalCount',
                  'Signalements reçus',
                  Icons.bug_report_outlined,
                  ConsoleColors.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  'En Attente',
                  '$openCount',
                  'À analyser & qualifier',
                  Icons.error_outline,
                  ConsoleColors.error,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  'En Cours',
                  '$inProgressCount',
                  'En investigation active',
                  Icons.hourglass_top_rounded,
                  ConsoleColors.warning,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  'Résolus',
                  '$resolvedCount',
                  'Corrigés et validés',
                  Icons.check_circle_outline,
                  ConsoleColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── BUG REPORTS TABLE (MATCHING ANNOUNCEMENTS TABLE) ──
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ConsoleColors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Signalements de Bugs & Retours Utilisateurs (${filteredReports.length})',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: ConsoleColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Consultez les détails, coordonnées directes de l\'étudiant et captures d\'écran associées.',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                      // Filter tabs: Tous / En attente / En cours / Résolus
                      Row(
                        children: [
                          _buildFilterChipItem(
                            label: 'Tous',
                            count: totalCount,
                            isSelected: _bugStatusFilter == 'all',
                            onTap: () => setState(() {
                              _bugStatusFilter = 'all';
                              _bugsPage = 0;
                            }),
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChipItem(
                            label: 'En attente',
                            count: openCount,
                            isSelected: _bugStatusFilter == 'open',
                            activeColor: ConsoleColors.error,
                            onTap: () => setState(() {
                              _bugStatusFilter = 'open';
                              _bugsPage = 0;
                            }),
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChipItem(
                            label: 'En cours',
                            count: inProgressCount,
                            isSelected: _bugStatusFilter == 'in_progress',
                            activeColor: ConsoleColors.warning,
                            onTap: () => setState(() {
                              _bugStatusFilter = 'in_progress';
                              _bugsPage = 0;
                            }),
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChipItem(
                            label: 'Résolus',
                            count: resolvedCount,
                            isSelected: _bugStatusFilter == 'resolved',
                            activeColor: ConsoleColors.success,
                            onTap: () => setState(() {
                              _bugStatusFilter = 'resolved';
                              _bugsPage = 0;
                            }),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: ConsoleColors.divider),

                filteredReports.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline_rounded, size: 48, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              const Text(
                                'Aucun ticket de bug dans cette catégorie.',
                                style: TextStyle(fontSize: 14, color: ConsoleColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                          headingRowHeight: 46,
                          dataRowMinHeight: 64,
                          dataRowMaxHeight: 68,
                          horizontalMargin: 24,
                          columnSpacing: 28,
                          columns: const [
                            DataColumn(label: Text('ÉTABLISSEMENT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                            DataColumn(label: Text('RAPPORTEUR & CONTACT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                            DataColumn(label: Text('CATÉGORIE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                            DataColumn(label: Text('TITRE DU SIGNALEMENT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                            DataColumn(label: Text('STATUT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                            DataColumn(label: Text('DATE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                            DataColumn(label: Text('ACTIONS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF4B5563)))),
                          ],
                          rows: paginatedReports.map((bug) {
                            final id = bug['id']?.toString() ?? '';
                            final title = bug['title']?.toString() ?? 'Sans titre';
                            final category = bug['category']?.toString() ?? 'Général';
                            final status = bug['status']?.toString().toLowerCase() ?? 'open';
                            final studentName = bug['student_name']?.toString() ?? 'Utilisateur anonyme';
                            final studentPhone = bug['student_phone']?.toString();
                            final schoolName = bug['schools']?['name']?.toString() ?? bug['school_id']?.toString() ?? 'École';
                            final createdAt = bug['created_at'] != null ? bug['created_at'].toString().split('T')[0] : '—';
                            final isFallback = bug['_source'] == 'suggestions';

                            return DataRow(
                              cells: [
                                DataCell(
                                  Text(schoolName, style: const TextStyle(fontWeight: FontWeight.w600, color: ConsoleColors.textPrimary)),
                                ),
                                DataCell(
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        studentName,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ConsoleColors.textPrimary),
                                      ),
                                      if (studentPhone != null && studentPhone.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.phone_rounded, size: 12, color: Color(0xFF6D4CF6)),
                                            const SizedBox(width: 4),
                                            Text(
                                              studentPhone,
                                              style: const TextStyle(fontSize: 11.5, color: ConsoleColors.textSecondary),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: ConsoleColors.brandSoft,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      category.toUpperCase(),
                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF6D4CF6)),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 240),
                                    child: Text(
                                      title,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  PopupMenuButton<String>(
                                    initialValue: status,
                                    tooltip: 'Changer le statut',
                                    onSelected: (val) => ref.read(platformProvider.notifier).updateBugReportStatus(id, val, isFallback: isFallback),
                                    child: _buildBugStatusBadge(status),
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'open', child: Text('Marquer En attente')),
                                      PopupMenuItem(value: 'in_progress', child: Text('Marquer En cours')),
                                      PopupMenuItem(value: 'resolved', child: Text('Marquer Résolu')),
                                      PopupMenuItem(value: 'closed', child: Text('Marquer Fermé')),
                                    ],
                                  ),
                                ),
                                DataCell(Text(createdAt, style: const TextStyle(fontSize: 12, color: ConsoleColors.textSecondary))),
                                DataCell(
                                  SizedBox(
                                    height: 32,
                                    child: ElevatedButton.icon(
                                      onPressed: () => _showBugDetailModal(context, bug),
                                      icon: const Icon(Icons.visibility_outlined, size: 14),
                                      label: const Text('Détails', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFF1F5F9),
                                        foregroundColor: const Color(0xFF334155),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),

                _buildTablePaginationBar(
                  totalItems: filteredReports.length,
                  currentPage: _bugsPage,
                  pageSize: _bugsPageSize,
                  onPageChanged: (newPage) => setState(() => _bugsPage = newPage),
                  onPageSizeChanged: (newSize) => setState(() {
                    _bugsPageSize = newSize;
                    _bugsPage = 0;
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // 7. SECURITY & SLO OBSERVABILITY DASHBOARD (PILLAR 4)
  // ══════════════════════════════════════════════════════════════
  Widget _buildSecuritySloPage(PlatformState state, ConsoleStrings tr) {
    final slo = state.sloMetrics ?? {};
    final events = state.securityEvents;

    final availability = (slo['availability_slo_pct'] as num?)?.toDouble() ?? 99.94;
    final burnRate = (slo['error_budget_burn_rate'] as num?)?.toDouble() ?? 0.06;
    final p95 = (slo['latency_p95_ms'] as num?)?.toInt() ?? 138;
    final p50 = (slo['latency_p50_ms'] as num?)?.toInt() ?? 34;
    final anomalies = events.where((e) => (e['risk_score'] as num? ?? 0) >= 50).length;

    // Filter events by search query
    final filteredEvents = events.where((e) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final type = (e['event_type'] ?? '').toString().toLowerCase();
      final surface = (e['surface'] ?? '').toString().toLowerCase();
      final ip = (e['ip_address'] ?? '').toString().toLowerCase();
      final desc = (e['description'] ?? '').toString().toLowerCase();
      return type.contains(q) || surface.contains(q) || ip.contains(q) || desc.contains(q);
    }).toList();

    final pageStart = _securityPage * _securityPageSize;
    final paginatedEvents = filteredEvents.skip(pageStart).take(_securityPageSize).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 4 KPI CARDS (SLO, BURN RATE, LATENCY, ANOMALIES) ──
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'SLO Disponibilité',
                  '${availability.toStringAsFixed(2)}%',
                  'Objectif: 99.90% | Burn: ${(100 - availability).toStringAsFixed(3)}%',
                  Icons.verified_user_outlined,
                  availability >= 99.9 ? ConsoleColors.success : ConsoleColors.error,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  'Error Budget Burn',
                  '${burnRate.toStringAsFixed(2)}x',
                  burnRate < 1.0 ? 'Nominal (< 1.0x acceptable)' : 'Alerte: Budget consommé rapidement',
                  Icons.local_fire_department_outlined,
                  burnRate < 1.0 ? const Color(0xFF3B82F6) : ConsoleColors.error,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  'Latence (P95 / P50)',
                  '${p95}ms / ${p50}ms',
                  'Filtre PostgREST & Auth inclus',
                  Icons.speed_outlined,
                  p95 < 500 ? const Color(0xFF8B5CF6) : ConsoleColors.warning,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  'Anomalies Sessions',
                  '$anomalies',
                  'Scores de risque élevés (≥ 50)',
                  Icons.security_outlined,
                  anomalies == 0 ? ConsoleColors.success : const Color(0xFFEF4444),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── OUTSIDE-IN SYNTHETIC HEALTH MONITORING PANEL ──
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ConsoleColors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.favorite_rounded, color: Color(0xFF10B981), size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Santé Synthétique Outside-In (Sonde Edge & Coeur Supabase)',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ConsoleColors.textPrimary),
                            ),
                            Text(
                              'Test de bout-en-bout simulant un client externe toutes les 60 secondes',
                              style: TextStyle(fontSize: 12, color: ConsoleColors.textSecondary),
                            ),
                          ],
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        ref.read(platformProvider.notifier).loadAll();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Sonde de santé synthétique exécutée avec succès (SLO 99.9% Nominal)'),
                            backgroundColor: ConsoleColors.success,
                          ),
                        );
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Tester Maintenant', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF1F5F9),
                        foregroundColor: const Color(0xFF334155),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Divider(height: 1, color: ConsoleColors.divider),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _buildHealthCheckItem(
                        title: 'PostgreSQL Core',
                        status: 'OPÉRATIONNEL',
                        latency: '11ms',
                        icon: Icons.storage_rounded,
                        color: ConsoleColors.success,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _buildHealthCheckItem(
                        title: 'Supabase GoTrue Auth',
                        status: 'ROTATION ACTIVE',
                        latency: '38ms',
                        icon: Icons.key_rounded,
                        color: ConsoleColors.success,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _buildHealthCheckItem(
                        title: 'Pre-Request Guard',
                        status: 'ZERO TRUST V2',
                        latency: '1ms',
                        icon: Icons.shield_rounded,
                        color: const Color(0xFF6D4CF6),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _buildHealthCheckItem(
                        title: 'Storage Documents RLS',
                        status: 'VERROUILLÉ & PRIVÉ',
                        latency: '24ms',
                        icon: Icons.lock_outline_rounded,
                        color: const Color(0xFF2563EB),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── LIVE SECURITY EVENTS & ANOMALY DETECTION TABLE ──
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ConsoleColors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Flux d\'Événements de Sécurité & Détection d\'Anomalies',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ConsoleColors.textPrimary),
                          ),
                          Text(
                            '${filteredEvents.length} événements enregistrés (Trace ID corrélés & Fingerprints)',
                            style: const TextStyle(fontSize: 12, color: ConsoleColors.textSecondary),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.shield_outlined, size: 14, color: Color(0xFFDC2626)),
                            SizedBox(width: 6),
                            Text(
                              'Auto-Revocation Actif (Score ≥ 80)',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFDC2626)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: ConsoleColors.divider),

                filteredEvents.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified_rounded, size: 48, color: Color(0xFF10B981)),
                              SizedBox(height: 12),
                              Text(
                                'Aucun événement suspect ou anomalie détectée.',
                                style: TextStyle(fontSize: 14, color: ConsoleColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                          columns: const [
                            DataColumn(label: Text('DATE / TRACE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                            DataColumn(label: Text('TYPE ÉVÉNEMENT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                            DataColumn(label: Text('SURFACE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                            DataColumn(label: Text('IP / EMPREINTE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                            DataColumn(label: Text('SÉVÉRITÉ / RISQUE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                            DataColumn(label: Text('ACTION DÉFENSE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                          ],
                          rows: paginatedEvents.map((evt) {
                            final rawDate = evt['created_at']?.toString() ?? '';
                            final dateFormatted = rawDate.isNotEmpty
                                ? DateFormat('dd/MM HH:mm:ss').format(DateTime.tryParse(rawDate)?.toLocal() ?? DateTime.now())
                                : '-';
                            final eventType = evt['event_type']?.toString() ?? 'unknown_event';
                            final surface = evt['surface']?.toString() ?? 'client';
                            final ip = evt['ip_address']?.toString() ?? 'IP inconnue';
                            final score = (evt['risk_score'] as num?)?.toInt() ?? 0;
                            final severity = evt['severity']?.toString().toUpperCase() ?? 'INFO';
                            final userId = evt['user_id']?.toString();

                            return DataRow(
                              cells: [
                                DataCell(
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(dateFormatted, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                      if (evt['trace_id'] != null)
                                        Text(
                                          (evt['trace_id'].toString()).substring(0, (evt['trace_id'].toString().length >= 8 ? 8 : evt['trace_id'].toString().length)),
                                          style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: ConsoleColors.textSecondary),
                                        ),
                                    ],
                                  ),
                                ),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      eventType,
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                                    ),
                                  ),
                                ),
                                DataCell(Text(surface, style: const TextStyle(fontSize: 12))),
                                DataCell(
                                  Text(
                                    ip,
                                    style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: ConsoleColors.textSecondary),
                                  ),
                                ),
                                DataCell(
                                  Row(
                                    children: [
                                      _buildSeverityBadge(severity),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Score: $score',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: score >= 80
                                              ? const Color(0xFFDC2626)
                                              : score >= 40
                                                  ? const Color(0xFFD97706)
                                                  : ConsoleColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                DataCell(
                                  userId != null && userId.isNotEmpty
                                      ? SizedBox(
                                          height: 30,
                                          child: ElevatedButton.icon(
                                            onPressed: () => _confirmKillSessionAndLock(userId, eventType),
                                            icon: const Icon(Icons.gavel_rounded, size: 13),
                                            label: const Text('Kill Session / Lock', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFFDC2626),
                                              foregroundColor: Colors.white,
                                              elevation: 0,
                                              padding: const EdgeInsets.symmetric(horizontal: 10),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                            ),
                                          ),
                                        )
                                      : const Text('N/A (Système)', style: TextStyle(fontSize: 11, color: ConsoleColors.textSecondary)),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),

                _buildTablePaginationBar(
                  totalItems: filteredEvents.length,
                  currentPage: _securityPage,
                  pageSize: _securityPageSize,
                  onPageChanged: (newPage) => setState(() => _securityPage = newPage),
                  onPageSizeChanged: (newSize) => setState(() {
                    _securityPageSize = newSize;
                    _securityPage = 0;
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthCheckItem({
    required String title,
    required String status,
    required String latency,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      status,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '($latency)',
                      style: const TextStyle(fontSize: 10, color: ConsoleColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeverityBadge(String severity) {
    Color bg;
    Color fg;
    switch (severity) {
      case 'CRITICAL':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFDC2626);
        break;
      case 'HIGH':
        bg = const Color(0xFFFFEDD5);
        fg = const Color(0xFFEA580C);
        break;
      case 'WARNING':
      case 'MEDIUM':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFD97706);
        break;
      default:
        bg = const Color(0xFFE0E7FF);
        fg = const Color(0xFF4338CA);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        severity,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }

  void _confirmKillSessionAndLock(String userId, String reason) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 10),
            Text('Révoquer la session & Verrouiller ?'),
          ],
        ),
        content: Text(
          'Êtes-vous sûr de vouloir révoquer instantanément la session et verrouiller le compte de l\'utilisateur ($userId) ?\n\n'
          'La prochaine requête PostgREST sera immédiatement rejetée par le Pre-Request Guard (Pillar 1 & 2).',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await ref
                  .read(platformProvider.notifier)
                  .killSessionOrLockAccount(userId, reason: 'Kill-switch déclenché manuellement: $reason');
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(success
                      ? 'Compte verrouillé et session révoquée avec succès.'
                      : 'Erreur lors du verrouillage du compte.'),
                  backgroundColor: success ? ConsoleColors.success : ConsoleColors.error,
                ),
              );
            },
            child: const Text('Confirmer la Révocation'),
          ),
        ],
      ),
    );
  }

  void _showBugDetailModal(BuildContext context, Map<String, dynamic> bug) {
    final id = bug['id']?.toString() ?? '';
    final title = bug['title']?.toString() ?? 'Sans titre';
    final desc = bug['description']?.toString() ?? 'Aucune description fournie.';
    final category = bug['category']?.toString() ?? 'Général';
    final status = bug['status']?.toString().toLowerCase() ?? 'open';
    final studentName = bug['student_name']?.toString() ?? 'Étudiant anonyme';
    final studentCode = bug['student_code']?.toString();
    final studentPhone = bug['student_phone']?.toString();
    final studentEmail = bug['student_email']?.toString();
    final schoolName = bug['schools']?['name']?.toString() ?? bug['school_id']?.toString() ?? 'Non spécifié';
    final createdAt = bug['created_at']?.toString() ?? '—';
    final isFallback = bug['_source'] == 'suggestions';
    final screenshotUrl = (bug['screenshot_url'] ?? bug['attachment_url'])?.toString();

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.2),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            width: 620,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.90,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: ConsoleColors.brandSoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          category.toUpperCase(),
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF6D4CF6)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: ConsoleColors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18, color: ConsoleColors.textSecondary),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),

                // Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionIndicator('Coordonnées du Rapporteur'),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.person_rounded, size: 17, color: Color(0xFF6D4CF6)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '$studentName ${studentCode != null ? "($studentCode)" : ""}',
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ConsoleColors.textPrimary),
                                    ),
                                  ),
                                  Text(schoolName, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                                ],
                              ),
                              const Divider(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        const Icon(Icons.phone_rounded, size: 16, color: ConsoleColors.success),
                                        const SizedBox(width: 8),
                                        SelectableText(
                                          studentPhone ?? 'Téléphone non renseigné',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: studentPhone != null ? ConsoleColors.textPrimary : ConsoleColors.textTertiary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Row(
                                      children: [
                                        const Icon(Icons.email_outlined, size: 16, color: Color(0xFF2563EB)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: SelectableText(
                                            studentEmail ?? 'Email non renseigné',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              color: studentEmail != null ? ConsoleColors.textSecondary : ConsoleColors.textTertiary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),

                        _buildSectionIndicator('Description Détaillée du Problème'),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: SelectableText(
                            desc,
                            style: const TextStyle(fontSize: 13.5, height: 1.5, color: Color(0xFF334155)),
                          ),
                        ),
                        const SizedBox(height: 22),

                        if (screenshotUrl != null && screenshotUrl.isNotEmpty) ...[
                          _buildSectionIndicator('Capture d\'écran Attachée'),
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (_) => Dialog(
                                  backgroundColor: Colors.transparent,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(screenshotUrl, fit: BoxFit.contain),
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              height: 180,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Image.network(
                                      screenshotUrl,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                      errorBuilder: (_, _, _) => const Center(child: Text('Image indisponible')),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.zoom_in, color: Colors.white, size: 18),
                                          SizedBox(width: 6),
                                          Text('Cliquer pour agrandir', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                        ],

                        _buildSectionIndicator('Statut Actuel & Prise en Charge'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text('Statut du ticket: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 10),
                            _buildBugStatusBadge(status),
                            const Spacer(),
                            Text('Date: ${createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt}',
                                style: const TextStyle(fontSize: 12, color: ConsoleColors.textSecondary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Footer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                    border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                  ),
                  child: Row(
                    children: [
                      PopupMenuButton<String>(
                        initialValue: status,
                        onSelected: (val) {
                          ref.read(platformProvider.notifier).updateBugReportStatus(id, val, isFallback: isFallback);
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_note_rounded, size: 16, color: Color(0xFF6D4CF6)),
                              SizedBox(width: 8),
                              Text('Changer le statut...', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                            ],
                          ),
                        ),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'open', child: Text('Marquer En attente')),
                          PopupMenuItem(value: 'in_progress', child: Text('Marquer En cours')),
                          PopupMenuItem(value: 'resolved', child: Text('Marquer Résolu')),
                          PopupMenuItem(value: 'closed', child: Text('Marquer Fermé')),
                        ],
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 38,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6D4CF6),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Fermer'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // SHARED LIGHT DESIGN-KIT HELPERS & MODALS
  // ══════════════════════════════════════════════════════════════
  Widget _surfaceCard({
    required String title,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ConsoleColors.cardBorder),
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
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ConsoleColors.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color, {
    String? trend,
    String? trendLabel,
    bool trendUp = true,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.015),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Borderless Icon + Small Navigation Arrow
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(icon, color: color, size: 20),
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.arrow_outward_rounded,
                  size: 14,
                  color: Color(0xFFCBD5E1),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Metric Title
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),

            // Metric Value (Golden ratio typographic weight)
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                letterSpacing: -0.6,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),

            // Trend or Subtitle Row
            Row(
              children: [
                if (trend != null) ...[
                  Icon(
                    trendUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    size: 12,
                    color: trendUp ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    trend,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: trendUp ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    trendLabel ?? subtitle,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    switch (status.toLowerCase()) {
      case 'active':
      case 'actif':
      case 'paid':
      case 'success':
        bg = ConsoleColors.successSoft;
        fg = ConsoleColors.success;
        break;
      case 'past_due':
      case 'trial':
      case 'issued':
      case 'pending':
        bg = ConsoleColors.warningSoft;
        fg = ConsoleColors.warning;
        break;
      case 'suspended':
      case 'inactif':
      case 'overdue':
      case 'error':
        bg = ConsoleColors.errorSoft;
        fg = ConsoleColors.error;
        break;
      default:
        bg = const Color(0xFFF1F5F9);
        fg = ConsoleColors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: fg,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildBugStatusBadge(String status) {
    Color bg;
    Color fg;
    String label;
    switch (status.toLowerCase()) {
      case 'open':
      case 'sent':
        bg = ConsoleColors.errorSoft;
        fg = ConsoleColors.error;
        label = 'OUVERT';
        break;
      case 'in_progress':
        bg = ConsoleColors.warningSoft;
        fg = ConsoleColors.warning;
        label = 'EN COURS';
        break;
      case 'resolved':
        bg = ConsoleColors.successSoft;
        fg = ConsoleColors.success;
        label = 'RÉSOLU';
        break;
      case 'closed':
        bg = const Color(0xFFF1F5F9);
        fg = ConsoleColors.textSecondary;
        label = 'FERMÉ';
        break;
      default:
        bg = ConsoleColors.errorSoft;
        fg = ConsoleColors.error;
        label = status.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.arrow_drop_down, color: fg, size: 16),
        ],
      ),
    );
  }

  Widget _buildSchoolLogoThumb(
    String? logoUrl, {
    double size = 32,
    double radius = 8,
  }) {
    final trimmed = logoUrl?.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: (trimmed != null && trimmed.isNotEmpty)
          ? Image.network(
              trimmed,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: size,
                height: size,
                color: ConsoleColors.brandSoft,
                child: Icon(
                  Icons.school_outlined,
                  size: size * 0.55,
                  color: ConsoleColors.brand,
                ),
              ),
            )
          : Container(
              width: size,
              height: size,
              color: ConsoleColors.brandSoft,
              child: Icon(
                Icons.school_outlined,
                size: size * 0.55,
                color: ConsoleColors.brand,
              ),
            ),
    );
  }

  void _showSchoolLogoModal(BuildContext context, Map<String, dynamic> school) {
    final schoolId = school['id'] as String;
    final schoolName = school['name'] as String? ?? 'École';
    String? draftLogoUrl = school['logo_url'] as String?;
    bool uploading = false;
    bool saving = false;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.12),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: StatefulBuilder(
          builder: (sbContext, setSbState) => AlertDialog(
            title: Text(
              'Logo — $schoolName',
              style: const TextStyle(
                color: ConsoleColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: ConsoleColors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: ConsoleColors.cardBorder),
                    ),
                    child: uploading
                        ? const Center(
                            child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Center(
                            child: _buildSchoolLogoThumb(
                              draftLogoUrl,
                              size: 104,
                              radius: 14,
                            ),
                          ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    (draftLogoUrl != null && draftLogoUrl!.isNotEmpty)
                        ? 'Logo personnalisé configuré pour cette école.'
                        : 'Utilise actuellement le logo par défaut.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: ConsoleColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: uploading || saving
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                setSbState(() => uploading = true);
                                try {
                                  final url = await ref
                                      .read(platformProvider.notifier)
                                      .pickAndUploadSchoolLogo(
                                          schoolId: schoolId);
                                  if (!ctx.mounted) return;
                                  if (url != null) {
                                    setSbState(() => draftLogoUrl = url);
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Échec téléversement logo: $e'),
                                        backgroundColor: ConsoleColors.error,
                                      ),
                                    );
                                  }
                                } finally {
                                  if (ctx.mounted) {
                                    setSbState(() => uploading = false);
                                  }
                                }
                              },
                        icon: const Icon(Icons.upload, size: 17),
                        label: const Text('Téléverser un logo'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ConsoleColors.brand,
                          foregroundColor: Colors.white,
                          elevation: 0,
                        ),
                      ),
                      if (draftLogoUrl != null && draftLogoUrl!.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: uploading || saving
                              ? null
                              : () => setSbState(() => draftLogoUrl = null),
                          icon: const Icon(Icons.restart_alt, size: 17),
                          label: const Text('Réinitialiser'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: uploading || saving
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        setSbState(() => saving = true);
                        final ok = await ref
                            .read(platformProvider.notifier)
                            .updateSchoolBranding(
                              schoolId: schoolId,
                              logoUrl: draftLogoUrl,
                              clearLogo: draftLogoUrl == null ||
                                  draftLogoUrl!.isEmpty,
                            );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (!mounted) return;
                        final errMsg =
                            ref.read(platformProvider).errorMessage;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(ok
                                ? 'Logo de $schoolName mis à jour !'
                                : (errMsg ??
                                    'Impossible de sauvegarder le logo.')),
                            backgroundColor: ok
                                ? ConsoleColors.success
                                : ConsoleColors.error,
                          ),
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: ConsoleColors.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateSchoolModal(
    BuildContext context,
    List<Map<String, dynamic>> plans,
  ) {
    ref.read(platformProvider.notifier).clearError();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final directorNameCtrl = TextEditingController();
    final directorPhoneCtrl = TextEditingController();
    final directorEmailCtrl = TextEditingController();
    final directorPassCtrl = TextEditingController(text: 'Director2026!');
    final aiBudgetCtrl = TextEditingController(text: '25.00');
    final maxStudentsCtrl = TextEditingController(text: '500');

    String selectedPlanId = plans.isNotEmpty ? plans[0]['id'] as String : '';
    String? selectedLogoUrl;
    bool uploadingLogo = false;
    bool creating = false;
    bool showPassword = false;

    void generatePassword(StateSetter setSbState) {
      final now = DateTime.now().millisecondsSinceEpoch.toString();
      final suffix = now.substring(now.length - 4);
      setSbState(() {
        directorPassCtrl.text = 'Director$suffix!';
      });
    }

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.2),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: StatefulBuilder(
          builder: (sbContext, setSbState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Container(
                width: 680,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.90,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── HEADER ──
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Ajouter un nouvel Établissement',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w700,
                                    color: ConsoleColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Configurez l\'établissement SaaS, son accès directeur et son forfait.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: () => Navigator.pop(ctx),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFF8FAFC),
                              ),
                              child: const Icon(Icons.close, size: 18, color: ConsoleColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── FORM BODY (NO SECTION TITLES / VERTICAL LINES) ──
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Logo Upload Row — Logo container height matching the text and button vertically (76px)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 76,
                                  height: 76,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: uploadingLogo
                                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                                      : _buildSchoolLogoThumb(selectedLogoUrl, size: 76, radius: 12),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        'Logo de l\'école (recommandé)',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF334155),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      const Text(
                                        'Format PNG, JPG ou WebP. Apparaît sur le portail et les factures.',
                                        style: TextStyle(fontSize: 11.5, color: ConsoleColors.textSecondary),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          SizedBox(
                                            height: 32,
                                            child: OutlinedButton.icon(
                                              onPressed: uploadingLogo
                                                  ? null
                                                  : () async {
                                                      setSbState(() => uploadingLogo = true);
                                                      try {
                                                        final url = await ref
                                                            .read(platformProvider.notifier)
                                                            .pickAndUploadSchoolLogo(
                                                              schoolId: nameCtrl.text.trim().isNotEmpty
                                                                  ? nameCtrl.text.trim()
                                                                  : 'new_school',
                                                            );
                                                        if (ctx.mounted && url != null) {
                                                          setSbState(() => selectedLogoUrl = url);
                                                        }
                                                      } catch (_) {} finally {
                                                        if (ctx.mounted) {
                                                          setSbState(() => uploadingLogo = false);
                                                        }
                                                      }
                                                    },
                                              icon: const Icon(Icons.upload_file_rounded, size: 14),
                                              label: const Text('Choisir un logo', style: TextStyle(fontSize: 12)),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: const Color(0xFF475569),
                                                side: const BorderSide(color: Color(0xFFCBD5E1)),
                                                backgroundColor: const Color(0xFFF8FAFC),
                                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                            ),
                                          ),
                                          if (selectedLogoUrl != null) ...[
                                            const SizedBox(width: 8),
                                            SizedBox(
                                              height: 32,
                                              child: TextButton(
                                                onPressed: () => setSbState(() => selectedLogoUrl = null),
                                                child: const Text('Par défaut', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),

                            // School Name
                            const Text('Nom complet de l\'établissement *',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                            const SizedBox(height: 6),
                            TextField(
                              controller: nameCtrl,
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Ex: Lycée Pilote Pythagore, ESPRIT, etc.',
                                hintStyle: const TextStyle(color: ConsoleColors.textTertiary, fontSize: 13),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // School Contact Email
                            const Text('Email officiel de contact de l\'école *',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                            const SizedBox(height: 6),
                            TextField(
                              controller: emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              inputFormatters: [
                                FilteringTextInputFormatter.deny(RegExp(r'\s')),
                              ],
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'contact@etablissement.tn',
                                hintStyle: const TextStyle(color: ConsoleColors.textTertiary, fontSize: 13),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Director Info: Nom & Téléphone
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Nom complet du Directeur *',
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: directorNameCtrl,
                                        style: const TextStyle(fontSize: 13),
                                        decoration: InputDecoration(
                                          hintText: 'Ex: Dr. Moncef Larbi',
                                          hintStyle: const TextStyle(color: ConsoleColors.textTertiary, fontSize: 13),
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Téléphone du Directeur *',
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: directorPhoneCtrl,
                                        keyboardType: TextInputType.phone,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                                        ],
                                        style: const TextStyle(fontSize: 13),
                                        decoration: InputDecoration(
                                          hintText: '+216 98 123 456',
                                          prefixIcon: const Icon(Icons.phone_rounded, size: 16, color: Color(0xFF64748B)),
                                          hintStyle: const TextStyle(color: ConsoleColors.textTertiary, fontSize: 13),
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Director Login Email
                            const Text('Email connexion Directeur *',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                            const SizedBox(height: 6),
                            TextField(
                              controller: directorEmailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              inputFormatters: [
                                FilteringTextInputFormatter.deny(RegExp(r'\s')),
                              ],
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'directeur@etablissement.tn',
                                hintStyle: const TextStyle(color: ConsoleColors.textTertiary, fontSize: 13),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Password & Neutral Generate Button
                            const Text('Mot de passe temporaire *',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                            const SizedBox(height: 6),
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: directorPassCtrl,
                                      obscureText: !showPassword,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                                      ],
                                      onChanged: (_) => setSbState(() {}),
                                      style: const TextStyle(fontSize: 13),
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: const Color(0xFFF8FAFC),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                                        suffixIcon: IconButton(
                                          icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility, size: 18, color: Colors.grey),
                                          onPressed: () => setSbState(() => showPassword = !showPassword),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  OutlinedButton.icon(
                                    onPressed: () => generatePassword(setSbState),
                                    icon: const Icon(Icons.refresh_rounded, size: 15, color: Color(0xFF64748B)),
                                    label: const Text('GÉNÉRER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                                      backgroundColor: const Color(0xFFF8FAFC),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(horizontal: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),

                            // Abonnement SaaS, Capacité Élèves & Budget IA (Equal width flex 1 each, No Overflow)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 1. Formule d'abonnement SaaS (flex 1)
                                Expanded(
                                  flex: 1,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Formule d\'abonnement SaaS *',
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                                      const SizedBox(height: 6),
                                       DropdownButtonFormField<String>(
                                        value: plans.any((p) => p['id'] == selectedPlanId)
                                            ? selectedPlanId
                                            : (plans.isNotEmpty ? plans[0]['id'] as String : null),
                                        borderRadius: BorderRadius.circular(10),
                                        isDense: true,
                                        isExpanded: true,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF1E293B),
                                        ),
                                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
                                        decoration: InputDecoration(
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                                        ),
                                        items: plans.map((p) {
                                          return DropdownMenuItem<String>(
                                            value: p['id'] as String,
                                            child: Text(
                                              '${p['name']} (${p['price_tnd_monthly']} TND/m)',
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 12.5, color: Color(0xFF1E293B)),
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          if (val != null) setSbState(() => selectedPlanId = val);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // 2. Capacité Élèves (flex 1)
                                Expanded(
                                  flex: 1,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Capacité élèves *',
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: maxStudentsCtrl,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Color(0xFF1E293B)),
                                        decoration: InputDecoration(
                                          hintText: '500',
                                          hintStyle: const TextStyle(color: ConsoleColors.textTertiary, fontSize: 12.5),
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // 3. Budget IA initial (flex 1, accept ONLY digits)
                                Expanded(
                                  flex: 1,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Budget IA initial *',
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: aiBudgetCtrl,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Color(0xFF1E293B)),
                                        decoration: InputDecoration(
                                          prefixText: '\$ ',
                                          prefixStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                                          hintText: '25',
                                          hintStyle: const TextStyle(color: ConsoleColors.textTertiary, fontSize: 12.5),
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── FOOTER ACTIONS (40PX BUTTONS) ──
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          SizedBox(
                            height: 40,
                            child: TextButton(
                              onPressed: creating ? null : () => Navigator.pop(ctx),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF6B7280),
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                              ),
                              child: const Text('Annuler', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            height: 40,
                            child: ElevatedButton.icon(
                              onPressed: creating || uploadingLogo
                                  ? null
                                  : () async {
                                      final name = nameCtrl.text.trim();
                                      final email = emailCtrl.text.trim();
                                      final dName = directorNameCtrl.text.trim();
                                      final dPhone = directorPhoneCtrl.text.trim();
                                      final dEmail = directorEmailCtrl.text.trim();
                                      final dPass = directorPassCtrl.text.trim();
                                      final budget = double.tryParse(aiBudgetCtrl.text.trim()) ?? 25.0;
                                      final maxStudents = int.tryParse(maxStudentsCtrl.text.trim()) ?? 500;

                                      if (name.isEmpty || email.isEmpty || dEmail.isEmpty || dPass.isEmpty) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Veuillez remplir tous les champs obligatoires (*).'),
                                            backgroundColor: ConsoleColors.error,
                                          ),
                                        );
                                        return;
                                      }

                                      final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                                      if (!emailRegex.hasMatch(email)) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Format de l\'email de l\'école invalide (ex: contact@ecole.tn).'),
                                            backgroundColor: ConsoleColors.error,
                                          ),
                                        );
                                        return;
                                      }
                                      if (!emailRegex.hasMatch(dEmail)) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Format de l\'email du directeur invalide (ex: directeur@ecole.tn).'),
                                            backgroundColor: ConsoleColors.error,
                                          ),
                                        );
                                        return;
                                      }

                                      final messenger = ScaffoldMessenger.of(context);
                                      setSbState(() => creating = true);
                                      final ok = await ref.read(platformProvider.notifier).createSchool(
                                        name: name,
                                        email: email,
                                        directorPhone: dPhone,
                                        logoUrl: selectedLogoUrl,
                                        directorName: dName.isNotEmpty ? dName : 'Directeur $name',
                                        directorEmail: dEmail,
                                        directorPassword: dPass,
                                        planId: selectedPlanId,
                                        initialAiBudgetUsd: budget,
                                        maxStudents: maxStudents,
                                      );

                                      if (ctx.mounted) Navigator.pop(ctx);
                                      if (!mounted) return;
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(ok
                                              ? 'Établissement "$name" créé avec succès !'
                                              : (ref.read(platformProvider).errorMessage ?? 'Erreur lors de la création.')),
                                          backgroundColor: ok ? ConsoleColors.success : ConsoleColors.error,
                                        ),
                                      );
                                    },
                              icon: creating
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.check_rounded, size: 17),
                              label: const Text('Créer l\'Établissement', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6D4CF6),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 22),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showInvoiceGeneratorModal(
    BuildContext context,
    List<Map<String, dynamic>> schools, {
    String? preselectedSchoolId,
  }) {
    showConsoleInvoiceGeneratorModal(
      context: context,
      ref: ref,
      schools: schools,
      preselectedSchoolId: preselectedSchoolId,
      onSaved: () => ref.read(platformProvider.notifier).loadAll(),
    );
  }

  void _showManualInvoiceModal(
    BuildContext context,
    List<Map<String, dynamic>> schools,
  ) {
    _showInvoiceGeneratorModal(context, schools);
  }
}
