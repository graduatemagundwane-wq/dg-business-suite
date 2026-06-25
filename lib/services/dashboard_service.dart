import '../database/local_db.dart';

class DashboardService {
  static final DashboardService instance =
      DashboardService._internal();

  factory DashboardService() => instance;

  DashboardService._internal();

  Future<Map<String, dynamic>> getDashboardData(
      int shopId) async {
    final db = LocalDatabase.instance;

    final totalSales =
        await db.getTotalSales(shopId);

    final totalProfit =
        await db.getTotalProfit(shopId);

    final productCount =
        await db.getProductCount(shopId);

    final lowStockProducts =
        await db.getLowStockProducts(shopId);

    final topEmployee =
        await db.getTopEmployee(shopId);

    return {
      'total_sales': totalSales,
      'total_profit': totalProfit,
      'product_count': productCount,
      'low_stock_count':
          lowStockProducts.length,
      'top_employee':
          topEmployee,
    };
  }

  Future<List<Map<String, dynamic>>>
      getLowStockItems(
          int shopId) async {
    return await LocalDatabase.instance
        .getLowStockProducts(shopId);
  }

  Future<Map<String, dynamic>?>
      getBestEmployee(
          int shopId) async {
    return await LocalDatabase.instance
        .getTopEmployee(shopId);
  }
}