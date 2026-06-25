class NotificationService {
  static final NotificationService instance =
      NotificationService._internal();

  factory NotificationService() =>
      instance;

  NotificationService._internal();

  String lowStockMessage({
    required String productName,
    required int stock,
  }) {
    return
        "⚠ Low Stock Alert\n$productName has only $stock items remaining.";
  }

  String outOfStockMessage(
      String productName) {
    return
        "❌ Out Of Stock\n$productName is out of stock.";
  }

  String dailySummary({
    required double sales,
    required double profit,
  }) {
    return
        "📊 Daily Summary\nSales: \$${sales.toStringAsFixed(2)}\nProfit: \$${profit.toStringAsFixed(2)}";
  }
}