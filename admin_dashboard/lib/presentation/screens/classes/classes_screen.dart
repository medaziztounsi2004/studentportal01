import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/utils/error_messages.dart';
import '../../../data/models/class_model.dart';
import '../../../data/models/academic_models.dart';
import '../../providers/classes_provider.dart';
import '../../providers/grade_levels_provider.dart';
import '../../providers/undo_redo_provider.dart';
import '../../widgets/admin_sidebar.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/ios_loader.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/undo_redo_toolbar_buttons.dart';
import '../../widgets/feedback_pill.dart';
import '../../widgets/admin_sort_dropdown.dart';

import 'class_form_dialog.dart';

// ═══════════════════════════════════════════════════════════════════
// ░░░  Gestion des Classes — 3-Column Layout  ░░░
// ═══════════════════════════════════════════════════════════════════

const _brand = Color(0xFF655DD5);
const _brandLight = Color(0xFFEEECFB);
const _brandDark = Color(0xFF4A42B0);

class ClassesScreen extends ConsumerStatefulWidget {
  const ClassesScreen({super.key});
  @override
  ConsumerState<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends ConsumerState<ClassesScreen> {
  String? _selectedClassId;
  String? _expandedNiveauId;
  String? _selectedSectionId;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortKey = 'name_asc';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleUndo() async {
    final notifier = ref.read(undoRedoProvider.notifier);
    if (!ref.read(undoRedoProvider).canUndo('classes')) return;
    try {
      final desc = await notifier.undo('classes');
      if (mounted && desc != null) {
        FeedbackPill.showUndo(context, message: 'Action annulée : $desc');
      }
    } catch (e) {
      if (mounted) FeedbackPill.showError(context, 'Impossible d\'annuler : $e');
    }
  }

  Future<void> _handleRedo() async {
    final notifier = ref.read(undoRedoProvider.notifier);
    if (!ref.read(undoRedoProvider).canRedo('classes')) return;
    try {
      final desc = await notifier.redo('classes');
      if (mounted && desc != null) {
        FeedbackPill.show(context, message: 'Action rétablie : $desc', type: FeedbackPillType.info);
      }
    } catch (e) {
      if (mounted) FeedbackPill.showError(context, 'Impossible de rétablir : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(classesProvider);
    final gradeLevelsAsync = ref.watch(gradeLevelsProvider);

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
          backgroundColor: const Color(0xFFF5F7FA),
          body: Row(
            children: [
              const AdminSidebar(currentRoute: '/classes'),
              Expanded(
                child: classesAsync.when(
                  loading: () => const ClassesSkeletonLoader(),
                  error: (e, _) => _buildErrorState(e),
                  data: (state) => gradeLevelsAsync.when(
                    loading: () => const ClassesSkeletonLoader(),
                    error: (e, _) => _buildErrorState(e),
                    data: (glState) => _buildBody(context, state, glState),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ClassesState state, GradeLevelsState glState) {
    final allClasses = state.classes;
    final totalStudents = allClasses.fold<int>(0, (s, c) => s + c.studentCount);

    List<ClassModel> visibleClasses;
    if (_selectedSectionId != null && _expandedNiveauId != null) {
      visibleClasses = allClasses
          .where((c) => c.gradeLevelId == _expandedNiveauId && c.sectionId == _selectedSectionId)
          .toList();
    } else if (_expandedNiveauId != null) {
      visibleClasses = allClasses.where((c) => c.gradeLevelId == _expandedNiveauId).toList();
    } else {
      visibleClasses = allClasses;
    }

    if (state.searchQuery != null && state.searchQuery!.isNotEmpty) {
      final q = state.searchQuery!.toLowerCase();
      visibleClasses = visibleClasses.where((c) =>
        c.name.toLowerCase().contains(q) ||
        (c.sectionName?.toLowerCase().contains(q) ?? false) ||
        (c.room?.toLowerCase().contains(q) ?? false)
      ).toList();
    }

    visibleClasses.sort((a, b) {
      switch (_sortKey) {
        case 'name_desc':
          return b.name.compareTo(a.name);
        case 'students_desc':
          return b.studentCount.compareTo(a.studentCount);
        case 'students_asc':
          return a.studentCount.compareTo(b.studentCount);
        case 'room_asc':
          return (a.room ?? '').compareTo(b.room ?? '');
        case 'date_desc':
          final aDate = a.createdAt ?? DateTime(2000);
          final bDate = b.createdAt ?? DateTime(2000);
          return bDate.compareTo(aDate);
        case 'date_asc':
          final aDate = a.createdAt ?? DateTime(2000);
          final bDate = b.createdAt ?? DateTime(2000);
          return aDate.compareTo(bDate);
        case 'name_asc':
        default:
          return a.name.compareTo(b.name);
      }
    });

    final ClassModel? selectedClass = _selectedClassId != null
        ? allClasses.where((c) => c.id == _selectedClassId).isNotEmpty
            ? allClasses.firstWhere((c) => c.id == _selectedClassId)
            : null
        : null;

    String headerTitle = 'Toutes les classes';
    if (_selectedSectionId != null) {
      for (final gl in glState.gradeLevels) {
        for (final s in gl.sections) {
          if (s.id == _selectedSectionId) {
            headerTitle = 'Classes: ${s.name}';
            break;
          }
        }
      }
    } else if (_expandedNiveauId != null) {
      final gl = glState.gradeLevels.where((g) => g.id == _expandedNiveauId);
      if (gl.isNotEmpty) headerTitle = 'Classes: ${gl.first.name}';
    }

    return Row(
      children: [
        Container(
          width: 280,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(right: BorderSide(color: AppColors.border.withOpacity(0.5))),
          ),
          child: _buildLeftPanel(allClasses, glState, totalStudents),
        ),
        Expanded(
          child: Column(
            children: [
              _buildCenterHeader(headerTitle, visibleClasses.length),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: visibleClasses.isEmpty
                          ? _buildEmptyState()
                          : SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: Wrap(
                                spacing: 16,
                                runSpacing: 16,
                                children: visibleClasses.map((cls) => _buildClassCard(cls)).toList(),
                              ),
                            ),
                    ),
                    Container(
                      width: 300,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(left: BorderSide(color: AppColors.border.withOpacity(0.5))),
                      ),
                      child: _buildRightPanel(selectedClass),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── LEFT PANEL ──
  Widget _buildLeftPanel(List<ClassModel> allClasses, GradeLevelsState glState, int totalStudents) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── TOTAL ÉTUDIANTS — flat white card ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: _brand,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.school_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'TOTAL ÉTUDIANTS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary.withOpacity(0.7),
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  '$totalStudents',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A2E),
                    height: 1,
                  ),
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: 0.68,
                    minHeight: 5,
                    backgroundColor: _brandLight,
                    valueColor: const AlwaysStoppedAnimation<Color>(_brand),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── Par niveau section title ──
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 14),
            child: Text(
              'Par niveau',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: const Color(0xFF1A1A2E),
                letterSpacing: -0.2,
              ),
            ),
          ),

          // ── Niveau cards ──
          ...(() {
            final sortedGL = List<GradeLevelModel>.from(glState.gradeLevels)
              ..sort((a, b) {
                final orderA = _getNiveauSortOrder(a.name);
                final orderB = _getNiveauSortOrder(b.name);
                if (orderA != orderB) return orderA.compareTo(orderB);
                return a.name.compareTo(b.name);
              });
            return sortedGL.map((gl) {
            final isExpanded = _expandedNiveauId == gl.id;
            final niveauClasses = allClasses.where((c) => c.gradeLevelId == gl.id).toList();
            final niveauCount = gl.sections.isNotEmpty ? gl.sections.length : niveauClasses.length;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: isExpanded ? const Color(0xFFF0EEFA) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    if (!isExpanded)
                      BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 2)),
                  ],
                  border: isExpanded
                      ? Border.all(color: _brand.withOpacity(0.12))
                      : Border.all(color: Colors.grey.withOpacity(0.06)),
                ),
                child: Column(
                  children: [
                    // ── Level header row ──
                    InkWell(
                      onTap: () => setState(() {
                        if (isExpanded) { _expandedNiveauId = null; _selectedSectionId = null; }
                        else { _expandedNiveauId = gl.id; _selectedSectionId = null; }
                      }),
                      borderRadius: BorderRadius.circular(16),
                      hoverColor: _brandLight.withOpacity(0.3),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                gl.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: isExpanded ? _brand : const Color(0xFF2D2D3A),
                                ),
                              ),
                            ),
                            Container(
                              width: 30, height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isExpanded ? _brand : const Color(0xFFE9EAF0),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '$niveauCount',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isExpanded ? Colors.white : const Color(0xFF7B7D8B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Expanded sections with vertical connecting line ──
                    if (isExpanded && gl.sections.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 20, right: 14, bottom: 14),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Vertical connecting line
                              Container(
                                width: 2,
                                margin: const EdgeInsets.only(top: 4, bottom: 4),
                                decoration: BoxDecoration(
                                  color: _brand.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                              const SizedBox(width: 14),
                              // Sub-items
                              Expanded(
                                child: Column(
                                  children: gl.sections.map((section) {
                                    final sClasses = niveauClasses.where((c) => c.sectionId == section.id).toList();
                                    final isSel = _selectedSectionId == section.id;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () => setState(() => _selectedSectionId = isSel ? null : section.id),
                                          borderRadius: BorderRadius.circular(12),
                                          hoverColor: Colors.white.withOpacity(0.8),
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                            decoration: BoxDecoration(
                                              color: isSel ? Colors.white : Colors.white.withOpacity(0.6),
                                              borderRadius: BorderRadius.circular(12),
                                              boxShadow: isSel ? [
                                                BoxShadow(color: _brand.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2)),
                                              ] : null,
                                              border: isSel
                                                  ? Border.all(color: _brand.withOpacity(0.2))
                                                  : Border.all(color: Colors.transparent),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    section.name,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: isSel ? FontWeight.w600 : FontWeight.w500,
                                                      color: isSel ? _brand : const Color(0xFF5A5B6A),
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: isSel ? _brandLight : const Color(0xFFF0F1F5),
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  child: Text(
                                                    '${sClasses.length}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w700,
                                                      color: isSel ? _brand : const Color(0xFF9B9DAB),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // ── Expanded classes (no sections) with connecting line ──
                    if (isExpanded && gl.sections.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 20, right: 14, bottom: 14),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                width: 2,
                                margin: const EdgeInsets.only(top: 4, bottom: 4),
                                decoration: BoxDecoration(
                                  color: _brand.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  children: niveauClasses.map((cls) {
                                    final isSel = _selectedClassId == cls.id;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () => setState(() => _selectedClassId = cls.id),
                                          borderRadius: BorderRadius.circular(12),
                                          hoverColor: Colors.white.withOpacity(0.8),
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                            decoration: BoxDecoration(
                                              color: isSel ? Colors.white : Colors.white.withOpacity(0.6),
                                              borderRadius: BorderRadius.circular(12),
                                              boxShadow: isSel ? [
                                                BoxShadow(color: _brand.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2)),
                                              ] : null,
                                              border: isSel
                                                  ? Border.all(color: _brand.withOpacity(0.2))
                                                  : Border.all(color: Colors.transparent),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    cls.name,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: isSel ? FontWeight.w600 : FontWeight.w500,
                                                      color: isSel ? _brand : const Color(0xFF5A5B6A),
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: isSel ? _brandLight : const Color(0xFFF0F1F5),
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  child: Text(
                                                    '${cls.studentCount}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w700,
                                                      color: isSel ? _brand : const Color(0xFF9B9DAB),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          });
        })(),
      ],
    ),
  );
}

  int _getNiveauSortOrder(String? str) {
    if (str == null || str.trim().isEmpty) return 999;
    final s = str.toLowerCase().trim();

    if (s.contains('7') || s.startsWith('7b') || s.contains('sept')) return 10;
    if (s.contains('8') || s.startsWith('8b') || s.contains('huit')) return 20;
    if (s.contains('9') || s.startsWith('9b') || s.contains('neuf')) return 30;
    if (s.contains('1') || s.startsWith('1s') || s.contains('prem')) return 40;
    if (s.contains('2') || s.startsWith('2s') || s.contains('deux')) return 50;
    if (s.contains('3') || s.startsWith('3s') || s.contains('trois')) return 60;
    if (s.contains('4') || s.startsWith('4s') || s.contains('bac') || s.contains('quatre')) return 70;

    return 999;
  }

  // ── CENTER HEADER ──
  Widget _buildCenterHeader(String title, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE9EAF2))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text('$count classe(s)', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Search bar — responsive
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchController,
                onChanged: (v) {
                  setState(() {
                    _searchQuery = v;
                  });
                  ref.read(classesProvider.notifier).setSearch(v);
                },
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Rechercher...',
                  hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                  prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textTertiary),
                  suffixIcon: _searchQuery.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.slate50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text('⌘K', style: TextStyle(fontSize: 10, color: AppColors.textTertiary, fontFamily: 'monospace')),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                            ref.read(classesProvider.notifier).setSearch('');
                          },
                        ),
                  filled: true,
                  fillColor: AppColors.slate50,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.primary.withOpacity(0.4), width: 1.5),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AdminSortDropdown<String>(
            selectedValue: _sortKey,
            options: const [
              SortOption(value: 'name_asc', label: 'Nom: A → Z', icon: Icons.sort_by_alpha_rounded),
              SortOption(value: 'name_desc', label: 'Nom: Z → A', icon: Icons.sort_by_alpha_rounded),
              SortOption(value: 'students_desc', label: 'Élèves: Plus au moins', icon: Icons.groups_rounded),
              SortOption(value: 'students_asc', label: 'Élèves: Moins au plus', icon: Icons.group_outlined),
              SortOption(value: 'room_asc', label: 'Salle: A → Z', icon: Icons.meeting_room_outlined),
              SortOption(value: 'date_desc', label: 'Date: Plus récent', icon: Icons.schedule_rounded),
              SortOption(value: 'date_asc', label: 'Date: Plus ancien', icon: Icons.history_rounded),
            ],
            onSelected: (val) {
              setState(() {
                _sortKey = val;
              });
            },
          ),
          const SizedBox(width: 8),
          const UndoRedoToolbarButtons(scope: 'classes'),
          const SizedBox(width: 12),
          // + Nouvelle classe button
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: () => _showClassDialog(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Nouvelle classe', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6D4CF6),
                foregroundColor: Colors.white,
                elevation: 2,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                shadowColor: const Color(0xFF6D4CF6).withOpacity(0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── CLASS CARD ──
  Widget _buildClassCard(ClassModel cls) {
    final isSelected = _selectedClassId == cls.id;
    final fillRate = cls.capacity != null && cls.capacity! > 0 ? cls.studentCount / cls.capacity! : 0.0;
    final isFull = fillRate >= 1.0;
    final isNearFull = fillRate >= 0.8;
    final teacherAsync = ref.watch(classMainTeacherProvider(cls.id));
    final teacher = teacherAsync.value;
    Color barColor = _brand;
    if (isFull) barColor = AppColors.error;
    else if (isNearFull) barColor = AppColors.warning;

    return InkWell(
      onTap: () => setState(() => _selectedClassId = cls.id),
      onDoubleTap: () => context.push('/classes/${cls.id}'),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 280,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? _brand : AppColors.border.withOpacity(0.4), width: isSelected ? 2 : 1),
          boxShadow: isSelected
              ? [BoxShadow(color: _brand.withOpacity(0.15), blurRadius: 16, offset: const Offset(0, 4))]
              : [BoxShadow(color: AppColors.shadow, blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: isSelected ? _brand : AppColors.slate100, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.class_rounded, color: isSelected ? Colors.white : AppColors.textTertiary, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cls.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              if (cls.sectionName != null) Text(cls.sectionName!, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
            ])),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz, size: 18, color: AppColors.textTertiary),
              tooltip: 'Actions',
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 8,
              offset: const Offset(-160, 40),
              onSelected: (v) {
                if (v == 'view') context.push('/classes/${cls.id}');
                if (v == 'edit') _showClassDialog(context, cls: cls);
                if (v == 'delete') _confirmDelete(context, cls);
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(value: 'view', height: 40, child: Row(children: [
                  Icon(Icons.visibility_outlined, size: 18, color: AppColors.success),
                  const SizedBox(width: 12),
                  Text('Voir détails', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                ])),
                PopupMenuItem(value: 'edit', height: 40, child: Row(children: [
                  Icon(Icons.edit_outlined, size: 18, color: const Color(0xFF655DD5)),
                  const SizedBox(width: 12),
                  Text('Modifier', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                ])),
                const PopupMenuDivider(),
                PopupMenuItem(value: 'delete', height: 40, child: Row(children: [
                  Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                  const SizedBox(width: 12),
                  Text('Supprimer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.error)),
                ])),
              ],
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textTertiary), const SizedBox(width: 4),
            Text(cls.room ?? 'Non assigné', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: fillRate.clamp(0.0, 1.0), minHeight: 6, backgroundColor: AppColors.slate100, valueColor: AlwaysStoppedAnimation<Color>(barColor)))),
            const SizedBox(width: 10),
            Text('${cls.studentCount}/${cls.capacity ?? "?"}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: barColor)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            UserAvatar(
              name: teacher?.fullName ?? '?',
              photoUrl: teacher?.photoUrl,
              radius: 14,
            ),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(teacher?.fullName ?? 'Non assigné', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const Text('Professeur Principal', style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
            ])),
          ]),
        ]),
      ),
    );
  }

  // ── RIGHT PANEL ──
  Widget _buildRightPanel(ClassModel? cls) {
    if (cls == null) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE9EAF2))),
            ),
            child: const Row(
              children: [
                Icon(Icons.dashboard_customize_outlined, size: 18, color: _brand),
                SizedBox(width: 8),
                Text(
                  'Aperçu de la classe',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(color: AppColors.slate100, shape: BoxShape.circle),
                      child: const Icon(Icons.touch_app_rounded, size: 28, color: AppColors.textTertiary),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Sélectionnez une classe',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Cliquez sur une carte pour voir les détails',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final timetableAsync = ref.watch(classTimetableTodayProvider(cls.id));

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE9EAF2))),
          ),
          child: Row(
            children: [
              const Icon(Icons.dashboard_customize_outlined, size: 18, color: _brand),
              const SizedBox(width: 8),
              const Text(
                'Détails de la classe',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
              ),
              const Spacer(),
              InkWell(
                onTap: () => setState(() => _selectedClassId = null),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 16, color: AppColors.textTertiary),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── DÉTAILS RAPIDES — modern gradient card ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFF7B6CF0), Color(0xFF5A4FCF), Color(0xFF6C5CE7)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(color: _brand.withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 8)),
                  ],
                ),
                child: Stack(
                  children: [
                    // Decorative watermark icon
                    Positioned(
                      right: -8, bottom: -8,
                      child: Icon(Icons.school_rounded, size: 80, color: Colors.white.withOpacity(0.07)),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('DÉTAILS RAPIDES', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                      const SizedBox(height: 10),
                      Text(cls.name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                      const SizedBox(height: 6),
                      Text(
                        '${cls.studentCount} Étudiants • ${cls.room ?? 'Non assigné'}',
                        style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 16),
                      // Étudiants row with stacked avatars
                      Row(children: [
                        const Text('Étudiants', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        InkWell(
                          onTap: () => context.push('/classes/${cls.id}'),
                          child: Text('Voir tout', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      // Stacked student avatars from real data
                      Consumer(builder: (context, ref, _) {
                        final previewAsync = ref.watch(classStudentPreviewsProvider(cls.id));
                        if (previewAsync.isLoading) {
                          return ShimmerLoading(
                            child: Row(
                              children: List.generate(
                                (cls.studentCount > 0 ? cls.studentCount : 3).clamp(1, 4),
                                (i) => Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  child: SkeletonCircle(
                                    size: 32,
                                    color: Colors.white.withOpacity(0.25),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                        final students = previewAsync.asData?.value ?? [];
                        final hasExtra = cls.studentCount > 4;
                        final count = students.length.clamp(0, 4);
                        final total = count + (hasExtra ? 1 : 0);
                        const double radius = 17;
                        const double overlap = 24.0;
                        final double totalWidth = total > 0 ? (radius * 2) + ((total - 1) * overlap) : 0;
                        return SizedBox(
                          height: radius * 2 + 2,
                          width: totalWidth,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ...List.generate(count, (i) {
                                final s = students[i];
                                return Positioned(
                                  left: i * overlap,
                                  top: 0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                    child: UserAvatar(
                                      name: s.fullName,
                                      photoUrl: s.photoUrl,
                                      gender: s.gender,
                                      radius: radius - 2,
                                    ),
                                  ),
                                );
                              }),
                              if (hasExtra)
                                Positioned(
                                  left: count * overlap,
                                  top: 0,
                                  child: CircleAvatar(
                                    radius: radius,
                                    backgroundColor: Colors.white,
                                    child: CircleAvatar(
                                      radius: radius - 2,
                                      backgroundColor: Colors.white.withOpacity(0.25),
                                      child: Text(
                                        '+${cls.studentCount - 4}',
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 16),
                      // Voir les détails button
                      SizedBox(
                        width: double.infinity,
                        child: Material(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: () => context.push('/classes/${cls.id}'),
                            borderRadius: BorderRadius.circular(12),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 11),
                              child: Text('Voir les détails →', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── PROCHAIN COURS — timeline card ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12, offset: const Offset(0, 3)),
                  ],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(color: _brandLight, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.schedule_rounded, color: _brand, size: 16),
                    ),
                    const SizedBox(width: 10),
                    const Text('Cours du jour', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1A1A2E))),
                  ]),
                  const SizedBox(height: 18),

                  timetableAsync.when(
                    loading: () => const ClassTimetableSkeletonLoader(),
                    error: (_, __) => const Text('Unable to load schedule', style: TextStyle(color: AppColors.error, fontSize: 12)),
                    data: (slots) {
                      if (slots.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.event_busy_rounded, size: 28, color: AppColors.textTertiary.withOpacity(0.5)),
                            const SizedBox(height: 8),
                            const Text('Aucun cours aujourd\'hui', style: TextStyle(color: Color(0xFF9B9DAB), fontSize: 12)),
                          ])),
                        );
                      }

                      final now = TimeOfDay.now();
                      final nowMinutes = now.hour * 60 + now.minute;

                      // Sort: current courses first, then upcoming, then past — limit 6
                      int toMin(String t) { final p = t.split(':'); return int.parse(p[0]) * 60 + int.parse(p[1]); }
                      final sortedSlots = List.of(slots)..sort((a, b) {
                        final aS = toMin(a.startTime), aE = toMin(a.endTime);
                        final bS = toMin(b.startTime), bE = toMin(b.endTime);
                        final aCur = nowMinutes >= aS && nowMinutes < aE;
                        final bCur = nowMinutes >= bS && nowMinutes < bE;
                        final aPast = nowMinutes >= aE;
                        final bPast = nowMinutes >= bE;
                        if (aCur && !bCur) return -1;
                        if (!aCur && bCur) return 1;
                        if (!aPast && bPast) return -1;
                        if (aPast && !bPast) return 1;
                        return aS.compareTo(bS);
                      });
                      final displaySlots = sortedSlots.take(6).toList();

                      return Column(children: [
                        ...displaySlots.asMap().entries.map((entry) {
                        final slot = entry.value;
                        final startParts = slot.startTime.split(':');
                        final endParts = slot.endTime.split(':');
                        final startMin = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
                        final endMin = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
                        final isCurrent = nowMinutes >= startMin && nowMinutes < endMin;
                        final isPast = nowMinutes >= endMin;
                        final isLast = entry.key == displaySlots.length - 1;

                        return IntrinsicHeight(
                          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            // Timeline column
                            SizedBox(
                              width: 24,
                              child: Column(children: [
                                Container(
                                  width: isCurrent ? 12 : 10,
                                  height: isCurrent ? 12 : 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isCurrent ? _brand : (isPast ? const Color(0xFFD0D1D9) : const Color(0xFFE4E5EB)),
                                    border: isCurrent ? Border.all(color: _brand.withOpacity(0.3), width: 3) : null,
                                  ),
                                ),
                                if (!isLast)
                                  Expanded(
                                    child: Container(
                                      width: 2,
                                      margin: const EdgeInsets.symmetric(vertical: 2),
                                      color: isCurrent ? _brand.withOpacity(0.2) : const Color(0xFFE4E5EB),
                                    ),
                                  ),
                              ]),
                            ),
                            const SizedBox(width: 12),
                            // Course card
                            Expanded(
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isCurrent ? const Color(0xFFF5F3FF) : const Color(0xFFFAFAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: isCurrent
                                      ? Border.all(color: _brand.withOpacity(0.25), width: 1.5)
                                      : Border.all(color: const Color(0xFFEEEFF2)),
                                ),
                                child: Row(children: [
                                  // Left content
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Row(children: [
                                      Flexible(
                                        child: Text(
                                          slot.subjectName ?? 'Cours',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            color: isCurrent ? _brand : const Color(0xFF2D2D3A),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isCurrent) ...[const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(color: _brand, borderRadius: BorderRadius.circular(6)),
                                          child: const Text('EN COURS', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                                        ),
                                      ],
                                    ]),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${slot.startTime.substring(0, 5)} - ${slot.endTime.substring(0, 5)}${slot.room != null ? ' • ${slot.room}' : ''}',
                                      style: TextStyle(fontSize: 11, color: isPast ? const Color(0xFFC0C2CC) : const Color(0xFF9B9DAB)),
                                    ),
                                    if (slot.teacherName != null) ...[const SizedBox(height: 3),
                                      Row(children: [
                                        UserAvatar(
                                          name: slot.teacherName!,
                                          photoUrl: slot.teacherPhotoUrl,
                                          radius: 8,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(slot.teacherName!, style: TextStyle(fontSize: 10, color: isPast ? const Color(0xFFC0C2CC) : const Color(0xFF7B7D8B))),
                                      ]),
                                    ],
                                  ])),
                                  // Right time
                                  Text(
                                    slot.startTime.substring(0, 5),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: isCurrent ? _brand : const Color(0xFFB0B3BE),
                                    ),
                                  ),
                                ]),
                              ),
                            ),
                          ]),
                        );
                      }).toList(),
                        if (slots.length > 6) ...[
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              '+ ${slots.length - 6} autres cours',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _brand),
                            ),
                          ),
                        ],
                      ]);
                    },
                  ),
                ]),
              ),
              const SizedBox(height: 18),

              // ── PROFESSEUR PRINCIPAL CARD ──
              Consumer(
                builder: (context, ref, _) {
                  final teacherAsync = ref.watch(classMainTeacherProvider(cls.id));
                  final teacher = teacherAsync.value;
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 30, height: 30,
                              decoration: BoxDecoration(color: _brandLight, borderRadius: BorderRadius.circular(8)),
                              child: const Icon(Icons.person_outline_rounded, color: _brand, size: 16),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Professeur principal',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1A1A2E)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            UserAvatar(
                              name: teacher?.fullName ?? '?',
                              photoUrl: teacher?.photoUrl,
                              radius: 18,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    teacher?.fullName ?? 'Non assigné',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    teacher != null ? 'Professeur titulaire' : 'Aucun professeur assigné',
                                    style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),

              // ── INFORMATIONS & CAPACITÉ CARD ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12, offset: const Offset(0, 3)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 30, height: 30,
                          decoration: BoxDecoration(color: _brandLight, borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.analytics_outlined, color: _brand, size: 16),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Informations & Capacité',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1A1A2E)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Salle
                    Row(
                      children: [
                        const Icon(Icons.meeting_room_outlined, size: 15, color: AppColors.textTertiary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Salle : ${cls.room ?? 'Non assignée'}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    if (cls.sectionName != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.folder_outlined, size: 15, color: AppColors.textTertiary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Section : ${cls.sectionName}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    // Capacity Progress
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (cls.capacity != null && cls.capacity! > 0)
                                  ? (cls.studentCount / cls.capacity!).clamp(0.0, 1.0)
                                  : 0.0,
                              minHeight: 6,
                              backgroundColor: AppColors.slate100,
                              valueColor: AlwaysStoppedAnimation<Color>(_brand),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${cls.studentCount}/${cls.capacity ?? '—'} élèves',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _brand),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── ACTIONS RAPIDES ──
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showClassDialog(context, cls: cls),
                      icon: const Icon(Icons.edit_outlined, size: 14),
                      label: const Text('Modifier', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        foregroundColor: AppColors.textSecondary,
                        side: BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => context.push('/classes/${cls.id}'),
                      icon: const Icon(Icons.open_in_new_rounded, size: 14),
                      label: const Text('Ouvrir', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        backgroundColor: _brand,
                        foregroundColor: Colors.white,
                        elevation: 1,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ]),
          ),
        ),
      ],
    );
  }

  // ── EMPTY STATE ──
  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 72, height: 72, decoration: const BoxDecoration(color: AppColors.slate100, shape: BoxShape.circle),
        child: const Icon(Icons.class_rounded, size: 36, color: AppColors.textTertiary)),
      const SizedBox(height: 20),
      const Text('Aucune classe trouvée', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      const Text('Ajoutez une classe pour commencer', style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
      const SizedBox(height: 24),
      Material(color: _brand, borderRadius: BorderRadius.circular(10),
        child: InkWell(onTap: () => _showClassDialog(context), borderRadius: BorderRadius.circular(10),
          child: const Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_rounded, color: Colors.white, size: 18), SizedBox(width: 8),
              Text('Ajouter une classe', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ])))),
    ]));
  }

  // ── ERROR STATE ──
  Widget _buildErrorState(Object error) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
      const SizedBox(height: 16),
      Text(
        UserFriendlyError.format(
          error,
          fallback: 'Unable to load classes right now. Please try again.',
        ),
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
      const SizedBox(height: 16),
      Material(color: _brand, borderRadius: BorderRadius.circular(10),
        child: InkWell(onTap: () => ref.read(classesProvider.notifier).refresh(), borderRadius: BorderRadius.circular(10),
          child: const Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Text('Réessayer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))))),
    ]));
  }

  void _showClassDialog(BuildContext context, {ClassModel? cls}) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: ClassFormDialog(classModel: cls),
      ),
    );
  }

  void _confirmDelete(BuildContext context, ClassModel cls) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          surfaceTintColor: Colors.transparent,
          backgroundColor: Colors.white,
          title: Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.errorSoft, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20)),
            const SizedBox(width: 14),
            const Expanded(child: Text('Confirmer la suppression', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
          ]),
          content: Text('Voulez-vous vraiment supprimer la classe ${cls.name} ?', style: const TextStyle(color: Color(0xFF5A5B6A), fontSize: 14)),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
              child: const Text('Annuler', style: TextStyle(color: Color(0xFF7B7D8B), fontWeight: FontWeight.w600, fontSize: 14)),
            ),
            const SizedBox(width: 8),
            Material(
              color: AppColors.error, borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () {
                  final classSnapshot = cls;
                  ref.read(classesProvider.notifier).delete(cls.id);
                  Navigator.pop(ctx);
                  ref.read(undoRedoProvider.notifier).recordAction(
                    AppAction(
                      scope: 'classes',
                      title: 'Suppression classe',
                      description: 'Suppression de ${cls.name}',
                      undo: (r) async {
                        final user = SupabaseConfig.client.auth.currentUser;
                        final profile = user != null
                            ? await SupabaseConfig.adminClient
                                .from('users')
                                .select('school_id')
                                .eq('id', user.id)
                                .single()
                            : null;
                        await SupabaseConfig.adminClient.from('classes').insert({
                          'id': classSnapshot.id,
                          'name': classSnapshot.name,
                          'school_id': profile?['school_id'],
                          'niveau_id': classSnapshot.gradeLevelId,
                          'section_id': classSnapshot.sectionId,
                          'room': classSnapshot.room,
                          'capacity': classSnapshot.capacity,
                        });
                        await r.read(classesProvider.notifier).refresh();
                      },
                      redo: (r) async {
                        await r.read(classesProvider.notifier).delete(classSnapshot.id);
                      },
                    ),
                  );
                  if (mounted) FeedbackPill.showSuccess(context, 'Classe "${cls.name}" supprimée');
                },
                borderRadius: BorderRadius.circular(10),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                  child: Text('Supprimer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}