import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/utils/error_messages.dart';
import '../../providers/semesters_provider.dart';
import '../../providers/undo_redo_provider.dart';
import '../../widgets/admin_sidebar.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/ios_loader.dart';
import '../../widgets/undo_redo_toolbar_buttons.dart';
import '../../widgets/feedback_pill.dart';

const _brand = Color(0xFF7C3AED);
const _brandLight = Color(0xFFF3E8FF);

class SemestersScreen extends ConsumerStatefulWidget {
  const SemestersScreen({super.key});
  @override
  ConsumerState<SemestersScreen> createState() => _SemestersScreenState();
}

class _SemestersScreenState extends ConsumerState<SemestersScreen> {
  Future<void> _handleUndo() async {
    final notifier = ref.read(undoRedoProvider.notifier);
    if (!ref.read(undoRedoProvider).canUndo('semesters')) return;
    try {
      final desc = await notifier.undo('semesters');
      if (mounted && desc != null) {
        FeedbackPill.showUndo(context, message: 'Action annulée : $desc');
      }
    } catch (e) {
      if (mounted) FeedbackPill.showError(context, 'Impossible d\'annuler : $e');
    }
  }

  Future<void> _handleRedo() async {
    final notifier = ref.read(undoRedoProvider.notifier);
    if (!ref.read(undoRedoProvider).canRedo('semesters')) return;
    try {
      final desc = await notifier.redo('semesters');
      if (mounted && desc != null) {
        FeedbackPill.show(context, message: 'Action rétablie : $desc', type: FeedbackPillType.info);
      }
    } catch (e) {
      if (mounted) FeedbackPill.showError(context, 'Impossible de rétablir : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final semestersAsync = ref.watch(semestersProvider);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () => _handleUndo(),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () => _handleUndo(),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () => _handleRedo(),
        const SingleActivator(LogicalKeyboardKey.keyY, meta: true): () => _handleRedo(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
      body: Row(
        children: [
          const AdminSidebar(currentRoute: '/semesters'),
          Expanded(
            child: Stack(
              children: [
                // Decorative blur
                Positioned(
                  top: -80,
                  right: -80,
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      color: _brand.withOpacity(0.03),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Column(
                  children: [
                    _buildHeader(context, semestersAsync),
                    Expanded(
                      child: semestersAsync.when(
                        skipLoadingOnReload: false,
                        loading: () =>
                            const SemestersSkeletonLoader(),
                        error: (e, _) => Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                size: 48,
                                color: AppColors.error,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                UserFriendlyError.format(
                                  e,
                                  fallback: 'Unable to load academic periods right now. Please try again.',
                                ),
                                style: TextStyle(color: AppColors.error),
                              ),
                            ],
                          ),
                        ),
                        data: (state) => _buildContent(context, state),
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

  Widget _buildHeader(
    BuildContext context,
    AsyncValue<SemestersState> semestersAsync,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE9EAF2))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Title
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Périodes académiques',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Gestion des périodes académiques',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
          const Spacer(),
          const UndoRedoToolbarButtons(scope: 'semesters'),
          const SizedBox(width: 8),
          // Academic year configuration button
          SizedBox(
            height: 40,
            child: OutlinedButton.icon(
              onPressed: () {
                final state = semestersAsync.asData?.value;
                final year = state?.selectedAcademicYear ?? state?.currentAcademicYear;
                _showAcademicYearConfigDialog(context, year);
              },
              icon: const Icon(Icons.school_rounded, size: 18),
              label: const Text(
                'Année scolaire',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF334155),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Add button
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: () => _handleAjouterClicked(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text(
                'Ajouter',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
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
    );
  }

  Widget _buildContent(BuildContext context, SemestersState state) {
    final semesters = state.filteredSemesters;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Academic Year Configuration Card ──
          _buildAcademicYearCard(context, state),
          const SizedBox(height: 16),

          // ── Period Cards ──
          if (semesters.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(48),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border.withOpacity(0.5)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today_rounded, size: 56, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'Aucun ${state.periodLabel.toLowerCase()}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cliquez sur "Ajouter" pour créer une période',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
                ],
              ),
            )
          else
            ...semesters.map((s) => _buildPeriodCard(context, state, s)),

          // ── Exam Period Cards ──
          if (state.filteredExamPeriods.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.school_rounded, size: 18, color: const Color(0xFFEA580C)),
                const SizedBox(width: 8),
                Text(
                  'Périodes d\'examens',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.grey.shade800),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${state.filteredExamPeriods.length}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF92400E)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...state.filteredExamPeriods.map((ep) => _buildExamPeriodCard(context, ep)),
          ],

          const SizedBox(height: 16),

          // ── Footer ──
          Center(
            child: Text(
              'Affichage de ${semesters.length} ${semesters.length > 1 ? state.periodLabelPlural.toLowerCase() : state.periodLabel.toLowerCase()}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodCard(BuildContext context, SemestersState state, SemesterModel s) {

    final shortDateFormat = DateFormat('d MMM yyyy', 'fr');
    final rawDuration = s.endDate.difference(s.startDate).inDays;
    final duration = rawDuration < 0 ? 0 : rawDuration;
    final weeks = (duration / 7).ceil();
    final now = DateTime.now();
    final monthsFr = ['Janv.', 'Févr.', 'Mars', 'Avr.', 'Mai', 'Juin', 'Juil.', 'Août', 'Sept.', 'Oct.', 'Nov.', 'Déc.'];

    // Build month list for this period
    final List<DateTime> periodMonthDates = [];
    final List<bool> periodMonthsIsCurrent = [];
    DateTime cursor = DateTime(s.startDate.year, s.startDate.month);
    final endMonth = DateTime(s.endDate.year, s.endDate.month);
    while (!cursor.isAfter(endMonth)) {
      periodMonthDates.add(cursor);
      periodMonthsIsCurrent.add(cursor.year == now.year && cursor.month == now.month);
      cursor = DateTime(cursor.year, cursor.month + 1);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.border.withOpacity(0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row (clone of overview card header) ──
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _brandLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.calendar_month_rounded, color: _brand, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            state.formatPeriodDisplayName(s),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                          ),
                          if (s.isCurrent) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _brandLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Actuel',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _brand),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${shortDateFormat.format(s.startDate)} → ${shortDateFormat.format(s.endDate)}',
                        style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ),
                // Actions
                _gradeActionButton(
                  Icons.edit,
                  () => _showSemesterDialog(context, semester: s),
                ),
                const SizedBox(width: 4),
                _gradeActionButton(
                  Icons.delete_outline,
                  () => _confirmDelete(context, s),
                  isDelete: true,
                ),
              ],
            ),
            // ── Stats row ──
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _brandLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timeline_rounded, color: _brand, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        '$weeks semaines · $duration jours',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _brand),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
              ],
            ),
            // ── Horizontal timeline (exact clone of header) ──
            if (periodMonthDates.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 110,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: periodMonthDates.length,
                  itemBuilder: (context, i) {
                    final mDate = periodMonthDates[i];
                    final isCur = periodMonthsIsCurrent[i];
                    final isLast = i == periodMonthDates.length - 1;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (i == 0) const SizedBox(width: 4),
                        Column(
                          children: [
                            // Month label
                            Text(
                              monthsFr[mDate.month - 1].toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isCur ? _brand : AppColors.textTertiary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Node
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isCur ? _brand : _brandLight,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isCur ? _brand : _brand.withOpacity(0.3),
                                  width: isCur ? 2 : 1,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: isCur ? Colors.white : _brand,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Status
                            if (isCur)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _brandLight,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Actuel',
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: _brand),
                                ),
                              )
                            else if (i == 0)
                              Text(
                                DateFormat('d MMM', 'fr').format(s.startDate),
                                style: TextStyle(fontSize: 9, color: AppColors.textTertiary),
                              )
                            else if (isLast)
                              Text(
                                DateFormat('d MMM', 'fr').format(s.endDate),
                                style: TextStyle(fontSize: 9, color: AppColors.textTertiary),
                              )
                            else
                              Text(
                                monthsFr[mDate.month - 1],
                                style: TextStyle(fontSize: 9, color: AppColors.textTertiary),
                              ),
                          ],
                        ),
                        // Connector line
                        if (!isLast)
                          Container(
                            margin: const EdgeInsets.only(top: 18),
                            width: 24,
                            height: 2,
                            decoration: BoxDecoration(
                              color: _brand.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        if (isLast) const SizedBox(width: 4),
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExamPeriodCard(BuildContext context, ExamPeriodModel ep) {
    final dateFormat = DateFormat('dd MMM yyyy', 'fr');
    final duration = ep.endDate.difference(ep.startDate).inDays;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isActive = !today.isBefore(ep.startDate) && !today.isAfter(ep.endDate);
    final isPast = today.isAfter(ep.endDate);


    final statusColor = isActive ? const Color(0xFF059669) : isPast ? Colors.grey.shade400 : const Color(0xFFEA580C);
    final statusText = isActive ? 'En cours' : isPast ? 'Terminé' : 'À venir';
    final statusBg = isActive ? const Color(0xFFECFDF5) : isPast ? Colors.grey.shade100 : const Color(0xFFFEF3C7);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? const Color(0xFFEA580C).withOpacity(0.3) : AppColors.border.withOpacity(0.5),
          width: 1,
        ),
        boxShadow: isActive
            ? [BoxShadow(color: const Color(0xFFEA580C).withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))]
            : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFFEA580C) : const Color(0xFFFED7AA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.school_rounded,
                color: isActive ? Colors.white : const Color(0xFFEA580C),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ep.name ?? 'Examen',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${dateFormat.format(ep.startDate)} → ${dateFormat.format(ep.endDate)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$duration jour${duration > 1 ? 's' : ''}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusText,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gradeActionButton(IconData icon, VoidCallback onTap, {bool isDelete = false}) {
    final color = isDelete ? AppColors.error : AppColors.slate500;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      hoverColor: color.withOpacity(0.1),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }

  void _handleAjouterClicked(BuildContext context) {
    final state = ref.read(semestersProvider).value;
    if (state == null) return;

    final year = state.selectedAcademicYear ??
        state.currentAcademicYear ??
        state.academicYears.firstOrNull;
    if (year == null) {
      _showAcademicYearConfigDialog(context, null);
      return;
    }

    if (state.isCurrentYearFullyCovered) {
      _showFullyCoveredDialog(context, year);
      return;
    }

    _showCreatePeriodsDialog(context);
  }

  void _showFullyCoveredDialog(BuildContext context, AcademicYearModel year) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(color: Colors.black.withOpacity(0.28)),
            ),
          ),
          Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: 440,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.event_busy_rounded,
                      size: 24,
                      color: Color(0xFFD97706),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Année scolaire complète',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Toutes les périodes pour l\'année scolaire ${year.name} sont déjà configurées jusqu\'au ${DateFormat('dd MMMM yyyy', 'fr').format(year.endDate)}.\n\nIl est impossible de créer une période supplémentaire sans libérer une plage de dates.\n\nPour réorganiser le calendrier, modifiez d\'abord les dates des périodes existantes avec l\'icône crayon.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brand,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 1,
                      ),
                      child: const Text(
                        'Compris',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSemesterDialog(BuildContext context, {SemesterModel? semester}) {
    final asyncState = ref.read(semestersProvider);
    final state = asyncState.value;
    if (state == null) return;

    final isNew = semester == null;
    final lockedType = state.allowedPeriodType;

    // Period type: locked if periods exist, otherwise admin chooses
    String chosenType = lockedType ?? state.periodType;

    // Auto-name based on chosen type
    int autoNumber = isNew ? 1 : semester.number;
    String autoName = isNew ? '$chosenType $autoNumber' : semester.name;

    final nameCtrl = TextEditingController(text: autoName);
    int semesterNumber = autoNumber;

    String? selectedYearId = semester?.academicYearId ??
        state.selectedAcademicYearId ??
        state.selectedAcademicYear?.id ??
        state.currentAcademicYear?.id ??
        state.academicYears.firstOrNull?.id;
    final selectedYear = state.academicYears.where((y) => y.id == selectedYearId).firstOrNull;

    final minStartDate = state.minStartDateForNewSemester;
    DateTime startDate = semester?.startDate ?? minStartDate ?? selectedYear?.startDate ?? DateTime.now();
    if (selectedYear != null && startDate.isBefore(selectedYear.startDate)) {
      startDate = selectedYear.startDate;
    }

    // Auto-calculate duration based on type
    int durationDays = chosenType == 'trimestre' ? 92 : 183;
    DateTime calculatedEnd = startDate.add(Duration(days: durationDays));
    if (selectedYear != null && calculatedEnd.isAfter(selectedYear.endDate)) {
      calculatedEnd = selectedYear.endDate;
    }
    DateTime endDate = semester?.endDate ?? calculatedEnd;
    String? errorMessage;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          bool isSubmitting = false;

          void validateDates() {
            errorMessage = null;
            if (!startDate.isBefore(endDate)) {
              errorMessage = 'La date de début doit être strictement antérieure à la date de fin';
            }
            if (errorMessage == null && nameCtrl.text.trim().isEmpty) {
              errorMessage = 'Le nom de la période ne peut pas être vide';
            }
            if (errorMessage == null) {
              final nameErr = state.validateName(nameCtrl.text.trim(), excludeId: semester?.id);
              if (nameErr != null) errorMessage = nameErr;
            }
            if (errorMessage == null && selectedYearId != null) {
              final year = state.academicYears.where((y) => y.id == selectedYearId).firstOrNull;
              if (year != null) {
                final sStart = SemestersState.stripTime(startDate);
                final sEnd = SemestersState.stripTime(endDate);
                final yStart = SemestersState.stripTime(year.startDate);
                final yEnd = SemestersState.stripTime(year.endDate);
                if (sStart.isBefore(yStart) || sEnd.isAfter(yEnd)) {
                  errorMessage = 'La période doit être comprise dans l\'année scolaire (du ${DateFormat('d MMMM yyyy', 'fr_FR').format(yStart)} au ${DateFormat('d MMMM yyyy', 'fr_FR').format(yEnd)})';
                }
              }
            }
            if (errorMessage == null) {
              final overlap = state.validateOverlap(
                startDate,
                endDate,
                excludeId: semester?.id,
              );
              if (overlap != null) {
                errorMessage = overlap;
              }
            }
            setDialogState(() {});
          }

          return Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: Container(color: Colors.black.withOpacity(0.28)),
                ),
              ),
              Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  width: 480,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _brandLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isNew ? Icons.add_rounded : Icons.edit_rounded,
                              size: 20,
                              color: _brand,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isNew
                                      ? 'Nouveau ${chosenType == 'trimestre' ? 'trimestre' : 'semestre'}'
                                      : 'Modifier le ${state.periodLabel.toLowerCase()}',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isNew
                                      ? 'Créer une nouvelle période académique'
                                      : 'Mettre à jour les informations',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              if (!isSubmitting) Navigator.pop(ctx);
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Divider(height: 1, color: Colors.grey.shade200),
                      const SizedBox(height: 20),
                      // Period type selector (only when no periods exist yet)
                      if (isNew && lockedType == null) ...[
                        _semLabel('Type de période'),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setDialogState(() {
                                  chosenType = 'semestre';
                                  durationDays = 183;
                                  endDate = startDate.add(
                                    Duration(days: durationDays),
                                  );
                                  autoNumber = 1;
                                  nameCtrl.text = 'Semestre 1';
                                  semesterNumber = 1;
                                  validateDates();
                                }),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: chosenType == 'semestre'
                                        ? _brand
                                        : const Color(0xFFF9FAFB),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: chosenType == 'semestre'
                                          ? _brand
                                          : Colors.grey.shade200,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.date_range_rounded,
                                        color: chosenType == 'semestre'
                                            ? Colors.white
                                            : Colors.grey.shade500,
                                        size: 20,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Semestre',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: chosenType == 'semestre'
                                              ? Colors.white
                                              : Colors.grey.shade700,
                                        ),
                                      ),
                                      Text(
                                        '~6 mois',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: chosenType == 'semestre'
                                              ? Colors.white70
                                              : Colors.grey.shade400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setDialogState(() {
                                  chosenType = 'trimestre';
                                  durationDays = 92;
                                  endDate = startDate.add(
                                    Duration(days: durationDays),
                                  );
                                  autoNumber = 1;
                                  nameCtrl.text = 'Trimestre 1';
                                  semesterNumber = 1;
                                  validateDates();
                                }),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: chosenType == 'trimestre'
                                        ? _brand
                                        : const Color(0xFFF9FAFB),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: chosenType == 'trimestre'
                                          ? _brand
                                          : Colors.grey.shade200,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.view_week_rounded,
                                        color: chosenType == 'trimestre'
                                            ? Colors.white
                                            : Colors.grey.shade500,
                                        size: 20,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Trimestre',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: chosenType == 'trimestre'
                                              ? Colors.white
                                              : Colors.grey.shade700,
                                        ),
                                      ),
                                      Text(
                                        '~3 mois',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: chosenType == 'trimestre'
                                              ? Colors.white70
                                              : Colors.grey.shade400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      // Number + Name (N° field removed as per user request)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _semLabel('Nom'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: nameCtrl,
                            onChanged: (_) => validateDates(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: _semInputDeco(
                              'Ex: ${chosenType == 'trimestre' ? 'Trimestre' : 'Semestre'} 1',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (isNew && minStartDate != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _brandLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                size: 18,
                                color: _brand,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Le ${state.periodLabel.toLowerCase()} précédent se termine le ${DateFormat('d MMMM yyyy', 'fr_FR').format(minStartDate.subtract(const Duration(days: 1)))}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _brand,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // Date pickers
                      Row(
                        children: [
                          Expanded(
                            child: _datePicker(
                              ctx,
                              'Date de début',
                              startDate,
                              setDialogState,
                              (d) {
                                startDate = d;
                                if (!endDate.isAfter(startDate)) {
                                  endDate = startDate.add(
                                    Duration(days: durationDays),
                                  );
                                }
                                validateDates();
                              },
                              firstDate: DateTime(2020),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _datePicker(
                              ctx,
                              'Date de fin',
                              endDate,
                              setDialogState,
                              (d) {
                                endDate = d;
                                validateDates();
                              },
                              firstDate: startDate.add(const Duration(days: 1)),
                            ),
                          ),
                        ],
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 16,
                                color: Color(0xFFDC2626),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  errorMessage!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Divider(height: 1, color: Colors.grey.shade200),
                      const SizedBox(height: 16),
                      // Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          SizedBox(
                            height: 40,
                            child: TextButton(
                              onPressed: () {
                                if (!isSubmitting) Navigator.pop(ctx);
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF6B7280),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                              ),
                              child: const Text(
                                'Annuler',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            height: 40,
                            child: ElevatedButton(
                              onPressed: isSubmitting ||
                                      errorMessage != null ||
                                      nameCtrl.text.trim().isEmpty ||
                                      selectedYearId == null
                                  ? null
                                  : () async {
                                      if (isNew) {
                                        Navigator.pop(ctx);
                                        final notifier = ref.read(
                                          semestersProvider.notifier,
                                        );
                                        notifier.create(
                                          name: nameCtrl.text.trim(),
                                          number: semesterNumber,
                                          startDate: startDate,
                                          endDate: endDate,
                                          academicYearId: selectedYearId,
                                        ).then((_) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Row(
                                                  children: [
                                                    Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                                    SizedBox(width: 8),
                                                    Text('Période créée avec succès'),
                                                  ],
                                                ),
                                                backgroundColor: Color(0xFF10B981),
                                                behavior: SnackBarBehavior.floating,
                                              ),
                                            );
                                          }
                                        }).catchError((e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Row(
                                                  children: [
                                                    const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
                                                    const SizedBox(width: 8),
                                                    Expanded(child: Text(UserFriendlyError.format(e, fallback: 'Unable to save this academic period right now. Please check your dates and try again.'))),
                                                  ],
                                                ),
                                                backgroundColor: const Color(0xFFEF4444),
                                                behavior: SnackBarBehavior.floating,
                                              ),
                                            );
                                          }
                                        });
                                        return;
                                      }
                                      setDialogState(() => isSubmitting = true);
                                      try {
                                        final notifier = ref.read(
                                          semestersProvider.notifier,
                                        );
                                        await notifier.updateSemester(
                                          id: semester.id,
                                          name: nameCtrl.text.trim(),
                                          number: semesterNumber,
                                          startDate: startDate,
                                          endDate: endDate,
                                        );
                                        if (ctx.mounted) Navigator.pop(ctx);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Row(
                                                children: [
                                                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                                  SizedBox(width: 8),
                                                  Text('Période mise à jour avec succès'),
                                                ],
                                              ),
                                              backgroundColor: Color(0xFF10B981),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        setDialogState(() => isSubmitting = false);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Row(
                                                children: [
                                                  const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
                                                  const SizedBox(width: 8),
                                                  Expanded(child: Text(UserFriendlyError.format(e, fallback: 'Unable to save this academic period right now. Please check your dates and try again.'))),
                                                ],
                                              ),
                                              backgroundColor: const Color(0xFFEF4444),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _brand,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: _brand.withOpacity(
                                  0.3,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                elevation: 2,
                              ),
                              child: isSubmitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : Text(
                                      isNew ? 'Créer' : 'Modifier',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _datePicker(
    BuildContext ctx,
    String label,
    DateTime date,
    void Function(void Function()) setDialogState,
    void Function(DateTime) onPicked, {
    required DateTime firstDate,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _semLabel(label),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: ctx,
              initialDate: date,
              firstDate: firstDate,
              lastDate: DateTime(2030),
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: _brand,
                      onPrimary: Colors.white,
                      surface: Colors.white,
                      onSurface: Color(0xFF111827),
                    ),
                    textButtonTheme: TextButtonThemeData(
                      style: TextButton.styleFrom(
                        foregroundColor: _brand,
                        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                    dialogTheme: DialogThemeData(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 12,
                    ),
                    datePickerTheme: DatePickerThemeData(
                      headerBackgroundColor: _brand,
                      headerForegroundColor: Colors.white,
                      headerHelpStyle: const TextStyle(fontSize: 12, color: Colors.white70),
                      dayStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 10,
                      shadowColor: Colors.black26,
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (picked != null) setDialogState(() => onPicked(picked));
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 16,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(width: 8),
                Text(
                  DateFormat('dd MMMM yyyy', 'fr').format(date),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static Widget _semLabel(String text) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFF111827),
      ),
    ),
  );

  static InputDecoration _semInputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      color: Colors.grey.shade400,
      fontWeight: FontWeight.w400,
      fontSize: 14,
    ),
    filled: true,
    fillColor: const Color(0xFFF9FAFB),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade200),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade200),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _brand, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    isDense: true,
  );

  void _showCreatePeriodsDialog(BuildContext context) {
    final state = ref.read(semestersProvider).value;
    if (state == null) return;

    final year = state.selectedAcademicYear ??
        state.currentAcademicYear ??
        state.academicYears.firstOrNull;
    if (year == null) {
      _showAcademicYearConfigDialog(context, null);
      return;
    }

    final existingSemesters = state.semesters
        .where((s) => s.academicYearId == year.id)
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));

    final isFullyCovered = existingSemesters.isNotEmpty &&
        !SemestersState.stripTime(existingSemesters.last.endDate)
            .isBefore(SemestersState.stripTime(year.endDate));

    if (isFullyCovered) {
      _showFullyCoveredDialog(context, year);
      return;
    }

    final DateTime initialStart;
    if (existingSemesters.isNotEmpty) {
      initialStart = existingSemesters.last.endDate.add(const Duration(days: 1));
    } else {
      initialStart = year.startDate;
    }

    // The teaching/instructional period ends on June 30 before summer vacation (July-August)
    DateTime getTeachingEnd() {
      if (year.endDate.month >= 7 && year.endDate.year >= year.startDate.year) {
        return DateTime(year.endDate.year, 6, 30);
      }
      return year.endDate;
    }

    final teachingEnd = getTeachingEnd();

    var selectedType = existingSemesters.isEmpty ? 'semestre' : 'single';

    final defaultDurationDays = state.periodTypeDuration;
    DateTime calculateDefaultEnd(DateTime start) {
      final calculated = start.add(Duration(days: defaultDurationDays));
      return calculated.isAfter(teachingEnd) ? teachingEnd : calculated;
    }

    var ranges = existingSemesters.isEmpty
        ? _splitYear(initialStart, teachingEnd, 2)
        : [(start: initialStart, end: calculateDefaultEnd(initialStart))];
    var manualVacations = <({DateTime start, DateTime end})>[];
    var examPeriods = <({DateTime start, DateTime end})>[];
    String? errorMessage;

    List<({DateTime start, DateTime end})> computeAutoGaps() {
      if (ranges.isEmpty) return [];
      final allRanges = [
        ...existingSemesters.map((s) => (start: s.startDate, end: s.endDate)),
        ...ranges,
      ]..sort((a, b) => a.start.compareTo(b.start));

      final gaps = <({DateTime start, DateTime end})>[];

      if (allRanges.first.start.isAfter(year.startDate)) {
        final gapEnd = allRanges.first.start.subtract(const Duration(days: 1));
        if (!gapEnd.isBefore(year.startDate)) {
          gaps.add((start: year.startDate, end: gapEnd));
        }
      }
      for (var i = 0; i < allRanges.length - 1; i++) {
        final nextStart = allRanges[i + 1].start;
        final prevEnd = allRanges[i].end;
        if (nextStart.isAfter(prevEnd.add(const Duration(days: 1)))) {
          gaps.add((
            start: prevEnd.add(const Duration(days: 1)),
            end: nextStart.subtract(const Duration(days: 1)),
          ));
        }
      }
      if (allRanges.last.end.isBefore(year.endDate)) {
        final gapStart = allRanges.last.end.add(const Duration(days: 1));
        if (!gapStart.isAfter(year.endDate)) {
          gaps.add((start: gapStart, end: year.endDate));
        }
      }
      return gaps;
    }

    bool isSubmitting = false;
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final label = selectedType == 'trimestre' ? 'Trimestre' : selectedType == 'single' ? 'Période' : 'Semestre';
          final autoGaps = computeAutoGaps();

          void validate() {
            errorMessage = null;

            // 1. Each range must have start strictly before end and stay within year bounds
            for (var i = 0; i < ranges.length; i++) {
              final rStart = SemestersState.stripTime(ranges[i].start);
              final rEnd = SemestersState.stripTime(ranges[i].end);
              final numLabel = '$label ${existingSemesters.length + i + 1}';

              if (!rStart.isBefore(rEnd)) {
                errorMessage =
                    'La date de début doit être strictement antérieure à la date de fin pour $numLabel';
                return;
              }

              if (rStart.isBefore(SemestersState.stripTime(year.startDate))) {
                errorMessage =
                    '$numLabel ne peut pas commencer avant le début de l\'année scolaire (${DateFormat('d MMMM yyyy', 'fr_FR').format(year.startDate)})';
                return;
              }

              if (rEnd.isAfter(SemestersState.stripTime(year.endDate))) {
                errorMessage =
                    '$numLabel ne peut pas se terminer après la fin de l\'année scolaire (${DateFormat('d MMMM yyyy', 'fr_FR').format(year.endDate)})';
                return;
              }
            }

            // 2. Ranges must not overlap each other
            for (var i = 0; i < ranges.length; i++) {
              final rStartI = SemestersState.stripTime(ranges[i].start);
              final rEndI = SemestersState.stripTime(ranges[i].end);
              for (var j = i + 1; j < ranges.length; j++) {
                final rStartJ = SemestersState.stripTime(ranges[j].start);
                final rEndJ = SemestersState.stripTime(ranges[j].end);
                if (!rStartI.isAfter(rEndJ) && !rEndI.isBefore(rStartJ)) {
                  errorMessage =
                      'Les périodes créées se chevauchent entre elles ($label ${existingSemesters.length + i + 1} et $label ${existingSemesters.length + j + 1})';
                  return;
                }
              }
            }

            // 3. Ranges must not overlap or duplicate any existing semester
            for (var i = 0; i < ranges.length; i++) {
              final rStart = SemestersState.stripTime(ranges[i].start);
              final rEnd = SemestersState.stripTime(ranges[i].end);
              final numLabel = '$label ${existingSemesters.length + i + 1}';

              for (final existing in existingSemesters) {
                final existStart = SemestersState.stripTime(existing.startDate);
                final existEnd = SemestersState.stripTime(existing.endDate);

                if (rStart == existStart && rEnd == existEnd) {
                  errorMessage =
                      'Une période avec exactement les mêmes dates existe déjà ("${existing.name}" du ${DateFormat('d MMMM yyyy', 'fr_FR').format(existStart)} au ${DateFormat('d MMMM yyyy', 'fr_FR').format(existEnd)})';
                  return;
                }

                if (!rStart.isAfter(existEnd) && !rEnd.isBefore(existStart)) {
                  errorMessage =
                      '$numLabel chevauche avec "${existing.name}" (du ${DateFormat('d MMMM yyyy', 'fr_FR').format(existStart)} au ${DateFormat('d MMMM yyyy', 'fr_FR').format(existEnd)})';
                  return;
                }
              }
            }
          }

          // Initial validation pass on mount
          validate();

          void onTypeChanged(String type) {
            selectedType = type;
            if (type == 'single') {
              ranges = [(start: initialStart, end: calculateDefaultEnd(initialStart))];
            } else {
              ranges = _splitYear(
                initialStart,
                teachingEnd,
                type == 'semestre' ? 2 : 3,
              );
            }
            validate();
          }

          void onStartChanged(int index, DateTime d) {
            final newRanges = List<({DateTime start, DateTime end})>.from(ranges);
            var newEnd = newRanges[index].end;
            if (newEnd.isBefore(d)) {
              newEnd = d.add(const Duration(days: 90));
              if (newEnd.isAfter(year.endDate)) newEnd = year.endDate;
            }
            newRanges[index] = (start: d, end: newEnd);

            for (var k = index; k < newRanges.length - 1; k++) {
              final nextStart = newRanges[k].end.add(const Duration(days: 1));
              if (newRanges[k + 1].start.isBefore(nextStart)) {
                var kNextEnd = newRanges[k + 1].end;
                if (kNextEnd.isBefore(nextStart)) {
                  kNextEnd = nextStart.add(const Duration(days: 90));
                  if (kNextEnd.isAfter(year.endDate)) kNextEnd = year.endDate;
                }
                newRanges[k + 1] = (start: nextStart, end: kNextEnd);
              }
            }
            ranges = newRanges;
            validate();
          }

          void onEndChanged(int index, DateTime d) {
            final newRanges = List<({DateTime start, DateTime end})>.from(ranges);
            newRanges[index] = (start: newRanges[index].start, end: d);

            for (var k = index; k < newRanges.length - 1; k++) {
              final nextStart = newRanges[k].end.add(const Duration(days: 1));
              var kNextEnd = newRanges[k + 1].end;
              if (kNextEnd.isBefore(nextStart)) {
                kNextEnd = nextStart.add(const Duration(days: 90));
                if (kNextEnd.isAfter(year.endDate)) kNextEnd = year.endDate;
              }
              newRanges[k + 1] = (start: nextStart, end: kNextEnd);
            }
            ranges = newRanges;
            validate();
          }

          return Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: Container(color: Colors.black.withOpacity(0.28)),
                ),
              ),
              Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  width: 560,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.85,
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _brandLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              size: 20,
                              color: _brand,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Nouvelles périodes',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Année scolaire: ${year.name}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              if (!isSubmitting) Navigator.pop(ctx);
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Divider(height: 1, color: Colors.grey.shade200),
                      const SizedBox(height: 20),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                      // Type selector
                      _semLabel('Type de période'),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _typeOption(
                            'Période unique',
                            'single',
                            selectedType,
                            Icons.today_rounded,
                            onTypeChanged,
                            expand: existingSemesters.isEmpty,
                          ),
                          if (existingSemesters.isEmpty) ...[
                            const SizedBox(width: 12),
                            _typeOption(
                              'Semestre',
                              'semestre',
                              selectedType,
                              Icons.date_range_rounded,
                              onTypeChanged,
                            ),
                            const SizedBox(width: 12),
                            _typeOption(
                              'Trimestre',
                              'trimestre',
                              selectedType,
                              Icons.view_week_rounded,
                              onTypeChanged,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Date ranges
                      ...List.generate(ranges.length, (index) {
                        final periodIndexNumber = existingSemesters.length + index + 1;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$label $periodIndexNumber',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: _datePicker(
                                      ctx,
                                      'Date de début',
                                      ranges[index].start,
                                      setDialogState,
                                      (d) => onStartChanged(index, d),
                                      firstDate: DateTime(2020),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _datePicker(
                                      ctx,
                                      'Date de fin',
                                      ranges[index].end,
                                      setDialogState,
                                      (d) => onEndChanged(index, d),
                                      firstDate: ranges[index].start.add(const Duration(days: 1)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                      // Auto vacations (gaps between periods)
                      if (autoGaps.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _semLabel('Vacances automatiques (gaps)'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: autoGaps.map((g) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFFDE68A)),
                            ),
                            child: Text(
                              '${DateFormat('dd MMM', 'fr').format(g.start)} - ${DateFormat('dd MMM', 'fr').format(g.end)}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                            ),
                          )).toList(),
                        ),
                      ],
                      // Manual vacations
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _semLabel('Vacances supplémentaires'),
                          GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                manualVacations.add((
                                  start: year.startDate,
                                  end: year.startDate,
                                ));
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.add, size: 14, color: Color(0xFF374151)),
                                  SizedBox(width: 4),
                                  Text('Ajouter', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (manualVacations.isEmpty)
                        Text('Aucune vacance supplémentaire', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                      ...List.generate(manualVacations.length, (index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: _datePicker(
                                  ctx,
                                  'Début',
                                  manualVacations[index].start,
                                  setDialogState,
                                  (d) => setDialogState(() {
                                    manualVacations[index] = (start: d, end: manualVacations[index].end);
                                  }),
                                  firstDate: DateTime(2020),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _datePicker(
                                  ctx,
                                  'Fin',
                                  manualVacations[index].end,
                                  setDialogState,
                                  (d) => setDialogState(() {
                                    manualVacations[index] = (start: manualVacations[index].start, end: d);
                                  }),
                                  firstDate: manualVacations[index].start,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline, size: 18, color: Colors.grey.shade400),
                                onPressed: () => setDialogState(() => manualVacations.removeAt(index)),
                              ),
                            ],
                          ),
                        );
                      }),
                      // Exam periods
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _semLabel('Périodes d\'examens'),
                          GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                examPeriods.add((
                                  start: year.startDate,
                                  end: year.startDate,
                                ));
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.add, size: 14, color: Color(0xFF374151)),
                                  SizedBox(width: 4),
                                  Text('Ajouter', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (examPeriods.isEmpty)
                        Text('Aucune période d\'examen', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                       ...List.generate(examPeriods.length, (index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: _datePicker(
                                  ctx,
                                  'Début',
                                  examPeriods[index].start,
                                  setDialogState,
                                  (d) => setDialogState(() {
                                    examPeriods[index] = (start: d, end: d.isAfter(examPeriods[index].end) ? d : examPeriods[index].end);
                                  }),
                                  firstDate: DateTime(2020),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _datePicker(
                                  ctx,
                                  'Fin',
                                  examPeriods[index].end,
                                  setDialogState,
                                  (d) => setDialogState(() {
                                    examPeriods[index] = (start: examPeriods[index].start, end: d);
                                  }),
                                  firstDate: examPeriods[index].start,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline, size: 18, color: Colors.grey.shade400),
                                onPressed: () => setDialogState(() => examPeriods.removeAt(index)),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 16,
                                color: Color(0xFFDC2626),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  errorMessage!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                               ),
                             ],
                           ),
                         ),
                       ], // end errorMessage spread
                       ], // end inner Column children
                       ), // end inner Column
                       ), // end SingleChildScrollView
                       ), // end Flexible
                       const SizedBox(height: 20),
                      Divider(height: 1, color: Colors.grey.shade200),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          SizedBox(
                            height: 40,
                            child: TextButton(
                              onPressed: () {
                                if (!isSubmitting) Navigator.pop(ctx);
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF6B7280),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                              ),
                              child: const Text(
                                'Annuler',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            height: 40,
                            child: ElevatedButton(
                              onPressed: errorMessage != null
                                  ? null
                                  : () {
                                      Navigator.pop(ctx);
                                      final notifier = ref.read(
                                        semestersProvider.notifier,
                                      );
                                      notifier.createPeriods(
                                        type: selectedType,
                                        ranges: ranges,
                                        manualVacations: manualVacations,
                                        examPeriods: examPeriods,
                                      ).then((_) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Row(
                                                children: [
                                                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                                  SizedBox(width: 8),
                                                  Text('Périodes créées avec succès'),
                                                ],
                                              ),
                                              backgroundColor: Color(0xFF10B981),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      }).catchError((e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Row(
                                                children: [
                                                  const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
                                                  const SizedBox(width: 8),
                                                  Expanded(child: Text(UserFriendlyError.format(e, fallback: 'Unable to save this academic period right now. Please check your dates and try again.'))),
                                                ],
                                              ),
                                              backgroundColor: const Color(0xFFEF4444),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      });
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _brand,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: _brand.withOpacity(
                                  0.3,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                elevation: 2,
                              ),
                              child: const Text(
                                'Créer',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<({DateTime start, DateTime end})> _splitYear(
    DateTime start,
    DateTime end,
    int count,
  ) {
    final totalDays = end.difference(start).inDays + 1;
    final partDays = totalDays ~/ count;
    final result = <({DateTime start, DateTime end})>[];
    for (var i = 0; i < count; i++) {
      final partStart = start.add(Duration(days: i * partDays));
      final partEnd = i == count - 1
          ? end
          : start.add(Duration(days: (i + 1) * partDays - 1));
      result.add((start: partStart, end: partEnd));
    }
    return result;
  }

  Widget _typeOption(
    String title,
    String type,
    String selectedType,
    IconData icon,
    ValueChanged<String> onChanged, {
    bool expand = true,
  }) {
    final isSelected = selectedType == type;
    final content = GestureDetector(
      onTap: () => onChanged(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF3F0FF) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _brand : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? _brand : Colors.grey.shade500,
              size: 20,
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? _brand : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );

    if (expand) {
      return Expanded(child: content);
    }
    return SizedBox(width: 160, child: content);
  }

  void _confirmDelete(BuildContext context, SemesterModel s) {
    final periodState = ref.read(semestersProvider).value;
    final periodLabel = periodState?.periodLabel ?? 'Semestre';
    final displayName = periodState != null
        ? periodState.formatPeriodDisplayName(s)
        : s.name;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(color: Colors.black.withOpacity(0.28)),
            ),
          ),
          AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.errorSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
                ),
                const SizedBox(width: 12),
                Text('Supprimer le ${periodLabel.toLowerCase()} ?', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Voulez-vous vraiment supprimer "$displayName" ? Cette action est irréversible.'),
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
                      child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final sSnapshot = {
                          'id': s.id,
                          'name': s.name,
                          'number': s.number,
                          'start_date': DateFormat('yyyy-MM-dd').format(s.startDate),
                          'end_date': DateFormat('yyyy-MM-dd').format(s.endDate),
                          'is_current': s.isCurrent,
                          'academic_year_id': s.academicYearId,
                        };
                        Navigator.pop(ctx);
                        try {
                          await ref.read(semestersProvider.notifier).delete(s.id);
                          if (context.mounted) {
                            FeedbackPill.showSuccess(context, 'Période "$displayName" supprimée');
                          }
                          ref.read(undoRedoProvider.notifier).recordAction(
                            AppAction(
                              scope: 'semesters',
                              title: 'Suppression période',
                              description: 'Suppression de la période "$displayName"',
                              undo: (r) async {
                                await SupabaseConfig.adminClient.from('semesters').insert(sSnapshot);
                                await r.read(semestersProvider.notifier).refresh();
                              },
                              redo: (r) async {
                                await r.read(semestersProvider.notifier).delete(s.id);
                              },
                            ),
                          );
                        } catch (e) {
                          if (context.mounted) {
                            FeedbackPill.showError(
                              context,
                              UserFriendlyError.format(
                                e,
                                fallback: 'Impossible de supprimer cette période scolaire.',
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Supprimer', style: TextStyle(fontWeight: FontWeight.w700)),
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
        ],
      ),
    );
  }

  Widget _buildAcademicYearCard(BuildContext context, SemestersState state) {
    final year = state.selectedAcademicYear ?? state.currentAcademicYear;
    final shortDateFormat = DateFormat('d MMMM yyyy', 'fr');

    if (year == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 28),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aucune année scolaire active',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF92400E)),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Veuillez configurer la date de début et de fin de l\'année scolaire.',
                    style: TextStyle(fontSize: 13, color: Color(0xFFB45309)),
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => _showAcademicYearConfigDialog(context, null),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Configurer l\'année'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      );
    }

    final duration = year.endDate.difference(year.startDate).inDays;
    final months = (duration / 30.4).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.border.withOpacity(0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _brandLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.school_rounded, color: _brand, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Année scolaire ${year.name}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                        if (year.isCurrent) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _brandLight,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Actuelle',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _brand,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${shortDateFormat.format(year.startDate)} → ${shortDateFormat.format(year.endDate)}',
                      style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
              // Action buttons: Edit pencil, and delete trash if non-current
              _gradeActionButton(
                Icons.edit,
                () => _showAcademicYearConfigDialog(context, year),
              ),
              if (!year.isCurrent) ...[
                const SizedBox(width: 4),
                _gradeActionButton(
                  Icons.delete_outline,
                  () => _confirmDeleteAcademicYear(context, year),
                  isDelete: true,
                ),
              ],
            ],
          ),

          const SizedBox(height: 14),

          // Duration in a purple pill with icon (matching the period cards)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _brandLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timeline_rounded, color: _brand, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      '$months mois · $duration jours',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _brand),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Visual Partition Graph ──
          _buildYearPartitionGraph(context, state, year),
        ],
      ),
    );
  }

  Widget _buildYearPartitionGraph(BuildContext context, SemestersState state, AcademicYearModel year) {
    final now = DateTime.now();
    final monthsFr = ['Janv.', 'Févr.', 'Mars', 'Avr.', 'Mai', 'Juin', 'Juil.', 'Août', 'Sept.', 'Oct.', 'Nov.', 'Déc.'];
    final shortDateFormat = DateFormat('d MMM', 'fr');

    final startYear = DateTime(year.startDate.year, year.startDate.month, year.startDate.day);
    final endYear = DateTime(year.endDate.year, year.endDate.month, year.endDate.day);

    // 1. Month list for timeline markings
    final List<DateTime> yearMonths = [];
    DateTime mCursor = DateTime(startYear.year, startYear.month);
    final endMonth = DateTime(endYear.year, endYear.month);
    while (!mCursor.isAfter(endMonth)) {
      yearMonths.add(mCursor);
      mCursor = DateTime(mCursor.year, mCursor.month + 1);
    }

    // 2. Collect period partition items
    final yearSemesters = state.semesters.where((s) => s.academicYearId == year.id).toList();
    final yearVacations = state.filteredVacations(year.id);
    final yearExams = state.filteredExams(year.id);

    final List<_PartitionItem> items = [];
    for (final s in yearSemesters) {
      items.add(_PartitionItem(
        id: s.id,
        name: state.formatPeriodDisplayName(s),
        start: s.startDate,
        end: s.endDate,
        type: 'semester',
        color: _brand,
        lightColor: _brandLight,
        icon: Icons.calendar_month_rounded,
      ));
    }
    for (final v in yearVacations) {
      items.add(_PartitionItem(
        id: v.id,
        name: v.name ?? 'Vacances',
        start: v.startDate,
        end: v.endDate,
        type: 'vacation',
        color: const Color(0xFFD97706),
        lightColor: const Color(0xFFFEF3C7),
        icon: Icons.beach_access_rounded,
      ));
    }
    for (final e in yearExams) {
      items.add(_PartitionItem(
        id: e.id,
        name: e.name ?? 'Session d\'examen',
        start: e.startDate,
        end: e.endDate,
        type: 'exam',
        color: const Color(0xFFDC2626),
        lightColor: const Color(0xFFFEE2E2),
        icon: Icons.assignment_turned_in_rounded,
      ));
    }

    // 3. Build continuous non-overlapping timeline segments from startYear to endYear
    final Set<DateTime> boundaryDates = {startYear, endYear.add(const Duration(days: 1))};
    for (final item in items) {
      final s = DateTime(item.start.year, item.start.month, item.start.day);
      final e = DateTime(item.end.year, item.end.month, item.end.day).add(const Duration(days: 1));
      if (!s.isBefore(startYear) && !s.isAfter(endYear)) boundaryDates.add(s);
      if (!e.isBefore(startYear) && !e.isAfter(endYear.add(const Duration(days: 1)))) boundaryDates.add(e);
    }

    final sortedDates = boundaryDates.toList()..sort();
    final List<_TimelineSegment> segments = [];

    for (int i = 0; i < sortedDates.length - 1; i++) {
      final segStart = sortedDates[i];
      final segEndExclusive = sortedDates[i + 1];
      final segEnd = segEndExclusive.subtract(const Duration(days: 1));
      if (segEnd.isBefore(segStart)) continue;

      final days = segEnd.difference(segStart).inDays + 1;
      if (days <= 0) continue;

      // Priority: exam > vacation > semester
      _PartitionItem? activeItem;
      for (final it in items.where((x) => x.type == 'exam')) {
        if (!segStart.isBefore(it.start) && !segEnd.isAfter(it.end)) {
          activeItem = it;
          break;
        }
      }
      if (activeItem == null) {
        for (final it in items.where((x) => x.type == 'vacation')) {
          if (!segStart.isBefore(it.start) && !segEnd.isAfter(it.end)) {
            activeItem = it;
            break;
          }
        }
      }
      if (activeItem == null) {
        for (final it in items.where((x) => x.type == 'semester')) {
          if (!segStart.isBefore(it.start) && !segEnd.isAfter(it.end)) {
            activeItem = it;
            break;
          }
        }
      }

      if (segments.isNotEmpty && segments.last.item?.id == activeItem?.id && segments.last.item?.type == activeItem?.type) {
        final prev = segments.removeLast();
        segments.add(_TimelineSegment(
          start: prev.start,
          end: segEnd,
          days: prev.days + days,
          item: activeItem,
        ));
      } else {
        segments.add(_TimelineSegment(
          start: segStart,
          end: segEnd,
          days: days,
          item: activeItem,
        ));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header (legend dots removed per user request)
          const Text(
            'Partition de l\'année scolaire',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),

          const SizedBox(height: 12),

          // Proportional segmented bar of blocks - compact, clean, smaller pill design
          if (items.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 18,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: segments.map((seg) {
                    if (seg.item == null) {
                      return Expanded(
                        flex: seg.days,
                        child: Tooltip(
                          message: '${shortDateFormat.format(seg.start)} → ${shortDateFormat.format(seg.end)} (${seg.days} j)\nNon configuré',
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 0.75),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      );
                    }
                    return Expanded(
                      flex: seg.days,
                      child: Tooltip(
                        message: '${seg.item!.name}\n${shortDateFormat.format(seg.start)} → ${shortDateFormat.format(seg.end)} (${seg.days} j)',
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 0.75),
                          decoration: BoxDecoration(
                            color: seg.item!.color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            seg.item!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              child: const Text(
                'Aucune période configurée pour cette année scolaire.',
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
            ),

          const SizedBox(height: 6),

          // Month names placed directly under the rectangle visual at their correct places
          if (yearMonths.isNotEmpty)
            Row(
              children: yearMonths.map((mDate) {
                DateTime mStart = DateTime(mDate.year, mDate.month, 1);
                if (mStart.isBefore(startYear)) mStart = startYear;
                DateTime nextM = DateTime(mDate.year, mDate.month + 1, 1);
                DateTime mEnd = nextM.subtract(const Duration(days: 1));
                if (mEnd.isAfter(endYear)) mEnd = endYear;
                final daysInMonth = math.max(1, mEnd.difference(mStart).inDays + 1);
                final isCur = mDate.year == now.year && mDate.month == now.month;

                return Expanded(
                  flex: daysInMonth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 1.5,
                        height: 4,
                        color: isCur ? _brand : const Color(0xFFCBD5E1),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        monthsFr[mDate.month - 1],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isCur ? FontWeight.w700 : FontWeight.w500,
                          color: isCur ? _brand : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  void _confirmDeleteAcademicYear(BuildContext context, AcademicYearModel year) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer l\'année scolaire'),
        content: Text(
          'Êtes-vous sûr de vouloir supprimer l\'année scolaire "${year.name}" ? Toutes les périodes, vacances et examens associés seront également supprimés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(semestersProvider.notifier).deleteAcademicYear(year.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Année scolaire supprimée avec succès'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(UserFriendlyError.format(e)),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Supprimer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAcademicYearConfigDialog(BuildContext context, AcademicYearModel? existingYear) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(color: Colors.black.withOpacity(0.28)),
            ),
          ),
          Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: _AcademicYearConfigDialogContent(existingYear: existingYear),
          ),
        ],
      ),
    );
  }
}

class _AcademicYearConfigDialogContent extends ConsumerStatefulWidget {
  final AcademicYearModel? existingYear;

  const _AcademicYearConfigDialogContent({this.existingYear});

  @override
  ConsumerState<_AcademicYearConfigDialogContent> createState() =>
      _AcademicYearConfigDialogContentState();
}

class _AcademicYearConfigDialogContentState
    extends ConsumerState<_AcademicYearConfigDialogContent> {
  late TextEditingController _nameController;
  late DateTime _startDate;
  late DateTime _endDate;
  late bool _isCurrent;
  bool _isSaving = false;
  String? _error;
  bool _userEditedName = false;

  String _formatAcademicYearName(DateTime start, DateTime end) {
    return '${start.year}-${end.year}';
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final defaultStartYear = now.month >= 8 ? now.year : now.year - 1;
    _startDate = widget.existingYear?.startDate ?? DateTime(defaultStartYear, 9, 1);
    _endDate = widget.existingYear?.endDate ?? DateTime(defaultStartYear + 1, 6, 30);
    _isCurrent = widget.existingYear?.isCurrent ?? true;
    _userEditedName = widget.existingYear != null && widget.existingYear!.name.trim().isNotEmpty;
    final initialName = widget.existingYear?.name.trim().isNotEmpty == true
        ? widget.existingYear!.name
        : _formatAcademicYearName(_startDate, _endDate);
    _nameController = TextEditingController(text: initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _brand,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF111827),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: _brand,
                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (!_startDate.isBefore(_endDate)) {
            _endDate = _startDate.add(const Duration(days: 270));
          }
        } else {
          _endDate = picked;
        }
        if (!_userEditedName || _nameController.text.trim().isEmpty) {
          _nameController.text = _formatAcademicYearName(_startDate, _endDate);
        }
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    var name = _nameController.text.trim();
    if (name.isEmpty) {
      name = _formatAcademicYearName(_startDate, _endDate);
      _nameController.text = name;
    }
    if (!_startDate.isBefore(_endDate)) {
      setState(() => _error = 'La date de début doit être strictement antérieure à la date de fin.');
      return;
    }

    // Safety checks against existing semesters
    final state = ref.read(semestersProvider).value;
    if (state != null && widget.existingYear != null) {
      final semesters = state.semesters
          .where((s) => s.academicYearId == widget.existingYear!.id)
          .toList();
      if (semesters.isNotEmpty) {
        semesters.sort((a, b) => a.startDate.compareTo(b.startDate));
        final firstSemStart = SemestersState.stripTime(semesters.first.startDate);
        final lastSemEnd = SemestersState.stripTime(semesters.last.endDate);

        if (SemestersState.stripTime(_startDate).isAfter(firstSemStart)) {
          setState(() => _error =
              'La date de début ne peut pas être postérieure au début de la première période (${DateFormat('d MMM yyyy', 'fr').format(firstSemStart)}).');
          return;
        }
        if (SemestersState.stripTime(_endDate).isBefore(lastSemEnd)) {
          setState(() => _error =
              'La date de fin ne peut pas être antérieure à la fin de la dernière période (${DateFormat('d MMM yyyy', 'fr').format(lastSemEnd)}).');
          return;
        }
      }
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final notifier = ref.read(semestersProvider.notifier);
      if (widget.existingYear != null) {
        await notifier.updateAcademicYear(
          id: widget.existingYear!.id,
          name: name,
          startDate: _startDate,
          endDate: _endDate,
          isCurrent: _isCurrent,
        );
      } else {
        await notifier.createAcademicYear(
          name: name,
          startDate: _startDate,
          endDate: _endDate,
          isCurrent: _isCurrent,
        );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  widget.existingYear != null
                      ? 'Année scolaire mise à jour avec succès'
                      : 'Année scolaire créée avec succès',
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = UserFriendlyError.format(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = _endDate.difference(_startDate).inDays;
    final months = (duration / 30.4).toStringAsFixed(1);
    final dateFormat = DateFormat('d MMMM yyyy', 'fr');

    return Container(
      width: 500,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 20, 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _brandLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.edit_calendar_rounded, color: _brand, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.existingYear != null
                            ? 'Modifier l\'année scolaire'
                            : 'Nouvelle année scolaire',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Définissez les dates de début et de fin de l\'année',
                        style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),

          // Body
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name
                const Text(
                  'Nom de l\'année scolaire',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameController,
                  onChanged: (val) {
                    _userEditedName = val.trim().isNotEmpty;
                  },
                  decoration: InputDecoration(
                    hintText: _formatAcademicYearName(_startDate, _endDate),
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _brand, width: 1.5),
                    ),
                  ),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 18),

                // Start / End Date pickers
                const Text(
                  'Dates de l\'année scolaire',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Start date
                    Expanded(
                      child: InkWell(
                        onTap: () => _pickDate(isStart: true),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.calendar_today_outlined, size: 14, color: _brand),
                                  SizedBox(width: 6),
                                  Text(
                                    'Date de début',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                dateFormat.format(_startDate),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // End date
                    Expanded(
                      child: InkWell(
                        onTap: () => _pickDate(isStart: false),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.event_outlined, size: 14, color: _brand),
                                  SizedBox(width: 6),
                                  Text(
                                    'Date de fin',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                dateFormat.format(_endDate),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Duration indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E8FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timelapse_rounded, size: 14, color: _brand),
                      const SizedBox(width: 6),
                      Text(
                        'Durée totale : $duration jours (~$months mois)',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _brand),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Is Current Checkbox
                InkWell(
                  onTap: () => setState(() => _isCurrent = !_isCurrent),
                  borderRadius: BorderRadius.circular(10),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _isCurrent,
                        onChanged: (v) => setState(() => _isCurrent = v ?? false),
                        activeColor: _brand,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Définir comme année scolaire actuelle',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F2937)),
                            ),
                            Text(
                              'Les nouvelles périodes et emplois du temps utiliseront cette année.',
                              style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Error message
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFFB91C1C)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
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
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    child: const Text(
                      'Annuler',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const IosLoader.small(color: Colors.white)
                        : const Icon(Icons.check_rounded, size: 16),
                    label: Text(
                      widget.existingYear != null ? 'Enregistrer' : 'Créer l\'année',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6D4CF6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 2,
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
}

class _PartitionItem {
  final String id;
  final String name;
  final DateTime start;
  final DateTime end;
  final String type;
  final Color color;
  final Color lightColor;
  final IconData icon;

  _PartitionItem({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
    required this.type,
    required this.color,
    required this.lightColor,
    required this.icon,
  });
}

class _TimelineSegment {
  final DateTime start;
  final DateTime end;
  final int days;
  final _PartitionItem? item;

  _TimelineSegment({
    required this.start,
    required this.end,
    required this.days,
    this.item,
  });
}
