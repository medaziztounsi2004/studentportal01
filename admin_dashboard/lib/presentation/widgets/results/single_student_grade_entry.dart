import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../skeleton_loader.dart';
import '../user_avatar.dart';
import 'subject_exam_config_dialog.dart';

/// A widget for entering grades for a SINGLE student
/// Shows all subjects in a modern DataTable layout matching the users screen
class SingleStudentGradeEntry extends StatefulWidget {
  final Map<String, dynamic> student;
  final List<Map<String, dynamic>> subjectOfferings;
  final Function(List<Map<String, dynamic>> grades) onSaveGrades;
  final VoidCallback onBack;
  final VoidCallback? onRefresh;
  final String? levelId; // Level/Niveau ID for applying config to all classes
  final String? semesterId; // Current semester ID
  final String? externalSearchQuery; // Search query from header search bar

  const SingleStudentGradeEntry({
    super.key,
    required this.student,
    required this.subjectOfferings,
    required this.onSaveGrades,
    required this.onBack,
    this.onRefresh,
    this.levelId,
    this.semesterId,
    this.externalSearchQuery,
  });

  @override
  State<SingleStudentGradeEntry> createState() => _SingleStudentGradeEntryState();
}

class _SingleStudentGradeEntryState extends State<SingleStudentGradeEntry> {
  final Map<String, Map<String, TextEditingController>> _gradeControllers = {};
  final Map<String, Map<String, String>> _gradeStatus = {};
  final Set<String> _selectedOfferingIds = {};
  bool _isLoadingGrades = true;

  String get _effectiveSearchQuery =>
      (widget.externalSearchQuery ?? '').trim().toLowerCase();

  /// Get the student's full name from nested users object
  String get _studentName {
    final users = widget.student['users'] as Map<String, dynamic>?;
    if (users != null && users['full_name'] != null) {
      return users['full_name'].toString();
    }
    return widget.student['full_name']?.toString() ?? 'Élève';
  }

  /// Get photo URL
  String? get _studentPhotoUrl {
    final users = widget.student['users'] as Map<String, dynamic>?;
    return users?['photo_url']?.toString() ?? widget.student['photo_url']?.toString();
  }

  /// Get gender
  String? get _studentGender {
    final users = widget.student['users'] as Map<String, dynamic>?;
    return users?['gender']?.toString() ?? widget.student['gender']?.toString();
  }

  /// Get student code
  String get _studentCode {
    final enrollmentCode = widget.student['student_code'];
    if (enrollmentCode != null && enrollmentCode.toString().isNotEmpty) {
      return enrollmentCode.toString();
    }
    final users = widget.student['users'] as Map<String, dynamic>?;
    if (users != null) {
      final userCode = users['student_code'];
      if (userCode != null && userCode.toString().isNotEmpty) {
        return userCode.toString();
      }
    }
    return 'N/A';
  }

  String get _enrollmentId => widget.student['id'] as String? ?? '';

  String? get _userId {
    String? userId = widget.student['user_id'] as String?;
    if (userId == null) {
      final users = widget.student['users'] as Map<String, dynamic>?;
      userId = users?['id'] as String?;
    }
    return userId;
  }

  @override
  void initState() {
    super.initState();
    _initControllers();
    _loadExistingGrades();
  }

  @override
  void didUpdateWidget(SingleStudentGradeEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subjectOfferings != widget.subjectOfferings) {
      _initControllers();
      _loadExistingGrades();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (final subjectControllers in _gradeControllers.values) {
      for (final controller in subjectControllers.values) {
        controller.dispose();
      }
    }
    _gradeControllers.clear();
    _gradeStatus.clear();
  }

  void _initControllers() {
    _disposeControllers();

    for (final offering in widget.subjectOfferings) {
      final offeringId = offering['id'] as String;
      final components = offering['grade_components'] as List?;

      if (components != null && components.isNotEmpty) {
        _gradeControllers[offeringId] = {};
        _gradeStatus[offeringId] = {};

        for (final comp in components) {
          final componentId = comp['id'] as String;
          _gradeControllers[offeringId]![componentId] = TextEditingController();
          _gradeStatus[offeringId]![componentId] = 'OK';
        }
      }
    }
  }

  /// Load existing grades from database and populate controllers
  Future<void> _loadExistingGrades() async {
    if (_enrollmentId.isEmpty) {
      setState(() => _isLoadingGrades = false);
      return;
    }

    try {
      final supabase = Supabase.instance.client;

      // Get all grades for this enrollment
      final grades = await supabase
          .from('grades')
          .select('subject_offering_id, component_id, grade_value, status')
          .eq('enrollment_id', _enrollmentId);

      // Populate controllers with existing values
      for (final grade in grades) {
        final offeringId = grade['subject_offering_id'] as String?;
        final componentId = grade['component_id'] as String?;
        final gradeValue = grade['grade_value'];
        final status = grade['status'] as String? ?? 'OK';

        if (offeringId != null && componentId != null) {
          final controller = _gradeControllers[offeringId]?[componentId];
          if (controller != null && gradeValue != null) {
            controller.text = gradeValue.toString();
          }
          if (_gradeStatus[offeringId] != null) {
            _gradeStatus[offeringId]![componentId] = status;
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading existing grades: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingGrades = false);
      }
    }
  }

  Future<void> _saveGradesForOffering(String offeringId) async {
    if (_enrollmentId.isEmpty || _userId == null) return;
    setState(() => _isLoadingGrades = true);
    try {
      final subjectControllers = _gradeControllers[offeringId];
      final subjectStatus = _gradeStatus[offeringId];
      if (subjectControllers == null || subjectStatus == null) return;

      final grades = <Map<String, dynamic>>[];
      for (final entry in subjectControllers.entries) {
        final componentId = entry.key;
        final controller = entry.value;
        final status = subjectStatus[componentId] ?? 'OK';
        double? gradeValue;
        if (controller.text.isNotEmpty) {
          gradeValue = double.tryParse(controller.text.replaceAll(',', '.'));
        }
        if (gradeValue != null || status != 'OK') {
          grades.add({
            'enrollment_id': _enrollmentId,
            'student_id': _userId,
            'subject_offering_id': offeringId,
            'component_id': componentId,
            'grade_value': gradeValue,
            'status': status,
          });
        }
      }
      if (grades.isNotEmpty) {
        await widget.onSaveGrades(grades);
        await _loadExistingGrades();
        widget.onRefresh?.call();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Notes enregistrées avec succès'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFriendlyError.format(e, fallback: 'Erreur lors de l\'enregistrement')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingGrades = false);
    }
  }

  Future<void> _saveGradesForSelected() async {
    if (_enrollmentId.isEmpty || _userId == null) return;
    setState(() => _isLoadingGrades = true);
    try {
      final grades = <Map<String, dynamic>>[];
      for (final offeringId in _selectedOfferingIds) {
        final subjectControllers = _gradeControllers[offeringId];
        final subjectStatus = _gradeStatus[offeringId];
        if (subjectControllers == null || subjectStatus == null) continue;

        for (final entry in subjectControllers.entries) {
          final componentId = entry.key;
          final controller = entry.value;
          final status = subjectStatus[componentId] ?? 'OK';
          double? gradeValue;
          if (controller.text.isNotEmpty) {
            gradeValue = double.tryParse(controller.text.replaceAll(',', '.'));
          }
          if (gradeValue != null || status != 'OK') {
            grades.add({
              'enrollment_id': _enrollmentId,
              'student_id': _userId,
              'subject_offering_id': offeringId,
              'component_id': componentId,
              'grade_value': gradeValue,
              'status': status,
            });
          }
        }
      }

      if (grades.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Aucune note à enregistrer pour les matières sélectionnées'),
              backgroundColor: AppColors.warning,
            ),
          );
        }
        return;
      }

      await widget.onSaveGrades(grades);
      await _loadExistingGrades();
      widget.onRefresh?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${grades.length} note(s) enregistrée(s)'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFriendlyError.format(e, fallback: 'Erreur lors de l\'enregistrement')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingGrades = false);
    }
  }

  Future<void> _clearGradesForSelected() async {
    if (_selectedOfferingIds.isEmpty) return;
    final count = _selectedOfferingIds.length;
    final confirmed = await showDialog<bool>(
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
                decoration: BoxDecoration(color: AppColors.errorSoft, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                count > 1 ? 'Effacer les notes ($count) ?' : 'Effacer les notes ?',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                count > 1
                    ? 'Voulez-vous vraiment effacer les notes pour ces $count matières ?'
                    : 'Voulez-vous vraiment effacer les notes pour la matière sélectionnée ?',
              ),
              const SizedBox(height: 6),
              const Text(
                'Cette action est irréversible. Les notes saisies seront définitivement supprimées.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: Text(count > 1 ? 'Effacer $count' : 'Effacer', style: const TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
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

    if (confirmed != true) return;

    setState(() => _isLoadingGrades = true);
    final offeringIds = _selectedOfferingIds.toList();
    try {
      if (_enrollmentId.isNotEmpty) {
        final supabase = Supabase.instance.client;
        await supabase
            .from('grades')
            .delete()
            .eq('enrollment_id', _enrollmentId)
            .inFilter('subject_offering_id', offeringIds);
      }
      for (final offeringId in offeringIds) {
        final subjectControllers = _gradeControllers[offeringId];
        final subjectStatus = _gradeStatus[offeringId];
        if (subjectControllers != null) {
          for (final c in subjectControllers.values) {
            c.clear();
          }
        }
        if (subjectStatus != null) {
          for (final k in subjectStatus.keys) {
            subjectStatus[k] = 'OK';
          }
        }
      }
      _selectedOfferingIds.clear();
      await _loadExistingGrades();
      widget.onRefresh?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notes effacées avec succès'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFriendlyError.format(e, fallback: 'Erreur lors de la suppression des notes')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingGrades = false);
    }
  }

  Future<void> _confirmClearGradesForOffering(String offeringId, String subjectName) async {
    final confirmed = await showDialog<bool>(
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
                decoration: BoxDecoration(color: AppColors.errorSoft, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
              ),
              const SizedBox(width: 12),
              const Text('Effacer les notes ?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Voulez-vous vraiment effacer les notes pour "$subjectName" ?'),
              const SizedBox(height: 6),
              const Text(
                'Cette action est irréversible. Les notes saisies seront définitivement supprimées.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Effacer', style: TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
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

    if (confirmed != true) return;

    setState(() => _isLoadingGrades = true);
    try {
      if (_enrollmentId.isNotEmpty) {
        final supabase = Supabase.instance.client;
        await supabase
            .from('grades')
            .delete()
            .eq('enrollment_id', _enrollmentId)
            .eq('subject_offering_id', offeringId);
      }
      final subjectControllers = _gradeControllers[offeringId];
      final subjectStatus = _gradeStatus[offeringId];
      if (subjectControllers != null) {
        for (final c in subjectControllers.values) {
          c.clear();
        }
      }
      if (subjectStatus != null) {
        for (final k in subjectStatus.keys) {
          subjectStatus[k] = 'OK';
        }
      }
      await _loadExistingGrades();
      widget.onRefresh?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Notes effacées pour $subjectName'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFriendlyError.format(e, fallback: 'Erreur lors de la suppression des notes')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingGrades = false);
    }
  }

  /// Show dialog to configure exam types for a subject
  void _showExamConfigDialog(
    String subjectOfferingId,
    String subjectName,
    String subjectId,
    List<dynamic> currentComponents,
  ) {
    showDialog(
      context: context,
      builder: (context) => SubjectExamConfigDialog(
        subjectOfferingId: subjectOfferingId,
        subjectName: subjectName,
        subjectId: subjectId,
        levelId: widget.levelId,
        semesterId: widget.semesterId,
        currentComponents: currentComponents
            .map((c) => c as Map<String, dynamic>)
            .toList(),
        onSaved: () {
          widget.onRefresh?.call();
        },
      ),
    );
  }

  String _getComponentDisplayName(String name) {
    switch (name.toUpperCase()) {
      case 'ORALE':
        return 'Orale';
      case 'CC':
        return 'Contrôle Continu';
      case 'SYNTHESE':
      case 'SYNTHÈSE':
        return 'Synthèse';
      case 'TP':
        return 'Travaux Pratiques';
      case 'EXAMEN':
        return 'Examen';
      default:
        return name;
    }
  }

  Color _getComponentColor(String name) {
    switch (name.toUpperCase()) {
      case 'ORALE':
        return const Color(0xFF2563EB); // Blue
      case 'CC':
        return const Color(0xFF7C3AED); // Purple
      case 'SYNTHESE':
      case 'SYNTHÈSE':
        return const Color(0xFFDB2777); // Pink
      case 'TP':
        return const Color(0xFF059669); // Green
      case 'EXAMEN':
        return const Color(0xFFD97706); // Amber
      default:
        return const Color(0xFF475569); // Slate
    }
  }

  IconData _getComponentIcon(String name) {
    switch (name.toUpperCase()) {
      case 'ORALE':
        return Icons.mic_rounded;
      case 'CC':
        return Icons.edit_document;
      case 'SYNTHESE':
      case 'SYNTHÈSE':
        return Icons.auto_stories_rounded;
      case 'TP':
        return Icons.science_rounded;
      case 'EXAMEN':
        return Icons.assignment_rounded;
      default:
        return Icons.grade_rounded;
    }
  }

  List<Map<String, dynamic>> _getFilteredOfferings() {
    final query = _effectiveSearchQuery;
    return widget.subjectOfferings.where((offering) {
      if (query.isEmpty) return true;
      final subject = offering['subjects'] as Map<String, dynamic>?;
      final name = (subject?['name']?.toString() ?? '').toLowerCase();
      final code = (subject?['code']?.toString() ?? '').toLowerCase();
      return name.contains(query) || code.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredOfferings = _getFilteredOfferings();

    return Container(
      color: const Color(0xFFF8FAFC),
      child: Stack(
        children: [
          Column(
            children: [
              _buildHeader(filteredOfferings),
              Expanded(
                child: _isLoadingGrades
                    ? const SingleStudentGradeEntrySkeletonLoader()
                    : widget.subjectOfferings.isEmpty
                        ? _buildNoSubjectsMessage()
                        : _buildSubjectsTable(filteredOfferings),
              ),
            ],
          ),
          if (_selectedOfferingIds.isNotEmpty)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: _buildFloatingSelectionBar(context, filteredOfferings),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(List<Map<String, dynamic>> filteredOfferings) {
    final photoUrl = _studentPhotoUrl;
    final gender = _studentGender;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          // Student Avatar
          UserAvatar(
            name: _studentName,
            photoUrl: photoUrl,
            gender: gender,
            radius: 20,
          ),
          const SizedBox(width: 14),
          // Student info (clean: no class/niveau pills)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _studentName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      'Matricule : ',
                      style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                    ),
                    Text(
                      _studentCode,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        color: Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Light pill for subject count (placed correctly on the right)
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9999),
              border: Border.all(color: const Color(0xFFECECF3)),
            ),
            child: Center(
              child: Text(
                '${filteredOfferings.length} matière(s)',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSubjectsMessage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.menu_book_rounded, size: 36, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 18),
          const Text(
            'Aucune matière configurée',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Les matières et types d\'examens doivent être configurés\npour cette classe et ce semestre.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _headerLabel(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textTertiary,
          fontSize: 11,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSubjectsTable(List<Map<String, dynamic>> filteredOfferings) {
    final query = _effectiveSearchQuery;

    if (filteredOfferings.isEmpty && query.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.search_off_rounded, size: 28, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Aucune matière trouvée',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 4),
              Text(
                'Aucune matière ne correspond à "$query"',
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            const checkboxW = 44.0;
            const actionsW = 44.0;
            const codeW = 90.0;
            const coefW = 90.0;
            const evalW = 290.0;
            const noteW = 120.0;
            const statutW = 110.0;

            final fixedW = checkboxW + codeW + coefW + evalW + noteW + statutW + actionsW;
            final nameW = (availableWidth - fixedW).clamp(140.0, 280.0);
            final allSelected = filteredOfferings.isNotEmpty &&
                filteredOfferings.every((o) => _selectedOfferingIds.contains(o['id'] as String));

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
                  headingTextStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textTertiary,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                  showCheckboxColumn: false,
                  columns: [
                    // Checkbox column with Select All
                    DataColumn(
                      label: SizedBox(
                        width: checkboxW,
                        child: Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: Checkbox(
                              value: allSelected && filteredOfferings.isNotEmpty,
                              tristate: false,
                              onChanged: (v) {
                                setState(() {
                                  if (allSelected) {
                                    for (final o in filteredOfferings) {
                                      _selectedOfferingIds.remove(o['id'] as String);
                                    }
                                  } else {
                                    for (final o in filteredOfferings) {
                                      _selectedOfferingIds.add(o['id'] as String);
                                    }
                                  }
                                });
                              },
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                              side: BorderSide(color: AppColors.slate300, width: 1.5),
                              activeColor: const Color(0xFF655DD5),
                            ),
                          ),
                        ),
                      ),
                    ),
                    DataColumn(label: SizedBox(width: codeW, child: _headerLabel('CODE'))),
                    DataColumn(label: SizedBox(width: nameW, child: _headerLabel('MATIÈRE'))),
                    DataColumn(label: SizedBox(width: coefW, child: _headerLabel('COEFFICIENT'))),
                    DataColumn(label: SizedBox(width: evalW, child: _headerLabel('ÉVALUATIONS'))),
                    DataColumn(label: SizedBox(width: noteW, child: _headerLabel('NOTE / MOYENNE'))),
                    DataColumn(label: SizedBox(width: statutW, child: _headerLabel('STATUT'))),
                    DataColumn(label: SizedBox(width: actionsW, child: Container())),
                  ],
                  rows: filteredOfferings.map((offering) {
                    final offeringId = offering['id'] as String;
                    final subject = offering['subjects'] as Map<String, dynamic>?;
                    final subjectName = subject?['name'] as String? ?? 'Matière';
                    final subjectCode = subject?['code'] as String? ?? '';
                    final subjectId = subject?['id'] as String? ?? '';
                    final coefficient = offering['coefficient'] as num? ?? 1.0;
                    final components = offering['grade_components'] as List?;
                    final hasComponents = components != null && components.isNotEmpty;
                    final isSelected = _selectedOfferingIds.contains(offeringId);

                    return DataRow(
                      color: WidgetStateProperty.resolveWith<Color?>((states) {
                        if (isSelected) return const Color(0xFFF5F3FF).withOpacity(0.4);
                        if (states.contains(WidgetState.hovered)) return const Color(0xFFF9FAFB);
                        return null;
                      }),
                      onSelectChanged: (_) => _handleAction('edit_grades', offering),
                      cells: [
                        // Checkbox
                        DataCell(
                          SizedBox(
                            width: checkboxW,
                            child: Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: Checkbox(
                                  value: isSelected,
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selectedOfferingIds.add(offeringId);
                                      } else {
                                        _selectedOfferingIds.remove(offeringId);
                                      }
                                    });
                                  },
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                                  side: BorderSide(color: AppColors.slate300, width: 1.5),
                                  activeColor: const Color(0xFF655DD5),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Code
                        DataCell(
                          SizedBox(
                            width: codeW,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(9999),
                                  ),
                                  child: Text(
                                    subjectCode.isNotEmpty ? subjectCode : '—',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          onTap: () => _showGradeEntryDialog(offering),
                        ),
                        // Nom de la matière
                        DataCell(
                          SizedBox(
                            width: nameW,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF655DD5).withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.menu_book_rounded, color: Color(0xFF655DD5), size: 16),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      subjectName,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF0F172A),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          onTap: () => _showGradeEntryDialog(offering),
                        ),
                        // Coefficient
                        DataCell(
                          SizedBox(
                            width: coefW,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEEF2FF),
                                    borderRadius: BorderRadius.circular(9999),
                                  ),
                                  child: Text(
                                    'Coef $coefficient',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF4F46E5),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          onTap: () => _showGradeEntryDialog(offering),
                        ),
                        // Évaluations
                        DataCell(
                          SizedBox(
                            width: evalW,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: !hasComponents
                                  ? Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFFBEB),
                                          borderRadius: BorderRadius.circular(9999),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.warning_amber_rounded, size: 13, color: Color(0xFFD97706)),
                                            SizedBox(width: 4),
                                            Text(
                                              'Non configuré',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFFB45309),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: components.map<Widget>((c) {
                                          final compMap = c as Map<String, dynamic>;
                                          final compName = compMap['name']?.toString() ?? '';
                                          final weight = compMap['weight_percent'] ?? 0;
                                          final col = _getComponentColor(compName);
                                          return Padding(
                                            padding: const EdgeInsets.only(right: 6),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: col.withOpacity(0.08),
                                                borderRadius: BorderRadius.circular(9999),
                                              ),
                                              child: Text(
                                                '$compName ($weight%)',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: col,
                                                ),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                            ),
                          ),
                          onTap: () => hasComponents
                              ? _showGradeEntryDialog(offering)
                              : _showExamConfigDialog(offeringId, subjectName, subjectId, []),
                        ),
                        // Note / Moyenne
                        DataCell(
                          SizedBox(
                            width: noteW,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: _buildGradeSummaryCell(offeringId, components),
                            ),
                          ),
                          onTap: () => _showGradeEntryDialog(offering),
                        ),
                        // Statut
                        DataCell(
                          SizedBox(
                            width: statutW,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: _buildStatusCell(offeringId, components),
                            ),
                          ),
                          onTap: () => _showGradeEntryDialog(offering),
                        ),
                        // Actions (Three dots)
                        DataCell(
                          SizedBox(
                            width: actionsW,
                            child: PopupMenuButton<String>(
                              icon: Icon(Icons.more_horiz, size: 18, color: AppColors.textTertiary),
                              tooltip: 'Actions',
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 8,
                              offset: const Offset(-160, 40),
                              onSelected: (action) => _handleAction(action, offering),
                              itemBuilder: (ctx) => [
                                _buildPopupItem('edit_grades', Icons.edit_note_rounded, 'Saisir les notes', const Color(0xFF655DD5)),
                                _buildPopupItem('config', Icons.tune_rounded, 'Configurer l\'évaluation', AppColors.textSecondary),
                                const PopupMenuDivider(),
                                _buildPopupItem('clear', Icons.delete_outline_rounded, 'Effacer les notes', AppColors.error),
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
        ),
      ),
    );
  }

  Widget _buildGradeSummaryCell(String offeringId, List<dynamic>? components) {
    if (components == null || components.isEmpty) {
      return Text('—', style: TextStyle(color: AppColors.slate400, fontSize: 12));
    }

    double weightedSum = 0;
    double totalWeight = 0;
    int filledCount = 0;
    bool hasNonOk = false;
    String? nonOkStatus;

    for (final c in components) {
      final comp = c as Map<String, dynamic>;
      final compId = comp['id'] as String;
      final weight = (comp['weight_percent'] as num? ?? 0).toDouble();
      final status = _gradeStatus[offeringId]?[compId] ?? 'OK';
      if (status != 'OK') {
        hasNonOk = true;
        nonOkStatus = status;
      }
      final text = _gradeControllers[offeringId]?[compId]?.text.trim() ?? '';
      if (text.isNotEmpty) {
        final val = double.tryParse(text.replaceAll(',', '.'));
        if (val != null) {
          weightedSum += val * weight;
          totalWeight += weight;
          filledCount++;
        }
      }
    }

    if (hasNonOk && filledCount == 0) {
      final color = nonOkStatus == 'ND' ? const Color(0xFFD97706) : const Color(0xFFDC2626);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Text(
          nonOkStatus ?? '—',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
        ),
      );
    }

    if (filledCount > 0 && totalWeight > 0) {
      final avg = weightedSum / totalWeight;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            avg.toStringAsFixed(2),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: avg >= 10 ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
            ),
          ),
          const Text(
            ' / 20',
            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
          ),
        ],
      );
    }

    return Text(
      '— / 20',
      style: TextStyle(fontSize: 12, color: AppColors.slate400, fontWeight: FontWeight.w500),
    );
  }

  Widget _buildStatusCell(String offeringId, List<dynamic>? components) {
    if (components == null || components.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(9999),
        ),
        child: const Text(
          'À configurer',
          style: TextStyle(color: Color(0xFFD97706), fontSize: 11, fontWeight: FontWeight.w600),
        ),
      );
    }

    int filledCount = 0;
    bool hasNonOk = false;
    for (final c in components) {
      final comp = c as Map<String, dynamic>;
      final compId = comp['id'] as String;
      final status = _gradeStatus[offeringId]?[compId] ?? 'OK';
      if (status != 'OK') hasNonOk = true;
      final text = _gradeControllers[offeringId]?[compId]?.text.trim() ?? '';
      if (text.isNotEmpty) filledCount++;
    }

    if (filledCount == components.length) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(9999),
        ),
        child: const Text(
          'Complète',
          style: TextStyle(color: Color(0xFF16A34A), fontSize: 11, fontWeight: FontWeight.w600),
        ),
      );
    }

    if (filledCount > 0 || hasNonOk) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Text(
          'Partielle ($filledCount/${components.length})',
          style: const TextStyle(color: Color(0xFF2563EB), fontSize: 11, fontWeight: FontWeight.w600),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(9999),
      ),
      child: const Text(
        'En attente',
        style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }

  PopupMenuItem<String> _buildPopupItem(String value, IconData icon, String label, Color color) {
    return PopupMenuItem(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: value == 'clear' ? AppColors.error : AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _handleAction(String action, Map<String, dynamic> offering) {
    final offeringId = offering['id'] as String;
    final subject = offering['subjects'] as Map<String, dynamic>?;
    final subjectName = subject?['name'] as String? ?? 'Matière';
    final subjectId = subject?['id'] as String? ?? '';
    final components = offering['grade_components'] as List? ?? [];

    switch (action) {
      case 'edit_grades':
        _showGradeEntryDialog(offering);
        break;
      case 'config':
        _showExamConfigDialog(offeringId, subjectName, subjectId, components);
        break;
      case 'clear':
        _confirmClearGradesForOffering(offeringId, subjectName);
        break;
    }
  }

  void _showGradeEntryDialog(Map<String, dynamic> offering) {
    final subject = offering['subjects'] as Map<String, dynamic>?;
    final subjectName = subject?['name'] as String? ?? 'Matière';
    final subjectCode = subject?['code'] as String? ?? '';
    final subjectId = subject?['id'] as String? ?? '';
    final coefficient = offering['coefficient'] as num? ?? 1.0;
    final components = (offering['grade_components'] as List?)
            ?.map((c) => c as Map<String, dynamic>)
            .toList() ??
        [];
    final offeringId = offering['id'] as String;

    if (components.isEmpty) {
      _showExamConfigDialog(offeringId, subjectName, subjectId, []);
      return;
    }

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.2),
      builder: (dialogCtx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: StatefulBuilder(
            builder: (dCtx, setDialogState) {
              double weightedSum = 0;
              double totalWeight = 0;
              int filled = 0;
              for (final comp in components) {
                final compId = comp['id'] as String;
                final weight = (comp['weight_percent'] as num? ?? 0).toDouble();
                final ctrl = _gradeControllers[offeringId]?[compId];
                if (ctrl != null && ctrl.text.trim().isNotEmpty) {
                  final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
                  if (v != null) {
                    weightedSum += v * weight;
                    totalWeight += weight;
                    filled++;
                  }
                }
              }
              final double? liveAverage = (filled > 0 && totalWeight > 0)
                  ? (weightedSum / totalWeight)
                  : null;

              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Container(
                  width: 580,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 50,
                        offset: const Offset(0, 20),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                          border: Border(bottom: BorderSide(color: AppColors.slate100)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFF6D4CF6).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Center(
                                child: Icon(Icons.edit_note_rounded, color: Color(0xFF6D4CF6), size: 24),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          subjectName,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0F172A),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (subjectCode.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.slate100,
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: Text(
                                            subjectCode,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontFamily: 'monospace',
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEEF2FF),
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                        child: Text(
                                          'Coef $coefficient',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF4F46E5),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Élève : $_studentName • $_studentCode',
                                    style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                                  ),
                                ],
                              ),
                            ),
                            InkWell(
                              onTap: () => Navigator.pop(dialogCtx),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.slate50),
                                child: const Icon(Icons.close, size: 18, color: AppColors.textTertiary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Body: Grade inputs for components
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final comp in components) ...[
                                _buildDialogComponentRow(offeringId, comp, setDialogState),
                                const SizedBox(height: 14),
                              ],
                              const SizedBox(height: 10),
                              // Average preview banner
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.calculate_outlined, size: 20, color: Color(0xFF655DD5)),
                                    const SizedBox(width: 10),
                                    const Text(
                                      'Moyenne calculée :',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                                    ),
                                    const Spacer(),
                                    if (liveAverage != null)
                                      Text(
                                        '${liveAverage.toStringAsFixed(2)} / 20',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: liveAverage >= 10 ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                                        ),
                                      )
                                    else
                                      const Text(
                                        '— / 20',
                                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Footer
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(top: BorderSide(color: AppColors.slate100)),
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            SizedBox(
                              height: 40,
                              child: TextButton(
                                onPressed: () => Navigator.pop(dialogCtx),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF6B7280),
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                ),
                                child: const Text('Annuler', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              height: 40,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  Navigator.pop(dialogCtx);
                                  await _saveGradesForOffering(offeringId);
                                },
                                icon: const Icon(Icons.check_rounded, size: 16),
                                label: const Text('Enregistrer', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6D4CF6),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  elevation: 2,
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
        );
      },
    ).then((_) {
      setState(() {});
    });
  }

  Widget _buildDialogComponentRow(
    String offeringId,
    Map<String, dynamic> component,
    void Function(void Function()) setDialogState,
  ) {
    final compId = component['id'] as String;
    final name = component['name'] as String? ?? 'Note';
    final weight = component['weight_percent'] as num? ?? 0;
    final displayName = _getComponentDisplayName(name);
    final color = _getComponentColor(name);
    final icon = _getComponentIcon(name);

    final controller = _gradeControllers[offeringId]?[compId];
    final currentStatus = _gradeStatus[offeringId]?[compId] ?? 'OK';
    if (controller == null) return const SizedBox.shrink();

    final isNonOk = currentStatus != 'OK';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isNonOk
            ? (currentStatus == 'ND' ? const Color(0xFFFFFBEB) : const Color(0xFFFEF2F2))
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(displayName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('$weight%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
          ),
          const Spacer(),
          SizedBox(
            width: 120,
            height: 38,
            child: TextField(
              controller: controller,
              enabled: currentStatus == 'OK',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,2}')),
                TextInputFormatter.withFunction((oldValue, newValue) {
                  if (newValue.text.isEmpty) return newValue;
                  final normalized = newValue.text.replaceAll(',', '.');
                  final val = double.tryParse(normalized);
                  if (val != null && val > 20.0) {
                    return oldValue;
                  }
                  return newValue;
                }),
              ],
              onChanged: (text) {
                final normalized = text.replaceAll(',', '.');
                final val = double.tryParse(normalized);
                if (val != null && val > 20.0) {
                  controller.text = '20';
                  controller.selection = TextSelection.fromPosition(const TextPosition(offset: 2));
                }
                setDialogState(() {});
                setState(() {});
              },
              decoration: InputDecoration(
                hintText: currentStatus == 'OK' ? 'Note / 20' : currentStatus,
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: currentStatus == 'OK'
                      ? AppColors.slate400
                      : (currentStatus == 'ND' ? const Color(0xFFD97706) : const Color(0xFFDC2626)),
                  fontWeight: isNonOk ? FontWeight.w700 : FontWeight.normal,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                suffixText: currentStatus == 'OK' ? '/20' : null,
                suffixStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                filled: true,
                fillColor: currentStatus == 'OK' ? Colors.white : Colors.transparent,
              ),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: currentStatus == 'OK'
                    ? const Color(0xFF0F172A)
                    : (currentStatus == 'ND' ? const Color(0xFFD97706) : const Color(0xFFDC2626)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            initialValue: currentStatus,
            tooltip: 'Statut de la note',
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 8,
            onSelected: (value) {
              setDialogState(() {
                _gradeStatus[offeringId]![compId] = value;
                if (value != 'OK') controller.clear();
              });
              setState(() {});
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'OK',
                height: 38,
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                    SizedBox(width: 8),
                    Text('Note standard', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'ND',
                height: 38,
                child: Row(
                  children: [
                    Icon(Icons.remove_circle_outline_rounded, color: Color(0xFFF59E0B), size: 16),
                    SizedBox(width: 8),
                    Text('ND (Non Dispensé)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'NP',
                height: 38,
                child: Row(
                  children: [
                    Icon(Icons.cancel_rounded, color: Color(0xFFEF4444), size: 16),
                    SizedBox(width: 8),
                    Text('NP (Non Présent)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: currentStatus == 'OK'
                    ? Colors.white
                    : (currentStatus == 'ND' ? const Color(0xFFFEF3C7) : const Color(0xFFFEE2E2)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                currentStatus == 'OK'
                    ? Icons.tune_rounded
                    : (currentStatus == 'ND' ? Icons.remove_circle_outline_rounded : Icons.cancel_rounded),
                size: 16,
                color: currentStatus == 'OK'
                    ? const Color(0xFF64748B)
                    : (currentStatus == 'ND' ? const Color(0xFFD97706) : const Color(0xFFDC2626)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingSelectionBar(BuildContext context, List<Map<String, dynamic>> offerings) {
    final count = _selectedOfferingIds.length;

    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(10),
      color: const Color(0xFF111827),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Count badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: Colors.white.withOpacity(0.15))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: const Color(0xFF655DD5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        '$count',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Sélectionnées',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white),
                  ),
                ],
              ),
            ),
            // Actions
            _buildSelectionAction(Icons.check_circle_outline, 'Enregistrer', Colors.white, () => _saveGradesForSelected()),
            _buildSelectionAction(Icons.delete_outline, 'Effacer notes', const Color(0xFFFCA5A5), () => _clearGradesForSelected()),
            // Close button
            Container(
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: Colors.white.withOpacity(0.15))),
              ),
              child: IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.white60),
                onPressed: () => setState(() => _selectedOfferingIds.clear()),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
          ],
        ),
      ),
    );
  }
}
