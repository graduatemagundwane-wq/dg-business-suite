import 'dart:io';

import '../auth/activation_service.dart';
import '../database/local_db.dart';
import 'api_config.dart';
import 'backup_service.dart';
import 'sync_service.dart';

enum HealthState {
  healthy,
  warning,
  error,
}

class DiagnosticItem {
  final String label;
  final HealthState state;
  final String message;

  const DiagnosticItem({
    required this.label,
    required this.state,
    required this.message,
  });
}

class AppHealthReport {
  final DateTime generatedAt;
  final List<DiagnosticItem> items;

  const AppHealthReport({
    required this.generatedAt,
    required this.items,
  });

  HealthState get overallState {
    if (items.any((item) => item.state == HealthState.error)) {
      return HealthState.error;
    }
    if (items.any((item) => item.state == HealthState.warning)) {
      return HealthState.warning;
    }
    return HealthState.healthy;
  }
}

class DiagnosticsService {
  static final DiagnosticsService instance = DiagnosticsService._internal();

  factory DiagnosticsService() => instance;

  DiagnosticsService._internal();

  Future<AppHealthReport> buildReport({
    int shopId = 1,
    ActivationStatus activationStatus = ActivationStatus.pending,
  }) async {
    final items = <DiagnosticItem>[
      await _databaseHealth(),
      await _syncHealth(shopId),
      await _internetHealth(),
      _activationHealth(activationStatus),
      _backupHealth(),
    ];

    return AppHealthReport(
      generatedAt: DateTime.now(),
      items: items,
    );
  }

  Future<DiagnosticItem> _databaseHealth() async {
    try {
      final db = await LocalDatabase.instance.database;
      final result =
          await db.rawQuery('SELECT COUNT(*) AS total FROM products');
      final count = result.first['total'] ?? 0;

      return DiagnosticItem(
        label: 'Database Health',
        state: HealthState.healthy,
        message: 'SQLite is available. Products indexed: $count.',
      );
    } catch (error) {
      return DiagnosticItem(
        label: 'Database Health',
        state: HealthState.error,
        message: 'Database check failed: $error',
      );
    }
  }

  Future<DiagnosticItem> _syncHealth(int shopId) async {
    final snapshot = await SyncService.instance.getSnapshot(shopId: shopId);
    final pending = snapshot.entities.fold<int>(
      0,
      (total, entity) => total + entity.pendingChanges,
    );

    return DiagnosticItem(
      label: 'Sync Status',
      state: HealthState.warning,
      message: '$pending local records are ready for cloud sync.',
    );
  }

  Future<DiagnosticItem> _internetHealth() async {
    try {
      final result = await InternetAddress.lookup(ApiConfig.hostName)
          .timeout(const Duration(seconds: 3));
      final online = result.isNotEmpty && result.first.rawAddress.isNotEmpty;

      return DiagnosticItem(
        label: 'Internet Status',
        state: online ? HealthState.healthy : HealthState.warning,
        message: online ? 'Internet is reachable.' : 'Internet is unavailable.',
      );
    } catch (_) {
      return const DiagnosticItem(
        label: 'Internet Status',
        state: HealthState.warning,
        message: 'Offline mode active.',
      );
    }
  }

  DiagnosticItem _activationHealth(ActivationStatus status) {
    return DiagnosticItem(
      label: 'Activation Status',
      state: status.allowsBusinessAccess
          ? HealthState.healthy
          : HealthState.warning,
      message: status.label,
    );
  }

  DiagnosticItem _backupHealth() {
    final backup = BackupService.instance.lastBackup;

    if (backup == null) {
      return const DiagnosticItem(
        label: 'Backup Status',
        state: HealthState.warning,
        message: 'No backup has been created in this session.',
      );
    }

    return DiagnosticItem(
      label: 'Backup Status',
      state: backup.status == BackupStatus.completed
          ? HealthState.healthy
          : HealthState.error,
      message: backup.message,
    );
  }
}

extension HealthStateLabel on HealthState {
  String get label {
    switch (this) {
      case HealthState.healthy:
        return 'Healthy';
      case HealthState.warning:
        return 'Warning';
      case HealthState.error:
        return 'Error';
    }
  }
}
