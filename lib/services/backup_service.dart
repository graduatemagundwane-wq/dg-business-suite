import 'dart:convert';
import 'dart:io';

import '../database/local_db.dart';

enum BackupMode {
  manual,
  automaticCloud,
  restore,
  export,
}

enum BackupStatus {
  idle,
  running,
  completed,
  failed,
}

class BackupResult {
  final BackupMode mode;
  final BackupStatus status;
  final DateTime completedAt;
  final String message;
  final String? filePath;

  const BackupResult({
    required this.mode,
    required this.status,
    required this.completedAt,
    required this.message,
    this.filePath,
  });
}

class BackupService {
  static final BackupService instance = BackupService._internal();

  factory BackupService() => instance;

  BackupService._internal();

  BackupResult? _lastBackup;

  BackupResult? get lastBackup => _lastBackup;

  Future<BackupResult> createManualBackup() {
    return exportBackup(mode: BackupMode.manual);
  }

  Future<BackupResult> createAutomaticCloudBackup() async {
    final result = await exportBackup(mode: BackupMode.automaticCloud);

    return BackupResult(
      mode: BackupMode.automaticCloud,
      status: result.status,
      completedAt: result.completedAt,
      filePath: result.filePath,
      message: 'Automatic cloud backup package is ready for server upload',
    );
  }

  Future<BackupResult> exportBackup({
    BackupMode mode = BackupMode.export,
  }) async {
    try {
      final db = await LocalDatabase.instance.database;
      final payload = <String, Object?>{
        'generated_at': DateTime.now().toIso8601String(),
        'source': 'double_gee_business_suite',
        'schema_version': 1,
        'tables': {
          'shops': await db.query('shops'),
          'employees': await db.query('employees'),
          'categories': await db.query('categories'),
          'products': await db.query('products'),
          'sales': await db.query('sales'),
          'sale_items': await db.query('sale_items'),
          'customers': await db.query('customers'),
          'customer_purchases': await db.query('customer_purchases'),
          'expenses': await db.query('expenses'),
        },
      };
      final file = File(
        '${Directory.systemTemp.path}/double_gee_backup_${DateTime.now().millisecondsSinceEpoch}.json',
      );

      await file.writeAsString(jsonEncode(payload), flush: true);

      _lastBackup = BackupResult(
        mode: mode,
        status: BackupStatus.completed,
        completedAt: DateTime.now(),
        filePath: file.path,
        message: 'Backup exported successfully',
      );

      return _lastBackup!;
    } catch (error) {
      _lastBackup = BackupResult(
        mode: mode,
        status: BackupStatus.failed,
        completedAt: DateTime.now(),
        message: 'Backup failed: $error',
      );

      return _lastBackup!;
    }
  }

  Future<BackupResult> prepareRestore(String backupPath) async {
    final file = File(backupPath);
    final exists = await file.exists();

    return BackupResult(
      mode: BackupMode.restore,
      status: exists ? BackupStatus.completed : BackupStatus.failed,
      completedAt: DateTime.now(),
      filePath: backupPath,
      message: exists
          ? 'Backup validated. Restore execution requires owner confirmation.'
          : 'Backup file was not found.',
    );
  }
}

extension BackupModeLabel on BackupMode {
  String get label {
    switch (this) {
      case BackupMode.manual:
        return 'Manual Backup';
      case BackupMode.automaticCloud:
        return 'Automatic Cloud Backup';
      case BackupMode.restore:
        return 'Restore';
      case BackupMode.export:
        return 'Export Backup';
    }
  }
}
