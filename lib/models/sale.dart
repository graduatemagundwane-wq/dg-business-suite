class Sale {
  final int? id;
  final int shopId;
  final int employeeId;
  final int? customerId;
  final String receiptNumber;
  final double totalAmount;
  final double totalProfit;
  final String saleDate;

  Sale({
    this.id,
    required this.shopId,
    required this.employeeId,
    this.customerId,
    required this.receiptNumber,
    required this.totalAmount,
    required this.totalProfit,
    required this.saleDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shop_id': shopId,
      'employee_id': employeeId,
      'customer_id': customerId,
      'receipt_number': receiptNumber,
      'total_amount': totalAmount,
      'total_profit': totalProfit,
      'sale_date': saleDate,
    };
  }

  factory Sale.fromMap(Map<String, dynamic> map) {
    return Sale(
      id: map['id'] as int?,
      shopId: (map['shop_id'] as int?) ?? 1,
      employeeId: (map['employee_id'] as int?) ?? 1,
      customerId: map['customer_id'] as int?,
      receiptNumber: (map['receipt_number'] ?? '').toString(),
      totalAmount: ((map['total_amount'] ?? 0) as num).toDouble(),
      totalProfit: ((map['total_profit'] ?? 0) as num).toDouble(),
      saleDate: (map['sale_date'] ?? '').toString(),
    );
  }
}
