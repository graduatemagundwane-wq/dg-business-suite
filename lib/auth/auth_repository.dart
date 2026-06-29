import '../database/local_db.dart';
import 'customer_auth.dart';
import 'employee_auth.dart';
import 'owner_auth.dart';

class AuthRepository {
  static const int defaultEmployeeLimit = 5;

  const AuthRepository();

  Future<Map<String, dynamic>?> loginOwner(String shopCode) {
    return OwnerAuth.instance.loginShop(shopCode.trim());
  }

  Future<Map<String, dynamic>?> loginEmployee(String employeeCode) {
    return EmployeeAuth.instance.loginEmployee(employeeCode.trim());
  }

  Future<Map<String, dynamic>> loginCustomer({
    required String customerName,
    required String phoneNumber,
  }) {
    return CustomerAuth.instance.findOrCreateCustomer(
      customerName: customerName,
      phoneNumber: phoneNumber,
    );
  }

  Future<Map<String, dynamic>?> getShopById(int shopId) async {
    final db = await LocalDatabase.instance.database;
    final result = await db.query(
      'shops',
      where: 'id = ?',
      whereArgs: [shopId],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return result.first;
  }

  Future<bool> activateShop({
    required String shopCode,
    required String activationCode,
  }) {
    return OwnerAuth.instance.activateShop(
      shopCode: shopCode.trim(),
      activationCode: activationCode.trim(),
    );
  }

  bool shopIsActivated(Map<String, dynamic>? shop) {
    return shop?['activated'] == 1;
  }
}

