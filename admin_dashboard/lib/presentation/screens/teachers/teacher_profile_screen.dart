import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../widgets/admin_sidebar.dart';
import '../../widgets/ios_loader.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/admin_sort_dropdown.dart';
import '../../providers/undo_redo_provider.dart';
import '../../widgets/feedback_pill.dart';
import 'professors_screen.dart' show professorsProvider;

const _brand = Color(0xFF655DD5);
const _brandLight = Color(0xFFEEECFB);

class TeacherProfileScreen extends ConsumerStatefulWidget {
  final String teacherId;
  const TeacherProfileScreen({super.key, required this.teacherId});

  @override
  ConsumerState<TeacherProfileScreen> createState() => _TeacherProfileScreenState();
}

class _TeacherProfileScreenState extends ConsumerState<TeacherProfileScreen> {
  bool _loading = true;
  bool _showWeeklySchedule = false;
  String _classSortKey = 'name_asc';
  Map<String, dynamic>? _user;
  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _classDetails = [];
  List<Map<String, dynamic>> _timetableToday = [];
  List<Map<String, dynamic>> _timetableAllSlots = [];
  Set<String> _subjects = {};
  Set<String> _niveaux = {};
  Map<String, String> _niveauFilieres = {};
  String _mainSubject = '';
  String _hireDate = '-';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  int _parseDayOfWeek(dynamic value) {
    if (value is int) return value.clamp(1, 7);
    if (value is String) {
      switch (value.toLowerCase().trim()) {
        case 'monday':
        case 'lundi':
        case '1':
          return 1;
        case 'tuesday':
        case 'mardi':
        case '2':
          return 2;
        case 'wednesday':
        case 'mercredi':
        case '3':
          return 3;
        case 'thursday':
        case 'jeudi':
        case '4':
          return 4;
        case 'friday':
        case 'vendredi':
        case '5':
          return 5;
        case 'saturday':
        case 'samedi':
        case '6':
          return 6;
        case 'sunday':
        case 'dimanche':
        case '7':
          return 7;
      }
    }
    return 1;
  }

  int _parseTimeToMinutes(String? timeStr) {
    if (timeStr == null || !timeStr.contains(':')) return 0;
    final parts = timeStr.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    return h * 60 + m;
  }

  String _formatShortTime(String? timeStr) {
    if (timeStr == null || timeStr.length < 5) return '??:??';
    return timeStr.substring(0, 5);
  }

  Future<void> _loadData() async {
    _assignments = [];
    _classDetails = [];
    _timetableToday = [];
    _timetableAllSlots = [];
    _subjects = {};
    _niveaux = {};
    _niveauFilieres = {};
    _mainSubject = '';
    _hireDate = '-';

    final supabase = SupabaseConfig.adminClient;
    try {
      _user = await supabase
          .from('users')
          .select('id, full_name, email, phone, photo_url, role, is_active, created_at, gender, nationality, school_id')
          .eq('id', widget.teacherId)
          .maybeSingle();

      final raw = await supabase
          .from('teacher_assignments')
          .select('id, subject_id, class_id, niveau_id, subjects(name, code), niveaux(id, name, code), classes(id, name, room, capacity, niveau_id, section_id, niveaux(name, code), sections:section_id(name, code))')
          .eq('teacher_id', widget.teacherId)
          .eq('is_active', true);
      _assignments = List<Map<String, dynamic>>.from(raw as List);

      // Student counts per class
      final classIds = _assignments
          .map((a) => a['class_id']?.toString())
          .where((id) => id != null)
          .toSet()
          .toList();
      for (final cId in classIds) {
        try {
          final countResp = await supabase.from('enrollments').select('id').eq('class_id', cId!);
          final classRow = _assignments.firstWhere((a) => a['class_id'] == cId, orElse: () => {});
          final cls = classRow['classes'] as Map<String, dynamic>?;
          final assignmentNiveau = classRow['niveaux'] as Map<String, dynamic>?;
          final classNiveau = cls?['niveaux'] as Map<String, dynamic>?;
          final niveauName = assignmentNiveau?['name'] ?? classNiveau?['name'] ?? '';
          _classDetails.add({
            'class_id': cId,
            'name': cls?['name'] ?? '',
            'room': cls?['room'],
            'niveau_name': niveauName,
            'student_count': (countResp as List).length,
          });
        } catch (_) {}
      }

      // Weekly + Today timetable across subject_offerings.teacher_id AND teacher_assignments (subject_id + class_id)
      final now = DateTime.now();
      try {
        final Set<String> offeringIds = {};

        final directOfferings = await supabase
            .from('subject_offerings')
            .select('id')
            .eq('teacher_id', widget.teacherId);
        for (final o in (directOfferings as List)) {
          final oid = o['id']?.toString();
          if (oid != null) offeringIds.add(oid);
        }

        final assignmentPairs = _assignments
            .where((a) => a['subject_id'] != null && a['class_id'] != null)
            .map((a) => '${a['subject_id']}_${a['class_id']}')
            .toSet();

        if (classIds.isNotEmpty && assignmentPairs.isNotEmpty) {
          final classOfferings = await supabase
              .from('subject_offerings')
              .select('id, subject_id, class_id')
              .inFilter('class_id', classIds.cast<String>());
          for (final o in (classOfferings as List)) {
            final key = '${o['subject_id']}_${o['class_id']}';
            if (assignmentPairs.contains(key)) {
              final oid = o['id']?.toString();
              if (oid != null) offeringIds.add(oid);
            }
          }
        }

        final List<Map<String, dynamic>> rawSlots = [];
        final Set<String> seenSlotIds = {};

        if (offeringIds.isNotEmpty) {
          final slotsResp = await supabase
              .from('timetable_slots')
              .select('*, subject_offerings(subject_id, class_id, subjects(name, code), classes(name))')
              .inFilter('subject_offering_id', offeringIds.toList())
              .order('start_time');
          for (final s in (slotsResp as List)) {
            final slot = Map<String, dynamic>.from(s as Map);
            final type = (slot['timetable_type'] as String? ?? 'class').toLowerCase();
            if (type == 'exam') continue;
            final id = slot['id']?.toString();
            if (id == null || seenSlotIds.add(id)) {
              rawSlots.add(slot);
            }
          }
        }

        // Also match by teacher_name if any slot references teacher name directly
        final teacherName = (_user?['full_name'] as String?)?.trim() ?? '';
        if (teacherName.isNotEmpty) {
          try {
            final namedSlotsResp = await supabase
                .from('timetable_slots')
                .select('*, subject_offerings(subject_id, class_id, subjects(name, code), classes(name))')
                .ilike('teacher_name', teacherName)
                .order('start_time');
            for (final s in (namedSlotsResp as List)) {
              final slot = Map<String, dynamic>.from(s as Map);
              final type = (slot['timetable_type'] as String? ?? 'class').toLowerCase();
              if (type == 'exam') continue;
              final id = slot['id']?.toString();
              if (id == null || seenSlotIds.add(id)) {
                rawSlots.add(slot);
              }
            }
          } catch (_) {}
        }

        // Test data injection for teacher gcvygvc@hcv
        final emailLower = (_user?['email'] as String? ?? '').toLowerCase();
        final nameLower = teacherName.toLowerCase();
        if (emailLower.contains('gcvygvc') || emailLower.contains('hcv') || nameLower.contains('gcvygvc')) {
          final todayDow = now.weekday; // 1 = Monday, 7 = Sunday
          final testSlots = <Map<String, dynamic>>[
            // Today's sessions (rich test schedule for Gantt view)
            {
              'id': 'demo-today-1',
              'day_of_week': todayDow,
              'start_time': '08:30:00',
              'end_time': '10:30:00',
              'room': 'Salle C3',
              'subject_offerings': {
                'subject_id': 'demo-sub-1',
                'class_id': 'demo-cls-1',
                'subjects': {'name': 'Bases de Données', 'code': 'BD'},
                'classes': {'name': '7B-2'},
              },
            },
            {
              'id': 'demo-today-2',
              'day_of_week': todayDow,
              'start_time': '10:45:00',
              'end_time': '12:15:00',
              'room': 'Lab Info 1',
              'subject_offerings': {
                'subject_id': 'demo-sub-2',
                'class_id': 'demo-cls-2',
                'subjects': {'name': 'Algorithmique', 'code': 'ALGO'},
                'classes': {'name': '9B-2'},
              },
            },
            {
              'id': 'demo-today-3',
              'day_of_week': todayDow,
              'start_time': '13:30:00',
              'end_time': '15:00:00',
              'room': 'Salle B12',
              'subject_offerings': {
                'subject_id': 'demo-sub-3',
                'class_id': 'demo-cls-3',
                'subjects': {'name': 'Systèmes & Réseaux', 'code': 'SYS'},
                'classes': {'name': '8B-1'},
              },
            },
            {
              'id': 'demo-today-4',
              'day_of_week': todayDow,
              'start_time': '15:30:00',
              'end_time': '17:30:00',
              'room': 'Lab Info 2',
              'subject_offerings': {
                'subject_id': 'demo-sub-4',
                'class_id': 'demo-cls-4',
                'subjects': {'name': 'Technologies Web', 'code': 'WEB'},
                'classes': {'name': '9B-2'},
              },
            },
            // Other days across the week
            for (int day = 1; day <= 6; day++)
              if (day != todayDow) ...[
                {
                  'id': 'demo-day-$day-1',
                  'day_of_week': day,
                  'start_time': '08:30:00',
                  'end_time': '10:30:00',
                  'room': day % 2 == 0 ? 'Lab Info 2' : 'Salle C3',
                  'subject_offerings': {
                    'subject_id': 'demo-sub-$day-1',
                    'class_id': 'demo-cls-$day-1',
                    'subjects': {'name': day % 2 == 0 ? 'Programmation Python' : 'Bases de Données', 'code': 'INF'},
                    'classes': {'name': day % 2 == 0 ? '9B-2' : '7B-2'},
                  },
                },
                {
                  'id': 'demo-day-$day-2',
                  'day_of_week': day,
                  'start_time': '10:45:00',
                  'end_time': '12:45:00',
                  'room': 'Lab Info 1',
                  'subject_offerings': {
                    'subject_id': 'demo-sub-$day-2',
                    'class_id': 'demo-cls-$day-2',
                    'subjects': {'name': 'Algorithmique', 'code': 'ALGO'},
                    'classes': {'name': '8B-1'},
                  },
                },
                if (day == 2 || day == 4)
                  {
                    'id': 'demo-day-$day-3',
                    'day_of_week': day,
                    'start_time': '14:00:00',
                    'end_time': '16:00:00',
                    'room': 'Salle 204',
                    'subject_offerings': {
                      'subject_id': 'demo-sub-$day-3',
                      'class_id': 'demo-cls-$day-3',
                      'subjects': {'name': 'Technologies Web', 'code': 'WEB'},
                      'classes': {'name': '9B-2'},
                    },
                  },
              ],
          ];
          for (final slot in testSlots) {
            final id = slot['id']?.toString();
            final slotDay = _parseDayOfWeek(slot['day_of_week']);
            final sMin = _parseTimeToMinutes(_formatShortTime(slot['start_time']?.toString()));
            final eMin = _parseTimeToMinutes(_formatShortTime(slot['end_time']?.toString()));
            final overlaps = rawSlots.any((existing) {
              if (_parseDayOfWeek(existing['day_of_week']) != slotDay) return false;
              final exSMin = _parseTimeToMinutes(_formatShortTime(existing['start_time']?.toString()));
              final exEMin = _parseTimeToMinutes(_formatShortTime(existing['end_time']?.toString()));
              return sMin < exEMin && eMin > exSMin;
            });
            if (!overlaps && (id == null || seenSlotIds.add(id))) {
              rawSlots.add(slot);
            }
          }
          _subjects.addAll(['Bases de Données', 'Algorithmique', 'Systèmes & Réseaux', 'Programmation Python']);
        }

        final enriched = rawSlots.map((slot) {
          final startStr = _formatShortTime(slot['start_time']?.toString());
          final endStr = _formatShortTime(slot['end_time']?.toString());
          final sMin = _parseTimeToMinutes(startStr);
          final eMin = _parseTimeToMinutes(endStr);
          final durationMin = (eMin > sMin) ? (eMin - sMin) : 0;
          final dayNum = _parseDayOfWeek(slot['day_of_week']);

          String? rawRoom = slot['room']?.toString();
          if (rawRoom != null && rawRoom.contains('·')) {
            rawRoom = rawRoom.split('·').map((e) => e.trim()).last;
          }

          return {
            ...slot,
            'dayNum': dayNum,
            'startShort': startStr,
            'endShort': endStr,
            'startMin': sMin,
            'endMin': eMin,
            'durationMin': durationMin,
            'shortRoom': rawRoom,
          };
        }).toList()
          ..sort((a, b) {
            final dCmp = (a['dayNum'] as int).compareTo(b['dayNum'] as int);
            if (dCmp != 0) return dCmp;
            return (a['startMin'] as int).compareTo(b['startMin'] as int);
          });

        // Filter out overlapping slots so a teacher never teaches two classes at the same time
        final nonOverlapping = <Map<String, dynamic>>[];
        final Map<int, int> lastEndMinByDay = {};
        for (final slot in enriched) {
          final day = slot['dayNum'] as int;
          final sMin = slot['startMin'] as int;
          final eMin = slot['endMin'] as int;
          final lastEnd = lastEndMinByDay[day] ?? -1;
          if (sMin < lastEnd) {
            // Simultaneous class conflict: skip overlapping slot
            continue;
          }
          lastEndMinByDay[day] = eMin;
          nonOverlapping.add(slot);
        }

        _timetableAllSlots = nonOverlapping;
        _timetableToday =
            nonOverlapping.where((s) => s['dayNum'] == now.weekday).toList();
      } catch (e) {
        debugPrint('Teacher timetable load error: $e');
      }

      // Derive subjects & niveaux from assignments
      for (final a in _assignments) {
        final sName = (a['subjects'] as Map?)?['name']?.toString();
        if (sName != null) _subjects.add(sName);
        final aN = (a['niveaux'] as Map?)?['name']?.toString();
        final cN = ((a['classes'] as Map?)?['niveaux'] as Map?)?['name']?.toString();
        final sectionName = ((a['classes'] as Map?)?['sections'] as Map?)?['name']?.toString();
        if (aN != null) {
          _niveaux.add(aN);
          if (sectionName != null) _niveauFilieres[aN] = sectionName;
        } else if (cN != null) {
          _niveaux.add(cN);
          if (sectionName != null) _niveauFilieres[cN] = sectionName;
        }
      }
      _mainSubject = _subjects.isNotEmpty ? _subjects.first : 'N/A';

      // Format hire date
      if (_user?['created_at'] != null) {
        try {
          final dt = DateTime.parse(_user!['created_at'].toString());
          const months = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'];
          _hireDate = '${dt.day} ${months[dt.month - 1]} ${dt.year}';
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Teacher profile load error: $e');
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(children: [
        const AdminSidebar(currentRoute: '/users'),
        Expanded(
          child: _loading
              ? const TeacherProfileSkeletonLoader()
              : _user == null
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.person_off_rounded, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        const Text('Enseignant introuvable', style: TextStyle(fontSize: 14, color: AppColors.textTertiary)),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: () => context.go('/classes'),
                          icon: const Icon(Icons.arrow_back_rounded, size: 16),
                          label: const Text('Retour'),
                        ),
                      ]),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 32),
                          _buildBody(),
                        ],
                      ),
                    ),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  HEADER (MATCHING STUDENT PROFILE HEADER STYLE)
  // ══════════════════════════════════════════════════════════════
  Widget _buildHeader() {
    final fullName = _user?['full_name']?.toString() ?? 'Enseignant';
    final isActive = _user?['is_active'] == true;

    return Container(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.slate100)),
      ),
      child: Row(
        children: [
          _iconButton(
            icon: Icons.arrow_back_rounded,
            onTap: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/users');
              }
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const Text(
                  'Profil enseignant',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: _showToggleActiveConfirmation,
                  icon: Icon(
                    isActive ? Icons.pause_circle_outline_rounded : Icons.check_circle_outline_rounded,
                    size: 16,
                    color: isActive ? AppColors.warning : const Color(0xFF16A34A),
                  ),
                  label: Text(
                    isActive ? 'Désactiver' : 'Activer',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isActive ? const Color(0xFFDC2626) : const Color(0xFF15803D),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: isActive ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                    side: BorderSide(
                      color: isActive ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: _showEditTeacherDialog,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text(
                    'Modifier le profil',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6D4CF6),
                    foregroundColor: Colors.white,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    shadowColor: const Color(0xFF6D4CF6).withOpacity(0.3),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showToggleActiveConfirmation() {
    final bool currentActive = _user?['is_active'] == true;
    final bool nextActive = !currentActive;
    final String fullName = _user?['full_name']?.toString() ?? 'Enseignant';
    final String? photoUrl = _user?['photo_url']?.toString();
    final String speciality = _mainSubject.isNotEmpty ? _mainSubject : 'Enseignant';

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: currentActive ? AppColors.warningSoft : AppColors.successSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  currentActive ? Icons.pause_circle_outline_rounded : Icons.check_circle_outline_rounded,
                  color: currentActive ? AppColors.warning : AppColors.success,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                currentActive ? 'Désactiver ce professeur ?' : 'Activer ce professeur ?',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                ),
                child: Row(
                  children: [
                    UserAvatar(
                      name: fullName,
                      photoUrl: photoUrl,
                      radius: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            fullName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            speciality,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.slate500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                currentActive ? 'Ce professeur sera désactivé.' : 'Ce professeur sera réactivé.',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  height: 40,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
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
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _executeToggleActive(nextActive);
                    },
                    icon: Icon(
                      currentActive ? Icons.pause_circle_outline_rounded : Icons.check_circle_outline_rounded,
                      size: 16,
                    ),
                    label: Text(
                      currentActive ? 'Désactiver' : 'Activer',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: currentActive ? AppColors.warning : AppColors.success,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  Future<void> _executeToggleActive(bool newActive) async {
    final String fullName = _user?['full_name']?.toString() ?? 'Enseignant';
    try {
      await SupabaseConfig.adminClient
          .from('users')
          .update({'is_active': newActive})
          .eq('id', widget.teacherId);

      if (mounted) {
        setState(() {
          _user = Map<String, dynamic>.from(_user ?? {})..[ 'is_active'] = newActive;
        });
        ref.invalidate(professorsProvider);

        FeedbackPill.showSuccess(
          context,
          newActive ? 'Professeur "$fullName" activé' : 'Professeur "$fullName" désactivé',
        );

        ref.read(undoRedoProvider.notifier).recordAction(
          AppAction(
            title: newActive ? 'Activation professeur' : 'Désactivation professeur',
            description: newActive ? 'Activation de $fullName' : 'Désactivation de $fullName',
            undo: () async {
              await SupabaseConfig.adminClient
                  .from('users')
                  .update({'is_active': !newActive})
                  .eq('id', widget.teacherId);
              if (mounted) {
                setState(() {
                  _user = Map<String, dynamic>.from(_user ?? {})..[ 'is_active'] = !newActive;
                });
                ref.invalidate(professorsProvider);
              }
            },
            redo: () async {
              await SupabaseConfig.adminClient
                  .from('users')
                  .update({'is_active': newActive})
                  .eq('id', widget.teacherId);
              if (mounted) {
                setState(() {
                  _user = Map<String, dynamic>.from(_user ?? {})..[ 'is_active'] = newActive;
                });
                ref.invalidate(professorsProvider);
              }
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        FeedbackPill.showError(context, 'Erreur lors du changement de statut : $e');
      }
    }
  }

  Widget _iconButton({required IconData icon, required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 20, color: AppColors.slate600),
          ),
        ),
      ),
    );
  }

  Widget _outlineButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: AppColors.slate500),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.slate500,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
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
  //  BODY – 2-column layout
  // ══════════════════════════════════════════════════════════════
  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── LEFT: Profile card (exact match to Student Profile 360px) ──
            SizedBox(width: 360, child: _buildProfileCard()),
            const SizedBox(width: 32),
            // ── RIGHT: Specialty & Classes ──
            Expanded(child: _buildRightColumn()),
          ],
        ),
        const SizedBox(height: 24),
        // ── FULL WIDTH: Emploi du temps ──
        _buildTimetableSection(),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  LEFT PROFILE CARD (MATCHES STUDENT PROFILE CARD + COPIABLE)
  // ══════════════════════════════════════════════════════════════
  Widget _buildProfileCard() {
    final fullName = _user?['full_name']?.toString() ?? 'Enseignant';
    final email = _user?['email']?.toString() ?? '-';
    final phone = (_user?['phone']?.toString() ?? '').trim();
    final photoUrl = _user?['photo_url']?.toString();
    final gender = _user?['gender']?.toString();
    final nationality = _user?['nationality']?.toString();
    final isActive = _user?['is_active'] == true;
    final teacherCode = 'TEA-${widget.teacherId.substring(0, 8).toUpperCase()}';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          // Avatar
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              UserAvatar(
                name: fullName,
                photoUrl: photoUrl,
                radius: 50,
                gender: gender,
              ),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _pickAndUploadPhoto,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border, width: 2),
                      boxShadow: AppShadows.sm,
                    ),
                    child: Icon(Icons.camera_alt_rounded, size: 14, color: AppColors.slate500),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Name (click to copy)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: fullName));
                FeedbackPill.showSuccess(context, 'Nom copié !');
              },
              child: Text(
                fullName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.slate800,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Active/Inactive badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isActive ? 'Actif' : 'Inactif',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isActive ? const Color(0xFF15803D) : const Color(0xFFDC2626),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Clickable Teacher ID
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: teacherCode));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('ID copié!'),
                    duration: Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Text(
                teacherCode,
                style: TextStyle(
                  color: AppColors.slate400,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Copiable Info Rows
          _profileInfoRow('Spécialité', _mainSubject),
          _profileInfoRow('Embauche', _hireDate),
          if (gender != null && gender.isNotEmpty) _profileInfoRow('Genre', gender),
          if (nationality != null && nationality.isNotEmpty)
            _profileInfoRow('Nationalité', nationality),
          const SizedBox(height: 20),
          Divider(color: AppColors.border, thickness: 1),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Contact Rapide',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.slate500,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _contactRow(Icons.email_outlined, email),
          const SizedBox(height: 8),
          _contactRow(Icons.phone_outlined, phone.isNotEmpty ? phone : '-'),
        ],
      ),
    );
  }

  Widget _profileInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.slate400,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$label copié!'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        style: const TextStyle(
                          color: AppColors.slate700,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.copy, size: 12, color: AppColors.slate300),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactRow(IconData icon, String text) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$text copié!'),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 14, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: AppColors.slate600, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.copy, size: 12, color: AppColors.slate300),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  RIGHT COLUMN
  // ══════════════════════════════════════════════════════════════
  Widget _buildRightColumn() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildSpecialitySection(),
      const SizedBox(height: 24),
      _buildClassesSection(),
    ]);
  }

  // ── Spécialité & Niveaux ──
  Widget _buildSpecialitySection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('SPÉCIALITÉ & NIVEAUX',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade400, letterSpacing: 1.2)),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          // Main subject badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _brand,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.terminal_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Text(_mainSubject.toUpperCase(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
            ]),
          ),
          if (_niveaux.isNotEmpty) ...[
            Container(width: 1, height: 32, color: Colors.grey.shade200, margin: const EdgeInsets.symmetric(horizontal: 4)),
            ..._niveaux.map((n) {
            final filiere = _niveauFilieres[n];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(n, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey.shade700)),
                if (filiere != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDE9FE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(filiere, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF7C3AED))),
                  ),
                ],
              ]),
            );
          }),
          ],
        ]),
      ]),
    );
  }

  // ── Classes Assignées ──
  Widget _buildClassesSection() {
    final sortedClasses = List<Map<String, dynamic>>.from(_classDetails);
    sortedClasses.sort((a, b) {
      switch (_classSortKey) {
        case 'name_desc':
          final na = (a['name']?.toString() ?? '').toLowerCase();
          final nb = (b['name']?.toString() ?? '').toLowerCase();
          return nb.compareTo(na);
        case 'niveau_asc':
          final nva = (a['niveau_name']?.toString() ?? '').toLowerCase();
          final nvb = (b['niveau_name']?.toString() ?? '').toLowerCase();
          return nva.compareTo(nvb);
        case 'students_desc':
          final ea = int.tryParse(a['student_count']?.toString() ?? '0') ?? 0;
          final eb = int.tryParse(b['student_count']?.toString() ?? '0') ?? 0;
          return eb.compareTo(ea);
        case 'students_asc':
          final ea = int.tryParse(a['student_count']?.toString() ?? '0') ?? 0;
          final eb = int.tryParse(b['student_count']?.toString() ?? '0') ?? 0;
          return ea.compareTo(eb);
        case 'name_asc':
        default:
          final na = (a['name']?.toString() ?? '').toLowerCase();
          final nb = (b['name']?.toString() ?? '').toLowerCase();
          return na.compareTo(nb);
      }
    });

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Classes Assignées', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const Spacer(),
        AdminSortDropdown<String>(
          selectedValue: _classSortKey,
          height: 32,
          radius: 8,
          options: const [
            SortOption(value: 'name_asc', label: 'Classe: A → Z', icon: Icons.sort_by_alpha_rounded),
            SortOption(value: 'name_desc', label: 'Classe: Z → A', icon: Icons.sort_by_alpha_rounded),
            SortOption(value: 'niveau_asc', label: 'Niveau: A → Z', icon: Icons.school_outlined),
            SortOption(value: 'students_desc', label: 'Effectif: Plus élevé', icon: Icons.groups_rounded),
            SortOption(value: 'students_asc', label: 'Effectif: Moins élevé', icon: Icons.groups_outlined),
          ],
          onSelected: (val) {
            setState(() {
              _classSortKey = val;
            });
          },
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text('Total: ${_classDetails.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ),
      ]),
      const SizedBox(height: 16),
      if (sortedClasses.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Center(child: Column(children: [
            Icon(Icons.class_rounded, size: 36, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            const Text('Aucune classe assignée', style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
          ])),
        )
      else
        LayoutBuilder(builder: (context, constraints) {
          final crossCount = constraints.maxWidth > 700 ? 2 : 1;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: sortedClasses.map((c) {
              final cardWidth = (constraints.maxWidth - (crossCount - 1) * 16) / crossCount;
              return SizedBox(
                width: cardWidth,
                child: _buildClassCard(c),
              );
            }).toList(),
          );
        }),
    ]);
  }

  Widget _buildClassCard(Map<String, dynamic> c) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c['name']?.toString() ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(c['niveau_name']?.toString() ?? '', style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          ])),
          InkWell(
            onTap: () {
              final classId = c['class_id']?.toString();
              if (classId != null) context.push('/classes/$classId');
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: _brand.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.arrow_outward_rounded, size: 18, color: _brand),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Container(height: 1, color: Colors.grey.shade100),
        const SizedBox(height: 14),
        Row(children: [
          Icon(Icons.groups_rounded, size: 15, color: Colors.grey.shade400),
          const SizedBox(width: 6),
          Text('${c['student_count']} Étudiants', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade500)),
          if (c['room'] != null) ...[
            const SizedBox(width: 20),
            Icon(Icons.room_rounded, size: 15, color: Colors.grey.shade400),
            const SizedBox(width: 6),
            Text(c['room'].toString(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade500)),
          ],
        ]),
      ]),
    );
  }

  // ── Emploi du temps ──
  String _formatHoursMinutes(int totalMinutes) {
    if (totalMinutes <= 0) return '0h 00min';
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m.toString().padLeft(2, '0')}';
  }

  String _formatShortHours(int totalMinutes) {
    if (totalMinutes <= 0) return '—';
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h${m.toString().padLeft(2, '0')}';
  }

  Widget _buildTimetableSection() {
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final activeSlots =
        _showWeeklySchedule ? _timetableAllSlots : _timetableToday;
    final activeMinutes = activeSlots.fold<int>(
      0,
      (sum, s) => sum + (s['durationMin'] as int? ?? 0),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, size: 18, color: _brand),
              const SizedBox(width: 10),
              const Text(
                'Emploi du temps',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _brandLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_formatHoursMinutes(activeMinutes)} • ${activeSlots.length} séance${activeSlots.length > 1 ? 's' : ''}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _brand,
                  ),
                ),
              ),
              const Spacer(),
              // Clickable Toggle buttons
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    _buildScheduleToggleBtn(
                      label: 'Aujourd\'hui',
                      isActive: !_showWeeklySchedule,
                      onTap: () => setState(() => _showWeeklySchedule = false),
                    ),
                    _buildScheduleToggleBtn(
                      label: 'Semaine',
                      isActive: _showWeeklySchedule,
                      onTap: () => setState(() => _showWeeklySchedule = true),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Timeline: Today (Full width) vs Week
          if (!_showWeeklySchedule)
            _buildTodayTimelineGantt(nowMin)
          else ...[
            _buildWorkingHoursChart(now.weekday),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                child: _timetableAllSlots.isEmpty
                    ? _buildEmptyScheduleState(
                        'Aucune séance planifiée cette semaine')
                    : _buildWeeklyScheduleView(now.weekday),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScheduleToggleBtn({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              color: isActive ? AppColors.textPrimary : Colors.grey.shade500,
            ),
          ),
        ),
      ),
    );
  }

  String _extractClassName(Map<String, dynamic> slot) {
    final so = slot['subject_offerings'] as Map<String, dynamic>?;
    final cls = so?['classes']?['name']?.toString().trim();
    if (cls != null && cls.isNotEmpty) return cls;
    return 'Classe';
  }

  static const List<Map<String, Color>> _ganttPalettes = [
    {
      'bg': Color(0xFF2563EB), // Bold Blue
      'accent': Color(0xFF1D4ED8),
      'text': Colors.white,
      'subtext': Color(0xFFE0E7FF),
    },
    {
      'bg': Color(0xFF059669), // Bold Emerald Green
      'accent': Color(0xFF047857),
      'text': Colors.white,
      'subtext': Color(0xFFD1FAE5),
    },
    {
      'bg': Color(0xFF7C3AED), // Bold Purple / Violet
      'accent': Color(0xFF6D28D9),
      'text': Colors.white,
      'subtext': Color(0xFFEDE9FE),
    },
    {
      'bg': Color(0xFFEA580C), // Bold Orange
      'accent': Color(0xFFC2410C),
      'text': Colors.white,
      'subtext': Color(0xFFFFEDD5),
    },
    {
      'bg': Color(0xFFDB2777), // Bold Rose / Pink
      'accent': Color(0xFFBE185D),
      'text': Colors.white,
      'subtext': Color(0xFFFCE7F3),
    },
    {
      'bg': Color(0xFF0D9488), // Bold Teal
      'accent': Color(0xFF0F766E),
      'text': Colors.white,
      'subtext': Color(0xFFCCFBF1),
    },
  ];

  Widget _buildTodayTimelineGantt(int nowMin) {
    if (_timetableToday.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.event_available_rounded, color: Color(0xFF94A3B8), size: 24),
              ),
              const SizedBox(height: 12),
              const Text(
                'Aucune séance programmée aujourd\'hui',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 4),
              const Text(
                'Ce professeur n\'a pas de cours prévu pour cette journée.',
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ),
      );
    }

    // Determine timetable day bounds
    int startHour = 8;
    int endHour = 18;

    for (final s in _timetableToday) {
      final sMin = s['startMin'] as int? ?? 0;
      final eMin = s['endMin'] as int? ?? 0;
      if (sMin > 0 && (sMin ~/ 60) < startHour) {
        startHour = (sMin ~/ 60).clamp(6, 8);
      }
      if (eMin > 0 && ((eMin + 59) ~/ 60) > endHour) {
        endHour = ((eMin + 59) ~/ 60).clamp(18, 22);
      }
    }

    final totalHours = endHour - startHour;
    final startMinutes = startHour * 60;
    final totalDayMinutes = totalHours * 60;
    final endMinutes = endHour * 60;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
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
          // Header info
          Row(
            children: [
              const Text(
                'CHRONOLOGIE D\'AUJOURD\'HUI',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: AppColors.textTertiary,
                ),
              ),
              const Spacer(),
              Text(
                '$startHour:00 - $endHour:00',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Responsive Gantt view
          LayoutBuilder(
            builder: (context, constraints) {
              final plotWidth = constraints.maxWidth.clamp(740.0, 3000.0);
              const double rowHeight = 52.0;
              final double canvasHeight = _timetableToday.length * rowHeight + 14.0;

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: SizedBox(
                  width: plotWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Canvas with grid and pills
                      Container(
                        height: canvasHeight,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFCFDFE),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // 1. Vertical hour grid lines
                            ...List.generate(totalHours + 1, (i) {
                              final x = (i / totalHours) * plotWidth;
                              return Positioned(
                                left: x.clamp(0.0, plotWidth - 1),
                                top: 0,
                                bottom: 0,
                                width: 1,
                                child: Container(
                                  color: const Color(0xFFF1F5F9),
                                ),
                              );
                            }),

                            // 2. Horizontal row dividing grid lines
                            ...List.generate(_timetableToday.length + 1, (i) {
                              final y = i * rowHeight + 6.0;
                              return Positioned(
                                left: 0,
                                right: 0,
                                top: y,
                                height: 1,
                                child: Container(
                                  color: const Color(0xFFF8FAFC),
                                ),
                              );
                            }),

                            // 3. Current Time Vertical Line (if inside today's hours)
                            if (nowMin >= startMinutes && nowMin <= endMinutes) ...[
                              Positioned(
                                left: (((nowMin - startMinutes) / totalDayMinutes) * plotWidth)
                                    .clamp(0.0, plotWidth - 2),
                                top: 0,
                                bottom: 0,
                                width: 2,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF4444),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],

                            // 4. Staggered pills for each class
                            ...List.generate(_timetableToday.length, (i) {
                              final slot = _timetableToday[i];
                              final sMin = slot['startMin'] as int? ?? startMinutes;
                              final eMin = slot['endMin'] as int? ?? (sMin + 60);
                              final dMin = (eMin > sMin) ? (eMin - sMin) : 60;

                              final subjectName = (slot['subject_offerings']?['subjects']?['name'] ??
                                      slot['subjects']?['name'] ??
                                      'Matière')
                                  .toString();
                              final className = _extractClassName(slot);
                              final room = slot['shortRoom']?.toString() ??
                                  slot['room']?.toString() ??
                                  '';
                              final startTime = slot['startShort']?.toString() ??
                                  _formatShortTime(slot['start_time']?.toString());
                              final endTime = slot['endShort']?.toString() ??
                                  _formatShortTime(slot['end_time']?.toString());

                              final left = (((sMin - startMinutes) / totalDayMinutes) * plotWidth)
                                  .clamp(0.0, plotWidth - 60);
                              final rawWidth = ((dMin / totalDayMinutes) * plotWidth);
                              final width = rawWidth.clamp(140.0, plotWidth - left);
                              final top = i * rowHeight + 8.0;

                              final palette = _ganttPalettes[i % _ganttPalettes.length];

                              return Positioned(
                                left: left,
                                top: top,
                                width: width,
                                height: 44.0,
                                child: Tooltip(
                                  message:
                                      '$subjectName • $className • $startTime - $endTime${room.isNotEmpty ? ' • $room' : ''}',
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      onTap: () => _showTodayClassDetailModal(
                                        className,
                                        [slot],
                                        nowMin,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: palette['bg'],
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              subjectName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                                letterSpacing: -0.2,
                                              ),
                                            ),
                                            const SizedBox(height: 1),
                                            Text(
                                              '$startTime - $endTime  •  $className${room.isNotEmpty ? ' ($room)' : ''}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white.withValues(alpha: 0.90),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Continuous Today Timeline Bar (teaching blocks vs free breaks)
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Stack(
                          children: _timetableToday.map((slot) {
                            final i = _timetableToday.indexOf(slot);
                            final sMin = slot['startMin'] as int? ?? startMinutes;
                            final eMin = slot['endMin'] as int? ?? (sMin + 60);
                            final dMin = (eMin > sMin) ? (eMin - sMin) : 60;
                            final left = (((sMin - startMinutes) / totalDayMinutes) * plotWidth)
                                .clamp(0.0, plotWidth);
                            final width = ((dMin / totalDayMinutes) * plotWidth)
                                .clamp(4.0, plotWidth - left);
                            final palette = _ganttPalettes[i % _ganttPalettes.length];

                            return Positioned(
                              left: left,
                              top: 0,
                              bottom: 0,
                              width: width,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: palette['bg'],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // X-Axis Line & Hour Ticks
                      SizedBox(
                        height: 24,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Baseline
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
                              height: 1,
                              child: Container(color: const Color(0xFFCBD5E1)),
                            ),
                            // Hour markers
                            ...List.generate(totalHours + 1, (i) {
                              final h = startHour + i;
                              final x = (i / totalHours) * plotWidth;
                              return Positioned(
                                left: (x - 22).clamp(0.0, plotWidth - 44),
                                top: 0,
                                width: 44,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 1,
                                      height: 5,
                                      color: const Color(0xFF94A3B8),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${h.toString().padLeft(2, '0')}:00',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWorkingHoursChart(int currentWeekday) {
    final Map<int, int> minutesByDay = {
      1: 0,
      2: 0,
      3: 0,
      4: 0,
      5: 0,
      6: 0,
      7: 0,
    };
    final Map<int, List<Map<String, dynamic>>> slotsByDay = {};
    for (final s in _timetableAllSlots) {
      final d = s['dayNum'] as int? ?? 1;
      minutesByDay[d] = (minutesByDay[d] ?? 0) + (s['durationMin'] as int? ?? 0);
      slotsByDay.putIfAbsent(d, () => []).add(s);
    }

    final showSunday = (minutesByDay[7] ?? 0) > 0 || currentWeekday == 7;
    final days = showSunday ? [1, 2, 3, 4, 5, 6, 7] : [1, 2, 3, 4, 5, 6];
    const dayLabels = {
      1: 'Lun',
      2: 'Mar',
      3: 'Mer',
      4: 'Jeu',
      5: 'Ven',
      6: 'Sam',
      7: 'Dim',
    };

    int maxMinutes = 60;
    for (final d in days) {
      final m = minutesByDay[d] ?? 0;
      if (m > maxMinutes) maxMinutes = m;
    }

    final displayedMinutes = _timetableAllSlots.fold<int>(
        0, (sum, s) => sum + (s['durationMin'] as int? ?? 0));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'HEURES DE TRAVAIL — CETTE SEMAINE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '• Cliquer pour détails',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textTertiary,
                ),
              ),
              const Spacer(),
              Text(
                _formatHoursMinutes(displayedMinutes),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _brand,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 104,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: days.map((d) {
                final mins = minutesByDay[d] ?? 0;
                final isToday = d == currentWeekday;
                final hasWork = mins > 0;
                final barHeight = mins <= 0
                    ? 6.0
                    : (mins / maxMinutes * 46.0).clamp(10.0, 46.0);

                return Expanded(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showDayDetailModal(
                        d,
                        slotsByDay[d] ?? [],
                        isToday,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            _formatShortHours(mins),
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight:
                                  hasWork ? FontWeight.w700 : FontWeight.w500,
                              color: hasWork
                                  ? (isToday ? _brand : AppColors.textSecondary)
                                  : AppColors.slate300,
                            ),
                          ),
                          const SizedBox(height: 4),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            width: 28,
                            height: barHeight,
                            decoration: BoxDecoration(
                              color: mins <= 0
                                  ? const Color(0xFFE2E8F0)
                                  : isToday
                                      ? _brand
                                      : _brand.withOpacity(0.68),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            dayLabels[d] ?? '',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight:
                                  isToday ? FontWeight.w700 : FontWeight.w500,
                              color: isToday ? _brand : AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _showTodayClassDetailModal(
    String className,
    List<Map<String, dynamic>> slots,
    int nowMin,
  ) {
    final totalMin =
        slots.fold<int>(0, (sum, s) => sum + (s['durationMin'] as int? ?? 0));
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.12),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _brandLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.class_rounded, size: 18, color: _brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      className,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Aujourd\'hui • ${_formatHoursMinutes(totalMin)} (${slots.length} séance${slots.length > 1 ? 's' : ''})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: slots.map((slot) {
                final start = slot['startShort']?.toString() ?? '??:??';
                final end = slot['endShort']?.toString() ?? '??:??';
                final room =
                    slot['shortRoom']?.toString() ?? slot['room']?.toString();
                final durationMin = slot['durationMin'] as int? ?? 0;
                final sMin = slot['startMin'] as int? ?? 0;
                final eMin = slot['endMin'] as int? ?? 0;
                final isCurrent = nowMin >= sMin && nowMin < eMin;
                final isPast = nowMin >= eMin;
                return _buildDetailSessionTile(
                  primary: '$start – $end',
                  secondary:
                      '${_formatHoursMinutes(durationMin)}${room != null && room.isNotEmpty ? ' • $room' : ''}',
                  statusLabel: isCurrent
                      ? 'EN COURS'
                      : (isPast ? 'TERMINÉ' : 'À VENIR'),
                  isHighlighted: isCurrent,
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDayDetailModal(
    int dayNum,
    List<Map<String, dynamic>> slots,
    bool isToday,
  ) {
    const fullDayNames = {
      1: 'Lundi',
      2: 'Mardi',
      3: 'Mercredi',
      4: 'Jeudi',
      5: 'Vendredi',
      6: 'Samedi',
      7: 'Dimanche',
    };
    final dayName = fullDayNames[dayNum] ?? '';
    final totalMin =
        slots.fold<int>(0, (sum, s) => sum + (s['durationMin'] as int? ?? 0));

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.12),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _brandLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.calendar_today_rounded,
                    size: 18, color: _brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isToday ? '$dayName (Aujourd\'hui)' : dayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      slots.isEmpty
                          ? 'Aucune séance planifiée'
                          : '${_formatHoursMinutes(totalMin)} • ${slots.length} séance${slots.length > 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: slots.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Cet enseignant n\'a aucune séance prévue ce jour-là.',
                      style:
                          TextStyle(fontSize: 13, color: AppColors.textTertiary),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: slots.map((slot) {
                      final cls = _extractClassName(slot);
                      final start = slot['startShort']?.toString() ?? '??:??';
                      final end = slot['endShort']?.toString() ?? '??:??';
                      final room = slot['shortRoom']?.toString() ??
                          slot['room']?.toString();
                      final durationMin = slot['durationMin'] as int? ?? 0;
                      return _buildDetailSessionTile(
                        primary: cls,
                        secondary:
                            '$start – $end • ${_formatHoursMinutes(durationMin)}${room != null && room.isNotEmpty ? ' • $room' : ''}',
                        statusLabel: _formatShortHours(durationMin),
                        isHighlighted: isToday,
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailSessionTile({
    required String primary,
    required String secondary,
    required String statusLabel,
    required bool isHighlighted,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isHighlighted ? const Color(0xFFF5F3FF) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlighted
              ? _brand.withOpacity(0.35)
              : const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primary,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  secondary,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isHighlighted ? _brandLight : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isHighlighted ? _brand : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyScheduleState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Icon(Icons.event_busy_rounded, size: 32, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyScheduleView(int currentWeekday) {
    const fullDayNames = {
      1: 'Lundi',
      2: 'Mardi',
      3: 'Mercredi',
      4: 'Jeudi',
      5: 'Vendredi',
      6: 'Samedi',
      7: 'Dimanche',
    };

    final Map<int, List<Map<String, dynamic>>> grouped = {};
    for (final s in _timetableAllSlots) {
      final d = s['dayNum'] as int? ?? 1;
      grouped.putIfAbsent(d, () => []).add(s);
    }

    final sortedDays = grouped.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sortedDays.map((dayNum) {
        final daySlots = grouped[dayNum]!;
        final dayMins = daySlots.fold<int>(
          0,
          (sum, s) => sum + (s['durationMin'] as int? ?? 0),
        );
        final isToday = dayNum == currentWeekday;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    fullDayNames[dayNum] ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isToday ? _brand : AppColors.textPrimary,
                    ),
                  ),
                  if (isToday) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _brandLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Aujourd\'hui',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _brand,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    '${_formatHoursMinutes(dayMins)} • ${daySlots.length} séance${daySlots.length > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...daySlots.map((slot) {
                final className = _extractClassName(slot);
                final startTime = slot['startShort']?.toString() ?? '??:??';
                final endTime = slot['endShort']?.toString() ?? '??:??';
                final room = slot['shortRoom']?.toString();
                final durationMin = slot['durationMin'] as int? ?? 0;

                return _buildSlotRow(
                  startTime: startTime,
                  endTime: endTime,
                  className: className,
                  durationMin: durationMin,
                  room: room,
                  isCurrent: false,
                  isPast: false,
                  showStatusBadge: false,
                );
              }),
            ],
          ),
        );
      }).toList(),
    );
  }

  List<Widget> _buildTimetableSlots(int nowMin) {
    final widgets = <Widget>[];
    for (int i = 0; i < _timetableToday.length; i++) {
      final slot = _timetableToday[i];
      final className = _extractClassName(slot);
      final startTime = slot['startShort']?.toString() ??
          _formatShortTime(slot['start_time']?.toString());
      final endTime = slot['endShort']?.toString() ??
          _formatShortTime(slot['end_time']?.toString());
      final room = slot['shortRoom']?.toString() ?? slot['room']?.toString();
      final durationMin = slot['durationMin'] as int? ?? 0;

      final sMin = slot['startMin'] as int? ?? _parseTimeToMinutes(startTime);
      final eMin = slot['endMin'] as int? ?? _parseTimeToMinutes(endTime);
      final isCurrent = nowMin >= sMin && nowMin < eMin;
      final isPast = nowMin >= eMin;

      // Check for gap -> Pause / Préparation
      if (i > 0) {
        final prevSlot = _timetableToday[i - 1];
        final prevEnd = prevSlot['endShort']?.toString() ??
            _formatShortTime(prevSlot['end_time']?.toString());
        if (prevEnd != startTime) {
          widgets.add(_buildPauseSlot(prevEnd, startTime));
        }
      }

      widgets.add(_buildSlotRow(
        startTime: startTime,
        endTime: endTime,
        className: className,
        durationMin: durationMin,
        room: room,
        isCurrent: isCurrent,
        isPast: isPast,
      ));
    }
    return widgets;
  }

  Widget _buildPauseSlot(String startTime, String endTime) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        // Time column
        SizedBox(
          width: 52,
          child: Column(children: [
            Text(startTime, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade500)),
            Text(endTime, style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
          ]),
        ),
        // Separator line
        Container(width: 1, height: 32, color: Colors.grey.shade200),
        const SizedBox(width: 14),
        // Break card
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200, style: BorderStyle.solid),
            ),
            child: Center(
              child: Text('Pause / Préparation', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildSlotRow({
    required String startTime,
    required String endTime,
    required String className,
    required int durationMin,
    String? room,
    required bool isCurrent,
    required bool isPast,
    bool showStatusBadge = true,
  }) {
    final subtitleParts = <String>[
      _formatHoursMinutes(durationMin),
      if (room != null && room.isNotEmpty) room,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: isPast ? 0.5 : 1.0,
        child: Row(children: [
          // Time column
          SizedBox(
            width: 52,
            child: Column(children: [
              Text(startTime, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isCurrent ? AppColors.textPrimary : Colors.grey.shade700)),
              Text(endTime, style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
            ]),
          ),
          // Separator line
          Container(width: 1, height: 38, color: Colors.grey.shade200),
          const SizedBox(width: 14),
          // Class + hours card (no course title)
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isCurrent ? const Color(0xFFEDE9FE) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isCurrent
                      ? _brand.withOpacity(0.4)
                      : Colors.grey.shade200,
                ),
              ),
              child: Row(children: [
                if (isCurrent)
                  Container(
                    width: 4,
                    height: 30,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: _brand,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(className, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    subtitleParts.join(' • '),
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: isCurrent ? _brand : AppColors.textTertiary),
                  ),
                ])),
                if (showStatusBadge)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isCurrent ? _brand.withOpacity(0.1) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isCurrent ? 'EN COURS' : (isPast ? 'TERMINÉ' : 'À VENIR'),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isCurrent ? _brand : Colors.grey.shade500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  PICK & UPLOAD PHOTO
  // ══════════════════════════════════════════════════════════════
  Future<void> _pickAndUploadPhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85);
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final path = 'avatars/${widget.teacherId}.$ext';

      await SupabaseConfig.adminClient.storage.from('avatars').uploadBinary(
        path, bytes,
        fileOptions: const FileOptions(upsert: true),
      );
      final url = SupabaseConfig.adminClient.storage.from('avatars').getPublicUrl(path);

      await SupabaseConfig.adminClient.from('users').update({'photo_url': url}).eq('id', widget.teacherId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Photo mise à jour'), backgroundColor: const Color(0xFF16A34A), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        );
        setState(() => _loading = true);
        _classDetails = [];
        _subjects = {};
        _niveaux = {};
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFriendlyError.format(
                e,
                fallback: 'Unable to update the photo right now. Please try again.',
              ),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  EDIT TEACHER DIALOG
  // ══════════════════════════════════════════════════════════════
  void _showEditTeacherDialog() async {
    final nameCtrl = TextEditingController(text: _user?['full_name']?.toString() ?? '');
    final emailCtrl = TextEditingController(text: _user?['email']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: _user?['phone']?.toString() ?? '');
    bool saving = false;

    // Load all niveaux, classes, and subjects for the school
    List<Map<String, dynamic>> allNiveaux = [];
    List<Map<String, dynamic>> allClasses = [];
    List<Map<String, dynamic>> allSubjects = [];
    String? schoolId;
    try {
      final schoolResp = await SupabaseConfig.adminClient
          .from('users').select('school_id').eq('id', widget.teacherId).maybeSingle();
      schoolId = schoolResp?['school_id']?.toString();
      if (schoolId != null) {
        // niveaux is a global reference table — no school_id column
        final nResp = await SupabaseConfig.adminClient
            .from('niveaux').select('id, name, code, has_sections').order('name');
        allNiveaux = List<Map<String, dynamic>>.from(nResp as List);
        final cResp = await SupabaseConfig.adminClient
            .from('classes')
            .select('id, name, niveau_id, section_id, sections(id, name, code)')
            .eq('school_id', schoolId)
            .order('name');
        allClasses = List<Map<String, dynamic>>.from(cResp as List);
        final sResp = await SupabaseConfig.adminClient
            .from('subjects').select('id, name, code').eq('school_id', schoolId).order('name');
        allSubjects = List<Map<String, dynamic>>.from(sResp as List);
      }
    } catch (_) {}

    // Build currently assigned subject + niveaux + classes from _assignments
    String? selectedSubjectId;
    final Set<String> selectedNiveauIds = {};
    final Map<String, Set<String>> selectedClassIdsByNiveau = {};
    final Map<String, Set<String>> selectedSectionIdsByNiveau = {};

    // Track original assignments for diffing on save
    final List<Map<String, dynamic>> originalAssignments = List.from(_assignments);

    for (final a in _assignments) {
      // Get subject
      if (selectedSubjectId == null && a['subject_id'] != null) {
        selectedSubjectId = a['subject_id']?.toString();
      }
      final niveauId = a['niveau_id']?.toString() ?? (a['niveaux'] as Map?)?['id']?.toString();
      final classId = a['class_id']?.toString();
      if (niveauId != null) {
        selectedNiveauIds.add(niveauId);
        selectedClassIdsByNiveau.putIfAbsent(niveauId, () => {});
        selectedSectionIdsByNiveau.putIfAbsent(niveauId, () => {});
        if (classId != null) {
          selectedClassIdsByNiveau[niveauId]!.add(classId);
          // Pre-select section if class belongs to one
          final cls = allClasses.where((c) => c['id'] == classId).toList();
          if (cls.isNotEmpty) {
            final sectionId = cls.first['section_id']?.toString();
            if (sectionId != null) selectedSectionIdsByNiveau[niveauId]!.add(sectionId);
          }
        }
      }
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Stack(
            children: [
              // Blurred backdrop
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: Container(color: Colors.black.withOpacity(0.3)),
                  ),
                ),
              ),
              // Dialog
              Center(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: 580,
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 30, offset: const Offset(0, 8))],
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Row(children: [
                          Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(color: _brandLight, borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.edit_rounded, size: 20, color: _brand),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Modifier l\'enseignant', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                              SizedBox(height: 2),
                              Text('Mettez à jour les informations du profil et les affectations', style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                            ]),
                          ),
                          InkWell(
                            onTap: () => Navigator.of(ctx).pop(),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.close_rounded, size: 18, color: AppColors.textTertiary),
                            ),
                          ),
                        ]),
                      ),
                      Divider(height: 1, color: Colors.grey.shade200),
                      // Scrollable content
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            // ── Personal Info Section ──
                            _sectionHeader('Informations Personnelles'),
                            const SizedBox(height: 12),
                            _fieldLabel('Nom complet'),
                            const SizedBox(height: 6),
                            _textField(nameCtrl, 'Nom complet', Icons.person_outlined),
                            const SizedBox(height: 16),
                            Row(children: [
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                _fieldLabel('Email'),
                                const SizedBox(height: 6),
                                _textField(emailCtrl, 'Adresse email', Icons.mail_outlined),
                              ])),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                _fieldLabel('Téléphone'),
                                const SizedBox(height: 6),
                                _textField(phoneCtrl, 'Numéro de téléphone', Icons.phone_outlined, inputFormatters: [FilteringTextInputFormatter.digitsOnly], keyboardType: TextInputType.phone),
                              ])),
                            ]),

                            const SizedBox(height: 24),
                            Divider(color: Colors.grey.shade100),
                            const SizedBox(height: 20),

                            // ── Subject/Matière Section ──
                            _sectionHeader('Matière Enseignée'),
                            const SizedBox(height: 12),
                            _fieldLabel('Matière'),
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              height: 48,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9FAFB),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: selectedSubjectId,
                                  isExpanded: true,
                                  icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade400, size: 20),
                                  hint: Row(children: [
                                    Icon(Icons.menu_book_rounded, size: 18, color: Colors.grey.shade400),
                                    const SizedBox(width: 10),
                                    Text('Sélectionner une matière', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                                  ]),
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                                  borderRadius: BorderRadius.circular(12),
                                  items: allSubjects.map((s) => DropdownMenuItem(
                                    value: s['id'] as String,
                                    child: Text(s['name']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
                                  )).toList(),
                                  onChanged: (v) => setDialogState(() => selectedSubjectId = v),
                                ),
                              ),
                            ),

                            const SizedBox(height: 24),
                            Divider(color: Colors.grey.shade100),
                            const SizedBox(height: 20),

                            // ── Niveaux Section ──
                            _sectionHeader('Niveaux & Classes'),
                            const SizedBox(height: 12),
                            _fieldLabel('Niveaux assignés'),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9FAFB),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                // Selected niveaux pills
                                if (selectedNiveauIds.isNotEmpty)
                                  Wrap(
                                    spacing: 8, runSpacing: 8,
                                    children: selectedNiveauIds.map((nId) {
                                      final nv = allNiveaux.firstWhere((n) => n['id'] == nId, orElse: () => {'name': nId});
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(color: _brandLight, borderRadius: BorderRadius.circular(8)),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          Text(nv['name']?.toString() ?? nId, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _brand)),
                                          const SizedBox(width: 4),
                                          InkWell(
                                            onTap: () => setDialogState(() {
                                              selectedNiveauIds.remove(nId);
                                              selectedClassIdsByNiveau.remove(nId);
                                              selectedSectionIdsByNiveau.remove(nId);
                                            }),
                                            child: const Icon(Icons.close_rounded, size: 14, color: _brand),
                                          ),
                                        ]),
                                      );
                                    }).toList(),
                                  ),
                                if (selectedNiveauIds.isNotEmpty) const SizedBox(height: 8),
                                // Add niveau dropdown
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: null,
                                      isExpanded: true,
                                      hint: const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 12),
                                        child: Text('+ Ajouter un niveau', style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      borderRadius: BorderRadius.circular(12),
                                      items: allNiveaux
                                          .where((n) => !selectedNiveauIds.contains(n['id']))
                                          .map((n) => DropdownMenuItem(
                                            value: n['id'] as String,
                                            child: Text(n['name']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
                                          )).toList(),
                                      onChanged: (v) {
                                        if (v != null) {
                                          setDialogState(() {
                                            selectedNiveauIds.add(v);
                                            selectedClassIdsByNiveau.putIfAbsent(v, () => {});
                                            selectedSectionIdsByNiveau.putIfAbsent(v, () => {});
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                            const SizedBox(height: 20),
                            // ── Classes per niveau ──
                            if (selectedNiveauIds.isNotEmpty) ...[
                              _fieldLabel('Classes par niveau'),
                              const SizedBox(height: 8),
                              ...selectedNiveauIds.map((nId) {
                                final nv = allNiveaux.firstWhere((n) => n['id'] == nId, orElse: () => {'name': nId});
                                final niveauClasses = allClasses.where((c) => c['niveau_id'] == nId).toList();
                                final selectedIds = selectedClassIdsByNiveau[nId] ?? {};

                                // Auto-detect sections: collect unique non-null section_ids from classes
                                final sectionsMap = <String, Map<String, dynamic>>{};
                                for (final c in niveauClasses) {
                                  final sectionId = c['section_id']?.toString();
                                  final sectionData = c['sections'];
                                  if (sectionId != null && sectionId.isNotEmpty && sectionData != null) {
                                    sectionsMap[sectionId] = Map<String, dynamic>.from(sectionData as Map);
                                  }
                                }

                                // If this niveau has sections, show section-based UI
                                if (sectionsMap.isNotEmpty) {
                                  final sectionsList = sectionsMap.values.toList()
                                    ..sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
                                  final selectedSectionIds = selectedSectionIdsByNiveau.putIfAbsent(nId, () => {});

                                  return Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.grey.shade200),
                                    ),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      // Niveau label + count
                                      Row(children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(color: _brandLight, borderRadius: BorderRadius.circular(6)),
                                          child: Text(nv['name']?.toString() ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _brand)),
                                        ),
                                        const Spacer(),
                                        Text('${selectedIds.length}/${niveauClasses.length}', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                                      ]),
                                      const SizedBox(height: 12),
                                      // Section chips row
                                      Text('Sections', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8, runSpacing: 8,
                                        children: sectionsList.map((sec) {
                                          final sId = sec['id']?.toString() ?? '';
                                          final isSecSelected = selectedSectionIds.contains(sId);
                                          final sectionClasses = niveauClasses.where((c) => c['section_id']?.toString() == sId).toList();
                                          return InkWell(
                                            onTap: () => setDialogState(() {
                                              if (isSecSelected) {
                                                selectedSectionIds.remove(sId);
                                                for (final c in sectionClasses) {
                                                  selectedClassIdsByNiveau[nId]?.remove(c['id']?.toString());
                                                }
                                              } else {
                                                selectedSectionIds.add(sId);
                                              }
                                            }),
                                            borderRadius: BorderRadius.circular(8),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                              decoration: BoxDecoration(
                                                color: isSecSelected ? _brandLight : const Color(0xFFF3F4F6),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: isSecSelected ? _brand.withOpacity(0.4) : Colors.grey.shade200),
                                              ),
                                              child: Text(
                                                sec['name']?.toString() ?? '',
                                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isSecSelected ? _brand : AppColors.textSecondary),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                      // Classes per selected section
                                      if (selectedSectionIds.isNotEmpty) ...[
                                        const SizedBox(height: 14),
                                        ...selectedSectionIds.map((sId) {
                                          final secData = sectionsMap[sId];
                                          if (secData == null) return const SizedBox.shrink();
                                          final sectionClasses = niveauClasses.where((c) => c['section_id']?.toString() == sId).toList();
                                          final allSelected = sectionClasses.isNotEmpty && sectionClasses.every((c) => selectedIds.contains(c['id']?.toString()));
                                          return Container(
                                            margin: const EdgeInsets.only(bottom: 10),
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF9FAFB),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: _brand.withOpacity(0.15)),
                                            ),
                                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                              Row(children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                  decoration: BoxDecoration(color: _brand, borderRadius: BorderRadius.circular(5)),
                                                  child: Text(secData['code']?.toString() ?? '', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(secData['name']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                                const Spacer(),
                                                GestureDetector(
                                                  onTap: () => setDialogState(() {
                                                    for (final c in sectionClasses) {
                                                      final cId = c['id']?.toString() ?? '';
                                                      if (allSelected) {
                                                        selectedClassIdsByNiveau[nId]?.remove(cId);
                                                      } else {
                                                        selectedClassIdsByNiveau[nId]?.add(cId);
                                                      }
                                                    }
                                                  }),
                                                  child: Text(
                                                    allSelected ? 'Tout désélectionner' : 'Tout sélectionner',
                                                    style: const TextStyle(fontSize: 11, color: _brand, fontWeight: FontWeight.w600),
                                                  ),
                                                ),
                                              ]),
                                              const SizedBox(height: 8),
                                              Wrap(
                                                spacing: 6, runSpacing: 6,
                                                children: sectionClasses.map((c) {
                                                  final cId = c['id']?.toString() ?? '';
                                                  final isSelected = selectedIds.contains(cId);
                                                  return InkWell(
                                                    onTap: () => setDialogState(() {
                                                      if (isSelected) {
                                                        selectedClassIdsByNiveau[nId]!.remove(cId);
                                                      } else {
                                                        selectedClassIdsByNiveau[nId]!.add(cId);
                                                      }
                                                    }),
                                                    borderRadius: BorderRadius.circular(7),
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                                      decoration: BoxDecoration(
                                                        color: isSelected ? _brand : Colors.white,
                                                        borderRadius: BorderRadius.circular(7),
                                                        border: Border.all(color: isSelected ? _brand : Colors.grey.shade300),
                                                      ),
                                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                        if (isSelected) ...[
                                                          const Icon(Icons.check_rounded, size: 12, color: Colors.white),
                                                          const SizedBox(width: 3),
                                                        ],
                                                        Text(c['name']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isSelected ? Colors.white : AppColors.textPrimary)),
                                                      ]),
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                            ]),
                                          );
                                        }),
                                      ],
                                    ]),
                                  );
                                }

                                // No sections — flat class list
                                return Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Row(children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(color: _brandLight, borderRadius: BorderRadius.circular(6)),
                                        child: Text(nv['name']?.toString() ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _brand)),
                                      ),
                                      const Spacer(),
                                      Text('${selectedIds.length}/${niveauClasses.length}', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                                    ]),
                                    const SizedBox(height: 8),
                                    if (niveauClasses.isEmpty)
                                      Text('Aucune classe dans ce niveau', style: TextStyle(fontSize: 12, color: Colors.grey.shade400))
                                    else
                                      Wrap(
                                        spacing: 8, runSpacing: 8,
                                        children: niveauClasses.map((c) {
                                          final cId = c['id']?.toString() ?? '';
                                          final isSelected = selectedIds.contains(cId);
                                          return InkWell(
                                            onTap: () => setDialogState(() {
                                              if (isSelected) {
                                                selectedClassIdsByNiveau[nId]!.remove(cId);
                                              } else {
                                                selectedClassIdsByNiveau[nId]!.add(cId);
                                              }
                                            }),
                                            borderRadius: BorderRadius.circular(8),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: isSelected ? _brand : const Color(0xFFF9FAFB),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: isSelected ? _brand : Colors.grey.shade200),
                                              ),
                                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                if (isSelected) ...[
                                                  const Icon(Icons.check_rounded, size: 13, color: Colors.white),
                                                  const SizedBox(width: 4),
                                                ],
                                                Text(c['name']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isSelected ? Colors.white : AppColors.textPrimary)),
                                              ]),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                  ]),
                                );
                              }),
                              const SizedBox(height: 4),
                            ],
                          ]),
                        ),
                      ),
                      // Bottom buttons
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                        child: Column(children: [
                          Divider(height: 1, color: Colors.grey.shade200),
                          const SizedBox(height: 14),
                          Row(children: [
                            const Spacer(),
                            SizedBox(
                              height: 40,
                              child: TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF6B7280),
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                ),
                                child: const Text('Annuler', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              height: 40,
                              child: ElevatedButton.icon(
                                onPressed: saving
                                    ? null
                                    : () async {
                                        setDialogState(() => saving = true);
                                        try {
                                          final supabase = SupabaseConfig.adminClient;

                                          // 1. Update user profile fields
                                          final updates = <String, dynamic>{};
                                          final newName = nameCtrl.text.trim();
                                          final newEmail = emailCtrl.text.trim();
                                          final newPhone = phoneCtrl.text.trim();
                                          if (newName.isNotEmpty && newName != _user?['full_name']) updates['full_name'] = newName;
                                          if (newEmail.isNotEmpty && newEmail != _user?['email']) updates['email'] = newEmail;
                                          if (newPhone != (_user?['phone'] ?? '')) updates['phone'] = newPhone;

                                          if (updates.isNotEmpty) {
                                            await supabase.from('users').update(updates).eq('id', widget.teacherId);
                                          }

                                          // 2. Sync teacher_assignments: delete removed, add new
                                          // Deactivate all current assignments
                                          for (final a in originalAssignments) {
                                            final aId = a['id']?.toString();
                                            if (aId != null && aId.isNotEmpty) {
                                              await supabase.from('teacher_assignments').update({'is_active': false}).eq('id', aId);
                                            }
                                          }

                                          // Build new assignment set from selected niveaux + classes
                                          for (final nId in selectedNiveauIds) {
                                            final classIds = selectedClassIdsByNiveau[nId] ?? {};
                                            if (classIds.isEmpty) {
                                              // Assigned to niveau but no specific class
                                              await supabase.from('teacher_assignments').insert({
                                                'teacher_id': widget.teacherId,
                                                'subject_id': selectedSubjectId,
                                                'niveau_id': nId,
                                                'class_id': null,
                                                'school_id': schoolId,
                                                'is_active': true,
                                              });
                                            } else {
                                              // One assignment per class
                                              for (final cId in classIds) {
                                                await supabase.from('teacher_assignments').insert({
                                                  'teacher_id': widget.teacherId,
                                                  'subject_id': selectedSubjectId,
                                                  'niveau_id': nId,
                                                  'class_id': cId,
                                                  'school_id': schoolId,
                                                  'is_active': true,
                                                });
                                              }
                                            }
                                          }

                                          if (ctx.mounted) Navigator.of(ctx).pop();
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: const Text('Profil et affectations mis à jour'), backgroundColor: const Color(0xFF16A34A), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                            );
                                            setState(() => _loading = true);
                                            _classDetails = [];
                                            _subjects = {};
                                            _niveaux = {};
                                            _loadData();
                                          }
                                        } catch (e) {
                                          setDialogState(() => saving = false);
                                          if (ctx.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  UserFriendlyError.format(
                                                    e,
                                                    fallback: 'Unable to save teacher details right now. Please try again.',
                                                  ),
                                                ),
                                                backgroundColor: Colors.red,
                                                behavior: SnackBarBehavior.floating,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                icon: saving
                                    ? const IosLoader.small(color: Colors.white)
                                    : const Icon(Icons.check_rounded, size: 17),
                                label: const Text('Enregistrer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6D4CF6),
                                  foregroundColor: Colors.white,
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                  disabledBackgroundColor: Colors.grey.shade300,
                                ),
                              ),
                            ),
                          ]),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Row(children: [
      Container(width: 3, height: 16, decoration: BoxDecoration(color: const Color(0xFF6D4CF6), borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(title.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.8)),
    ]);
  }

  Widget _fieldLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
    );
  }

  Widget _textField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    List<TextInputFormatter>? inputFormatters,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.w400),
        prefixIcon: Icon(icon, size: 18, color: AppColors.textTertiary),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _brand, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}

