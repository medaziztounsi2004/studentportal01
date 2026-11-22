class DashboardKpis {
  final int totalStudents;
  final int activeStudents;
  final int totalTeachers;
  final int totalStaff;
  final int totalClasses;
  final int openSuggestions;
  final double totalPaymentsDue;
  final double totalPaymentsCollected;
  final double thisMonthRevenue;
  final double lastMonthRevenue;
  final double unpaidAmount;
  final double attendanceRate;
  final int studentsAtRisk;
  final double avgSemesterGrade;

  // Real trend & growth fields
  final double revenueGrowth;
  final String revenueGrowthLabel;
  final bool revenueGrowthUp;

  final double monthlyGrowth;
  final double monthlyGrowthTrend;
  final String monthlyGrowthLabel;
  final bool monthlyGrowthUp;

  final double studentTargetDiff;
  final String studentTargetLabel;
  final bool studentTargetUp;

  final double teacherStaffGrowth;
  final String teacherStaffGrowthLabel;
  final bool teacherStaffGrowthUp;

  final double recoveryRate;
  final double recoveryRateDiff;
  final String recoveryRateLabel;
  final bool recoveryRateUp;

  DashboardKpis({
    this.totalStudents = 0,
    this.activeStudents = 0,
    this.totalTeachers = 0,
    this.totalStaff = 0,
    this.totalClasses = 0,
    this.openSuggestions = 0,
    this.totalPaymentsDue = 0,
    this.totalPaymentsCollected = 0,
    this.thisMonthRevenue = 0,
    this.lastMonthRevenue = 0,
    this.unpaidAmount = 0,
    this.attendanceRate = 100,
    this.studentsAtRisk = 0,
    this.avgSemesterGrade = 0,
    this.revenueGrowth = 0.0,
    this.revenueGrowthLabel = "vs mois dernier",
    this.revenueGrowthUp = true,
    this.monthlyGrowth = 0.0,
    this.monthlyGrowthTrend = 0.0,
    this.monthlyGrowthLabel = "vs mois dernier",
    this.monthlyGrowthUp = true,
    this.studentTargetDiff = 0.0,
    this.studentTargetLabel = "actifs",
    this.studentTargetUp = true,
    this.teacherStaffGrowth = 0.0,
    this.teacherStaffGrowthLabel = "profs",
    this.teacherStaffGrowthUp = true,
    this.recoveryRate = 0.0,
    this.recoveryRateDiff = 0.0,
    this.recoveryRateLabel = "du total facturé",
    this.recoveryRateUp = true,
  });

  factory DashboardKpis.fromJson(Map<String, dynamic> json) {
    final totalDue = (json['total_payments_due'] ?? 0).toDouble();
    final totalPaid = (json['total_payments_collected'] ?? 0).toDouble();
    final thisMonth = (json['this_month_revenue'] ?? 0).toDouble();
    final lastMonth = (json['last_month_revenue'] ?? 0).toDouble();
    final unpaid = (json['unpaid_amount'] ?? (totalDue - totalPaid).clamp(0.0, double.infinity)).toDouble();
    final recovery = totalDue > 0 ? (totalPaid / totalDue * 100) : (totalPaid > 0 ? 100.0 : 0.0);
    final totalStudents = (json['total_students'] ?? 0) as int;
    final activeStudents = (json['active_students'] ?? totalStudents) as int;

    return DashboardKpis(
      totalStudents: totalStudents,
      activeStudents: activeStudents,
      totalTeachers: json['total_teachers'] ?? 0,
      totalStaff: json['total_staff'] ?? 0,
      totalClasses: json['total_classes'] ?? 0,
      openSuggestions: json['open_suggestions'] ?? 0,
      totalPaymentsDue: totalDue,
      totalPaymentsCollected: totalPaid,
      thisMonthRevenue: thisMonth,
      lastMonthRevenue: lastMonth,
      unpaidAmount: unpaid,
      attendanceRate: (json['attendance_rate'] ?? 100).toDouble(),
      studentsAtRisk: json['students_at_risk'] ?? 0,
      avgSemesterGrade: (json['avg_semester_grade'] ?? 0).toDouble(),
      revenueGrowth: (json['revenue_growth'] ?? 0.0).toDouble(),
      revenueGrowthLabel: json['revenue_growth_label'] ?? "vs mois dernier",
      revenueGrowthUp: json['revenue_growth_up'] ?? true,
      monthlyGrowth: (json['monthly_growth'] ?? 0.0).toDouble(),
      monthlyGrowthTrend: (json['monthly_growth_trend'] ?? 0.0).toDouble(),
      monthlyGrowthLabel: json['monthly_growth_label'] ?? "vs mois dernier",
      monthlyGrowthUp: json['monthly_growth_up'] ?? true,
      studentTargetDiff: (json['student_target_diff'] ?? 0.0).toDouble(),
      studentTargetLabel: json['student_target_label'] ?? "actifs",
      studentTargetUp: json['student_target_up'] ?? true,
      teacherStaffGrowth: (json['teacher_staff_growth'] ?? 0.0).toDouble(),
      teacherStaffGrowthLabel: json['teacher_staff_growth_label'] ?? "profs",
      teacherStaffGrowthUp: json['teacher_staff_growth_up'] ?? true,
      recoveryRate: recovery,
      recoveryRateDiff: (json['recovery_rate_diff'] ?? 0.0).toDouble(),
      recoveryRateLabel: json['recovery_rate_label'] ?? "du total facturé",
      recoveryRateUp: json['recovery_rate_up'] ?? true,
    );
  }

  double get paymentProgress => totalPaymentsDue > 0 ? (totalPaymentsCollected / totalPaymentsDue * 100) : recoveryRate;
  double get outstandingPayments => totalPaymentsDue - totalPaymentsCollected;
}

class CashflowPoint {
  final double x;
  final double y;
  final double amount;
  final String label;
  final String fullDate;

  CashflowPoint({
    required this.x,
    required this.y,
    required this.amount,
    required this.label,
    required this.fullDate,
  });
}

class CashflowIntervalData {
  final List<CashflowPoint> points;
  final double minY;
  final double maxY;
  final double reimbursedAmount;
  final double totalCollected;
  final double peakAmount;
  final String peakDate;
  final double peakX;

  CashflowIntervalData({
    required this.points,
    this.minY = 0,
    this.maxY = 10,
    this.reimbursedAmount = 5133,
    this.totalCollected = 0,
    this.peakAmount = 0,
    this.peakDate = '',
    this.peakX = 0,
  });
}

class CategoryBreakdownItem {
  final String label;
  final double amount;
  final double percentage;
  final int colorValue;

  CategoryBreakdownItem({
    required this.label,
    required this.amount,
    required this.percentage,
    required this.colorValue,
  });
}

class FiliereDistributionItem {
  final String label;
  final int count;
  final double percentage;
  final int colorValue;

  FiliereDistributionItem({
    required this.label,
    required this.count,
    required this.percentage,
    required this.colorValue,
  });
}

class DashboardCalendarEvent {
  final String id;
  final String title;
  final String time;
  final String duration;
  final String room;
  final String classId;
  final String className;
  final String teacherName;
  final String teacherInitials;
  final String? teacherAvatarUrl;
  final bool isExam;
  final int dayOfWeek; // 1: Lun, 2: Mar, 3: Mer, 4: Jeu, 5: Ven, 6: Sam, 7: Dim

  DashboardCalendarEvent({
    required this.id,
    required this.title,
    required this.time,
    required this.duration,
    required this.room,
    required this.classId,
    required this.className,
    required this.teacherName,
    required this.teacherInitials,
    this.teacherAvatarUrl,
    this.isExam = false,
    required this.dayOfWeek,
  });
}

class AttendanceLevelItem {
  final String levelName;
  final double rate; // 0.0 to 1.0
  final String label; // "94%"

  AttendanceLevelItem({
    required this.levelName,
    required this.rate,
    required this.label,
  });
}

class AtRiskStudent {
  final String studentName;
  final String? studentCode;
  final String className;
  final String subjectName;
  final double absencePercent;
  final String status;

  AtRiskStudent({
    required this.studentName,
    this.studentCode,
    required this.className,
    required this.subjectName,
    required this.absencePercent,
    required this.status,
  });

  factory AtRiskStudent.fromJson(Map<String, dynamic> json) => AtRiskStudent(
    studentName: json['student_name'] ?? '',
    studentCode: json['student_code'],
    className: json['class_name'] ?? '',
    subjectName: json['subject_name'] ?? '',
    absencePercent: (json['absence_percent'] ?? 0).toDouble(),
    status: json['status'] ?? 'ok',
  );
}

class AbsenceTrend {
  final DateTime date;
  final String className;
  final String subjectName;
  final double totalHoursAbsent;
  final int studentsAbsent;

  AbsenceTrend({
    required this.date,
    required this.className,
    required this.subjectName,
    required this.totalHoursAbsent,
    required this.studentsAbsent,
  });

  factory AbsenceTrend.fromJson(Map<String, dynamic> json) => AbsenceTrend(
    date: DateTime.parse(json['date']),
    className: json['class_name'] ?? '',
    subjectName: json['subject_name'] ?? '',
    totalHoursAbsent: (json['total_hours_absent'] ?? 0).toDouble(),
    studentsAbsent: json['students_absent'] ?? 0,
  );
}

class GradeDistribution {
  final String semesterName;
  final String className;
  final String subjectName;
  final String gradeRange;
  final int studentCount;

  GradeDistribution({
    required this.semesterName,
    required this.className,
    required this.subjectName,
    required this.gradeRange,
    required this.studentCount,
  });

  factory GradeDistribution.fromJson(Map<String, dynamic> json) => GradeDistribution(
    semesterName: json['semester_name'] ?? '',
    className: json['class_name'] ?? '',
    subjectName: json['subject_name'] ?? '',
    gradeRange: json['grade_range'] ?? '',
    studentCount: json['student_count'] ?? 0,
  );
}

class PaymentSummary {
  final String studentName;
  final String? studentCode;
  final String className;
  final String planType;
  final double amountTotal;
  final double amountPaid;
  final double amountRemaining;
  final String currency;

  PaymentSummary({
    required this.studentName,
    this.studentCode,
    required this.className,
    required this.planType,
    required this.amountTotal,
    required this.amountPaid,
    required this.amountRemaining,
    required this.currency,
  });

  factory PaymentSummary.fromJson(Map<String, dynamic> json) => PaymentSummary(
    studentName: json['student_name'] ?? '',
    studentCode: json['student_code'],
    className: json['class_name'] ?? '',
    planType: json['plan_type'] ?? '',
    amountTotal: (json['amount_total'] ?? 0).toDouble(),
    amountPaid: (json['amount_paid'] ?? 0).toDouble(),
    amountRemaining: (json['amount_remaining'] ?? 0).toDouble(),
    currency: json['currency'] ?? 'DZD',
  );
}
