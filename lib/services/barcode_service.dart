import '../database/local_db.dart';

class BarcodeService {
  static final BarcodeService instance = BarcodeService._internal();

  factory BarcodeService() => instance;

  BarcodeService._internal();

  Future<Map<String, dynamic>?> findProductByBarcode({
    required int shopId,
    required String barcode,
  }) async {
    final products = await LocalDatabase.instance.getAllProducts(shopId);
    final normalized = barcode.trim().toLowerCase();

    for (final product in products) {
      final productBarcode = (product['barcode'] ?? '').toString().toLowerCase();
      if (productBarcode == normalized) return product;
    }

    return null;
  }

  Future<List<Map<String, dynamic>>> searchByNameOrBarcode({
    required int shopId,
    required String query,
  }) async {
    final products = await LocalDatabase.instance.getAllProducts(shopId);
    final normalized = query.trim().toLowerCase();

    if (normalized.isEmpty) return products;

    return products.where((product) {
      final name = (product['product_name'] ?? '').toString().toLowerCase();
      final barcode = (product['barcode'] ?? '').toString().toLowerCase();
      return name.contains(normalized) || barcode.contains(normalized);
    }).toList();
  }
}
