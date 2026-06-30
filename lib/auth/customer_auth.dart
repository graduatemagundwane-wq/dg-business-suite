import '../database/local_db.dart';

class CustomerAuth {
  static final CustomerAuth instance = CustomerAuth._internal();

  factory CustomerAuth() => instance;

  CustomerAuth._internal();

  Future<Map<String, dynamic>> findOrCreateCustomer({
    required String customerName,
    required String phoneNumber,
    String email = '',
    String location = '',
    String favouriteArea = '',
    bool notificationsEnabled = false,
  }) async {
    await LocalDatabase.instance.ensureProductionIdentityColumns();
    final db = await LocalDatabase.instance.database;
    final existing = await db.query(
      'customers',
      where: 'phone_number = ?',
      whereArgs: [phoneNumber.trim()],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      return existing.first;
    }

    final id = await db.insert(
      'customers',
      {
        'customer_name': customerName.trim(),
        'phone_number': phoneNumber.trim(),
        'email': email.trim(),
        'location': location.trim(),
        'favourite_area': favouriteArea.trim(),
        'notifications_enabled': notificationsEnabled ? 1 : 0,
        'customer_uid': 'DG-CUSTOMER-${DateTime.now().microsecondsSinceEpoch}',
        'total_spent': 0,
        'purchase_count': 0,
        'created_at': DateTime.now().toIso8601String(),
      },
    );

    final created = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    return created.first;
  }
}
