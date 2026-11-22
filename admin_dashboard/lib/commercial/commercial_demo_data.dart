import '../data/models/dashboard_models.dart';
import '../data/models/user_model.dart';
import '../presentation/providers/dashboard_provider.dart';

class CommercialAdminDemoData {
  static UserModel get demoDirectorUser => UserModel(
        id: 'dir-carthage-01',
        schoolId: 'carthage-01',
        role: 'school_admin',
        fullName: 'Dr. Mehdi Chebbi',
        email: 'direction@carthage-international.tn',
        phone: '+216 71 888 120',
        isActive: true,
        accountStatus: 'active',
        forcePasswordChange: false,
        createdAt: DateTime(2026, 1, 15),
        updatedAt: DateTime(2026, 11, 18),
      );

  static Map<String, dynamic> get demoSchoolBranding => {
        'id': 'carthage-01',
        'name': 'Lycée International de Carthage',
        'logo_url': null,
        'primary_color': '#2563EB',
        'secondary_color': '#6D4CF6',
      };

  static DashboardState buildDashboardState() {
    final now = DateTime.now();
    return DashboardState(
      isLoading: false,
      kpis: DashboardKpis(
        totalStudents: 580,
        activeStudents: 578,
        totalTeachers: 35,
        totalStaff: 12,
        totalClasses: 22,
        openSuggestions: 1,
        totalPaymentsDue: 493000.0,
        totalPaymentsCollected: 458000.0,
        thisMonthRevenue: 42000.0,
        lastMonthRevenue: 37500.0,
        unpaidAmount: 35000.0,
        attendanceRate: 98.4,
        studentsAtRisk: 2,
        avgSemesterGrade: 14.85,
        revenueGrowth: 12.0,
        monthlyGrowth: 12.0,
        monthlyGrowthTrend: 12.0,
        monthlyGrowthUp: true,
        recoveryRate: 92.9,
        recoveryRateDiff: 35000.0,
        recoveryRateUp: true,
      ),
      weeklyCashflow: CashflowIntervalData(
        points: [
          CashflowPoint(x: 1, y: 12500, amount: 12500, label: 'Lun', fullDate: '10 Nov'),
          CashflowPoint(x: 2, y: 18200, amount: 18200, label: 'Mar', fullDate: '11 Nov'),
          CashflowPoint(x: 3, y: 15400, amount: 15400, label: 'Mer', fullDate: '12 Nov'),
          CashflowPoint(x: 4, y: 22100, amount: 22100, label: 'Jeu', fullDate: '13 Nov'),
          CashflowPoint(x: 5, y: 28900, amount: 28900, label: 'Ven', fullDate: '14 Nov'),
          CashflowPoint(x: 6, y: 8400, amount: 8400, label: 'Sam', fullDate: '15 Nov'),
        ],
        totalCollected: 105500,
        peakAmount: 28900,
        peakDate: '14 Nov',
      ),
      monthlyCashflow: CashflowIntervalData(
        points: [
          CashflowPoint(x: 1, y: 65000, amount: 65000, label: 'Juil', fullDate: 'Juillet 2026'),
          CashflowPoint(x: 2, y: 142000, amount: 142000, label: 'Août', fullDate: 'Août 2026'),
          CashflowPoint(x: 3, y: 195000, amount: 195000, label: 'Sept', fullDate: 'Septembre 2026'),
          CashflowPoint(x: 4, y: 78000, amount: 78000, label: 'Oct', fullDate: 'Octobre 2026'),
          CashflowPoint(x: 5, y: 85000, amount: 85000, label: 'Nov', fullDate: 'Novembre 2026'),
        ],
        totalCollected: 458000,
        peakAmount: 195000,
        peakDate: 'Septembre 2026',
      ),
      annualCashflow: CashflowIntervalData(
        points: [
          CashflowPoint(x: 1, y: 380000, amount: 380000, label: '2024-2025', fullDate: '2024-2025'),
          CashflowPoint(x: 2, y: 493000, amount: 493000, label: '2025-2026', fullDate: '2025-2026'),
        ],
        totalCollected: 493000,
        peakAmount: 493000,
        peakDate: '2025-2026',
      ),
      categories: [
        CategoryBreakdownItem(
          label: 'Frais de Scolarité',
          amount: 380000,
          percentage: 78.0,
          colorValue: 0xFF2563EB,
        ),
        CategoryBreakdownItem(
          label: 'Restauration & Cantine',
          amount: 58000,
          percentage: 12.0,
          colorValue: 0xFF10B981,
        ),
        CategoryBreakdownItem(
          label: 'Transport Scolaire',
          amount: 48000,
          percentage: 10.0,
          colorValue: 0xFFF59E0B,
        ),
      ],
      filieres: [
        FiliereDistributionItem(
          label: 'Baccalauréat Mathématiques',
          count: 145,
          percentage: 25.0,
          colorValue: 0xFF2563EB,
        ),
        FiliereDistributionItem(
          label: 'Baccalauréat Sciences Exp.',
          count: 165,
          percentage: 28.5,
          colorValue: 0xFF6D4CF6,
        ),
        FiliereDistributionItem(
          label: 'Baccalauréat Économie & Gestion',
          count: 120,
          percentage: 20.7,
          colorValue: 0xFF10B981,
        ),
        FiliereDistributionItem(
          label: 'Collège Pilote & Secondaire',
          count: 150,
          percentage: 25.8,
          colorValue: 0xFFF59E0B,
        ),
      ],
      events: [
        DashboardCalendarEvent(
          id: 'ev-01',
          title: 'Mathématiques Approfondies',
          time: '08:00 - 10:00',
          duration: '2h',
          room: 'Salle B12 - Pôle Sciences',
          classId: 'cls-bac-math-1',
          className: '4ème Bac Maths 1',
          teacherName: 'Prof. Karim Trabelsi',
          teacherInitials: 'KT',
          isExam: false,
          dayOfWeek: now.weekday,
        ),
        DashboardCalendarEvent(
          id: 'ev-02',
          title: 'Physique & Chimie Expérimentale',
          time: '10:15 - 12:15',
          duration: '2h',
          room: 'Laboratoire L3',
          classId: 'cls-bac-sc-2',
          className: '4ème Bac Sciences 2',
          teacherName: 'Mme. Salma Ben Amor',
          teacherInitials: 'SA',
          isExam: false,
          dayOfWeek: now.weekday,
        ),
        DashboardCalendarEvent(
          id: 'ev-03',
          title: 'Philosophie & Épistémologie',
          time: '14:00 - 16:00',
          duration: '2h',
          room: 'Amphithéâtre Carthage',
          classId: 'cls-bac-math-1',
          className: '4ème Bac Maths 1',
          teacherName: 'Dr. Youssef Chahed',
          teacherInitials: 'YC',
          isExam: false,
          dayOfWeek: now.weekday,
        ),
      ],
      attendanceLevels: [
        AttendanceLevelItem(levelName: '7ème & 8ème Collège', rate: 0.991, label: '99.1%'),
        AttendanceLevelItem(levelName: '9ème Base Pilote', rate: 0.988, label: '98.8%'),
        AttendanceLevelItem(levelName: '1ère & 2ème Secondaire', rate: 0.982, label: '98.2%'),
        AttendanceLevelItem(levelName: '3ème & 4ème Baccalauréat', rate: 0.985, label: '98.5%'),
      ],
      atRiskStudents: [
        AtRiskStudent(
          studentName: 'Yassine M.',
          studentCode: 'ETU-2026-084',
          className: '3ème Sciences 1',
          subjectName: 'Mathématiques',
          absencePercent: 12.5,
          status: 'warning',
        ),
      ],
    );
  }
}
