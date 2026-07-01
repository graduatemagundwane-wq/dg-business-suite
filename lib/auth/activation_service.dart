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

  bool get allowsBusinessAccess {
    return this == ActivationStatus.activated ||
        this == ActivationStatus.offlineGrace;
  }
}

class ActivationService {
  static final ActivationService instance = ActivationService._internal();

  factory ActivationService() => instance;

  ActivationService._internal();

  final Random _random = Random();

  String generateShopCode() {
    final number = (_random.nextInt(9000) + 1000);

    return "DG-SHOP-$number";
  }

  String generateActivationCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

    String code = '';

    for (int i = 0; i < 8; i++) {
      code += chars[_random.nextInt(chars.length)];
    }

    return "ACT-$code";
  }

  String generateEmployeeCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

    String code = '';

    for (int i = 0; i < 5; i++) {
      code += chars[_random.nextInt(chars.length)];
    }

    return "DG-EMP-$code";
  }

  Future<ActivationStatus> checkRemoteActivation({
    required String shopCode,
    required bool locallyActivated,
  }) async {
    try {
      final response = await DoubleGeeApiService.instance.get(
        ApiConfig.activationStatus(shopCode),
      );
      final body = response.data.toString().toLowerCase();

      if (body.contains('suspended')) {
        await _cacheActivation(shopCode: shopCode, activated: false);
        return ActivationStatus.suspended;
      }

      if (body.contains('expired')) {
        await _cacheActivation(shopCode: shopCode, activated: false);
        return ActivationStatus.expired;
      }

      if (body.contains('activated') || body.contains('active')) {
        await _cacheActivation(shopCode: shopCode, activated: true);
        return ActivationStatus.activated;
      }

      await _cacheActivation(shopCode: shopCode, activated: false);
      return ActivationStatus.pending;
    } on ApiException catch (error) {
      if (!error.canUseOfflineMode) return ActivationStatus.pending;
      return locallyActivated
          ? ActivationStatus.offlineGrace
          : ActivationStatus.pending;
    }
  }

  Future<ActivationStatus> verifyActivationCode({
    required String shopCode,
    required String activationCode,
  }) async {
    try {
      final response = await DoubleGeeApiService.instance.post(
        ApiConfig.activationVerify,
        {
          'shop_code': shopCode,
          'activation_code': activationCode,
        },
      );
      final body = response.data.toString().toLowerCase();

      if (body.contains('activated') || body.contains('active')) {
        await _cacheActivation(shopCode: shopCode, activated: true);
        return ActivationStatus.activated;
      }

      if (body.contains('suspended')) return ActivationStatus.suspended;
      if (body.contains('expired')) return ActivationStatus.expired;
    } on ApiException catch (error) {
      if (!error.canUseOfflineMode) return ActivationStatus.pending;
      final local = await _verifyLocalActivationCode(
        shopCode: shopCode,
        activationCode: activationCode,
      );

      if (local) return ActivationStatus.offlineGrace;
    }

    return ActivationStatus.pending;
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

  Future<bool> _verifyLocalActivationCode({
    required String shopCode,
    required String activationCode,
  }) async {
    final db = await LocalDatabase.instance.database;
    final result = await db.query(
      'shops',
      where: 'shop_code = ? AND activation_code = ?',
      whereArgs: [shopCode, activationCode],
      limit: 1,
    );

    if (result.isEmpty) return false;

    await _cacheActivation(shopCode: shopCode, activated: true);
    return true;
  }
}
