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
    String email = '',
    String country = '',
    String currency = '',
    String businessType = '',
    String logoPath = '',
    String businessAddress = '',
    String gpsLocation = '',
    String taxNumber = '',
  }) async {
    await LocalDatabase.instance.ensureProductionIdentityColumns();
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
            'email': email,
            'country': country,
            'currency': currency,
            'business_type': businessType,
            'logo_path': logoPath,
            'business_address': businessAddress,
            'gps_location': gpsLocation,
            'tax_number': taxNumber,
            'business_uid': _id('BIZ'),
            'activation_uid': _id('ACTIVATION'),
            'device_uid': _id('DEVICE'),
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

  String _id(String prefix) {
    return 'DG-$prefix-${DateTime.now().microsecondsSinceEpoch}';
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
