import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/class_model.dart';
import '../../../data/models/academic_models.dart';
import '../../providers/classes_provider.dart';
import '../../providers/grade_levels_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../widgets/ios_loader.dart';
import '../../providers/undo_redo_provider.dart';
import '../../widgets/feedback_pill.dart';

class ClassFormDialog extends ConsumerStatefulWidget {
  final ClassModel? classModel;
  const ClassFormDialog({super.key, this.classModel});
  @override
  ConsumerState<ClassFormDialog> createState() => _ClassFormDialogState();
}

class _ClassFormDialogState extends ConsumerState<ClassFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _capacityController;
  String? _selectedGradeLevelId;
  String? _selectedSectionId;
  String? _selectedRoomId;
  bool _isLoading = false;
  bool _autoGenerateName = true;

  bool get isEditing => widget.classModel != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.classModel?.name ?? '',
    );
    _capacityController = TextEditingController(
      text: widget.classModel?.capacity?.toString() ?? '',
    );
    _selectedGradeLevelId = widget.classModel?.gradeLevelId;
    _selectedSectionId = widget.classModel?.sectionId;
    // Don't auto-generate name if editing
    if (isEditing) _autoGenerateName = false;
  }

  // Count existing classes for a given niveau/section to generate number suffix
  int _countClassesForLevel(String? gradeLevelId, String? sectionId) {
    final classesAsync = ref.read(classesProvider);
    return classesAsync.maybeWhen(
      data: (state) {
        return state.classes.where((c) {
          if (c.gradeLevelId != gradeLevelId) return false;
          if (sectionId != null && c.sectionId != sectionId) return false;
          if (sectionId == null && c.sectionId != null) return false;
          return true;
        }).length;
      },
      orElse: () => 0,
    );
  }

  // Generate class name from niveau code + section code + number
  String _generateClassName(GradeLevelsState state) {
    if (_selectedGradeLevelId == null) return '';

    final grade = state.gradeLevels.firstWhere(
      (g) => g.id == _selectedGradeLevelId,
      orElse: () =>
          GradeLevelModel(id: '', name: '', code: '', levelType: 'college'),
    );

    if (grade.id.isEmpty) return '';

    String baseName = grade.code;

    // Add section code for secondaire
    if (_selectedSectionId != null) {
      final section = grade.sections.firstWhere(
        (s) => s.id == _selectedSectionId,
        orElse: () => SectionModel(id: '', name: '', code: ''),
      );
      if (section.id.isNotEmpty) {
        baseName = '${grade.code}-${section.code}';
      }
    }

    // Add number suffix
    final existingCount = _countClassesForLevel(
      _selectedGradeLevelId,
      _selectedSectionId,
    );
    final nextNumber = existingCount + 1;

    return '$baseName-$nextNumber';
  }

  void _updateAutoName(GradeLevelsState state) {
    if (_autoGenerateName && !isEditing) {
      final newName = _generateClassName(state);
      if (newName.isNotEmpty) {
        _nameController.text = newName;
      }
    }
  }

  // Reusable label widget above fields
  Widget _fieldLabel(String label, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          text: label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF374151)),
          children: [
            if (required)
              const TextSpan(text: ' *', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  // Shared input decoration (light grey fill, rounded, no prefix icons)
  InputDecoration get _inputDeco => InputDecoration(
    filled: true,
    fillColor: const Color(0xFFF8F9FA),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    hintStyle: const TextStyle(color: Color(0xFFB0B3BE), fontSize: 14, fontWeight: FontWeight.w400),
  );

  @override
  Widget build(BuildContext context) {
    final gradeLevelsAsync = ref.watch(gradeLevelsProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      child: Container(
        width: 520,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEditing ? 'Modifier la classe' : 'Nouvelle classe',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isEditing
                              ? 'Modifiez les informations de la classe.'
                              : 'Créer une nouvelle classe pour votre établissement.',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF9B9DAB)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF7B7D8B)),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // ── Niveau scolaire ──
              gradeLevelsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                ),
                error: (e, _) => Text(
                  UserFriendlyError.format(
                    e,
                    fallback: 'Unable to load grade levels right now.',
                  ),
                  style: const TextStyle(color: AppColors.error),
                ),
                data: (state) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fieldLabel('Niveau scolaire', required: true),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedGradeLevelId,
                      decoration: _inputDeco.copyWith(
                        hintText: 'Sélectionner un niveau',
                      ),
                      borderRadius: BorderRadius.circular(12),
                      dropdownColor: Colors.white,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Color(0xFF1A1A2E)),
                      items: state.gradeLevels.map((g) => DropdownMenuItem<String>(
                        value: g.id,
                        child: Text(
                          '${g.name} (${g.levelType == 'college' ? 'Collège' : 'Secondaire'})',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
                        ),
                      )).toList(),
                      onChanged: (v) {
                        setState(() { _selectedGradeLevelId = v; _selectedSectionId = null; });
                        _updateAutoName(state);
                      },
                      validator: (v) => v == null || v.isEmpty ? 'Requis' : null,
                    ),
                    const SizedBox(height: 20),
                    _buildSectionDropdown(state),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Nom de la classe ──
              _fieldLabel('Nom de la classe', required: true),
              TextFormField(
                controller: _nameController,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Color(0xFF1A1A2E)),
                decoration: _inputDeco.copyWith(
                  hintText: 'Ex: 7B-1',
                  suffixIcon: !isEditing
                      ? Tooltip(
                          message: _autoGenerateName ? 'Nom auto-généré' : 'Nom manuel',
                          child: IconButton(
                            icon: Icon(
                              _autoGenerateName ? Icons.auto_awesome : Icons.edit,
                              color: _autoGenerateName ? AppColors.primary : AppColors.slate300,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() => _autoGenerateName = !_autoGenerateName);
                              if (_autoGenerateName) {
                                gradeLevelsAsync.whenData((state) => _updateAutoName(state));
                              }
                            },
                          ),
                        )
                      : null,
                ),
                validator: (v) => v?.isEmpty == true ? 'Requis' : null,
                onChanged: (v) { if (v.isNotEmpty) _autoGenerateName = false; },
              ),
              const SizedBox(height: 20),

              // ── Capacité ──
              _fieldLabel('Capacité'),
              TextFormField(
                controller: _capacityController,
                decoration: _inputDeco.copyWith(hintText: 'Ex: 30'),
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Color(0xFF1A1A2E)),
              ),

              const SizedBox(height: 32),

              // ── Actions ──
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    height: 40,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF6B7280),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6D4CF6),
                        foregroundColor: Colors.white,
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      child: _isLoading
                          ? const IosLoader.small(color: Colors.white)
                          : Text(isEditing ? 'Enregistrer' : 'Créer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionDropdown(GradeLevelsState state) {
    // Get sections available for the selected grade level
    List<SectionModel> availableSections = [];
    if (_selectedGradeLevelId != null) {
      final grade = state.gradeLevels.firstWhere(
        (g) => g.id == _selectedGradeLevelId,
        orElse: () =>
            GradeLevelModel(id: '', name: '', code: '', levelType: 'college'),
      );

      // Only secondaire grades have sections
      if (grade.levelType == 'secondaire') {
        availableSections = grade.sections;
      }
    }

    if (availableSections.isEmpty && _selectedGradeLevelId != null) {
      final grade = state.gradeLevels.firstWhere(
        (g) => g.id == _selectedGradeLevelId,
        orElse: () =>
            GradeLevelModel(id: '', name: '', code: '', levelType: 'college'),
      );
      if (grade.levelType == 'college') {
        return const SizedBox.shrink();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Filière'),
        DropdownButtonFormField<String>(
          initialValue: _selectedSectionId,
          decoration: _inputDeco.copyWith(hintText: 'Aucune filière'),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Color(0xFF1A1A2E)),
          borderRadius: BorderRadius.circular(12),
          dropdownColor: Colors.white,
          items: availableSections
              .map(
                (s) => DropdownMenuItem<String>(value: s.id, child: Text(s.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400))),
              )
              .toList(),
          onChanged: (v) {
            setState(() => _selectedSectionId = v);
            _updateAutoName(state);
          },
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final notifier = ref.read(classesProvider.notifier);
      final capacity = _capacityController.text.isEmpty
          ? null
          : int.tryParse(_capacityController.text);

      if (isEditing) {
        final oldCls = widget.classModel!;
        final newName = _nameController.text.trim();
        final newGradeLevelId = _selectedGradeLevelId;
        final newSectionId = _selectedSectionId;
        final newRoom = _selectedRoomId;
        final newCap = capacity;

        await notifier.updateClass(
          id: oldCls.id,
          name: newName,
          gradeLevelId: newGradeLevelId,
          sectionId: newSectionId,
          capacity: newCap,
          room: newRoom,
        );

        ref.read(undoRedoProvider.notifier).recordAction(
          AppAction(
            scope: 'classes',
            title: 'Modification classe',
            description: 'Modification de la classe "$newName"',
            undo: (r) async {
              await r.read(classesProvider.notifier).updateClass(
                id: oldCls.id,
                name: oldCls.name,
                gradeLevelId: oldCls.gradeLevelId,
                sectionId: oldCls.sectionId,
                capacity: oldCls.capacity,
                room: oldCls.room,
              );
            },
            redo: (r) async {
              await r.read(classesProvider.notifier).updateClass(
                id: oldCls.id,
                name: newName,
                gradeLevelId: newGradeLevelId,
                sectionId: newSectionId,
                capacity: newCap,
                room: newRoom,
              );
            },
          ),
        );
      } else {
        await notifier.create(
          name: _nameController.text.trim(),
          gradeLevelId: _selectedGradeLevelId,
          sectionId: _selectedSectionId,
          capacity: capacity,
          room: _selectedRoomId,
        );
      }
      final clsName = _nameController.text.trim();
      if (mounted) {
        Navigator.pop(context);
        FeedbackPill.showSuccess(context, isEditing ? 'Classe "$clsName" modifiée' : 'Classe "$clsName" créée');
      }
    } catch (e) {
      if (mounted) {
        final clsName = _nameController.text.trim();
        FeedbackPill.showError(
          context,
          UserFriendlyError.format(
            e,
            fallback: 'Impossible d\'enregistrer la classe "$clsName".',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
