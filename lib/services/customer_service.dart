import '../database/local_db.dart';

class CustomerSummary {
  final String customerName;
  final double lifetimeSpending;
  final int ordersPlaced;
  final int favouriteShops;
  final List<CustomerPurchase> recentPurchases;
  final CustomerSpendingAnalytics spending;

  const CustomerSummary({
    required this.customerName,
    required this.lifetimeSpending,
    required this.ordersPlaced,
    required this.favouriteShops,
    required this.recentPurchases,
    required this.spending,
  });
}

class CustomerPurchase {
  final String receiptNumber;
  final String shopName;
  final String productName;
  final DateTime date;
  final double total;

  const CustomerPurchase({
    required this.receiptNumber,
    required this.shopName,
    required this.productName,
    required this.date,
    required this.total,
  });
}

class CustomerOrder {
  final String orderNumber;
  final DateTime date;
  final String shopName;
  final double total;
  final CustomerOrderStatus status;

  const CustomerOrder({
    required this.orderNumber,
    required this.date,
    required this.shopName,
    required this.total,
    required this.status,
  });
}

enum CustomerOrderStatus {
  active,
  completed,
  cancelled,
}

extension CustomerOrderStatusLabel on CustomerOrderStatus {
  String get label {
    switch (this) {
      case CustomerOrderStatus.active:
        return 'Active';
      case CustomerOrderStatus.completed:
        return 'Completed';
      case CustomerOrderStatus.cancelled:
        return 'Cancelled';
    }
  }
}

class CustomerSpendingAnalytics {
  final double totalSpent;
  final double monthlySpending;
  final double yearlySpending;
  final String mostPurchasedShop;
  final String mostPurchasedProduct;
  final List<CustomerTimelinePoint> timeline;

  const CustomerSpendingAnalytics({
    required this.totalSpent,
    required this.monthlySpending,
    required this.yearlySpending,
    required this.mostPurchasedShop,
    required this.mostPurchasedProduct,
    required this.timeline,
  });
}

class CustomerTimelinePoint {
  final DateTime date;
  final double amount;

  const CustomerTimelinePoint({
    required this.date,
    required this.amount,
  });
}

class CustomerService {
  static final CustomerService instance = CustomerService._internal();

  factory CustomerService() => instance;

  CustomerService._internal();

  Future<CustomerSummary> getCustomerSummary({int customerId = 1}) async {
    final db = await LocalDatabase.instance.database;
    final customerRows = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    final customerName = customerRows.isEmpty
        ? 'Double Gee Customer'
        : (customerRows.first['customer_name'] ?? 'Double Gee Customer')
            .toString();
    final spending = await getSpendingAnalytics(customerId: customerId);
    final purchases = await getRecentPurchases(customerId: customerId);

    return CustomerSummary(
      customerName: customerName,
      lifetimeSpending: spending.totalSpent,
      ordersPlaced: purchases.length,
      favouriteShops: 0,
      recentPurchases: purchases.take(5).toList(),
      spending: spending,
    );
  }

  Future<List<CustomerPurchase>> getRecentPurchases({
    int customerId = 1,
  }) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        s.receipt_number,
        s.sale_date,
        s.total_amount,
        COALESCE(sh.shop_name, 'Double Gee Shop') AS shop_name,
        COALESCE(si.product_name, 'Mixed basket') AS product_name
      FROM sales s
      LEFT JOIN shops sh ON sh.id = s.shop_id
      LEFT JOIN sale_items si ON si.sale_id = s.id
      WHERE s.customer_id = ?
      GROUP BY s.id
      ORDER BY s.sale_date DESC
      LIMIT 20
      ''',
      [customerId],
    );

    return rows.map(_purchaseFromRow).toList();
  }

  Future<List<CustomerOrder>> getOrders({int customerId = 1}) async {
    final purchases = await getRecentPurchases(customerId: customerId);

    return purchases.asMap().entries.map((entry) {
      final index = entry.key;
      final purchase = entry.value;
      final status = index == 0
          ? CustomerOrderStatus.active
          : CustomerOrderStatus.completed;

      return CustomerOrder(
        orderNumber: purchase.receiptNumber.isEmpty
            ? 'DG-ORDER-${index + 1}'
            : purchase.receiptNumber,
        date: purchase.date,
        shopName: purchase.shopName,
        total: purchase.total,
        status: status,
      );
    }).toList();
  }

  Future<CustomerSpendingAnalytics> getSpendingAnalytics({
    int customerId = 1,
  }) async {
    final db = await LocalDatabase.instance.database;
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final yearStart = DateTime(now.year);
    final totals = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(total_amount), 0) AS total,
        COALESCE(SUM(CASE WHEN sale_date >= ? THEN total_amount ELSE 0 END), 0)
          AS monthly,
        COALESCE(SUM(CASE WHEN sale_date >= ? THEN total_amount ELSE 0 END), 0)
          AS yearly
      FROM sales
      WHERE customer_id = ?
      ''',
      [monthStart.toIso8601String(), yearStart.toIso8601String(), customerId],
    );
    final bestShop = await db.rawQuery(
      '''
      SELECT COALESCE(sh.shop_name, 'Double Gee Shop') AS shop_name
      FROM sales s
      LEFT JOIN shops sh ON sh.id = s.shop_id
      WHERE s.customer_id = ?
      GROUP BY s.shop_id
      ORDER BY SUM(s.total_amount) DESC
      LIMIT 1
      ''',
      [customerId],
    );
    final bestProduct = await db.rawQuery(
      '''
      SELECT COALESCE(si.product_name, 'No purchases yet') AS product_name
      FROM sale_items si
      INNER JOIN sales s ON s.id = si.sale_id
      WHERE s.customer_id = ?
      GROUP BY si.product_id, si.product_name
      ORDER BY SUM(si.quantity) DESC
      LIMIT 1
      ''',
      [customerId],
    );
    final timelineRows = await db.rawQuery(
      '''
      SELECT sale_date, total_amount
      FROM sales
      WHERE customer_id = ?
      ORDER BY sale_date DESC
      LIMIT 12
      ''',
      [customerId],
    );
    final row = totals.first;

    return CustomerSpendingAnalytics(
      totalSpent: _asDouble(row['total']),
      monthlySpending: _asDouble(row['monthly']),
      yearlySpending: _asDouble(row['yearly']),
      mostPurchasedShop: bestShop.isEmpty
          ? 'No shop yet'
          : (bestShop.first['shop_name'] ?? 'No shop yet').toString(),
      mostPurchasedProduct: bestProduct.isEmpty
          ? 'No product yet'
          : (bestProduct.first['product_name'] ?? 'No product yet').toString(),
      timeline: timelineRows.map((row) {
        return CustomerTimelinePoint(
          date: DateTime.tryParse((row['sale_date'] ?? '').toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0),
          amount: _asDouble(row['total_amount']),
        );
      }).toList(),
    );
  }

  CustomerPurchase _purchaseFromRow(Map<String, Object?> row) {
    return CustomerPurchase(
      receiptNumber: (row['receipt_number'] ?? '').toString(),
      shopName: (row['shop_name'] ?? 'Double Gee Shop').toString(),
      productName: (row['product_name'] ?? 'Mixed basket').toString(),
      date: DateTime.tryParse((row['sale_date'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      total: _asDouble(row['total_amount']),
    );
  }
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
