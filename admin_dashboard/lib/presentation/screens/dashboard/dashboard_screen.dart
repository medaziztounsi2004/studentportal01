import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/error_messages.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../widgets/admin_sidebar.dart';
import '../../widgets/skeleton_loader.dart';
import '../../../data/models/dashboard_models.dart';
import '../timetables/timetables_screen.dart' show selectedClassProvider, ClassInfo;

// ═══════════════════════════════════════════════════════════════════
// ░░░  MODERN MINIMALIST ADMIN DASHBOARD — GOLDEN RATIO EDITION  ░░░
// ═══════════════════════════════════════════════════════════════════

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  // Current real week days: 0: Lun .. 5: Sam
  late int _selectedDayIndex;
  int _selectedCalendarTab = 0; // 0: Séances, 1: Examens
  String _selectedInterval = 'Mensuel'; // 'Hebdomadaire', 'Mensuel', 'Annuel'
  int? _selectedChartIndex;
  int? _selectedFiliereIndex;
  int? _selectedCategoryIndex;

  @override
  void initState() {
    super.initState();
    // Default to today's day of week (1: Monday .. 6: Saturday, Sunday clamps to Saturday)
    final todayWeekday = DateTime.now().weekday; // 1 = Mon ... 7 = Sun
    _selectedDayIndex = (todayWeekday - 1).clamp(0, 5);
  }

  /// Calculates the 6 days of the current real week (Lun - Sam)
  List<Map<String, dynamic>> _getCurrentWeekDays() {
    final now = DateTime.now();
    // Find Monday of this current week (ISO 8601: 1 = Monday)
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final dayNames = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];
    return List.generate(6, (i) {
      final date = monday.add(Duration(days: i));
      return {
        'day': dayNames[i],
        'num': date.day.toString(),
        'dow': i + 1, // 1: Lun .. 6: Sam
        'date': date,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final dashboardAsync = ref.watch(dashboardProvider);
    final lastUpdated = dashboardAsync.whenOrNull(data: (s) => s.lastUpdated);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sidebar
          const AdminSidebar(currentRoute: '/dashboard'),

          // Main View Content
          Expanded(
            child: Column(
              children: [
                // ── PERSISTENT TOP HEADER (Never skeleton-loads, borderless pill) ──
                _buildTopBar(context, lastUpdated),

                // ── BODY CONTENT ──
                Expanded(
                  child: dashboardAsync.when(
                    loading: () => const DashboardSkeletonLoader(),
                    error: (e, _) => Center(
                      child: Container(
                        padding: const EdgeInsets.all(32),
                        margin: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.2)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 36),
                            const SizedBox(height: 12),
                            const Text(
                              'Une erreur est survenue lors du chargement',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              UserFriendlyError.format(
                                e,
                                fallback: 'Unable to load dashboard data right now. Please try again.',
                              ),
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () => ref.read(dashboardProvider.notifier).refresh(),
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Réessayer'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6D4CF6),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    data: (state) => _buildDashboardBody(context, authState, state),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // ░░░  PERSISTENT TOP HEADER — BORDERLESS PILL (NO SKELETON LOAD) ░░░
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildTopBar(BuildContext context, DateTime? lastUpdated) {
    final now = lastUpdated ?? DateTime.now();
    final nowFormatted = DateFormat('dd MMM yyyy, HH:mm', 'fr_FR').format(now);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE9EAF2))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                'Tableau de bord',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.4,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Vue d\'ensemble analytique et gestion en temps réel',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const Spacer(),

          // Last updated pill — BORDERLESS with subtle soft shadow
          InkWell(
            onTap: () => ref.read(dashboardProvider.notifier).refresh(),
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule_rounded, size: 14, color: Color(0xFF64748B)),
                  const SizedBox(width: 8),
                  Text(
                    'Mis à jour : $nowFormatted',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.sync_rounded, size: 14, color: Color(0xFF6D4CF6)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardBody(BuildContext context, AdminAuthState authState, DashboardState state) {
    final kpis = state.kpis;
    final currencyFormat = NumberFormat.currency(locale: 'fr_TN', symbol: 'TND ', decimalDigits: 0);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── ROW 1: 5 METRIC KPI CARDS (Golden ratio hierarchy, borderless icons) ──
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 980;

              // 1. Total Revenus (dynamic status based on actual collection health)
              final recRate = kpis.recoveryRate;
              final bool hasInvoices = kpis.totalPaymentsDue > 0;
              final bool isRecExcellent = recRate >= 75.0 && hasInvoices;
              final bool isRecModerate = recRate >= 50.0 && recRate < 75.0 && hasInvoices;
              final bool isRecPoor = recRate < 50.0 && hasInvoices;

              final revIconColor = !hasInvoices
                  ? const Color(0xFF6D4CF6)
                  : (isRecExcellent
                      ? const Color(0xFF10B981)
                      : (isRecModerate ? const Color(0xFFF59E0B) : const Color(0xFFEF4444)));
              final revIconBg = !hasInvoices
                  ? const Color(0xFFF5F3FF)
                  : (isRecExcellent
                      ? const Color(0xFFECFDF5)
                      : (isRecModerate ? const Color(0xFFFFFBEB) : const Color(0xFFFEF2F2)));
              final revTrendColor = !hasInvoices
                  ? const Color(0xFF64748B)
                  : (isRecExcellent
                      ? const Color(0xFF10B981)
                      : (isRecModerate ? const Color(0xFFF59E0B) : const Color(0xFFEF4444)));
              final bool? revTrendUp = !hasInvoices ? null : isRecExcellent;

              // 2. Revenus ce mois (dynamic arrow, green up, red down, neutral when flat/zero)
              final bool hasThisMonth = kpis.thisMonthRevenue > 0;
              final bool hasLastMonth = kpis.lastMonthRevenue > 0;
              final bool isGrowthPositive = hasThisMonth && (kpis.thisMonthRevenue >= kpis.lastMonthRevenue || !hasLastMonth);
              final bool isGrowthNegative = (hasLastMonth && kpis.thisMonthRevenue < kpis.lastMonthRevenue) || (!hasThisMonth && hasLastMonth);
              final bool isGrowthFlatZero = !hasThisMonth && !hasLastMonth;

              final mRevIcon = isGrowthFlatZero
                  ? Icons.receipt_long_outlined
                  : (isGrowthPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded);
              final mRevColor = isGrowthFlatZero
                  ? const Color(0xFF64748B)
                  : (isGrowthPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444));
              final mRevBg = isGrowthFlatZero
                  ? const Color(0xFFF1F5F9)
                  : (isGrowthPositive ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2));
              final String mRevTrend = isGrowthFlatZero
                  ? '0 TND'
                  : (hasThisMonth && !hasLastMonth
                      ? '+100%'
                      : (!hasThisMonth && hasLastMonth
                          ? '-100%'
                          : '${kpis.revenueGrowth >= 0 ? '+' : ''}${kpis.revenueGrowth.toStringAsFixed(0)}%'));
              final String mRevLabel = isGrowthFlatZero
                  ? 'aucun encaissement ce mois'
                  : (hasThisMonth && !hasLastMonth
                      ? 'premier mois d\'activité'
                      : 'vs mois dernier');
              final bool? mRevTrendUp = isGrowthFlatZero ? null : isGrowthPositive;

              // 3. Total Inscriptions (retention rate: green if >=90%, amber if 70-89%, red if <70%)
              final totalSt = kpis.totalStudents;
              final activeSt = kpis.activeStudents;
              final inactiveSt = (totalSt - activeSt).clamp(0, totalSt);
              final double activeRatio = totalSt > 0 ? (activeSt / totalSt * 100) : 0.0;
              final bool isStPerfect = totalSt > 0 && inactiveSt == 0;
              final bool isStHealthy = totalSt > 0 && activeRatio >= 90.0 && !isStPerfect;
              final bool isStWarning = totalSt > 0 && activeRatio >= 70.0 && activeRatio < 90.0;
              final bool isStCritical = totalSt > 0 && activeRatio < 70.0;

              final stColor = totalSt == 0
                  ? const Color(0xFF8B5CF6)
                  : (isStCritical
                      ? const Color(0xFFEF4444)
                      : (isStWarning ? const Color(0xFFF59E0B) : const Color(0xFF10B981)));
              final stBg = totalSt == 0
                  ? const Color(0xFFF5F3FF)
                  : (isStCritical
                      ? const Color(0xFFFEF2F2)
                      : (isStWarning ? const Color(0xFFFFFBEB) : const Color(0xFFECFDF5)));
              final bool? stTrendUp = totalSt == 0 ? null : (isStPerfect || isStHealthy);

              // 4. Enseignants & Staff (healthy staff ratio, alert if 0 teachers with enrolled students)
              final totalTeach = kpis.totalTeachers;
              final totalStaff = kpis.totalStaff;
              final bool isNoTeachers = totalSt > 0 && totalTeach == 0;
              final double ratioStudentsPerTeacher = totalTeach > 0 ? (totalSt / totalTeach) : 0.0;
              final bool isRatioHigh = totalTeach > 0 && ratioStudentsPerTeacher > 30.0;
              final teachColor = isNoTeachers
                  ? const Color(0xFFEF4444)
                  : (isRatioHigh
                      ? const Color(0xFFF59E0B)
                      : (totalTeach > 0 ? const Color(0xFF10B981) : const Color(0xFF0284C7)));
              final teachBg = isNoTeachers
                  ? const Color(0xFFFEF2F2)
                  : (isRatioHigh
                      ? const Color(0xFFFFFBEB)
                      : (totalTeach > 0 ? const Color(0xFFECFDF5) : const Color(0xFFF0F9FF)));
              final bool? teachTrendUp = (totalTeach == 0 && totalSt == 0) ? null : (!isNoTeachers && !isRatioHigh);

              // 5. Taux de Recouvrement (green if >= 80% or fully paid, amber if 50-79%, red if < 50%)
              final bool isFullyPaid = hasInvoices && kpis.unpaidAmount == 0;
              final bool isRecoveryGood = hasInvoices && recRate >= 75.0 && !isFullyPaid;
              final bool isRecoveryModerate = hasInvoices && recRate >= 50.0 && recRate < 75.0;
              final bool isRecoveryDanger = hasInvoices && recRate < 50.0;
              final recColor = !hasInvoices
                  ? const Color(0xFF64748B)
                  : (isFullyPaid || isRecoveryGood
                      ? const Color(0xFF10B981)
                      : (isRecoveryModerate ? const Color(0xFFF59E0B) : const Color(0xFFEF4444)));
              final recBg = !hasInvoices
                  ? const Color(0xFFF1F5F9)
                  : (isFullyPaid || isRecoveryGood
                      ? const Color(0xFFECFDF5)
                      : (isRecoveryModerate ? const Color(0xFFFFFBEB) : const Color(0xFFFEF2F2)));
              final bool? recTrendUp = !hasInvoices ? null : (isFullyPaid || isRecoveryGood);

              final cards = [
                _buildGoldenMetricCard(
                  icon: Icons.receipt_long_outlined,
                  iconColor: revIconColor,
                  iconBgColor: revIconBg,
                  title: 'Total Revenus',
                  value: currencyFormat.format(kpis.totalPaymentsCollected),
                  trend: hasInvoices ? '${recRate.toStringAsFixed(0)}%' : '0 TND',
                  trendLabel: hasInvoices ? 'du total facturé' : 'aucune facture émise',
                  trendColor: revTrendColor,
                  trendUp: revTrendUp,
                  showArrow: hasInvoices && !isRecModerate,
                  onTap: () => context.go('/payments'),
                ),
                _buildGoldenMetricCard(
                  icon: mRevIcon,
                  iconColor: mRevColor,
                  iconBgColor: mRevBg,
                  title: 'Revenus ce mois',
                  value: currencyFormat.format(kpis.thisMonthRevenue),
                  trend: mRevTrend,
                  trendLabel: mRevLabel,
                  trendColor: mRevColor,
                  trendUp: mRevTrendUp,
                  showArrow: !isGrowthFlatZero,
                  onTap: () => context.go('/payments'),
                ),
                _buildGoldenMetricCard(
                  icon: Icons.school_outlined,
                  iconColor: stColor,
                  iconBgColor: stBg,
                  title: 'Total Inscriptions',
                  value: NumberFormat.decimalPattern().format(totalSt),
                  trend: totalSt > 0 ? (isStPerfect ? '100% actifs' : '${activeSt} actifs') : '0 élève',
                  trendLabel: totalSt > 0
                      ? (isStPerfect
                          ? 'tous les élèves inscrits'
                          : '$inactiveSt inactif${inactiveSt > 1 ? 's' : ''}')
                      : 'aucune inscription',
                  trendColor: stColor,
                  trendUp: stTrendUp,
                  showArrow: false,
                  onTap: () => context.go('/users'),
                ),
                _buildGoldenMetricCard(
                  icon: Icons.people_outline_rounded,
                  iconColor: teachColor,
                  iconBgColor: teachBg,
                  title: 'Enseignants & Staff',
                  value: (totalTeach + totalStaff).toString(),
                  trend: isNoTeachers
                      ? '0 enseignant'
                      : (totalTeach > 0 ? '$totalTeach profs' : '0 prof'),
                  trendLabel: isNoTeachers
                      ? 'aucun prof assigné !'
                      : (totalTeach > 0
                          ? 'et $totalStaff staff (${ratioStudentsPerTeacher.toStringAsFixed(0)} él./prof)'
                          : 'et $totalStaff staff'),
                  trendColor: teachColor,
                  trendUp: teachTrendUp,
                  showArrow: isNoTeachers,
                  onTap: () => context.go('/professors'),
                ),
                _buildGoldenMetricCard(
                  icon: Icons.pie_chart_outline_rounded,
                  iconColor: recColor,
                  iconBgColor: recBg,
                  title: 'Taux de Recouvrement',
                  value: '${recRate.toStringAsFixed(0)}%',
                  trend: hasInvoices
                      ? (kpis.unpaidAmount > 0 ? currencyFormat.format(kpis.unpaidAmount) : 'Soldé')
                      : 'Soldé',
                  trendLabel: hasInvoices
                      ? (kpis.unpaidAmount > 0 ? 'reste à recouvrer' : '100% encaissé')
                      : 'aucune dette',
                  trendColor: recColor,
                  trendUp: recTrendUp,
                  showArrow: isRecoveryDanger,
                  onTap: () => context.go('/payments'),
                ),
              ];

              if (isWide) {
                return Row(
                  children: [
                    for (int i = 0; i < cards.length; i++) ...[
                      Expanded(child: cards[i]),
                      if (i < cards.length - 1) const SizedBox(width: 14),
                    ],
                  ],
                );
              } else {
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: cards.map((c) => SizedBox(width: (constraints.maxWidth - 14) / 2, child: c)).toList(),
                );
              }
            },
          ),
          const SizedBox(height: 24),

          // ── ROW 2: CASHFLOW LINE CHART & REVENUE BY CATEGORY (GOLDEN PROPORTIONS 62% : 38%) ──
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 980;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cashflow line chart (62%)
                    Expanded(
                      flex: 62,
                      child: _buildCashflowChartCard(context, state, currencyFormat),
                    ),
                    const SizedBox(width: 20),
                    // Répartition par Catégorie (38%)
                    Expanded(
                      flex: 38,
                      child: _buildCategoryBreakdownCard(context, state, currencyFormat),
                    ),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _buildCashflowChartCard(context, state, currencyFormat),
                    const SizedBox(height: 20),
                    _buildCategoryBreakdownCard(context, state, currencyFormat),
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 24),

          // ── ROW 3: THREE CARDS (Filière 30%, Calendrier & Séances 40%, Présence 30%) ──
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 1050;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Répartition par Filière (30%)
                    Expanded(
                      flex: 3,
                      child: _buildFiliereDonutCard(context, state),
                    ),
                    const SizedBox(width: 18),

                    // Calendrier & Séances / Examens (40%)
                    Expanded(
                      flex: 4,
                      child: _buildCalendarScheduleCard(context, state),
                    ),
                    const SizedBox(width: 18),

                    // Taux de Présence par Niveau (30%)
                    Expanded(
                      flex: 3,
                      child: _buildAttendanceByLevelCard(context, state),
                    ),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _buildFiliereDonutCard(context, state),
                    const SizedBox(height: 20),
                    _buildCalendarScheduleCard(context, state),
                    const SizedBox(height: 20),
                    _buildAttendanceByLevelCard(context, state),
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // ░░░  GOLDEN METRIC CARD (BORDERLESS ICON, 1.618 SPACING)  ░░░
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildGoldenMetricCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String title,
    required String value,
    required String trend,
    required String trendLabel,
    bool? trendUp,
    Color? trendColor,
    bool showArrow = true,
    required VoidCallback onTap,
  }) {
    final effectiveTrendColor = trendColor ??
        (trendUp == null
            ? const Color(0xFF64748B)
            : (trendUp ? const Color(0xFF10B981) : const Color(0xFFEF4444)));

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
                // Borderless soft icon container
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: iconColor),
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

            // Trend Indicator
            Row(
              children: [
                if (showArrow && trendUp != null) ...[
                  Icon(
                    trendUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    size: 12,
                    color: effectiveTrendColor,
                  ),
                  const SizedBox(width: 3),
                ],
                Text(
                  trend,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: effectiveTrendColor,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    trendLabel,
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

  // ═══════════════════════════════════════════════════════════════════
  // ░░░  CASHFLOW LINE CHART CARD (PILL INTERVAL, ANY-PIXEL CLICK) ░░░
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildCashflowChartCard(
    BuildContext context,
    DashboardState state,
    NumberFormat currencyFormat,
  ) {
    final CashflowIntervalData activeData;
    switch (_selectedInterval) {
      case 'Hebdomadaire':
        activeData = state.weeklyCashflow;
        break;
      case 'Annuel':
        activeData = state.annualCashflow;
        break;
      case 'Mensuel':
      default:
        activeData = state.monthlyCashflow;
        break;
    }

    final points = activeData.points;
    final spots = points.map((p) => FlSpot(p.x, p.y)).toList();
    final activeSpotIndex = _selectedChartIndex != null && _selectedChartIndex! < points.length
        ? _selectedChartIndex!
        : activeData.peakX.toInt().clamp(0, points.isEmpty ? 0 : points.length - 1);

    final lineBarData = LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.35,
      preventCurveOverShooting: true,
      color: const Color(0xFF6D4CF6),
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        checkToShowDot: (spot, barData) => spot.x == activeSpotIndex.toDouble(),
        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
          radius: 5,
          color: const Color(0xFF6D4CF6),
          strokeWidth: 2.5,
          strokeColor: Colors.white,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF6D4CF6).withValues(alpha: 0.16),
            const Color(0xFF6D4CF6).withValues(alpha: 0.0),
          ],
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with Pill Interval Selector and Styled 3-dots
          Row(
            children: [
              InkWell(
                onTap: () => context.go('/payments'),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'Flux de trésorerie',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF94A3B8)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Legend
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFF6D4CF6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Collecté ${currencyFormat.format(activeData.totalCollected)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              if (activeData.reimbursedAmount > 0) ...[
                const SizedBox(width: 12),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Remboursé ${currencyFormat.format(activeData.reimbursedAmount)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
              const Spacer(),

              // Interval Selector: BORDERLESS MODERN PILL DESIGN
              PopupMenuButton<String>(
                onSelected: (val) {
                  setState(() {
                    _selectedInterval = val;
                    _selectedChartIndex = null;
                  });
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 8,
                shadowColor: Colors.black.withValues(alpha: 0.08),
                color: Colors.white,
                surfaceTintColor: Colors.transparent,
                offset: const Offset(0, 36),
                itemBuilder: (context) => [
                  _buildPopupItem('Hebdomadaire', Icons.calendar_view_week_rounded, 'Hebdomadaire', const Color(0xFF6D4CF6)),
                  _buildPopupItem('Mensuel', Icons.calendar_view_month_rounded, 'Mensuel', const Color(0xFF6D4CF6)),
                  _buildPopupItem('Annuel', Icons.calendar_today_rounded, 'Annuel', const Color(0xFF6D4CF6)),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(20), // Borderless Pill!
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Intervalle : ',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                      Text(
                        _selectedInterval,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFF64748B)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // 3 Dots popup menu: Styled exactly like Users page
              _buildDashboardThreeDots(
                items: [
                  _buildPopupItem('view', Icons.visibility_outlined, 'Voir les paiements', const Color(0xFF6D4CF6)),
                  _buildPopupItem('refresh', Icons.sync_rounded, 'Actualiser les données', const Color(0xFF10B981)),
                ],
                onSelected: (val) {
                  if (val == 'view') context.go('/payments');
                  if (val == 'refresh') ref.read(dashboardProvider.notifier).refresh();
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Live Line Chart Area — CLICK ANY PIXEL TO SHOW DETAILS (EXACT PIXEL CALCULATED)
          SizedBox(
            height: 230,
            child: spots.isEmpty
                ? const Center(
                    child: Text(
                      'Aucune donnée pour cette période',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, chartConstraints) {
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) {
                          // Clicking ANYWHERE on the chart computes the exact closest point
                          const reservedLeft = 46.0;
                          final plotW = chartConstraints.maxWidth - reservedLeft;
                          if (plotW <= 0 || points.length <= 1) return;
                          final localX = (details.localPosition.dx - reservedLeft).clamp(0.0, plotW);
                          final fraction = (localX / plotW).clamp(0.0, 1.0);
                          final idx = (fraction * (points.length - 1)).round();
                          setState(() {
                            _selectedChartIndex = idx;
                          });
                        },
                        child: LineChart(
                          LineChartData(
                            showingTooltipIndicators: [
                              ShowingTooltipIndicators([
                                LineBarSpot(
                                  lineBarData,
                                  0,
                                  spots[activeSpotIndex],
                                ),
                              ]),
                            ],
                            lineTouchData: LineTouchData(
                              enabled: true,
                              handleBuiltInTouches: true,
                              touchSpotThreshold: 60,
                              touchCallback: (event, touchResponse) {
                                if (touchResponse?.lineBarSpots != null &&
                                    touchResponse!.lineBarSpots!.isNotEmpty) {
                                  final spot = touchResponse.lineBarSpots!.first;
                                  if (_selectedChartIndex != spot.spotIndex) {
                                    setState(() {
                                      _selectedChartIndex = spot.spotIndex;
                                    });
                                  }
                                }
                              },
                              touchTooltipData: LineTouchTooltipData(
                                getTooltipColor: (_) => const Color(0xFF0F172A),
                                fitInsideHorizontally: true,
                                fitInsideVertically: true,
                                getTooltipItems: (touchedSpots) {
                                  return touchedSpots.map((spot) {
                                    final idx = spot.spotIndex;
                                    final point = (idx >= 0 && idx < points.length) ? points[idx] : null;
                                    final amt = point?.amount ?? spot.y;
                                    return LineTooltipItem(
                                      '${currencyFormat.format(amt)}\n',
                                      const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                      children: [
                                        TextSpan(
                                          text: point?.fullDate ?? '',
                                          style: const TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList();
                                },
                              ),
                            ),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: (activeData.maxY / 4).clamp(1.0, double.infinity),
                              getDrawingHorizontalLine: (value) => const FlLine(
                                color: Color(0xFFF1F5F9),
                                strokeWidth: 1,
                                dashArray: [5, 4],
                              ),
                            ),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 46,
                                  interval: (activeData.maxY / 4).clamp(1.0, double.infinity),
                                  getTitlesWidget: (value, meta) {
                                    if (value == 0) {
                                      return const Text(
                                        '0',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF94A3B8),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      );
                                    }
                                    final String formatted;
                                    if (value >= 1000000) {
                                      final v = value / 1000000;
                                      formatted = '${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1)}M';
                                    } else if (value >= 1000) {
                                      final v = value / 1000;
                                      formatted = '${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1)}k';
                                    } else {
                                      formatted = value.toStringAsFixed(0);
                                    }
                                    return Text(
                                      formatted,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF94A3B8),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  interval: 1,
                                  getTitlesWidget: (value, meta) {
                                    final index = value.toInt();
                                    if (index >= 0 && index < points.length) {
                                      final isSelected = index == activeSpotIndex;
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          points[index].label,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isSelected ? const Color(0xFF6D4CF6) : const Color(0xFF64748B),
                                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                          ),
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            borderData: FlBorderData(show: false),
                            minX: 0,
                            maxX: (points.length - 1).toDouble(),
                            minY: activeData.minY,
                            maxY: activeData.maxY,
                            lineBarsData: [lineBarData],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // ░░░  CATEGORY BREAKDOWN CARD (STYLED THREE DOTS, NAVIGATION)   ░░░
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildCategoryBreakdownCard(
    BuildContext context,
    DashboardState state,
    NumberFormat currencyFormat,
  ) {
    final categories = state.categories;
    final totalDue = state.kpis.totalPaymentsDue;

    final selectedCategory = (_selectedCategoryIndex != null &&
            _selectedCategoryIndex! < categories.length)
        ? categories[_selectedCategoryIndex!]
        : null;

    final displayAmount = selectedCategory != null ? selectedCategory.amount : totalDue;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Header Row with styled 3-dots
          Row(
            children: [
              InkWell(
                onTap: () => context.go('/payments'),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'Répartition par Catégorie',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF94A3B8)),
                  ],
                ),
              ),
              const Spacer(),
              _buildDashboardThreeDots(
                items: [
                  _buildPopupItem('view', Icons.visibility_outlined, 'Voir tous les paiements', const Color(0xFF6D4CF6)),
                  _buildPopupItem('refresh', Icons.sync_rounded, 'Actualiser', const Color(0xFF10B981)),
                ],
                onSelected: (val) {
                  if (val == 'view') context.go('/payments');
                  if (val == 'refresh') ref.read(dashboardProvider.notifier).refresh();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Total Due & Trend / Selected Category Info
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    currencyFormat.format(displayAmount),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: selectedCategory != null
                          ? Color(selectedCategory.colorValue)
                          : const Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (selectedCategory != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Color(selectedCategory.colorValue).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${selectedCategory.percentage.toInt()}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(selectedCategory.colorValue),
                        ),
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _selectedCategoryIndex = null;
                        });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.close_rounded, size: 14, color: Color(0xFF94A3B8)),
                            SizedBox(width: 2),
                            Text(
                              'Réinitialiser',
                              style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (selectedCategory != null) ...[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: Color(selectedCategory.colorValue),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      selectedCategory.label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(selectedCategory.colorValue),
                      ),
                    ),
                    const Text(
                      ' • Catégorie sélectionnée',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ] else ...[
                    Icon(
                      state.kpis.recoveryRate >= 50 ? Icons.arrow_upward_rounded : Icons.trending_flat_rounded,
                      size: 13,
                      color: state.kpis.recoveryRate >= 50 ? const Color(0xFF10B981) : const Color(0xFF6D4CF6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${state.kpis.recoveryRate.toStringAsFixed(0)}% recouvré sur le total prévu',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: state.kpis.recoveryRate >= 50 ? const Color(0xFF10B981) : const Color(0xFF6D4CF6),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Segmented Progress Bar (Interactive with Zoom-In on Click)
          SizedBox(
            height: 26,
            child: Row(
              children: categories.isEmpty
                  ? [
                      Expanded(
                        child: Container(
                          height: 14,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ]
                  : categories.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final cat = entry.value;
                      final isSelected = _selectedCategoryIndex == idx;
                      final hasSelection = _selectedCategoryIndex != null;

                      return Expanded(
                        flex: (cat.percentage.toInt()).clamp(5, 100),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _selectedCategoryIndex = (_selectedCategoryIndex == idx) ? null : idx;
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            height: isSelected ? 24 : 14, // Zooms in when clicked!
                            margin: EdgeInsets.symmetric(horizontal: isSelected ? 2 : 1.5),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Color(cat.colorValue)
                                  : (hasSelection
                                      ? Color(cat.colorValue).withValues(alpha: 0.35)
                                      : Color(cat.colorValue)),
                              borderRadius: BorderRadius.circular(6),
                              border: isSelected
                                  ? Border.all(color: Colors.white, width: 2)
                                  : null,
                              boxShadow: null,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
            ),
          ),
          const SizedBox(height: 20),

          // Category Item Rows (Clickable with selection feedback)
          if (categories.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'Aucune catégorie de paiement enregistrée',
                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
              ),
            )
          else
            Column(
              children: categories.asMap().entries.map((entry) {
                final idx = entry.key;
                final cat = entry.value;
                final isSelected = _selectedCategoryIndex == idx;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedCategoryIndex = (_selectedCategoryIndex == idx) ? null : idx;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Color(cat.colorValue).withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: null,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Color(cat.colorValue),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              cat.label,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF475569),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${currencyFormat.format(cat.amount)} (${cat.percentage.toInt()}%)',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                              color: isSelected ? Color(cat.colorValue) : const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // ░░░  FILIÈRE DONUT CARD (NO GREY PILLS, STYLED THREE DOTS)    ░░░
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildFiliereDonutCard(BuildContext context, DashboardState state) {
    final filieres = state.filieres;
    final totalStudents = state.kpis.totalStudents;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with styled 3-dots
          Row(
            children: [
              InkWell(
                onTap: () => context.go('/grade-levels'),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'Répartition par Filière',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF94A3B8)),
                  ],
                ),
              ),
              const Spacer(),
              _buildDashboardThreeDots(
                items: [
                  _buildPopupItem('view', Icons.visibility_outlined, 'Voir les niveaux', const Color(0xFF6D4CF6)),
                  _buildPopupItem('refresh', Icons.sync_rounded, 'Actualiser', const Color(0xFF10B981)),
                ],
                onSelected: (val) {
                  if (val == 'view') context.go('/grade-levels');
                  if (val == 'refresh') ref.read(dashboardProvider.notifier).refresh();
                },
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Donut Chart
          SizedBox(
            height: 155,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    pieTouchData: PieTouchData(
                      mouseCursorResolver: (event, response) =>
                          response?.touchedSection != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
                      touchCallback: (FlTouchEvent event, pieTouchResponse) {
                          if (!event.isInterestedForInteractions ||
                              pieTouchResponse == null ||
                              pieTouchResponse.touchedSection == null) {
                            return;
                          }
                          if (event is FlTapUpEvent) {
                            final idx = pieTouchResponse.touchedSection!.touchedSectionIndex;
                            if (idx >= 0 && idx < filieres.length) {
                              setState(() {
                                _selectedFiliereIndex = (_selectedFiliereIndex == idx) ? null : idx;
                              });
                            }
                          }
                        },
                      ),
                      sectionsSpace: 3,
                      centerSpaceRadius: 46,
                      startDegreeOffset: -90,
                      sections: filieres.isEmpty
                          ? [
                              PieChartSectionData(
                                value: 100,
                                color: const Color(0xFFF1F5F9),
                                radius: 16,
                                showTitle: false,
                              )
                            ]
                          : filieres.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final f = entry.value;
                              final isSelected = _selectedFiliereIndex == idx;
                              final hasSelection = _selectedFiliereIndex != null;

                              return PieChartSectionData(
                                value: f.percentage > 0 ? f.percentage : 1,
                                color: isSelected
                                    ? Color(f.colorValue)
                                    : (hasSelection
                                        ? Color(f.colorValue).withValues(alpha: 0.35)
                                        : Color(f.colorValue)),
                                radius: isSelected ? 22 : 16, // Zooms in when clicked!
                                borderSide: isSelected
                                    ? const BorderSide(color: Colors.white, width: 2.5)
                                    : BorderSide.none,
                                showTitle: false,
                              );
                            }).toList(),
                    ),
                  ),

                // Center Text (Shows selected partition value & info on click)
                SizedBox(
                  width: 76,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_selectedFiliereIndex != null &&
                          _selectedFiliereIndex! < filieres.length) ...[
                        Text(
                          '${filieres[_selectedFiliereIndex!].count}',
                          style: TextStyle(
                            fontSize: 18,
                            height: 1.0,
                            fontWeight: FontWeight.w800,
                            color: Color(filieres[_selectedFiliereIndex!].colorValue),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${filieres[_selectedFiliereIndex!].percentage.toInt()}%',
                          style: const TextStyle(
                            fontSize: 10,
                            height: 1.0,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Text(
                            filieres[_selectedFiliereIndex!].label,
                            style: const TextStyle(
                              fontSize: 9,
                              height: 1.05,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ] else ...[
                        Text(
                          filieres.isNotEmpty
                              ? '${filieres.fold<int>(0, (sum, f) => sum + f.count)}'
                              : '$totalStudents',
                          style: const TextStyle(
                            fontSize: 18,
                            height: 1.0,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Élèves',
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.0,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Responsive List with clean items
          if (filieres.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Aucune classe ou filière configurée',
                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
              ),
            )
          else
            Column(
              children: [
                for (int i = 0; i < filieres.length; i += 2) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _buildCleanFiliereItem(
                          filieres[i],
                          isSelected: _selectedFiliereIndex == i,
                          onTap: () {
                            setState(() {
                              _selectedFiliereIndex =
                                  (_selectedFiliereIndex == i) ? null : i;
                            });
                          },
                        ),
                      ),
                      if (i + 1 < filieres.length) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildCleanFiliereItem(
                            filieres[i + 1],
                            isSelected: _selectedFiliereIndex == (i + 1),
                            onTap: () {
                              setState(() {
                                _selectedFiliereIndex =
                                    (_selectedFiliereIndex == (i + 1)) ? null : (i + 1);
                              });
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (i + 2 < filieres.length) const SizedBox(height: 4),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCleanFiliereItem(
    FiliereDistributionItem item, {
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? Color(item.colorValue).withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Color(item.colorValue),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 11.5,
                  color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF475569),
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${item.percentage.toInt()}%',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                color: isSelected ? Color(item.colorValue) : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // ░░░  CALENDAR & SÉANCES / EXAMENS (REAL CURRENT WEEK, PILL DAYS, PILL SALLE, BORDERLESS RECTANGLES) ░░░
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildCalendarScheduleCard(BuildContext context, DashboardState state) {
    // Current real week days
    final days = _getCurrentWeekDays();
    final currentDow = days[_selectedDayIndex.clamp(0, days.length - 1)]['dow'] as int;
    final isExamTab = _selectedCalendarTab == 1;

    // Filter events for selected day & selected tab (séances vs examens)
    final filteredEvents = state.events.where((e) {
      final matchesDay = e.dayOfWeek == currentDow;
      final matchesType = isExamTab ? e.isExam : !e.isExam;
      return matchesDay && matchesType;
    }).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with styled 3-dots
          Row(
            children: [
              InkWell(
                onTap: () => context.go('/timetables'),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'Calendrier & Séances',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF94A3B8)),
                  ],
                ),
              ),
              const Spacer(),
              _buildDashboardThreeDots(
                items: [
                  _buildPopupItem('view', Icons.visibility_outlined, 'Voir tout l\'emploi du temps', const Color(0xFF6D4CF6)),
                  _buildPopupItem('refresh', Icons.sync_rounded, 'Actualiser', const Color(0xFF10B981)),
                ],
                onSelected: (val) {
                  if (val == 'view') context.go('/timetables');
                  if (val == 'refresh') ref.read(dashboardProvider.notifier).refresh();
                },
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Day Carousel Selector — CURRENT REAL WEEK, PILL SHAPE & BORDERLESS
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9), // Borderless soft pill container
              borderRadius: BorderRadius.circular(30), // Pill!
            ),
            child: Row(
              children: [
                for (int i = 0; i < days.length; i++) ...[
                  Expanded(
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedDayIndex = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: _selectedDayIndex == i ? const Color(0xFF6D4CF6) : Colors.transparent,
                            borderRadius: BorderRadius.circular(24), // Pill inside!
                          ),
                          child: Center(
                            child: Text(
                              '${days[i]['day']} ${days[i]['num']}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: _selectedDayIndex == i ? FontWeight.w700 : FontWeight.w500,
                                color: _selectedDayIndex == i ? Colors.white : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (i < days.length - 1) const SizedBox(width: 2),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Tabs: Séances (Science Icon, NO TRUCK/CAR) vs Examens
          Row(
            children: [
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedCalendarTab = 0),
                    child: Container(
                      padding: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _selectedCalendarTab == 0 ? const Color(0xFF6D4CF6) : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.science_outlined, // Science icon
                            size: 15,
                            color: _selectedCalendarTab == 0 ? const Color(0xFF6D4CF6) : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Séances',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _selectedCalendarTab == 0 ? const Color(0xFF6D4CF6) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedCalendarTab = 1),
                    child: Container(
                      padding: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _selectedCalendarTab == 1 ? const Color(0xFF6D4CF6) : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.assignment_outlined,
                            size: 15,
                            color: _selectedCalendarTab == 1 ? const Color(0xFF6D4CF6) : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Examens',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _selectedCalendarTab == 1 ? const Color(0xFF6D4CF6) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Event List
          if (filteredEvents.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  isExamTab ? 'Aucun examen prévu ce jour-là' : 'Aucune séance prévue ce jour-là',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
              ),
            )
          else
            Column(
              children: filteredEvents.take(2).map((evt) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildEventCard(evt),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  /// Event Card: BORDERLESS RECTANGLE, PILL ROOM BADGE
  Widget _buildEventCard(DashboardCalendarEvent event) {
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: () {
        // Direct navigation to that class's timetable
        if (event.classId.isNotEmpty) {
          ref.read(selectedClassProvider.notifier).state = ClassInfo(
            id: event.classId,
            name: event.className,
          );
        }
        context.go('/timetables');
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC), // BORDERLESS soft surface
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  event.time,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // Teacher Initials Avatar
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: Color(0xFF6D4CF6),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      event.teacherInitials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${event.teacherName} • ${event.className}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                // Room Badge: PILL SHAPED
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20), // Pill!
                    border: Border.all(color: const Color(0xFF6D4CF6).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        event.room,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6D4CF6),
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Icon(Icons.chevron_right_rounded, size: 12, color: Color(0xFF6D4CF6)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // ░░░  ATTENDANCE BY LEVEL (SLIM BARS, STYLED THREE DOTS)       ░░░
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildAttendanceByLevelCard(BuildContext context, DashboardState state) {
    final levels = state.attendanceLevels;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with styled 3-dots
          Row(
            children: [
              InkWell(
                onTap: () => context.go('/absences'),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'Taux de Présence par Niveau',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF94A3B8)),
                  ],
                ),
              ),
              const Spacer(),
              _buildDashboardThreeDots(
                items: [
                  _buildPopupItem('view', Icons.visibility_outlined, 'Voir toutes les absences', const Color(0xFF6D4CF6)),
                  _buildPopupItem('refresh', Icons.sync_rounded, 'Actualiser', const Color(0xFF10B981)),
                ],
                onSelected: (val) {
                  if (val == 'view') context.go('/absences');
                  if (val == 'refresh') ref.read(dashboardProvider.notifier).refresh();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Slim Horizontal Progress Bars List
          if (levels.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Aucune donnée d\'absence enregistrée',
                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
              ),
            )
          else
            for (int i = 0; i < levels.length; i++) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          levels[i].levelName,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        levels[i].label,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6D4CF6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: levels[i].rate,
                      backgroundColor: const Color(0xFFF1F5F9),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6D4CF6)),
                      minHeight: 6, // Slim elegant height
                    ),
                  ),
                ],
              ),
              if (i < levels.length - 1) const SizedBox(height: 11),
            ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // ░░░  SHARED POPUP MENU & 3-DOTS BUTTON (STYLED LIKE USERS PAGE)░░░
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildDashboardThreeDots({
    required List<PopupMenuEntry<String>> items,
    required ValueChanged<String> onSelected,
  }) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz_rounded, size: 18, color: Color(0xFF94A3B8)),
      tooltip: 'Actions',
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10), // Same border radius as Users page!
        side: const BorderSide(color: Color(0xFFF1F5F9)),
      ),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      offset: const Offset(-140, 36),
      onSelected: onSelected,
      itemBuilder: (context) => items,
    );
  }

  PopupMenuItem<String> _buildPopupItem(String value, IconData icon, String label, Color color) {
    return PopupMenuItem<String>(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}