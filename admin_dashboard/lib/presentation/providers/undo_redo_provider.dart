import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppAction {
  final String id;
  final String title;
  final String description;
  final Future<void> Function() undo;
  final Future<void> Function() redo;
  final DateTime timestamp;

  AppAction({
    required this.title,
    required this.description,
    required this.undo,
    required this.redo,
    String? id,
    DateTime? timestamp,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp = timestamp ?? DateTime.now();
}

class UndoRedoState {
  final List<AppAction> undoStack;
  final List<AppAction> redoStack;
  final bool isExecuting;

  UndoRedoState({
    this.undoStack = const [],
    this.redoStack = const [],
    this.isExecuting = false,
  });

  bool get canUndo => undoStack.isNotEmpty && !isExecuting;
  bool get canRedo => redoStack.isNotEmpty && !isExecuting;

  AppAction? get currentUndoAction => undoStack.isNotEmpty ? undoStack.last : null;
  AppAction? get currentRedoAction => redoStack.isNotEmpty ? redoStack.last : null;

  String get undoTooltip => canUndo
      ? 'Annuler : ${currentUndoAction!.description} (Ctrl+Z)'
      : 'Annuler (Ctrl+Z)';

  String get redoTooltip => canRedo
      ? 'Rétablir : ${currentRedoAction!.description} (Ctrl+Y)'
      : 'Rétablir (Ctrl+Y)';

  UndoRedoState copyWith({
    List<AppAction>? undoStack,
    List<AppAction>? redoStack,
    bool? isExecuting,
  }) {
    return UndoRedoState(
      undoStack: undoStack ?? this.undoStack,
      redoStack: redoStack ?? this.redoStack,
      isExecuting: isExecuting ?? this.isExecuting,
    );
  }
}

final undoRedoProvider = NotifierProvider<UndoRedoNotifier, UndoRedoState>(
  UndoRedoNotifier.new,
);

class UndoRedoNotifier extends Notifier<UndoRedoState> {
  static const int _maxHistory = 50;

  @override
  UndoRedoState build() => UndoRedoState();

  /// Pushes a new action onto the undo stack and clears redo stack
  void recordAction(AppAction action) {
    final updatedUndo = [...state.undoStack, action];
    if (updatedUndo.length > _maxHistory) {
      updatedUndo.removeAt(0);
    }
    state = state.copyWith(
      undoStack: updatedUndo,
      redoStack: [], // New action clears redo history
      isExecuting: false,
    );
    debugPrint('[UndoRedo] Recorded action: ${action.title} - ${action.description}. Undo count: ${updatedUndo.length}');
  }

  /// Rollback the latest action and push it to redo
  Future<String?> undo() async {
    if (!state.canUndo) return null;

    final action = state.undoStack.last;
    final updatedUndo = state.undoStack.sublist(0, state.undoStack.length - 1);

    state = state.copyWith(
      isExecuting: true,
      undoStack: updatedUndo,
    );

    try {
      debugPrint('[UndoRedo] Executing UNDO: ${action.title}');
      await action.undo();
      final updatedRedo = [...state.redoStack, action];
      state = state.copyWith(
        redoStack: updatedRedo,
        isExecuting: false,
      );
      return action.description;
    } catch (e) {
      debugPrint('[UndoRedo] Error executing UNDO: $e');
      // Restore action to undo stack on failure
      state = state.copyWith(
        undoStack: [...state.undoStack, action],
        isExecuting: false,
      );
      rethrow;
    }
  }

  /// Re-execute the latest undone action and push back to undo
  Future<String?> redo() async {
    if (!state.canRedo) return null;

    final action = state.redoStack.last;
    final updatedRedo = state.redoStack.sublist(0, state.redoStack.length - 1);

    state = state.copyWith(
      isExecuting: true,
      redoStack: updatedRedo,
    );

    try {
      debugPrint('[UndoRedo] Executing REDO: ${action.title}');
      await action.redo();
      final updatedUndo = [...state.undoStack, action];
      state = state.copyWith(
        undoStack: updatedUndo,
        isExecuting: false,
      );
      return action.description;
    } catch (e) {
      debugPrint('[UndoRedo] Error executing REDO: $e');
      // Restore action to redo stack on failure
      state = state.copyWith(
        redoStack: [...state.redoStack, action],
        isExecuting: false,
      );
      rethrow;
    }
  }

  void clear() {
    state = UndoRedoState();
  }
}
