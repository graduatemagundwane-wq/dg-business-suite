import '../database/local_db.dart';
import 'activation_service.dart';

class OwnerAuth {
  static final OwnerAuth instance =
      OwnerAuth._internal();

  factory OwnerAuth() => instance;

  OwnerAuth._internal();

  Future<Map<String, dynamic>> registerShop({
    required String shopName,
    required String ownerName,
    required String whatsapp,
  }) async {
    final shopCode =
        ActivationService.instance.generateShopCode();

    final activationCode =
        ActivationService.instance.generateActivationCode();

    await LocalDatabase.instance.database.then(
      (db) async {
        await db.insert(
          'shops',
          {
            'shop_code': shopCode,
            'shop_name': shopName,
            'owner_name': ownerName,
            'whatsapp': whatsapp,
            'activation_code': activationCode,
            'activated': 0,
            'created_at':
                DateTime.now().toIso8601String(),
          },
        );
      },
    );

    return {
      'success': true,
      'shop_code': shopCode,
      'activation_code': activationCode,
    };
  }

  Future<bool> activateShop({
    required String shopCode,
    required String activationCode,
  }) async {
    final db =
        await LocalDatabase.instance.database;

    final result = await db.query(
      'shops',
      where:
          'shop_code = ? AND activation_code = ?',
      whereArgs: [
        shopCode,
        activationCode,
      ],
      limit: 1,
    );

    if (result.isEmpty) {
      return false;
    }

    await db.update(
      'shops',
      {
        'activated': 1,
      },
      where: 'id = ?',
      whereArgs: [
        result.first['id'],
      ],
    );

    return true;
  }

  Future<Map<String, dynamic>?>
      loginShop(String shopCode) async {
    final db =
        await LocalDatabase.instance.database;

    final result = await db.query(
      'shops',
      where: 'shop_code = ?',
      whereArgs: [shopCode],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return result.first;
  }

  Future<bool> isActivated(
      String shopCode) async {
    final db =
        await LocalDatabase.instance.database;

    final result = await db.query(
      'shops',
      where: 'shop_code = ?',
      whereArgs: [shopCode],
      limit: 1,
    );

    if (result.isEmpty) {
      return false;
    }

    return result.first['activated'] == 1;
  }
}