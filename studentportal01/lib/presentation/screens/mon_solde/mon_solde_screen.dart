import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/arabic_typography.dart';
import '../../../core/theme/responsive.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../data/services/core_data_service.dart';
import '../../../data/services/offline_cache_service.dart';
import '../../providers/student_context_provider.dart';
import '../../widgets/mon_solde_skeleton.dart';
import '../../widgets/bouncing_wrapper.dart';
import '../../widgets/ios_bounce_zoom_transition.dart';
import '../../widgets/empty_state_glass_card.dart';

// Semester state provider for this screen
final soldeSemesterProvider = StateProvider<int>((ref) => 1);

// Loading state for mon solde refresh
final soldeRefreshingProvider = StateProvider<bool>((ref) => false);

// Payment categories for Tunisia
enum PaymentCategory {
  scolarite('Scolarité', Icons.school_rounded, Color(0xFF8B5CF6)),
  transport('Transport/Bus', Icons.directions_bus_rounded, Color(0xFF8B5CF6)),
  inscription('Inscription', Icons.app_registration_rounded, Color(0xFF6366F1)),
  uniforme('Uniforme', Icons.checkroom_rounded, Color(0xFF3B82F6)),
  cantine('Cantine', Icons.restaurant_rounded, Color(0xFF06B6D4)),
  activites('Activités', Icons.sports_soccer_rounded, Color(0xFF10B981)),
  autres('Autres', Icons.more_horiz_rounded, Color(0xFFF59E0B));

  final String label;
  final IconData icon;
  final Color color;
  const PaymentCategory(this.label, this.icon, this.color);

  String getLocalizedLabel(AppLocalizations l10n) {
    switch (this) {
      case PaymentCategory.scolarite:
        return l10n.translate('cat_scolarite');
      case PaymentCategory.transport:
        return l10n.translate('cat_transport');
      case PaymentCategory.inscription:
        return l10n.translate('cat_inscription');
      case PaymentCategory.uniforme:
        return l10n.translate('cat_uniforme');
      case PaymentCategory.cantine:
        return l10n.translate('cat_cantine');
      case PaymentCategory.activites:
        return l10n.translate('cat_activites');
      case PaymentCategory.autres:
        return l10n.translate('cat_autres');
    }
  }
}

// Payment breakdown by category
class PaymentCategoryData {
  final PaymentCategory category;
  final double amount;
  final double paid;

  PaymentCategoryData({
    required this.category,
    required this.amount,
    required this.paid,
  });

  double get remaining => amount - paid;
  double get progressPercent => amount > 0 ? (paid / amount) * 100 : 0;
}

// Payment categories breakdown provider - returns all categories with active plans or pricing
final paymentCategoriesProvider = Provider<List<PaymentCategoryData>>((ref) {
  final plansAsync = ref.watch(paymentsDataProvider);
  final plans = plansAsync.asData?.value ?? [];
  final pricingAsync = ref.watch(pricingFallbackProvider);
  final pricing = pricingAsync.asData?.value ?? {};

  final Map<PaymentCategory, double> amounts = {};
  final Map<PaymentCategory, double> paid = {};

  for (final plan in plans) {
    final planCat = _mapCategory(
      plan.category,
      plan.description ?? plan.planType,
    );

    // If individual payments have their own specific categories
    final paymentsWithCat = plan.payments.where((p) =>
        (p.category != null && p.category!.isNotEmpty) ||
        (p.description != null && p.description!.isNotEmpty)).toList();

    if (paymentsWithCat.isNotEmpty) {
      for (final payment in plan.payments) {
        final pCat = _mapCategory(
          payment.category ?? plan.category,
          payment.description ?? payment.notes ?? plan.description,
        );
        amounts[pCat] = (amounts[pCat] ?? 0) + payment.amount;
        if (payment.isPaid || payment.status.toLowerCase() == 'paid' || payment.paidAt != null) {
          paid[pCat] = (paid[pCat] ?? 0) + payment.amount;
        }
      }
    } else {
      amounts[planCat] = (amounts[planCat] ?? 0) + plan.amountTotal;
      paid[planCat] = (paid[planCat] ?? 0) + plan.totalPaid;
    }
  }

  // Fill in pricing fallback for categories with 0 configured amount
  for (final entry in pricing.entries) {
    final cat = _mapCategory(entry.key);
    if ((amounts[cat] ?? 0) == 0 && entry.value > 0) {
      amounts[cat] = entry.value;
    }
  }

  // Only return categories that have an active plan or a configured price (> 0)
  return PaymentCategory.values
      .where((cat) => (amounts[cat] ?? 0) > 0 || (paid[cat] ?? 0) > 0)
      .map((cat) {
    final configuredAmount = amounts[cat] ?? 0;
    final totalPaid = paid[cat] ?? 0;
    return PaymentCategoryData(
      category: cat,
      amount: configuredAmount > totalPaid ? configuredAmount : totalPaid,
      paid: totalPaid,
    );
  }).toList();
});

// Semesters provider for Mon Solde - delegates to canonical dynamic semestersProvider
final monSoldeSemestersProvider = FutureProvider<List<SemesterInfo>>((ref) async {
  try {
    final list = await ref.watch(semestersProvider.future);
    if (list.isNotEmpty) return list;
  } catch (_) {}

  return [
    SemesterInfo(id: '1', name: 'Semestre 1', number: 1, isCurrent: true),
    SemesterInfo(id: '2', name: 'Semestre 2', number: 2, isCurrent: false),
    SemesterInfo(id: '3', name: 'Semestre 3', number: 3, isCurrent: false),
  ];
});

// Academic year date range provider
final academicYearDatesProvider =
    FutureProvider<({DateTime? start, DateTime? end})>((ref) async {
      try {
        final context = await ref.watch(studentContextProvider.future);
        final supabase = Supabase.instance.client;

        // Get academic year ID - try context first, then fallback
        String? academicYearId = context?.academicYearId;
        if (academicYearId == null || academicYearId.isEmpty) {
          try {
            final yearResp = await supabase
                .from('academic_years')
                .select('id, start_date, end_date')
                .eq('is_current', true)
                .order('start_date', ascending: false)
                .maybeSingle();
            if (yearResp != null) {
              return (
                start: DateTime.tryParse(yearResp['start_date']?.toString() ?? ''),
                end: DateTime.tryParse(yearResp['end_date']?.toString() ?? ''),
              );
            }
          } catch (_) {}
          return (start: null, end: null);
        }

        final resp = await supabase
            .from('academic_years')
            .select('start_date, end_date')
            .eq('id', academicYearId)
            .maybeSingle();
        if (resp == null) return (start: null, end: null);
        return (
          start: DateTime.tryParse(resp['start_date']?.toString() ?? ''),
          end: DateTime.tryParse(resp['end_date']?.toString() ?? ''),
        );
      } catch (e) {
        return (start: null, end: null);
      }
    });

// Pricing fallback provider - fetches pricing from payment_pricing for all categories
final pricingFallbackProvider = FutureProvider<Map<String, double>>((
  ref,
) async {
  const cacheKey = 'cached_payment_pricing';
  final cached = OfflineCacheService.instance.getMap(cacheKey);
  final cachedPricing = cached != null
      ? cached.map((k, v) => MapEntry(k, (v as num).toDouble()))
      : <String, double>{};

  if (ConnectivityService.instance.isOffline) {
    return cachedPricing;
  }
  try {
    final context = await ref.watch(studentContextProvider.future);
    if (context == null) {
      return cachedPricing;
    }
    final supabase = Supabase.instance.client;
    final Map<String, double> pricing = Map.from(cachedPricing);

    // Fast direct query on payment_pricing table (single query for all categories)
    try {
      var query = supabase.from('payment_pricing').select('category, amount, section_id, niveau_id');
      if (context.schoolId.isNotEmpty) {
        query = query.eq('school_id', context.schoolId);
      }
      if (context.niveauId != null && context.niveauId!.isNotEmpty) {
        query = query.eq('niveau_id', context.niveauId!);
      }
      final pricingResp = await query.timeout(const Duration(seconds: 4));
      for (final row in (pricingResp as List)) {
        final cat = row['category']?.toString();
        final amount = (row['amount'] as num?)?.toDouble();
        final secId = row['section_id']?.toString();
        if (cat != null && amount != null && amount > 0) {
          if (context.sectionId != null && secId == context.sectionId) {
            pricing[cat] = amount;
          } else if (secId == null && !pricing.containsKey(cat)) {
            pricing[cat] = amount;
          }
        }
      }
    } catch (_) {}

    // Fallback: school-wide pricing if no niveau-specific pricing found
    if (pricing.isEmpty && context.schoolId.isNotEmpty) {
      try {
        final fallbackResp = await supabase
            .from('payment_pricing')
            .select('category, amount')
            .eq('school_id', context.schoolId)
            .timeout(const Duration(seconds: 4));
        for (final row in (fallbackResp as List)) {
          final cat = row['category']?.toString();
          final amount = (row['amount'] as num?)?.toDouble();
          if (cat != null && amount != null && amount > 0 && !pricing.containsKey(cat)) {
            pricing[cat] = amount;
          }
        }
      } catch (_) {}
    }

    if (pricing.isNotEmpty) {
      OfflineCacheService.instance.setJson(cacheKey, pricing);
    }
    return pricing;
  } catch (e) {
    return cachedPricing;
  }
});

PaymentCategory _mapCategory(String? category, [String? description]) {
  final cat = (category ?? '').trim().toLowerCase();

  // 1. Direct match on canonical category name
  if (cat == 'inscription' || cat == 'inscript' || cat == 'registration') {
    return PaymentCategory.inscription;
  }
  if (cat == 'autres' || cat == 'autre' || cat == 'other' || cat == 'others') {
    return PaymentCategory.autres;
  }
  if (cat == 'uniforme' || cat == 'uniform' || cat == 'tenue') {
    return PaymentCategory.uniforme;
  }
  if (cat == 'cantine' || cat == 'canteen' || cat == 'repas') {
    return PaymentCategory.cantine;
  }
  if (cat == 'transport' || cat == 'bus') {
    return PaymentCategory.transport;
  }
  if (cat == 'activites' || cat == 'activite' || cat == 'activities' || cat == 'activity' || cat == 'sport') {
    return PaymentCategory.activites;
  }
  if (cat == 'scolarite' || cat == 'tuition') {
    return PaymentCategory.scolarite;
  }

  // 2. Keyword matching on description or combined text (specific non-tuition categories first)
  final desc = (description ?? '').trim().toLowerCase();
  final combined = '$cat $desc';

  if (combined.contains('inscript') || combined.contains('regist')) {
    return PaymentCategory.inscription;
  }
  if (combined.contains('unif') || combined.contains('tenue') || combined.contains('cloth')) {
    return PaymentCategory.uniforme;
  }
  if (combined.contains('cantin') || combined.contains('repas') || combined.contains('food') || combined.contains('restau')) {
    return PaymentCategory.cantine;
  }
  if (combined.contains('transp') || combined.contains('bus')) {
    return PaymentCategory.transport;
  }
  if (combined.contains('activ') || combined.contains('sport') || combined.contains('club')) {
    return PaymentCategory.activites;
  }
  if (combined.contains('autre') || combined.contains('other')) {
    return PaymentCategory.autres;
  }
  if (combined.contains('scolar') ||
      combined.contains('tuition') ||
      combined.contains('annual') ||
      combined.contains('mensuel') ||
      combined.contains('semestr') ||
      combined.contains('trimestr')) {
    return PaymentCategory.scolarite;
  }

  return PaymentCategory.autres;
}

class MonSoldeScreen extends ConsumerStatefulWidget {
  const MonSoldeScreen({super.key});

  @override
  ConsumerState<MonSoldeScreen> createState() => _MonSoldeScreenState();
}

class _MonSoldeScreenState extends ConsumerState<MonSoldeScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final paymentDataAsync = ref.watch(paymentsDataProvider);
    final categories = ref.watch(paymentCategoriesProvider);
    final semestersAsync = ref.watch(monSoldeSemestersProvider);
    final yearDates = ref.watch(academicYearDatesProvider);
    final pricingAsync = ref.watch(pricingFallbackProvider);
    final isRefreshing = ref.watch(soldeRefreshingProvider);

    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF8F0FC),
              Color(0xFFF0E6F8),
              Color(0xFFEAF0FA),
              Color(0xFFF4F8FC),
              Color(0xFFFAFCFD),
            ],
            stops: [0.0, 0.25, 0.5, 0.75, 1.0],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: const Color(0xFF8B5CF6),
            backgroundColor: Colors.white,
            onRefresh: () async {
              ref.read(soldeRefreshingProvider.notifier).state = true;
              try {
                ref.invalidate(studentContextProvider);
                ref.invalidate(semestersProvider);
                ref.invalidate(monSoldeSemestersProvider);
                await Future.wait([
                  ref.refresh(paymentsDataProvider.future),
                  ref.refresh(pricingFallbackProvider.future),
                ]);
              } finally {
                ref.read(soldeRefreshingProvider.notifier).state = false;
              }
            },
            child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(context.horizontalPadding, 20, context.horizontalPadding, 16),
                  child: _buildHeader(l10n),
                ),
              ),

              // Content
              if (isRefreshing || (pricingAsync.isLoading && !pricingAsync.hasValue))
                const MonSoldeSkeleton()
              else
              paymentDataAsync.when(
                data: (plans) {
                  try {
                    return _buildContent(
                      context,
                      plans,
                      categories,
                      l10n,
                      semestersAsync.asData?.value ?? [],
                      yearDates.asData?.value,
                      pricingAsync.asData?.value ?? {},
                    );
                  } catch (e, _) {
                    return SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                            const SizedBox(height: 16),
                            Text('Erreur: $e', textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () {
                                ref.invalidate(paymentsDataProvider);
                                ref.invalidate(monSoldeSemestersProvider);
                              },
                              child: const Text('Réessayer'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                },
                loading: () => const MonSoldeSkeleton(),
                error: (error, stack) {
                  final cached = OfflineCacheService.instance.getListOfMaps('payments_latest');
                  final cachedPlans = (cached != null && cached.isNotEmpty)
                      ? cached.map((e) => PaymentPlanInfo.fromJson(e)).toList()
                      : <PaymentPlanInfo>[];
                  return _buildContent(
                    context,
                    cachedPlans,
                    categories,
                    l10n,
                    semestersAsync.asData?.value ?? [],
                    yearDates.asData?.value,
                    pricingAsync.asData?.value ?? {},
                  );
                },
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    final iconBoxSize = (56 * context.responsiveScale).clamp(44.0, 56.0);
    final iconInnerSize = (28 * context.responsiveScale).clamp(22.0, 28.0);

    return Row(
      children: [
        Container(
          width: iconBoxSize,
          height: iconBoxSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            Icons.payment_rounded,
            color: Colors.white,
            size: iconInnerSize,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  l10n.monSolde,
                  style: ArabicTypography.headerStyle(
                    context,
                    fontSize: context.sp(28),
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF1F2937),
                    letterSpacing: -0.8,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.soldeSubtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ArabicTypography.subtitleStyle(
                  context,
                  fontSize: context.sp(14),
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF1F2937),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<PaymentPlanInfo> plans,
    List<PaymentCategoryData> categories,
    AppLocalizations l10n,
    List<SemesterInfo> semesters,
    ({DateTime? start, DateTime? end})? yearDates,
    Map<String, double> pricing,
  ) {
    // Balance card uses ALL categories — keep only the latest plan per category
    // Sort plans so the one with the latest payment due date comes first,
    // ensuring we keep the most recent plan per category.
    final sortedPlans = List<PaymentPlanInfo>.from(plans)
      ..sort((a, b) {
        final aLatest = a.payments.isNotEmpty
            ? a.payments.map((p) => p.dueDate ?? DateTime(2000)).reduce((d1, d2) => d1.isAfter(d2) ? d1 : d2)
            : DateTime(2000);
        final bLatest = b.payments.isNotEmpty
            ? b.payments.map((p) => p.dueDate ?? DateTime(2000)).reduce((d1, d2) => d1.isAfter(d2) ? d1 : d2)
            : DateTime(2000);
        return bLatest.compareTo(aLatest);
      });

    final latestPlansByCategory = <String, PaymentPlanInfo>{};
    for (final p in sortedPlans) {
      final cat = _mapCategory(p.category, p.description ?? p.planType).name;
      latestPlansByCategory.putIfAbsent(cat, () => p);
    }
    final dedupedPlans = latestPlansByCategory.values.toList();

    final allPlansTotal = dedupedPlans.fold<double>(
      0,
      (sum, p) => sum + p.amountTotal,
    );
    final allPaidAmount = dedupedPlans.fold<double>(0, (sum, p) => sum + p.totalPaid);
    final pricingTotal = pricing.values.fold<double>(0, (sum, v) => sum + v);
    final totalAmount = allPlansTotal > 0 ? allPlansTotal : pricingTotal;
    final paidAmount = allPaidAmount;
    final remainingAmount = totalAmount - paidAmount;
    final progressPercent = totalAmount > 0
        ? (paidAmount / totalAmount) * 100
        : 0.0;

    // Schedule uses scolarite only
    final scolaritePlans = dedupedPlans
        .where((p) => _mapCategory(p.category, p.description ?? p.planType) == PaymentCategory.scolarite)
        .toList();
    final scolaritePricing = pricing['scolarite'] ?? 0.0;
    final scheduleTotal = scolaritePlans.fold<double>(
      0,
      (sum, p) => sum + p.amountTotal,
    );
    final scheduleAmount = scheduleTotal > 0 ? scheduleTotal : scolaritePricing;

    // Get plan type from admin (monthly, semester, annual)
    final planType = scolaritePlans.isNotEmpty
        ? scolaritePlans.first.planType
        : 'semester';

    // Find current semester
    final currentSemester = semesters.firstWhereOrNull((s) => s.isCurrent) ??
        semesters.firstOrNull;

    // Flatten all scolarite payments across plans, sorted by due date
    final allPayments = scolaritePlans.expand((p) => p.payments).toList()
      ..sort((a, b) {
        final aDate = a.dueDate ?? DateTime(2100);
        final bDate = b.dueDate ?? DateTime(2100);
        return aDate.compareTo(bDate);
      });

    // Always build the full month schedule from the current semester,
    // then overlay real payment data where it exists
    final displayPayments = _buildFullSchedule(
      planType,
      semesters,
      currentSemester,
      yearDates,
      scheduleAmount,
      allPayments,
    );

    // Categories excluding scolarite that have a configured price or active payments
    final nonScolariteCategories = categories
        .where((c) =>
            c.category != PaymentCategory.scolarite &&
            (c.amount > 0 || c.paid > 0))
        .toList();

    // If no tuition or categories configured and no real payments exist, show unified EmptyStateGlassCard
    if (totalAmount <= 0 && allPayments.isEmpty && dedupedPlans.isEmpty && nonScolariteCategories.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyStateGlassCard(
          icon: Icons.account_balance_wallet_rounded,
          gradientColors: const [Color(0xFF8B5CF6), Color(0xFF6D4CF6)],
          title: l10n.noPayments,
          subtitle: l10n.translate('no_payments_desc'),
        ),
      );
    }

    final bottomInset = MediaQuery.of(context).padding.bottom;

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(context.horizontalPadding, 0, context.horizontalPadding, 136 + bottomInset),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          // Main Balance Card
          _buildBalanceCard(
            remainingAmount,
            paidAmount,
            totalAmount,
            progressPercent,
          ),
          const SizedBox(height: 28),

          // Payment Schedule Section
          _buildPaymentScheduleSection(
            planType,
            displayPayments,
            l10n,
            currentSemester,
          ),

          // Categories Section (only displayed if categories have configured prices or payments)
          if (nonScolariteCategories.isNotEmpty) ...[
            Text(
              l10n.translate('repartition_categorie'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 16),

            // Categories excluding scolarite
            ...nonScolariteCategories.mapIndexed(
              (index, cat) {
                const palette = [
                  Color(0xFF8B5CF6), // Purple - Mon Solde icon
                  Color(0xFF6366F1), // Indigo
                  Color(0xFF3B82F6), // Royal Blue
                  Color(0xFF06B6D4), // Cyan
                  Color(0xFF10B981), // Emerald Green
                  Color(0xFFF59E0B), // Amber
                  Color(0xFFEC4899), // Pink
                ];
                final cardColor = palette[index % palette.length];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _GlassyCategoryCard(
                    category: cat,
                    currency: l10n.translate('currency_tnd'),
                    cardColor: cardColor,
                  ),
                );
              },
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildPaymentScheduleSection(
    String planType,
    List<PaymentInfo> displayPayments,
    AppLocalizations l10n,
    SemesterInfo? currentSemester,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.paymentSchedule,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 16),
        if (displayPayments.isEmpty)
          EmptyStateGlassCard(
            horizontalMargin: 0,
            icon: Icons.event_available_rounded,
            gradientColors: const [Color(0xFF8B5CF6), Color(0xFF6D4CF6)],
            title: l10n.noPayments,
            subtitle: l10n.translate('no_payments_desc'),
          )
        else if (planType == 'monthly')
          _buildMonthlyPaymentGrid(displayPayments, currentSemester)
        else
          ...displayPayments.map(
            (payment) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _GlassyPaymentCard(payment: payment, currency: l10n.translate('currency_tnd')),
            ),
          ),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _buildMonthlyPaymentGrid(
    List<PaymentInfo> payments,
    SemesterInfo? currentSemester,
  ) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();

    // Always find the payment matching the actual current month first
    var currentIndex = payments.indexWhere(
      (p) =>
          p.dueDate != null &&
          p.dueDate!.year == now.year &&
          p.dueDate!.month == now.month,
    );

    // If no exact match, find by month only (ignoring year)
    if (currentIndex < 0) {
      currentIndex = payments.indexWhere(
        (p) => p.dueDate != null && p.dueDate!.month == now.month,
      );
    }

    // If still no match, find the closest past month
    if (currentIndex < 0) {
      final nowDate = DateTime(now.year, now.month, 1);
      var bestIndex = -1;
      for (var i = payments.length - 1; i >= 0; i--) {
        if (payments[i].dueDate != null) {
          final dueDate = DateTime(
            payments[i].dueDate!.year,
            payments[i].dueDate!.month,
            1,
          );
          if (!dueDate.isAfter(nowDate)) {
            bestIndex = i;
            break;
          }
        }
      }
      currentIndex = bestIndex;
    }

    final initialIndex = currentIndex >= 0 ? currentIndex : 0;

    // Find the index of the current month in the payments list
    final currentMonthIdx = payments.indexWhere(
      (p) =>
          p.dueDate != null &&
          p.dueDate!.year == now.year &&
          p.dueDate!.month == now.month,
    );

    return _PaymentCarousel(
      payments: payments,
      currency: l10n.translate('currency_tnd'),
      initialIndex: initialIndex,
      currentMonthIndex: currentMonthIdx,
    );
  }

  // Builds the payment schedule.  When real payments exist (admin has created
  // a plan) we return them directly so the student sees the exact due dates.
  // Only when there are no payments do we generate a preview from semester dates.
  List<PaymentInfo> _buildFullSchedule(
    String planType,
    List<SemesterInfo> semesters,
    SemesterInfo? currentSemester,
    ({DateTime? start, DateTime? end})? yearDates,
    double totalAmount,
    List<PaymentInfo> realPayments,
  ) {
    if (totalAmount <= 0 && realPayments.isEmpty) {
      return <PaymentInfo>[];
    }

    if (planType != 'monthly') {
      // For non-monthly plans, return real payments or generate placeholders
      if (realPayments.isNotEmpty) return realPayments;
      return _buildPlaceholderPaymentsForType(
        planType,
        semesters,
        yearDates,
        totalAmount,
      );
    }

    // If real payments exist, use them directly — the admin already created
    // the exact due dates. Only generate a semester-based schedule when there
    // are no real payments (preview / before first plan creation).
    if (realPayments.isNotEmpty) return realPayments;

    // For monthly plans with no real payments, generate all months covered by
    // the academic year's semesters so the user sees the expected schedule.
    final scheduleStart = semesters.isNotEmpty
        ? semesters
            .map((s) => s.startDate)
            .whereType<DateTime>()
            .reduce((a, b) => a.isBefore(b) ? a : b)
        : yearDates?.start;
    final scheduleEnd = semesters.isNotEmpty
        ? semesters
            .map((s) => s.endDate)
            .whereType<DateTime>()
            .reduce((a, b) => a.isAfter(b) ? a : b)
        : yearDates?.end;
    if (scheduleStart == null || scheduleEnd == null) {
      return realPayments.isNotEmpty
          ? realPayments
          : _buildPlaceholderPaymentsForType(
              planType,
              semesters,
              yearDates,
              totalAmount,
            );
    }

    // Generate all months in the semester range
    final allMonths = <DateTime>[];
    var current = DateTime(scheduleStart.year, scheduleStart.month, 1);
    final endMonth = DateTime(scheduleEnd.year, scheduleEnd.month, 1);
    while (!current.isAfter(endMonth)) {
      allMonths.add(current);
      current = DateTime(current.year, current.month + 1, 1);
    }

    if (allMonths.isEmpty) {
      return realPayments.isNotEmpty
          ? realPayments
          : _buildPlaceholderPaymentsForType(
              planType,
              semesters,
              yearDates,
              totalAmount,
            );
    }

    // Build a lookup of real payments by month — only include payments within the schedule range
    final realByMonth = <String, PaymentInfo>{};
    for (final p in realPayments) {
      if (p.dueDate != null) {
        final d = p.dueDate!;
        if (!d.isBefore(scheduleStart) && !d.isAfter(scheduleEnd)) {
          final key = '${d.year}-${d.month}';
          realByMonth[key] = p;
        }
      }
    }

    // For each month, use real payment if available, otherwise create a placeholder
    final partAmount =
        allMonths.isNotEmpty && totalAmount > 0 ? totalAmount / allMonths.length : 0.0;
    return allMonths.asMap().entries.map((e) {
      final month = e.value;
      final key = '${month.year}-${month.month}';
      if (realByMonth.containsKey(key)) {
        return realByMonth[key]!;
      }
      return PaymentInfo(
        id: 'schedule_${e.key}',
        amount: partAmount,
        dueDate: month,
        status: 'pending',
      );
    }).toList();
  }

  List<PaymentInfo> _buildPlaceholderPaymentsForType(
    String planType,
    List<SemesterInfo> semesters,
    ({DateTime? start, DateTime? end})? yearDates,
    double totalAmount,
  ) {
    final sortedSemesters = [...semesters]..sort((a, b) => a.number.compareTo(b.number));

    switch (planType) {
      case 'annual':
        return _buildAnnualPlaceholder(sortedSemesters, yearDates, totalAmount);
      case 'monthly':
        return _buildMonthlyPlaceholder(sortedSemesters, yearDates, totalAmount);
      case 'semesterly':
        return _buildSemesterPlaceholder(sortedSemesters, yearDates, totalAmount);
      case 'trimester':
        return _buildTrimesterPlaceholder(sortedSemesters, yearDates, totalAmount);
      case 'semester':
      default:
        return _buildSemesterPlaceholder(sortedSemesters, yearDates, totalAmount);
    }
  }

  List<PaymentInfo> _buildAnnualPlaceholder(
    List<SemesterInfo> semesters,
    ({DateTime? start, DateTime? end})? yearDates,
    double totalAmount,
  ) {
    final start = yearDates?.start ??
        semesters.firstOrNull?.startDate ??
        DateTime(DateTime.now().year, 9, 1);
    return [
      PaymentInfo(
        id: 'placeholder_annual',
        amount: totalAmount,
        dueDate: DateTime(start.year, start.month, 1),
        status: 'pending',
      ),
    ];
  }

  List<PaymentInfo> _buildSemesterPlaceholder(
    List<SemesterInfo> semesters,
    ({DateTime? start, DateTime? end})? yearDates,
    double totalAmount,
  ) {
    var effectiveSemesters = semesters;
    if (effectiveSemesters.isEmpty) {
      effectiveSemesters = [
        SemesterInfo(
          id: 'placeholder_s1',
          name: 'Semestre 1',
          number: 1,
          isCurrent: false,
          startDate: yearDates?.start ?? DateTime(DateTime.now().year, 9, 1),
          endDate: yearDates?.end ?? DateTime(DateTime.now().year + 1, 6, 30),
        ),
        SemesterInfo(
          id: 'placeholder_s2',
          name: 'Semestre 2',
          number: 2,
          isCurrent: false,
          startDate: yearDates?.start != null
              ? DateTime(yearDates!.start!.year, yearDates.start!.month + 5, 1)
              : DateTime(DateTime.now().year + 1, 2, 1),
          endDate: yearDates?.end ?? DateTime(DateTime.now().year + 1, 6, 30),
        ),
      ];
    }

    final partAmount = totalAmount > 0 ? totalAmount / effectiveSemesters.length : 0.0;
    return effectiveSemesters.asMap().entries.map((e) {
      final semester = e.value;
      final dueDate = semester.startDate != null
          ? DateTime(semester.startDate!.year, semester.startDate!.month, 1)
          : _fallbackDateFromYear(yearDates, e.key, effectiveSemesters.length);
      return PaymentInfo(
        id: 'placeholder_${e.key}',
        amount: partAmount,
        dueDate: dueDate,
        status: 'pending',
      );
    }).toList();
  }

  List<PaymentInfo> _buildTrimesterPlaceholder(
    List<SemesterInfo> semesters,
    ({DateTime? start, DateTime? end})? yearDates,
    double totalAmount,
  ) {
    const count = 3;
    final partAmount = totalAmount > 0 ? totalAmount / count : 0.0;
    return List.generate(count, (index) {
      final dueDate = _fallbackDateFromYear(yearDates, index, count);
      return PaymentInfo(
        id: 'placeholder_$index',
        amount: partAmount,
        dueDate: dueDate,
        status: 'pending',
      );
    });
  }

  List<PaymentInfo> _buildMonthlyPlaceholder(
    List<SemesterInfo> semesters,
    ({DateTime? start, DateTime? end})? yearDates,
    double totalAmount,
  ) {
    // Use actual semester dates first, not academic year bounds
    final firstSemStart = semesters.isNotEmpty ? semesters.first.startDate : null;
    final lastSemEnd = semesters.isNotEmpty ? semesters.last.endDate : null;
    final start = firstSemStart ?? yearDates?.start ?? DateTime(DateTime.now().year, 9, 1);
    final end = lastSemEnd ?? yearDates?.end ?? DateTime(start.year + 1, start.month, 1);

    final months = <DateTime>[];
    var current = DateTime(start.year, start.month, 1);
    final endMonth = DateTime(end.year, end.month, 1);
    while (!current.isAfter(endMonth)) {
      months.add(current);
      current = DateTime(current.year, current.month + 1, 1);
    }

    final partAmount = months.isNotEmpty && totalAmount > 0 ? totalAmount / months.length : 0.0;
    return months.asMap().entries.map((e) => PaymentInfo(
          id: 'placeholder_${e.key}',
          amount: partAmount,
          dueDate: e.value,
          status: 'pending',
        )).toList();
  }

  DateTime? _fallbackDateFromYear(
    ({DateTime? start, DateTime? end})? yearDates,
    int index,
    int count,
  ) {
    final start = yearDates?.start ?? DateTime(DateTime.now().year, 9, 1);
    final end = yearDates?.end ?? DateTime(start.year + 1, start.month, 1);
    final totalMonths = (end.year - start.year) * 12 + (end.month - start.month);
    final monthsPerPart = (totalMonths / count).ceil();
    return DateTime(start.year, start.month + (index * monthsPerPart), 1);
  }

  Widget _buildBalanceCard(
    double remaining,
    double paid,
    double total,
    double progressPercent,
  ) {
    final l10n = AppLocalizations.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: EdgeInsets.all(AppResponsive.cardPadding(context, base: 24.0)),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.translate('solde_restant'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatCurrency(remaining),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      height: 1,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 6, right: 6),
                    child: Text(
                      l10n.translate('currency_tnd'),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progressPercent / 100,
                minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${l10n.statusPaid}: ${_formatCurrency(paid)} ${l10n.translate('currency_tnd')}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${l10n.translate('total')}: ${_formatCurrency(total)} ${l10n.translate('currency_tnd')}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat('#,###', 'fr_FR');
    return formatter.format(amount);
  }
}

// Payment Carousel (horizontal scrollable circle cards)
class _PaymentCarousel extends StatefulWidget {
  final List<PaymentInfo> payments;
  final String currency;
  final int initialIndex;
  final int currentMonthIndex;

  const _PaymentCarousel({
    required this.payments,
    required this.currency,
    this.initialIndex = 0,
    this.currentMonthIndex = -1,
  });

  @override
  State<_PaymentCarousel> createState() => _PaymentCarouselState();
}

class _PaymentCarouselState extends State<_PaymentCarousel>
    with TickerProviderStateMixin {
  static const double _centerSize = 160.0;

  late PageController _pageController;
  late double _currentPage;
  late AnimationController _pressCtrl;
  late AnimationController _bounceCtrl;
  late Animation<double> _bounceAnim;
  bool _isCenterPressed = false;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialIndex.toDouble();
    _pageController = PageController(
      viewportFraction: 0.5,
      initialPage: widget.initialIndex,
    );
    _pageController.addListener(_onPageScroll);

    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    const shrink = 0.92;
    const overshoot = 1.06;
    final secondaryUndershoot = 1.0 - (1.0 - shrink) * 0.24;
    final secondaryOvershoot = 1.0 + (overshoot - 1.0) * 0.28;

    _bounceAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: shrink, end: overshoot)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 38,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: overshoot, end: secondaryUndershoot)
            .chain(CurveTween(curve: Curves.easeInOutQuad)),
        weight: 26,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: secondaryUndershoot, end: secondaryOvershoot)
            .chain(CurveTween(curve: Curves.easeInOutQuad)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: secondaryOvershoot, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 18,
      ),
    ]).animate(_bounceCtrl);
  }

  void _onPageScroll() {
    if (_pageController.hasClients && _pageController.page != null) {
      _currentPage = _pageController.page!;
    }
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageScroll);
    _pageController.dispose();
    _pressCtrl.dispose();
    _bounceCtrl.dispose();
    super.dispose();
  }

  double get _currentCenterBounceScale {
    if (_bounceCtrl.isAnimating) {
      return _bounceAnim.value;
    }
    return 1.0 - (_pressCtrl.value * (1.0 - 0.92));
  }

  double _scaleForDistance(double distance) {
    final abs = distance.abs();
    if (abs <= 1.0) {
      return lerpDouble(1.0, 0.68, abs)!;
    } else if (abs <= 2.0) {
      return lerpDouble(0.68, 0.44, abs - 1.0)!;
    } else {
      return lerpDouble(0.44, 0.25, (abs - 2.0).clamp(0.0, 1.0))!;
    }
  }

  double _xOffsetForDistance(double distance) {
    final abs = distance.abs();
    final sign = distance < 0 ? -1.0 : 1.0;
    double offset;
    if (abs <= 1.0) {
      offset = abs * 76.0;
    } else if (abs <= 2.0) {
      offset = 76.0 + (abs - 1.0) * 60.0;
    } else {
      offset = 136.0 + (abs - 2.0) * 50.0;
    }
    return sign * offset;
  }

  double _verticalOffset(double distance) {
    final abs = distance.abs();
    if (abs <= 1.0) {
      return abs * 36.0;
    } else if (abs <= 2.0) {
      return 36.0 + (abs - 1.0) * 52.0;
    } else {
      return 88.0 + (abs - 2.0) * 30.0;
    }
  }

  double _opacityForDistance(double distance) {
    final abs = distance.abs();
    if (abs <= 0.5) return 1.0;
    if (abs <= 1.2) {
      return lerpDouble(1.0, 0.70, (abs - 0.5) / 0.7)!;
    } else if (abs <= 2.0) {
      return lerpDouble(0.70, 0.35, (abs - 1.2) / 0.8)!;
    } else if (abs <= 2.3) {
      return lerpDouble(0.35, 0.0, (abs - 2.0) / 0.3)!;
    }
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 260,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final centerX = constraints.maxWidth / 2;
          final centerY = constraints.maxHeight * 0.36;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Visual circles animated reactively with 60fps hardware acceleration
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_pageController, _pressCtrl, _bounceCtrl]),
                  builder: (context, _) {
                    final currentPage = _pageController.hasClients && _pageController.page != null
                        ? _pageController.page!
                        : _currentPage;

                    final sortedIndices = List.generate(widget.payments.length, (i) => i)
                      ..sort((a, b) {
                        final distA = (a - currentPage).abs();
                        final distB = (b - currentPage).abs();
                        return distB.compareTo(distA);
                      });

                    final activeCenterIndex = currentPage.round().clamp(0, widget.payments.length - 1);

                    return Stack(
                      clipBehavior: Clip.none,
                      children: sortedIndices.map((index) {
                        final distance = index - currentPage;
                        final absDistance = distance.abs();
                        if (absDistance >= 2.4) return const SizedBox.shrink();

                        final opacity = _opacityForDistance(distance);
                        if (opacity <= 0.01) return const SizedBox.shrink();

                        final scale = _scaleForDistance(distance);
                        final xOffset = _xOffsetForDistance(distance);
                        final vOffset = _verticalOffset(distance);
                        final isCenter = index == activeCenterIndex && absDistance < 0.6;
                        final centerScaleMultiplier = isCenter ? _currentCenterBounceScale : 1.0;

                        // Depth-of-field blur for circles receding into the background
                        double blurSigma = 0.0;
                        if (absDistance > 0.6) {
                          blurSigma = ((absDistance - 0.6) * 3.5).clamp(0.0, 5.0);
                        }

                        Widget circleCard = _PaymentCircleCard(
                          key: ValueKey('payment_card_$index'),
                          payment: widget.payments[index],
                          currency: widget.currency,
                          isCenter: isCenter,
                          absDistance: absDistance,
                          isCurrentMonth: index == widget.currentMonthIndex,
                        );

                        if (blurSigma > 0.1) {
                          circleCard = ImageFiltered(
                            imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                            child: circleCard,
                          );
                        }

                        return Positioned(
                          key: ValueKey('circle_item_$index'),
                          left: centerX + xOffset - _centerSize / 2,
                          top: centerY + vOffset - _centerSize / 2,
                          child: SizedBox(
                            width: _centerSize,
                            height: _centerSize,
                            child: Transform.scale(
                              scale: scale * centerScaleMultiplier,
                              child: Opacity(
                                opacity: opacity,
                                child: circleCard,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),

              // Invisible PageView to enable smooth swipe gestures and taps
              // Directionality is locked to LTR so sliding left moves circles left
              // and sliding right moves circles right across both Arabic and Latin
              Positioned.fill(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: widget.payments.length,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (idx) {
                      _currentPage = idx.toDouble();
                    },
                    itemBuilder: (context, index) {
                      return GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTapDown: (_) {
                          final page = _pageController.hasClients && _pageController.page != null
                              ? _pageController.page!
                              : _currentPage;
                          final activeCenterIndex = page.round().clamp(0, widget.payments.length - 1);
                          final isCenter = index == activeCenterIndex || (page - index).abs() < 0.5;
                          if (isCenter) {
                            _isCenterPressed = true;
                            _bounceCtrl.stop();
                            _pressCtrl.animateTo(1.0, duration: const Duration(milliseconds: 120));
                          }
                        },
                        onTapUp: (_) {
                          if (_isCenterPressed) {
                            _isCenterPressed = false;
                            _pressCtrl.value = 0.0;
                            _bounceCtrl.forward(from: 0.0);
                          }
                        },
                        onTapCancel: () {
                          if (_isCenterPressed) {
                            _isCenterPressed = false;
                            _pressCtrl.animateTo(0.0, duration: const Duration(milliseconds: 140));
                          }
                        },
                        onTap: () {
                          final page = _pageController.hasClients && _pageController.page != null
                              ? _pageController.page!
                              : _currentPage;
                          final activeCenterIndex = page.round().clamp(0, widget.payments.length - 1);
                          final isCenter = index == activeCenterIndex || (page - index).abs() < 0.5;

                          if (isCenter) {
                            _showPaymentDetailsDialog(
                              context,
                              widget.payments[activeCenterIndex],
                              widget.currency,
                              DateFormat('dd/MM/yyyy'),
                            );
                          } else {
                            _pageController.animateToPage(
                              index,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        },
                        child: const SizedBox.expand(),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Circle Payment Card (matching the design)
class _PaymentCircleCard extends StatelessWidget {
  final PaymentInfo payment;
  final String currency;
  final bool isCenter;
  final double absDistance;
  final bool isCurrentMonth;

  const _PaymentCircleCard({
    super.key,
    required this.payment,
    required this.currency,
    required this.isCenter,
    this.absDistance = 0,
    this.isCurrentMonth = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lang = l10n.locale.languageCode;
    final monthFormat = DateFormat.MMM(lang);
    final monthLabel = payment.dueDate != null
        ? monthFormat.format(payment.dueDate!).replaceAll('.', '').toUpperCase()
        : '';
    final isPaid = payment.status == 'paid';
    final isOverdue =
        !isPaid &&
        payment.dueDate != null &&
        payment.dueDate!.isBefore(DateTime.now());

    final Color statusColor;
    final String statusText;
    if (isPaid) {
      statusColor = const Color(0xFF22C55E);
      statusText = l10n.statusPaid;
    } else if (isOverdue) {
      statusColor = const Color(0xFFEF4444);
      statusText = l10n.statusOverdue;
    } else {
      statusColor = const Color(0xFFFF6B9D);
      statusText = l10n.statusPending;
    }

    final monthColor = Color.lerp(
      const Color(0xFFFF6B9D),
      Colors.grey.shade400,
      (absDistance * 1.5).clamp(0.0, 1.0),
    ) ?? Colors.grey.shade400;

    Widget card = Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isCenter ? 0.07 : 0.04),
            blurRadius: isCenter ? 18 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            monthLabel,
            style: TextStyle(
              fontSize: 14.0,
              fontWeight: FontWeight.w600,
              color: monthColor,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _formatCurrency(payment.amount),
            style: const TextStyle(
              fontSize: 28.0,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1F2937),
              height: 1.1,
            ),
          ),
          Text(
            currency,
            style: TextStyle(
              fontSize: 11.0,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6.0,
                  height: 6.0,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 10.0,
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (isCurrentMonth) {
      card = Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          Positioned(
            top: -10,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B9D),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF6B9D).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  l10n.translate('badge_current'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (isCenter) {
      card = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showPaymentDetailsDialog(
          context,
          payment,
          currency,
          DateFormat('dd/MM/yyyy'),
        ),
        child: card,
      );
    }

    return card;
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat('#,###', 'fr_FR');
    return formatter.format(amount);
  }
}

// Glassy Category Card
class _GlassyCategoryCard extends StatelessWidget {
  final PaymentCategoryData category;
  final String currency;
  final Color? cardColor;

  const _GlassyCategoryCard({
    required this.category,
    required this.currency,
    this.cardColor,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cat = category.category;
    final color = cardColor ?? cat.color;
    final isPaid = category.amount > 0 && category.remaining <= 0;

    return BouncingWrapper(
      behavior: HitTestBehavior.opaque,
      shrinkScale: 0.94,
      overshootScale: 1.05,
      delayNavigation: false,
      onTap: () => _showCategoryDetailsDialog(context, category, currency, color),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(cat.icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            cat.getLocalizedLabel(l10n),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                        if (isPaid)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF10B981,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  size: 12,
                                  color: Color(0xFF10B981),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  l10n.statusPaid,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF10B981),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: category.progressPercent / 100,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Amounts
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_formatCurrency(category.paid)} $currency / ${_formatCurrency(category.amount)} $currency',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        if (!isPaid && category.amount > 0)
                          Text(
                            '${l10n.translate('remaining_short')}: ${_formatCurrency(category.remaining)} $currency',
                            style: ArabicTypography.bodyStyle(
                              context,
                              fontSize: 11,
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCategoryDetailsDialog(BuildContext context, PaymentCategoryData catData, String currency, Color effectiveColor) {
    final l10n = AppLocalizations.of(context);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final cat = catData.category;
    final isPaid = catData.amount > 0 && catData.remaining <= 0;
    final statusColor = isPaid ? const Color(0xFF10B981) : effectiveColor;
    final statusText = isPaid
        ? l10n.statusPaid
        : (catData.paid > 0
            ? l10n.translate('incomplete')
            : l10n.statusPending);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Center(
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(32),
            ),
            backgroundColor: Colors.white,
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: effectiveColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(cat.icon, color: effectiveColor, size: 36),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    cat.getLocalizedLabel(l10n),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 14,
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildDetailRow(
                    l10n.translate('total_amount'),
                    '${_formatCurrency(catData.amount)} $currency',
                    Icons.account_balance_wallet_rounded,
                    effectiveColor,
                  ),
                  _buildDetailRow(
                    l10n.translate('paid_amount'),
                    '${_formatCurrency(catData.paid)} $currency',
                    Icons.check_circle_rounded,
                    effectiveColor,
                  ),
                  _buildDetailRow(
                    l10n.translate('remaining_amount'),
                    '${_formatCurrency(catData.remaining)} $currency',
                    Icons.pending_actions_rounded,
                    effectiveColor,
                  ),
                  _buildDetailRow(
                    l10n.translate('progress'),
                    '${catData.progressPercent.toStringAsFixed(0)}%',
                    Icons.pie_chart_rounded,
                    effectiveColor,
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: effectiveColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        l10n.closeLabel,
                        style: isArabic
                            ? GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16)
                            : const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return buildIosBounceZoomTransition(
          context: context,
          animation: animation,
          child: child,
          backdropSigma: 8.0,
          maxFlightBlur: 14.0,
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat('#,###', 'fr_FR');
    return formatter.format(amount);
  }
}

// Glassy Payment Card
class _GlassyPaymentCard extends StatelessWidget {
  final PaymentInfo payment;
  final String currency;

  const _GlassyPaymentCard({required this.payment, required this.currency});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dateFormat = DateFormat('dd/MM/yyyy');
    final isPaid = payment.status == 'paid';
    final isOverdue =
        !isPaid &&
        payment.dueDate != null &&
        payment.dueDate!.isBefore(DateTime.now());

    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (isPaid) {
      statusColor = const Color(0xFF10B981);
      statusIcon = Icons.check_circle_rounded;
      statusText = l10n.statusPaid;
    } else if (isOverdue) {
      statusColor = const Color(0xFFEF4444);
      statusIcon = Icons.warning_rounded;
      statusText = l10n.statusOverdue;
    } else {
      statusColor = const Color(0xFFF59E0B);
      statusIcon = Icons.schedule_rounded;
      statusText = l10n.statusPending;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showPaymentDetailsDialog(context, payment, currency, dateFormat),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(statusIcon, color: statusColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.dueDateLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  if (payment.dueDate != null)
                    Text(
                      dateFormat.format(payment.dueDate!),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${_formatCurrency(payment.amount)} $currency',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 11,
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat('#,###', 'fr_FR');
    return formatter.format(amount);
  }
}

void _showPaymentDetailsDialog(
  BuildContext context,
  PaymentInfo payment,
  String currency,
  DateFormat dateFormat,
) {
  final l10n = AppLocalizations.of(context);
  final isPaid = payment.status == 'paid';
  final isOverdue =
      !isPaid &&
      payment.dueDate != null &&
      payment.dueDate!.isBefore(DateTime.now());

  Color statusColor;
  IconData statusIcon;
  String statusText;

  if (isPaid) {
    statusColor = const Color(0xFF10B981);
    statusIcon = Icons.check_circle_rounded;
    statusText = l10n.statusPaid;
  } else if (isOverdue) {
    statusColor = const Color(0xFFEF4444);
    statusIcon = Icons.warning_rounded;
    statusText = l10n.statusOverdue;
  } else {
    statusColor = const Color(0xFFF59E0B);
    statusIcon = Icons.schedule_rounded;
    statusText = l10n.statusPending;
  }

  // Calculate delay duration for overdue payments
  String? delayText;
  if (isOverdue && payment.dueDate != null) {
    final delay = DateTime.now().difference(payment.dueDate!);
    final days = delay.inDays;
    if (days > 0) {
      if (l10n.locale.languageCode == 'ar') {
        delayText = '$days يوم تأخير';
      } else if (l10n.locale.languageCode == 'en') {
        delayText = '$days day${days > 1 ? 's' : ''} overdue';
      } else {
        delayText = '$days jour${days > 1 ? 's' : ''} de retard';
      }
    }
  }

  // Generate reference if not exists
  final reference =
      payment.reference ??
      'PAY-${payment.id.length >= 8 ? payment.id.substring(0, 8).toUpperCase() : payment.id.toUpperCase()}';

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: '',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Center(
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
          backgroundColor: Colors.white,
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with status icon
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 36),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.locale.languageCode == 'ar'
                      ? 'تفاصيل الدفع'
                      : (l10n.locale.languageCode == 'en' ? 'Payment Details' : 'Détails du paiement'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 14,
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Show delay duration for overdue as info row
                if (delayText != null) ...[
                  const SizedBox(height: 24),
                  _buildPaymentDetailRow(
                    l10n.delayLabel,
                    delayText,
                    Icons.timer_off_rounded,
                    statusColor,
                  ),
                ],
                if (delayText == null) const SizedBox(height: 24),
                // Amount
                _buildPaymentDetailRow(
                  l10n.amountLabel,
                  '${NumberFormat('#,###', 'fr_FR').format(payment.amount)} $currency',
                  Icons.attach_money_rounded,
                  statusColor,
                ),
                // Due date
                if (payment.dueDate != null)
                  _buildPaymentDetailRow(
                    l10n.dueDateLabel,
                    dateFormat.format(payment.dueDate!),
                    Icons.calendar_today_rounded,
                    statusColor,
                  ),
                // Paid date
                if (payment.paidAt != null)
                  _buildPaymentDetailRow(
                    l10n.paymentDateLabel,
                    dateFormat.format(payment.paidAt!),
                    Icons.event_available_rounded,
                    statusColor,
                  ),
                // Payment method
                if (payment.method != null)
                  _buildPaymentDetailRow(
                    l10n.methodLabel,
                    payment.displayMethod,
                    Icons.payment_rounded,
                    statusColor,
                  ),
                // Reference
                _buildPaymentDetailRow(
                  l10n.locale.languageCode == 'ar'
                      ? 'المرجع'
                      : (l10n.locale.languageCode == 'en' ? 'Reference' : 'Référence'),
                  reference,
                  Icons.receipt_rounded,
                  statusColor,
                ),
                // Notes
                if (payment.notes != null && payment.notes!.isNotEmpty)
                  _buildPaymentDetailRow(
                    l10n.locale.languageCode == 'ar'
                        ? 'ملاحظات'
                        : (l10n.locale.languageCode == 'en' ? 'Notes' : 'Notes'),
                    payment.notes!,
                    Icons.note_rounded,
                    statusColor,
                  ),
                const SizedBox(height: 28),
                // Close button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: statusColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      l10n.closeLabel,
                      style: (l10n.locale.languageCode == 'ar'
                          ? GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16)
                          : const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return buildIosBounceZoomTransition(
        context: context,
        animation: animation,
        child: child,
        backdropSigma: 8.0,
        maxFlightBlur: 14.0,
      );
    },
  );
}

Widget _buildPaymentDetailRow(
  String label,
  String value,
  IconData icon,
  Color statusColor,
) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: statusColor, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
