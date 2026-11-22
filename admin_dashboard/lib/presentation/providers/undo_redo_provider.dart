import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef UndoRedoAsyncCallback = Future<void> Function(Ref ref);

class AppAction {
  final String id;
  final String title;
  final String description;
  final String? scope;
  final dynamic _undo;
  final dynamic _redo;
  final DateTime timestamp;

  AppAction({
    required this.title,
    required this.description,
    required dynamic undo,
    required dynamic redo,
    this.scope,
    String? id,
    DateTime? timestamp,
  })  : _undo = undo,
        _redo = redo,
        id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp = timestamp ?? DateTime.now();

  Future<void> executeUndo(Ref ref) async {
    if (_undo is Future<void> Function(Ref)) {
      await (_undo as Future<void> Function(Ref))(ref);
    } else if (_undo is Future<void> Function()) {
      await (_undo as Future<void> Function())();
    }
  }

  Future<void> executeRedo(Ref ref) async {
    if (_redo is Future<void> Function(Ref)) {
      await (_redo as Future<void> Function(Ref))(ref);
    } else if (_redo is Future<void> Function()) {
      await (_redo as Future<void> Function())();
    }
  }

  Future<void> Function() get undo => () => _undo is Future<void> Function(Ref)
      ? (_undo as Future<void> Function(Ref))(null as dynamic)
      : (_undo as Future<void> Function())();

  Future<void> Function() get redo => () => _redo is Future<void> Function(Ref)
      ? (_redo as Future<void> Function(Ref))(null as dynamic)
      : (_redo as Future<void> Function())();
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

  bool canUndo([String? scope]) {
    if (isExecuting) return false;
    if (scope == null) return undoStack.isNotEmpty;
    return undoStack.any((a) => a.scope == scope);
  }

  bool canRedo([String? scope]) {
    if (isExecuting) return false;
    if (scope == null) return redoStack.isNotEmpty;
    return redoStack.any((a) => a.scope == scope);
  }

  AppAction? currentUndoAction([String? scope]) {
    if (undoStack.isEmpty) return null;
    if (scope == null) return undoStack.last;
    try {
      return undoStack.lastWhere((a) => a.scope == scope);
    } catch (_) {
      return null;
    }
  }

  AppAction? currentRedoAction([String? scope]) {
    if (redoStack.isEmpty) return null;
    if (scope == null) return redoStack.last;
    try {
      return redoStack.lastWhere((a) => a.scope == scope);
    } catch (_) {
      return null;
    }
  }

  String undoTooltip([String? scope]) {
    final a = currentUndoAction(scope);
    return a != null
        ? 'Annuler : ${a.description} (Ctrl+Z)'
        : 'Annuler (Ctrl+Z)';
  }

  String redoTooltip([String? scope]) {
    final a = currentRedoAction(scope);
    return a != null
        ? 'Rétablir : ${a.description} (Ctrl+Y)'
        : 'Rétablir (Ctrl+Y)';
  }

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
    debugPrint('[UndoRedo] Recorded action (${action.scope ?? "global"}): ${action.title} - ${action.description}. Undo count: ${updatedUndo.length}');
  }

  /// Rollback the latest action and push it to redo
  Future<String?> undo([String? scope]) async {
    if (!state.canUndo(scope)) return null;

    final AppAction action;
    final List<AppAction> updatedUndo = List.from(state.undoStack);
    if (scope == null) {
      action = updatedUndo.removeLast();
    } else {
      final index = updatedUndo.lastIndexWhere((a) => a.scope == scope);
      if (index == -1) return null;
      action = updatedUndo.removeAt(index);
    }

    state = state.copyWith(
      isExecuting: true,
      undoStack: updatedUndo,
    );

    try {
      debugPrint('[UndoRedo] Executing UNDO (${action.scope ?? "global"}): ${action.title}');
      await action.executeUndo(ref);
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
  Future<String?> redo([String? scope]) async {
    if (!state.canRedo(scope)) return null;

    final AppAction action;
    final List<AppAction> updatedRedo = List.from(state.redoStack);
    if (scope == null) {
      action = updatedRedo.removeLast();
    } else {
      final index = updatedRedo.lastIndexWhere((a) => a.scope == scope);
      if (index == -1) return null;
      action = updatedRedo.removeAt(index);
    }

    state = state.copyWith(
      isExecuting: true,
      redoStack: updatedRedo,
    );

    try {
      debugPrint('[UndoRedo] Executing REDO (${action.scope ?? "global"}): ${action.title}');
      await action.executeRedo(ref);
      final updatedUndo = [...state.undoStack, action];
      state = state.copyWith(
        undoStack: updatedUndo,
        isExecuting: false,
      );
      return action.description;
    } catch (e) {
      debugPrint('[UndoRedo] Error executing REDO: $e');
      state = state.copyWith(
        redoStack: [...state.redoStack, action],
        isExecuting: false,
      );
      rethrow;
    }
  }

  void clear([String? scope]) {
    if (scope == null) {
      state = UndoRedoState();
    } else {
      state = state.copyWith(
        undoStack: state.undoStack.where((a) => a.scope != scope).toList(),
        redoStack: state.redoStack.where((a) => a.scope != scope).toList(),
      );
    }
  }
}
