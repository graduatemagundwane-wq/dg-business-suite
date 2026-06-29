class Product {
  final int? id;
  final int shopId;
  final int? categoryId;
  final String productName;
  final String barcode;
  final String imagePath;
  final double buyingPrice;
  final double sellingPrice;
  final int stockQuantity;
  final int lowStockLimit;
  final bool marketplaceVisible;

  Product({
    this.id,
    required this.shopId,
    this.categoryId,
    required this.productName,
    this.barcode = '',
    this.imagePath = '',
    required this.buyingPrice,
    required this.sellingPrice,
    required this.stockQuantity,
    this.lowStockLimit = 10,
    this.marketplaceVisible = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shop_id': shopId,
      'category_id': categoryId,
      'product_name': productName,
      'barcode': barcode,
      'image_path': imagePath,
      'buying_price': buyingPrice,
      'selling_price': sellingPrice,
      'stock_quantity': stockQuantity,
      'low_stock_limit': lowStockLimit,
      'marketplace_visible': marketplaceVisible ? 1 : 0,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as int?,
      shopId: (map['shop_id'] as int?) ?? 1,
      categoryId: map['category_id'] as int?,
      productName: (map['product_name'] ?? '').toString(),
      barcode: (map['barcode'] ?? '').toString(),
      imagePath: (map['image_path'] ?? '').toString(),
      buyingPrice: ((map['buying_price'] ?? 0) as num).toDouble(),
      sellingPrice: ((map['selling_price'] ?? 0) as num).toDouble(),
      stockQuantity: (map['stock_quantity'] as int?) ?? 0,
      lowStockLimit: (map['low_stock_limit'] as int?) ?? 10,
      marketplaceVisible: map['marketplace_visible'] == 1,
    );
  }
}
