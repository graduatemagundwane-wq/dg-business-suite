class SaleItem {
  final int? id;
  final int productId;
  final String productName;
  final double buyingPrice;
  final double sellingPrice;
  final int quantity;

  SaleItem({
    this.id,
    required this.productId,
    required this.productName,
    required this.buyingPrice,
    required this.sellingPrice,
    required this.quantity,
  });

  double get total =>
      sellingPrice * quantity;

  double get profit =>
      (sellingPrice - buyingPrice) * quantity;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'product_name': productName,
      'buying_price': buyingPrice,
      'selling_price': sellingPrice,
      'quantity': quantity,
    };
  }

  factory SaleItem.fromMap(
    Map<String, dynamic> map,
  ) {
    return SaleItem(
      id: map['id'],
      productId: map['product_id'],
      productName: map['product_name'],
      buyingPrice:
          (map['buying_price'] as num).toDouble(),
      sellingPrice:
          (map['selling_price'] as num).toDouble(),
      quantity: map['quantity'],
    );
  }
}