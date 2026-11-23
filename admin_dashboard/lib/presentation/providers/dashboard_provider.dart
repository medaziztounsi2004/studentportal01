import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/error_messages.dart';
import '../../data/models/dashboard_models.dart';

final dashboardProvider = AsyncNotifierProvider<DashboardNotifier, DashboardState>(DashboardNotifier.new);

class DashboardState {
  final DashboardKpis kpis;
  final CashflowIntervalData weeklyCashflow;
  final CashflowIntervalData monthlyCashflow;
  final CashflowIntervalData annualCashflow;
  final List<CategoryBreakdownItem> categories;
  final List<FiliereDistributionItem> filieres;
  final List<DashboardCalendarEvent> events;
  final List<AttendanceLevelItem> attendanceLevels;
  final List<AtRiskStudent> atRiskStudents;
  final bool isLoading;
  final String? error;
  final DateTime lastUpdated;

  DashboardState({
    DashboardKpis? kpis,
    CashflowIntervalData? weeklyCashflow,
    CashflowIntervalData? monthlyCashflow,
    CashflowIntervalData? annualCashflow,
    this.categories = const [],
    this.filieres = const [],
    this.events = const [],
    this.attendanceLevels = const [],
    this.atRiskStudents = const [],
    this.isLoading = false,
    this.error,
    DateTime? lastUpdated,
  })  : kpis = kpis ?? DashboardKpis(),
        weeklyCashflow = weeklyCashflow ?? CashflowIntervalData(points: []),
        monthlyCashflow = monthlyCashflow ?? CashflowIntervalData(points: []),
        annualCashflow = annualCashflow ?? CashflowIntervalData(points: []),
        lastUpdated = lastUpdated ?? DateTime.now();

  DashboardState copyWith({
    DashboardKpis? kpis,
    CashflowIntervalData? weeklyCashflow,
    CashflowIntervalData? monthlyCashflow,
    CashflowIntervalData? annualCashflow,
    List<CategoryBreakdownItem>? categories,
    List<FiliereDistributionItem>? filieres,
    List<DashboardCalendarEvent>? events,
    List<AttendanceLevelItem>? attendanceLevels,
    List<AtRiskStudent>? atRiskStudents,
    bool? isLoading,
    String? error,
    DateTime? lastUpdated,
  }) =>
      DashboardState(
        kpis: kpis ?? this.kpis,
        weeklyCashflow: weeklyCashflow ?? this.weeklyCashflow,
        monthlyCashflow: monthlyCashflow ?? this.monthlyCashflow,
        annualCashflow: annualCashflow ?? this.annualCashflow,
        categories: categories ?? this.categories,
        filieres: filieres ?? this.filieres,
        events: events ?? this.events,
        attendanceLevels: attendanceLevels ?? this.attendanceLevels,
        atRiskStudents: atRiskStudents ?? this.atRiskStudents,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );
}

class DashboardNotifier extends AsyncNotifier<DashboardState> {
  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  Future<DashboardState> build() async {
    return await _loadDashboard();
  }

  Future<DashboardState> _loadDashboard() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return _buildFallbackState();

      final userResp = await _supabase
          .from('users')
          .select('school_id')
          .eq('id', userId)
          .maybeSingle();

      final schoolId = userResp?['school_id'] as String?;
      if (schoolId == null) return _buildFallbackState();

      // Parallel data fetching for performance
      final results = await Future.wait([
        _loadKpis(schoolId),
        _loadCashflows(schoolId),
        _loadCategoryBreakdown(schoolId),
        _loadFiliereDistribution(schoolId),
        _loadCalendarEvents(schoolId),
        _loadAttendanceLevels(schoolId),
      ]);

      final kpis = results[0] as DashboardKpis;
      final cashflows = results[1] as Map<String, CashflowIntervalData>;
      final categories = results[2] as List<CategoryBreakdownItem>;
      final filieres = results[3] as List<FiliereDistributionItem>;
      final events = results[4] as List<DashboardCalendarEvent>;
      final attendance = results[5] as List<AttendanceLevelItem>;

      return DashboardState(
        kpis: kpis,
        weeklyCashflow: cashflows['weekly'],
        monthlyCashflow: cashflows['monthly'],
        annualCashflow: cashflows['annual'],
        categories: categories,
        filieres: filieres,
        events: events,
        attendanceLevels: attendance,
        isLoading: false,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      debugPrint('DashboardNotifier._loadDashboard error: $e');
      return _buildFallbackState(error: UserFriendlyError.format(
        e,
        fallback: 'Unable to load dashboard statistics right now. Please try again.',
      ));
    }
  }

  Future<DashboardKpis> _loadKpis(String schoolId) async {
    int totalStudents = 0;
    int activeStudents = 0;
    int totalTeachers = 0;
    int totalStaff = 0;
    int totalClasses = 0;
    double totalDue = 0;
    double totalPaid = 0;

    double thisMonthCollected = 0;
    double lastMonthCollected = 0;

    final now = DateTime.now();
    final currentMonthStart = DateTime(now.year, now.month, 1);
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);

    try {
      final studentsResp = await _supabase
          .from('users')
          .select('id, is_active, account_status')
          .eq('school_id', schoolId)
          .eq('role', 'student');
      final sList = (studentsResp as List).cast<Map<String, dynamic>>();
      totalStudents = sList.length;
      activeStudents = sList.where((s) => s['is_active'] != false && s['account_status'] != 'paused_unpaid').length;

      final teachersResp = await _supabase
          .from('users')
          .select('id')
          .eq('school_id', schoolId)
          .eq('role', 'teacher');
      totalTeachers = (teachersResp as List).length;

      final staffResp = await _supabase
          .from('users')
          .select('id')
          .eq('school_id', schoolId)
          .or('role.eq.staff,role.eq.admin');
      totalStaff = (staffResp as List).length;

      final classesResp = await _supabase
          .from('classes')
          .select('id')
          .eq('school_id', schoolId);
      totalClasses = (classesResp as List).length;
    } catch (e) {
      debugPrint('Error loading user/class counts for KPIs: $e');
    }

    try {
      final paymentsResp = await _supabase
          .from('payments')
          .select('amount, status, paid_at, created_at, school_id')
          .eq('school_id', schoolId);

      for (final p in paymentsResp as List) {
        final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
        final status = (p['status'] ?? '').toString().toLowerCase();

        if (status != 'cancelled') {
          totalDue += amt;
        }
        if (status == 'paid') {
          totalPaid += amt;

          DateTime? paidDate;
          if (p['paid_at'] != null) {
            paidDate = DateTime.tryParse(p['paid_at'].toString())?.toLocal();
          } else if (p['created_at'] != null) {
            paidDate = DateTime.tryParse(p['created_at'].toString())?.toLocal();
          }

          if (paidDate != null) {
            if (paidDate.isAfter(currentMonthStart) || paidDate.isAtSameMomentAs(currentMonthStart)) {
              thisMonthCollected += amt;
            } else if (paidDate.isAfter(lastMonthStart) && paidDate.isBefore(currentMonthStart)) {
              lastMonthCollected += amt;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading payments for KPIs: $e');
    }

    final collected = totalPaid;
    final due = totalDue > 0 ? totalDue : totalPaid;
    final unpaid = (due - collected).clamp(0.0, double.infinity);
    final recovery = (due > 0) ? (collected / due * 100).clamp(0.0, 100.0) : (collected > 0 ? 100.0 : 0.0);

    // Real Revenue Growth (this month vs last month)
    double revGrowth = 0.0;
    bool revGrowthUp = true;
    if (lastMonthCollected > 0) {
      revGrowth = ((thisMonthCollected - lastMonthCollected) / lastMonthCollected * 100).roundToDouble();
      revGrowthUp = revGrowth >= 0;
    } else if (thisMonthCollected > 0) {
      revGrowth = 100.0;
      revGrowthUp = true;
    } else {
      revGrowth = 0.0;
      revGrowthUp = true;
    }

    return DashboardKpis(
      totalStudents: totalStudents,
      activeStudents: activeStudents,
      totalTeachers: totalTeachers,
      totalStaff: totalStaff,
      totalClasses: totalClasses,
      totalPaymentsDue: due,
      totalPaymentsCollected: collected,
      thisMonthRevenue: thisMonthCollected,
      lastMonthRevenue: lastMonthCollected,
      unpaidAmount: unpaid,
      revenueGrowth: revGrowth,
      revenueGrowthLabel: "vs mois dernier",
      revenueGrowthUp: revGrowthUp,
      monthlyGrowth: revGrowth,
      monthlyGrowthTrend: revGrowth,
      monthlyGrowthLabel: "vs mois dernier",
      monthlyGrowthUp: revGrowthUp,
      studentTargetDiff: activeStudents.toDouble(),
      studentTargetLabel: "élèves actifs",
      studentTargetUp: activeStudents >= totalStudents,
      teacherStaffGrowth: totalTeachers.toDouble(),
      teacherStaffGrowthLabel: "profs",
      teacherStaffGrowthUp: true,
      recoveryRate: recovery,
      recoveryRateDiff: unpaid,
      recoveryRateLabel: unpaid > 0 ? "reste à recouvrer" : "aucun impayé",
      recoveryRateUp: unpaid == 0,
    );
  }

  Future<Map<String, CashflowIntervalData>> _loadCashflows(String schoolId) async {
    final now = DateTime.now();

    List<Map<String, dynamic>> payments = [];
    try {
      final resp = await _supabase
          .from('payments')
          .select('id, amount, status, paid_at, due_date, created_at, school_id')
          .eq('school_id', schoolId);
      payments = List<Map<String, dynamic>>.from(resp as List);
    } catch (e) {
      debugPrint('Error loading payments in _loadCashflows: $e');
    }

    DateTime? getPaymentDate(Map<String, dynamic> p) {
      if (p['paid_at'] != null) {
        final d = DateTime.tryParse(p['paid_at'].toString());
        if (d != null) return d.toLocal();
      }
      if (p['created_at'] != null) {
        final d = DateTime.tryParse(p['created_at'].toString());
        if (d != null) return d.toLocal();
      }
      if (p['due_date'] != null) {
        final d = DateTime.tryParse(p['due_date'].toString());
        if (d != null) return d.toLocal();
      }
      return null;
    }

    // ─────────────────────────────────────────────────────────────────
    // 1. WEEKLY CASHFLOW (Current week: Sunday -> Saturday)
    // ─────────────────────────────────────────────────────────────────
    final sunday = now.weekday == DateTime.sunday
        ? DateTime(now.year, now.month, now.day)
        : DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday));

    const dayShortLabels = ['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];
    const dayFullNames = ['Dimanche', 'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'];
    const monthShortNames = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin', 'Juil', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc'];

    final weeklyPoints = <CashflowPoint>[];
    double weeklyTotalCollected = 0;
    double weeklyReimbursed = 0;
    double weeklyPeakAmount = 0;
    String weeklyPeakDate = '';
    double weeklyPeakX = 0;

    for (int i = 0; i < 7; i++) {
      final currentDay = sunday.add(Duration(days: i));
      double dayCollected = 0;

      for (final p in payments) {
        final status = (p['status'] ?? '').toString().toLowerCase();
        final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
        final date = getPaymentDate(p);

        if (date != null &&
            date.year == currentDay.year &&
            date.month == currentDay.month &&
            date.day == currentDay.day) {
          if (status == 'paid') {
            dayCollected += amt;
          } else if (status == 'cancelled' || status == 'refunded') {
            weeklyReimbursed += amt;
          }
        }
      }

      weeklyTotalCollected += dayCollected;
      if (dayCollected > weeklyPeakAmount) {
        weeklyPeakAmount = dayCollected;
        weeklyPeakDate = '${dayFullNames[i]} ${currentDay.day} ${monthShortNames[currentDay.month - 1]} ${currentDay.year}';
        weeklyPeakX = i.toDouble();
      }

      weeklyPoints.add(
        CashflowPoint(
          x: i.toDouble(),
          y: dayCollected,
          amount: dayCollected,
          label: dayShortLabels[i],
          fullDate: '${dayFullNames[i]} ${currentDay.day} ${monthShortNames[currentDay.month - 1]} ${currentDay.year}',
        ),
      );
    }

    if (weeklyPeakDate.isEmpty) {
      weeklyPeakDate = '${dayFullNames[now.weekday % 7]} ${now.day} ${monthShortNames[now.month - 1]} ${now.year}';
      weeklyPeakX = (now.weekday % 7).toDouble();
    }

    final weeklyMaxY = weeklyPeakAmount > 0
        ? (weeklyPeakAmount * 1.25).ceilToDouble()
        : 1000.0;

    // ─────────────────────────────────────────────────────────────────
    // 2. MONTHLY CASHFLOW (12 Months of current year)
    // ─────────────────────────────────────────────────────────────────
    const monthFullNames = [
      'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
      'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'
    ];

    final monthlyPoints = <CashflowPoint>[];
    double monthlyTotalCollected = 0;
    double monthlyReimbursed = 0;
    double monthlyPeakAmount = 0;
    String monthlyPeakDate = '';
    double monthlyPeakX = 0;

    for (int m = 1; m <= 12; m++) {
      double monthCollected = 0;

      for (final p in payments) {
        final status = (p['status'] ?? '').toString().toLowerCase();
        final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
        final date = getPaymentDate(p);

        if (date != null && date.year == now.year && date.month == m) {
          if (status == 'paid') {
            monthCollected += amt;
          } else if (status == 'cancelled' || status == 'refunded') {
            monthlyReimbursed += amt;
          }
        }
      }

      monthlyTotalCollected += monthCollected;
      final idx = m - 1;
      if (monthCollected > monthlyPeakAmount) {
        monthlyPeakAmount = monthCollected;
        monthlyPeakDate = '${monthFullNames[idx]} ${now.year}';
        monthlyPeakX = idx.toDouble();
      }

      monthlyPoints.add(
        CashflowPoint(
          x: idx.toDouble(),
          y: monthCollected,
          amount: monthCollected,
          label: monthShortNames[idx],
          fullDate: '${monthFullNames[idx]} ${now.year}',
        ),
      );
    }

    if (monthlyPeakDate.isEmpty) {
      monthlyPeakDate = '${monthFullNames[now.month - 1]} ${now.year}';
      monthlyPeakX = (now.month - 1).toDouble();
    }

    final monthlyMaxY = monthlyPeakAmount > 0
        ? (monthlyPeakAmount * 1.25).ceilToDouble()
        : 1000.0;

    // ─────────────────────────────────────────────────────────────────
    // 3. ANNUAL CASHFLOW (Recent 5 years up to current year)
    // ─────────────────────────────────────────────────────────────────
    final startYear = now.year - 4;
    final annualPoints = <CashflowPoint>[];
    double annualTotalCollected = 0;
    double annualReimbursed = 0;
    double annualPeakAmount = 0;
    String annualPeakDate = '';
    double annualPeakX = 0;

    for (int y = startYear; y <= now.year; y++) {
      double yearCollected = 0;

      for (final p in payments) {
        final status = (p['status'] ?? '').toString().toLowerCase();
        final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
        final date = getPaymentDate(p);

        if (date != null && date.year == y) {
          if (status == 'paid') {
            yearCollected += amt;
          } else if (status == 'cancelled' || status == 'refunded') {
            annualReimbursed += amt;
          }
        }
      }

      annualTotalCollected += yearCollected;
      final idx = y - startYear;
      if (yearCollected > annualPeakAmount) {
        annualPeakAmount = yearCollected;
        annualPeakDate = 'Année $y';
        annualPeakX = idx.toDouble();
      }

      annualPoints.add(
        CashflowPoint(
          x: idx.toDouble(),
          y: yearCollected,
          amount: yearCollected,
          label: '$y',
          fullDate: 'Année $y',
        ),
      );
    }

    if (annualPeakDate.isEmpty) {
      annualPeakDate = 'Année ${now.year}';
      annualPeakX = (annualPoints.length - 1).toDouble();
    }

    final annualMaxY = annualPeakAmount > 0
        ? (annualPeakAmount * 1.25).ceilToDouble()
        : 5000.0;

    return {
      'weekly': CashflowIntervalData(
        points: weeklyPoints,
        minY: 0,
        maxY: weeklyMaxY,
        reimbursedAmount: weeklyReimbursed,
        totalCollected: weeklyTotalCollected,
        peakAmount: weeklyPeakAmount,
        peakDate: weeklyPeakDate,
        peakX: weeklyPeakX,
      ),
      'monthly': CashflowIntervalData(
        points: monthlyPoints,
        minY: 0,
        maxY: monthlyMaxY,
        reimbursedAmount: monthlyReimbursed,
        totalCollected: monthlyTotalCollected,
        peakAmount: monthlyPeakAmount,
        peakDate: monthlyPeakDate,
        peakX: monthlyPeakX,
      ),
      'annual': CashflowIntervalData(
        points: annualPoints,
        minY: 0,
        maxY: annualMaxY,
        reimbursedAmount: annualReimbursed,
        totalCollected: annualTotalCollected,
        peakAmount: annualPeakAmount,
        peakDate: annualPeakDate,
        peakX: annualPeakX,
      ),
    };
  }

  Future<List<CategoryBreakdownItem>> _loadCategoryBreakdown(String schoolId) async {
    try {
      final paymentsResp = await _supabase
          .from('payments')
          .select('amount, status, payment_plans(category, description)')
          .eq('school_id', schoolId);

      final categoryTotals = <String, double>{};
      double grandTotal = 0;

      for (final p in (paymentsResp as List)) {
        final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
        final plan = p['payment_plans'] as Map<String, dynamic>?;
        final cat = (plan?['category'] ?? plan?['description'] ?? 'scolarite').toString().toLowerCase();

        categoryTotals[cat] = (categoryTotals[cat] ?? 0.0) + amt;
        grandTotal += amt;
      }

      // If no payments found, query payment_plans directly
      if (grandTotal == 0) {
        final plans = await _supabase
            .from('payment_plans')
            .select('category, description, amount_total')
            .eq('school_id', schoolId);

        for (final p in (plans as List)) {
          final amt = (p['amount_total'] as num?)?.toDouble() ?? 0.0;
          final cat = (p['category'] ?? p['description'] ?? 'scolarite').toString().toLowerCase();
          categoryTotals[cat] = (categoryTotals[cat] ?? 0.0) + amt;
          grandTotal += amt;
        }
      }

      if (grandTotal > 0) {
        int getCategoryColor(String key, int index) {
          final k = key.toLowerCase();
          if (k.contains('scolarite') || k.contains('scolaire')) return 0xFF6D4CF6; // Royal Purple
          if (k.contains('cantine') || k.contains('repas') || k.contains('restauration')) return 0xFFF59E0B; // Amber Orange
          if (k.contains('transport') || k.contains('bus')) return 0xFF0284C7; // Ocean Blue
          if (k.contains('inscription') || k.contains('matricule')) return 0xFF10B981; // Emerald Green
          if (k.contains('uniforme') || k.contains('tenue')) return 0xFFEC4899; // Rose Pink
          if (k.contains('activite') || k.contains('sport') || k.contains('club')) return 0xFF8B5CF6; // Violet

          const distinctCategoryPalette = [
            0xFF6D4CF6, // Purple
            0xFFF59E0B, // Amber Orange
            0xFF0284C7, // Ocean Blue
            0xFF10B981, // Emerald Green
            0xFFEC4899, // Rose Pink
            0xFF06B6D4, // Cyan
            0xFF8B5CF6, // Violet
            0xFFE11D48, // Crimson
            0xFF84CC16, // Lime
          ];
          return distinctCategoryPalette[index % distinctCategoryPalette.length];
        }

        int cIdx = 0;
        return categoryTotals.entries.map((e) {
          final col = getCategoryColor(e.key, cIdx);
          cIdx++;
          String label;
          switch (e.key) {
            case 'scolarite':
              label = 'Frais de Scolarité';
              break;
            case 'cantine':
              label = 'Cantine & Restauration';
              break;
            case 'transport':
              label = 'Transport Scolaire';
              break;
            case 'inscription':
              label = 'Frais d\'Inscription';
              break;
            case 'uniforme':
              label = 'Uniforme & Tenues';
              break;
            case 'activites':
              label = 'Activités Extrascolaires';
              break;
            default:
              label = e.key.isNotEmpty ? e.key[0].toUpperCase() + e.key.substring(1) : 'Autres';
          }
          return CategoryBreakdownItem(
            label: label,
            amount: e.value,
            percentage: ((e.value / grandTotal) * 100).roundToDouble(),
            colorValue: col,
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('Error loading real category breakdown: $e');
    }

    return const [];
  }

  Future<List<FiliereDistributionItem>> _loadFiliereDistribution(String schoolId) async {
    try {
      final classesResp = await _supabase
          .from('classes')
          .select('id, name, capacity, section_id, sections(id, name, code, color, display_order), niveau_id, niveaux(id, name, code, cycle, display_order)')
          .eq('school_id', schoolId);

      final classList = List<Map<String, dynamic>>.from(classesResp as List);
      if (classList.isEmpty) return const [];

      final classIds = classList.map((c) => c['id'].toString()).toList();
      final enrollmentsResp = await _supabase
          .from('enrollments')
          .select('class_id')
          .inFilter('class_id', classIds);

      final Map<String, int> classEnrollmentCounts = {};
      int totalEnrolled = 0;
      for (final e in (enrollmentsResp as List)) {
        final cid = e['class_id']?.toString();
        if (cid != null) {
          classEnrollmentCounts[cid] = (classEnrollmentCounts[cid] ?? 0) + 1;
          totalEnrolled++;
        }
      }

      if (totalEnrolled == 0) return const [];

      final Map<String, int> counts = {};

      for (final c in classList) {
        final sec = c['sections'] as Map<String, dynamic>?;
        final niv = c['niveaux'] as Map<String, dynamic>?;

        final label = sec?['name'] ?? (niv?['cycle'] == 'base' ? 'Cycle de Base' : 'Tronc Commun');
        final cid = c['id']?.toString() ?? '';
        final classCount = classEnrollmentCounts[cid] ?? 0;

        if (classCount > 0) {
          counts[label] = (counts[label] ?? 0) + classCount;
        }
      }

      final grandTotal = counts.values.fold<int>(0, (a, b) => a + b);
      if (grandTotal > 0) {
        int getFiliereColor(String name, int index) {
          final lower = name.toLowerCase();
          if (lower.contains('math')) return 0xFF6D4CF6; // Mathématiques: Royal Purple
          if (lower.contains('expérimentale') || lower.contains('science exp') || lower.contains('svt')) {
            return 0xFF10B981; // Sciences Expérimentales: Emerald Green
          }
          if (lower.contains('informatique') || lower.contains('info')) {
            return 0xFF0284C7; // Informatique: Sky Blue
          }
          if (lower.contains('économie') || lower.contains('gestion') || lower.contains('éco')) {
            return 0xFFF59E0B; // Éco & Gestion: Amber Orange
          }
          if (lower.contains('lettre') || lower.contains('littéraire')) {
            return 0xFFEC4899; // Lettres: Rose Pink
          }
          if (lower.contains('technique') || lower.contains('techno')) {
            return 0xFF8B5CF6; // Sciences Techniques: Violet
          }
          if (lower.contains('base') || lower.contains('collège')) {
            return 0xFF06B6D4; // Cycle de Base: Cyan / Teal
          }
          if (lower.contains('commun') || lower.contains('tronc')) {
            return 0xFF64748B; // Tronc Commun: Slate Grey
          }

          const distinctColors = [
            0xFF6D4CF6, // Purple
            0xFF10B981, // Emerald Green
            0xFF0284C7, // Ocean Blue
            0xFFF59E0B, // Amber Orange
            0xFFEC4899, // Rose Pink
            0xFF8B5CF6, // Violet
            0xFF06B6D4, // Cyan
            0xFF64748B, // Slate
            0xFFE11D48, // Crimson
            0xFF84CC16, // Lime
          ];
          return distinctColors[index % distinctColors.length];
        }

        int cIdx = 0;
        final sorted = counts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return sorted.map((entry) {
          final color = getFiliereColor(entry.key, cIdx);
          cIdx++;
          final pct = (entry.value / grandTotal * 100).roundToDouble();
          return FiliereDistributionItem(
            label: entry.key,
            count: entry.value,
            percentage: pct,
            colorValue: color,
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('Error loading real filiere distribution: $e');
    }

    return const [];
  }

  Future<List<DashboardCalendarEvent>> _loadCalendarEvents(String schoolId) async {
    try {
      final slots = await _supabase
          .from('timetable_slots')
          .select('id, day_of_week, start_time, end_time, room, teacher_name, timetable_type, subject_offerings(id, class_id, classes(id, name, school_id), subjects(name), users(full_name))')
          .limit(50);

      final events = <DashboardCalendarEvent>[];
      for (final s in (slots as List)) {
        final off = s['subject_offerings'] as Map<String, dynamic>?;
        final cls = off?['classes'] as Map<String, dynamic>?;
        if (cls?['school_id'] != null && cls?['school_id'] != schoolId) continue;

        final subj = off?['subjects'] as Map<String, dynamic>?;
        final usr = off?['users'] as Map<String, dynamic>?;
        final teacherName = s['teacher_name'] ?? usr?['full_name'] ?? 'Professeur';
        final teacherInitials = _getInitials(teacherName);
        final title = subj?['name'] ?? 'Séance de cours';
        final isExam = (s['timetable_type'] ?? '') == 'exam';

        // Parse day of week
        int dow = 1;
        final rawDow = s['day_of_week'];
        if (rawDow is int) {
          dow = rawDow;
        } else if (rawDow is String) {
          switch (rawDow.toLowerCase()) {
            case 'monday': dow = 1; break;
            case 'tuesday': dow = 2; break;
            case 'wednesday': dow = 3; break;
            case 'thursday': dow = 4; break;
            case 'friday': dow = 5; break;
            case 'saturday': dow = 6; break;
            case 'sunday': dow = 7; break;
          }
        }

        events.add(DashboardCalendarEvent(
          id: s['id']?.toString() ?? '',
          title: title,
          time: '${s['start_time'] ?? '08:00'} - ${s['end_time'] ?? '10:00'}',
          duration: '90m',
          room: s['room'] ?? 'Salle 1',
          classId: cls?['id']?.toString() ?? '',
          className: cls?['name']?.toString() ?? 'Classe',
          teacherName: teacherName,
          teacherInitials: teacherInitials,
          isExam: isExam,
          dayOfWeek: dow,
        ));
      }

      return events;
    } catch (e) {
      debugPrint('Error loading calendar events: $e');
      return const [];
    }
  }

  Future<List<AttendanceLevelItem>> _loadAttendanceLevels(String schoolId) async {
    try {
      // 1. Fetch real active niveaux ordered by display_order
      final niveauxResp = await _supabase
          .from('niveaux')
          .select('id, name, code, display_order')
          .eq('is_active', true)
          .order('display_order');

      final niveauxList = List<Map<String, dynamic>>.from(niveauxResp as List);
      if (niveauxList.isEmpty) return const [];

      // 2. Fetch classes for this school
      final classesResp = await _supabase
          .from('classes')
          .select('id, niveau_id, capacity')
          .eq('school_id', schoolId);

      // Map classId -> niveauId
      final Map<String, String> classToNiveau = {};
      for (final c in (classesResp as List)) {
        final cid = c['id']?.toString();
        final nid = c['niveau_id']?.toString();
        if (cid != null && nid != null) {
          classToNiveau[cid] = nid;
        }
      }

      // If this school has NO classes, return empty list (never invent fake cohorts)
      if (classToNiveau.isEmpty) return const [];

      // 3. Fetch enrollments for classes of this school to get student count per niveau
      final enrollmentsResp = await _supabase
          .from('enrollments')
          .select('id, class_id')
          .inFilter('class_id', classToNiveau.keys.toList());

      final Map<String, String> enrollmentToNiveau = {};
      final Map<String, int> niveauStudentCounts = {};
      for (final e in (enrollmentsResp as List)) {
        final eid = e['id']?.toString();
        final cid = e['class_id']?.toString();
        if (eid != null && cid != null && classToNiveau.containsKey(cid)) {
          final nid = classToNiveau[cid]!;
          enrollmentToNiveau[eid] = nid;
          niveauStudentCounts[nid] = (niveauStudentCounts[nid] ?? 0) + 1;
        }
      }

      // If no students are enrolled in this school's classes, return empty list
      if (enrollmentToNiveau.isEmpty) return const [];

      // 4. Fetch absences strictly for this school's enrolled students
      final Map<String, double> absenceHoursByNiveau = {};
      final enrollmentIds = enrollmentToNiveau.keys.toList();
      if (enrollmentIds.isNotEmpty) {
        final absencesResp = await _supabase
            .from('absence_records')
            .select('enrollment_id, hours_absent')
            .inFilter('enrollment_id', enrollmentIds);

        for (final a in (absencesResp as List)) {
          final eid = a['enrollment_id']?.toString();
          final hours = (a['hours_absent'] as num?)?.toDouble() ?? 2.0;
          if (eid != null && enrollmentToNiveau.containsKey(eid)) {
            final nid = enrollmentToNiveau[eid]!;
            absenceHoursByNiveau[nid] = (absenceHoursByNiveau[nid] ?? 0.0) + hours;
          }
        }
      }

      // 5. Calculate real ABSENCE rate per niveau (only for niveaux present in this school with enrolled students)
      final List<AttendanceLevelItem> items = [];
      for (final n in niveauxList) {
        final nid = n['id']?.toString();
        if (nid == null || !classToNiveau.values.contains(nid)) continue;

        final studentCount = niveauStudentCounts[nid] ?? 0;
        if (studentCount == 0) continue;

        final name = (n['name'] ?? n['code'] ?? 'Niveau').toString();
        final absenceHours = absenceHoursByNiveau[nid] ?? 0.0;

        // Nominal monthly class hours = 120 hrs per student
        final totalExpectedHours = studentCount * 120.0;
        final rawAbsenceRate = totalExpectedHours > 0
            ? (absenceHours / totalExpectedHours).clamp(0.0, 1.0)
            : 0.0;

        items.add(AttendanceLevelItem(
          levelName: name,
          rate: rawAbsenceRate,
          label: '${(rawAbsenceRate * 100).toStringAsFixed(1)}%',
        ));
      }

      return items;
    } catch (e) {
      debugPrint('Error loading real attendance levels: $e');
      return const [];
    }
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return 'P';
    if (parts.length == 1) return parts[0].substring(0, math.min(2, parts[0].length)).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  DashboardState _buildFallbackState({String? error}) {
    return DashboardState(
      kpis: DashboardKpis(
        totalStudents: 0,
        totalTeachers: 0,
        totalStaff: 0,
        totalClasses: 0,
        totalPaymentsCollected: 0,
        totalPaymentsDue: 0,
        recoveryRate: 0.0,
      ),
      weeklyCashflow: CashflowIntervalData(
        points: const [],
        minY: 0,
        maxY: 1000,
        reimbursedAmount: 0,
        totalCollected: 0,
        peakAmount: 0,
        peakDate: '',
        peakX: 0,
      ),
      monthlyCashflow: CashflowIntervalData(
        points: const [],
        minY: 0,
        maxY: 1000,
        reimbursedAmount: 0,
        totalCollected: 0,
        peakAmount: 0,
        peakDate: '',
        peakX: 0,
      ),
      annualCashflow: CashflowIntervalData(
        points: const [],
        minY: 0,
        maxY: 1000,
        reimbursedAmount: 0,
        totalCollected: 0,
        peakAmount: 0,
        peakDate: '',
        peakX: 0,
      ),
      categories: const [],
      filieres: const [],
      events: const [],
      attendanceLevels: const [],
      isLoading: false,
      error: error,
      lastUpdated: DateTime.now(),
    );
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await _loadDashboard());
  }
}
