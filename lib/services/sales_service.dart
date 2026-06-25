import '../database/local_db.dart';
import 'receipt_service.dart';

class SalesService {
  static final SalesService instance =
      SalesService._internal();

  factory SalesService() => instance;

  SalesService._internal();

  Future<Map<String, dynamic>> completeSale({
    required int shopId,
    required int employeeId,
    required String cashierName,
    required String shopName,
    required List<Map<String, dynamic>> cartItems,
  }) async {
    final db = LocalDatabase.instance;

    double totalAmount = 0;
    double totalProfit = 0;

    for (final item in cartItems) {
      final selling =
          (item['selling_price'] as num)
              .toDouble();

      final buying =
          (item['buying_price'] as num)
              .toDouble();

      final quantity =
          item['quantity'] as int;

      totalAmount +=
          selling * quantity;

      totalProfit +=
          (selling - buying) * quantity;
    }

    final receiptNumber =
        await db.generateReceiptNumber();

    final saleId =
        await db.createSale({
      'shop_id': shopId,
      'employee_id': employeeId,
      'customer_id': null,
      'receipt_number':
          receiptNumber,
      'total_amount':
          totalAmount,
      'total_profit':
          totalProfit,
      'sale_date':
          DateTime.now()
              .toIso8601String(),
    });

    for (final item in cartItems) {
      final quantity =
          item['quantity'] as int;

      final selling =
          (item['selling_price'] as num)
              .toDouble();

      final buying =
          (item['buying_price'] as num)
              .toDouble();

      final itemTotal =
          selling * quantity;

      final itemProfit =
          (selling - buying) *
              quantity;

      await db.createSaleItem({
        'sale_id': saleId,
        'product_id': item['id'],
        'product_name':
            item['product_name'],
        'buying_price':
            buying,
        'selling_price':
            selling,
        'quantity':
            quantity,
        'total':
            itemTotal,
        'profit':
            itemProfit,
      });

      await db.deductStock(
        productId: item['id'],
        quantity: quantity,
      );
    }

    await db.updateEmployeeStats(
      employeeId: employeeId,
      revenue: totalAmount,
      profit: totalProfit,
    );

    final receipt =
        await ReceiptService
            .instance
            .generateReceipt(
      receiptNumber:
          receiptNumber,
      shopName: shopName,
      cashierName:
          cashierName,
      items: cartItems,
      totalAmount:
          totalAmount,
      totalProfit:
          totalProfit,
    );

    return {
      'success': true,
      'sale_id': saleId,
      'receipt_number':
          receiptNumber,
      'total_amount':
          totalAmount,
      'total_profit':
          totalProfit,
      'receipt': receipt,
    };
  }
}