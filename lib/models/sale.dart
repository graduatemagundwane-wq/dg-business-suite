class Sale {
  final int? id;
  final int shopId;
  final int employeeId;
  final String receiptNumber;
  final double totalAmount;
  final double totalProfit;
  final String saleDate;

  Sale({
    this.id,
    required this.shopId,
    required this.employeeId,
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
      'receipt_number': receiptNumber,
      'total_amount': totalAmount,
      'total_profit': totalProfit,
      'sale_date': saleDate,
    };
  }

  factory Sale.fromMap(
    Map<String, dynamic> map,
  ) {
    return Sale(
      id: map['id'],
      shopId: map['shop_id'],
      employeeId: map['employee_id'],
      receiptNumber: map['receipt_number'],
      totalAmount:
          (map['total_amount'] as num).toDouble(),
      totalProfit:
          (map['total_profit'] as num).toDouble(),
      saleDate: map['sale_date'],
    );
  }
}