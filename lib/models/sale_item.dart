class SaleItem {
  final int? id;
  final int? saleId;
  final int productId;
  final String productName;
  final double buyingPrice;
  final double sellingPrice;
  final int quantity;
  final double? recordedTotal;
  final double? recordedProfit;

  SaleItem({
    this.id,
    this.saleId,
    required this.productId,
    required this.productName,
    required this.buyingPrice,
    required this.sellingPrice,
    required this.quantity,
    this.recordedTotal,
    this.recordedProfit,
  });

  double get total => recordedTotal ?? sellingPrice * quantity;

  double get profit => recordedProfit ?? (sellingPrice - buyingPrice) * quantity;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sale_id': saleId,
      'product_id': productId,
      'product_name': productName,
      'buying_price': buyingPrice,
      'selling_price': sellingPrice,
      'quantity': quantity,
      'total': total,
      'profit': profit,
    };
  }

  factory SaleItem.fromMap(Map<String, dynamic> map) {
    return SaleItem(
      id: map['id'] as int?,
      saleId: map['sale_id'] as int?,
      productId: (map['product_id'] as int?) ?? 0,
      productName: (map['product_name'] ?? '').toString(),
      buyingPrice: ((map['buying_price'] ?? 0) as num).toDouble(),
      sellingPrice: ((map['selling_price'] ?? 0) as num).toDouble(),
      quantity: (map['quantity'] as int?) ?? 0,
      recordedTotal: (map['total'] as num?)?.toDouble(),
      recordedProfit: (map['profit'] as num?)?.toDouble(),
    );
  }
}
