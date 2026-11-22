import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/supabase_config.dart';
import '../../data/services/backup_service.dart';
import 'auth_provider.dart';

class BackupState {
  final bool isLoading;
  final bool isCreatingBackup;
  final List<BackupItem> backups;
  final BackupConfig config;
  final String? errorMessage;
  final String? successMessage;

  BackupState({
    this.isLoading = false,
    this.isCreatingBackup = false,
    this.backups = const [],
    BackupConfig? config,
    this.errorMessage,
    this.successMessage,
  }) : config = config ?? BackupConfig();

  BackupState copyWith({
    bool? isLoading,
    bool? isCreatingBackup,
    List<BackupItem>? backups,
    BackupConfig? config,
    String? errorMessage,
    String? successMessage,
    bool clearMessages = false,
  }) {
    return BackupState(
      isLoading: isLoading ?? this.isLoading,
      isCreatingBackup: isCreatingBackup ?? this.isCreatingBackup,
      backups: backups ?? this.backups,
      config: config ?? this.config,
      errorMessage: clearMessages ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearMessages ? null : (successMessage ?? this.successMessage),
    );
  }
}

final backupProvider = NotifierProvider<BackupNotifier, BackupState>(BackupNotifier.new);

class BackupNotifier extends Notifier<BackupState> {
  @override
  BackupState build() {
    ref.listen(authProvider, (previous, next) {
      if (previous?.user?.schoolId != next.user?.schoolId && next.user?.schoolId != null) {
        _load();
      }
    });

    Future.microtask(() => _load());
    return BackupState(isLoading: true);
  }

  Future<String?> _resolveSchoolId() async {
    final authSchoolId = ref.read(authProvider).user?.schoolId;
    if (authSchoolId != null && authSchoolId.isNotEmpty) return authSchoolId;

    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    if (currentUserId == null) return null;

    try {
      final userResp = await SupabaseConfig.adminClient
          .from('users')
          .select('school_id')
          .eq('id', currentUserId)
          .maybeSingle();
      return userResp?['school_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    final schoolId = await _resolveSchoolId();
    if (schoolId == null) {
      state = state.copyWith(isLoading: false);
      return;
    }

    try {
      // 1. Instantly load previous backups and config without blocking
      final backups = await BackupService.getBackups(schoolId);
      final config = await BackupService.getBackupConfig(schoolId);

      state = state.copyWith(
        isLoading: false,
        backups: backups,
        config: config,
      );

      // 2. Perform schedule check asynchronously in background
      Future.microtask(() async {
        try {
          await BackupService.checkAndRunScheduledBackup(schoolId);
          final freshBackups = await BackupService.getBackups(schoolId);
          final freshConfig = await BackupService.getBackupConfig(schoolId);
          state = state.copyWith(backups: freshBackups, config: freshConfig);
        } catch (e) {
          debugPrint('[BackupNotifier] Background check error: $e');
        }
      });
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Impossible de charger l\'historique des sauvegardes: $e',
      );
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, clearMessages: true);
    await _load();
  }

  Future<bool> triggerManualBackup() async {
    final schoolId = await _resolveSchoolId();
    if (schoolId == null) {
      state = state.copyWith(errorMessage: 'Établissement introuvable');
      return false;
    }

    state = state.copyWith(isCreatingBackup: true, clearMessages: true);
    try {
      final newItem = await BackupService.createBackup(schoolId);
      final updatedBackups = [newItem, ...state.backups.where((b) => b.id != newItem.id)];
      final updatedConfig = BackupConfig(
        cycle: state.config.cycle,
        autoEnabled: state.config.autoEnabled,
        lastBackupAt: newItem.createdAt,
      );

      state = state.copyWith(
        isCreatingBackup: false,
        backups: updatedBackups,
        config: updatedConfig,
        successMessage: 'Sauvegarde complète créée avec succès (${newItem.formattedSize}).',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isCreatingBackup: false,
        errorMessage: 'Échec de la sauvegarde: $e',
      );
      return false;
    }
  }

  Future<void> updateCycle(String newCycle) async {
    final schoolId = await _resolveSchoolId();
    if (schoolId == null) return;

    final updatedConfig = BackupConfig(
      cycle: newCycle,
      autoEnabled: state.config.autoEnabled,
      lastBackupAt: state.config.lastBackupAt,
    );

    state = state.copyWith(config: updatedConfig);
    await BackupService.saveBackupConfig(schoolId, updatedConfig);
  }

  Future<void> toggleAutoBackup(bool enabled) async {
    final schoolId = await _resolveSchoolId();
    if (schoolId == null) return;

    final updatedConfig = BackupConfig(
      cycle: state.config.cycle,
      autoEnabled: enabled,
      lastBackupAt: state.config.lastBackupAt,
    );

    state = state.copyWith(config: updatedConfig);
    await BackupService.saveBackupConfig(schoolId, updatedConfig);
  }

  Future<void> download(BackupItem item) async {
    await BackupService.downloadBackup(item);
  }
}
