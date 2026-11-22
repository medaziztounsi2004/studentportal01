import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../providers/undo_redo_provider.dart';
import 'feedback_pill.dart';

/// Modern borderless Undo and Redo toolbar buttons.
/// Styled cleanly like the filter icon without square containers or borders.
/// Optionally supports a [scope] string to isolate undo/redo history per section/page.
class UndoRedoToolbarButtons extends ConsumerWidget {
  final String? scope;
  final Future<void> Function()? onUndo;
  final Future<void> Function()? onRedo;

  const UndoRedoToolbarButtons({
    super.key,
    this.scope,
    this.onUndo,
    this.onRedo,
  });

  Future<void> _handleUndo(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(undoRedoProvider.notifier);
    if (!ref.read(undoRedoProvider).canUndo(scope)) return;

    if (onUndo != null) {
      await onUndo!();
      return;
    }

    try {
      final desc = await notifier.undo(scope);
      if (context.mounted && desc != null) {
        FeedbackPill.showUndo(
          context,
          message: 'Action annulée : $desc',
        );
      }
    } catch (e) {
      if (context.mounted) {
        FeedbackPill.showError(context, 'Impossible d\'annuler : $e');
      }
    }
  }

  Future<void> _handleRedo(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(undoRedoProvider.notifier);
    if (!ref.read(undoRedoProvider).canRedo(scope)) return;

    if (onRedo != null) {
      await onRedo!();
      return;
    }

    try {
      final desc = await notifier.redo(scope);
      if (context.mounted && desc != null) {
        FeedbackPill.show(
          context,
          message: 'Action rétablie : $desc',
          type: FeedbackPillType.info,
        );
      }
    } catch (e) {
      if (context.mounted) {
        FeedbackPill.showError(context, 'Impossible de rétablir : $e');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final undoState = ref.watch(undoRedoProvider);
    final canUndo = undoState.canUndo(scope);
    final canRedo = undoState.canRedo(scope);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.rotate_left_rounded, size: 20),
          tooltip: undoState.undoTooltip(scope),
          onPressed: canUndo ? () => _handleUndo(context, ref) : null,
          color: canUndo ? AppColors.textPrimary : AppColors.textTertiary.withValues(alpha: 0.35),
          disabledColor: AppColors.textTertiary.withValues(alpha: 0.35),
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide.none,
            ),
          ),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        ),
        IconButton(
          icon: const Icon(Icons.rotate_right_rounded, size: 20),
          tooltip: undoState.redoTooltip(scope),
          onPressed: canRedo ? () => _handleRedo(context, ref) : null,
          color: canRedo ? AppColors.textPrimary : AppColors.textTertiary.withValues(alpha: 0.35),
          disabledColor: AppColors.textTertiary.withValues(alpha: 0.35),
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide.none,
            ),
          ),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        ),
      ],
    );
  }
}
