class Product {
  final int? id;
  final int shopId;
  final String productName;
  final String barcode;
  final String category;
  final String imagePath;
  final double buyingPrice;
  final double sellingPrice;
  final int stockQuantity;

  Product({
    this.id,
    required this.shopId,
    required this.productName,
    required this.barcode,
    required this.category,
    required this.imagePath,
    required this.buyingPrice,
    required this.sellingPrice,
    required this.stockQuantity,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shop_id': shopId,
      'product_name': productName,
      'barcode': barcode,
      'category': category,
      'image_path': imagePath,
      'buying_price': buyingPrice,
      'selling_price': sellingPrice,
      'stock_quantity': stockQuantity,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      shopId: map['shop_id'],
      productName: map['product_name'],
      barcode: map['barcode'],
      category: map['category'],
      imagePath: map['image_path'] ?? '',
      buyingPrice: (map['buying_price'] as num).toDouble(),
      sellingPrice: (map['selling_price'] as num).toDouble(),
      stockQuantity: map['stock_quantity'],
    );
  }
}