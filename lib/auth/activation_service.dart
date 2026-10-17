import 'dart:math';

import '../database/local_db.dart';
import '../services/api_config.dart';
import '../services/double_gee_api_service.dart';

enum ActivationStatus {
  activated,
  pending,
  suspended,
  expired,
  offlineGrace,
}

extension ActivationStatusLabel on ActivationStatus {
  String get label {
    switch (this) {
      case ActivationStatus.activated:
        return 'Activated';
      case ActivationStatus.pending:
        return 'Pending';
      case ActivationStatus.suspended:
        return 'Suspended';
      case ActivationStatus.expired:
        return 'Expired';
      case ActivationStatus.offlineGrace:
        return 'Offline Grace';
    }
  }

  bool get allowsBusinessAccess =>
      this == ActivationStatus.activated || this == ActivationStatus.offlineGrace;
}

/// The client can request activation but cannot grant it.
///
/// The backend must check that the shop belongs to this authenticated user,
/// that the license was approved by DG Tech Master Control, and that its
/// validity/device limits are satisfied. Never trust a local activation code.
class ActivationService {
  static final ActivationService instance = ActivationService._internal();

  factory ActivationService() => instance;

  ActivationService._internal();

  final Random _random = Random.secure();

  String generateShopCode() {
    // Registration identifiers are not credentials and grant no privileges.
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final code = List.generate(
      12,
      (_) => chars[_random.nextInt(chars.length)],
    ).join();
    return 'DG-SHOP-$code';
  }

  String generateEmployeeCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final code = List.generate(
      8,
      (_) => chars[_random.nextInt(chars.length)],
    ).join();
    return 'DG-EMP-$code';
  }

  /// Accept only an explicit, structured server status. Substring matching
  /// such as "inactive".contains("active") would grant unauthorized access.
  static ActivationStatus statusFromPayload(Map<String, dynamic> payload) {
    final nested = payload['data'];
    final data = nested is Map<String, dynamic> ? nested : payload;
    final status = (data['activation_status'] ?? data['status'])
        ?.toString()
        .trim()
        .toLowerCase();

    switch (status) {
      case 'active':
      case 'activated':
        return ActivationStatus.activated;
      case 'suspended':
      case 'revoked':
      case 'frozen':
        return ActivationStatus.suspended;
      case 'expired':
        return ActivationStatus.expired;
      case 'pending':
      case 'inactive':
      case 'unapproved':
      case 'trial_requested':
        return ActivationStatus.pending;
    }

    // A typed boolean is accepted only when the service explicitly says so.
    if (data['activated'] == true) return ActivationStatus.activated;
    return ActivationStatus.pending;
  }

  Future<ActivationStatus> checkRemoteActivation({
    required String shopCode,
    required bool locallyActivated,
  }) async {
    if (shopCode.trim().isEmpty) return ActivationStatus.pending;
    try {
      final response = await DoubleGeeApiService.instance.get(
        ApiConfig.activationStatus(shopCode),
      );
      final status = statusFromPayload(response.data);
      await _cacheActivation(
        shopCode: shopCode,
        activated: status == ActivationStatus.activated,
      );
      return status;
    } on ApiException {
      // A locally edited SQLite flag is NOT a license. Offline access will
      // be enabled only after the master issues a cryptographically signed,
      // time-limited license lease and the app verifies it.
      return ActivationStatus.pending;
    }
  }

  Future<ActivationStatus> verifyActivationCode({
    required String shopCode,
    required String activationCode,
  }) async {
    if (shopCode.trim().isEmpty || activationCode.trim().isEmpty) {
      return ActivationStatus.pending;
    }

    try {
      final response = await DoubleGeeApiService.instance.post(
        ApiConfig.activationVerify,
        {
          'shop_code': shopCode.trim(),
          'activation_code': activationCode.trim(),
        },
      );
      final status = statusFromPayload(response.data);
      await _cacheActivation(
        shopCode: shopCode,
        activated: status == ActivationStatus.activated,
      );
      return status;
    } on ApiException {
      // Never fall back to comparing an activation code in the local database.
      return ActivationStatus.pending;
    }
  }

  Future<void> _cacheActivation({
    required String shopCode,
    required bool activated,
  }) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'shops',
      {'activated': activated ? 1 : 0},
      where: 'shop_code = ?',
      whereArgs: [shopCode],
    );
  }
}
