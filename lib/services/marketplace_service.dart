import '../database/local_db.dart';

class MarketplaceProduct {
  final int id;
  final int shopId;
  final String productName;
  final String shopName;
  final String category;
  final String? imagePath;
  final double sellingPrice;
  final int stockQuantity;
  final bool marketplaceVisible;
  final bool promoted;

  const MarketplaceProduct({
    required this.id,
    required this.shopId,
    required this.productName,
    required this.shopName,
    required this.category,
    required this.sellingPrice,
    required this.stockQuantity,
    required this.marketplaceVisible,
    this.imagePath,
    this.promoted = false,
  });

  bool get available => stockQuantity > 0;
}

class MarketplaceShop {
  final int id;
  final String name;
  final String ownerName;
  final String address;
  final String phone;
  final int productCount;
  final double rating;

  const MarketplaceShop({
    required this.id,
    required this.name,
    required this.ownerName,
    required this.address,
    required this.phone,
    required this.productCount,
    this.rating = 4.7,
  });
}

class MarketplaceComplaintDraft {
  final String subject;
  final String details;
  final DateTime createdAt;

  const MarketplaceComplaintDraft({
    required this.subject,
    required this.details,
    required this.createdAt,
  });
}

class MarketplaceService {
  static final MarketplaceService instance = MarketplaceService._internal();

  factory MarketplaceService() => instance;

  MarketplaceService._internal();

  final Set<int> _favoriteShopIds = <int>{};
  final List<MarketplaceComplaintDraft> _complaints = [];

  Future<List<MarketplaceProduct>> getMarketplaceProducts({
    String search = '',
    String category = 'All',
    bool marketplaceOnly = false,
  }) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        p.id,
        p.shop_id,
        p.product_name,
        p.image_path,
        p.selling_price,
        p.stock_quantity,
        p.marketplace_visible,
        COALESCE(c.category_name, 'Uncategorized') AS category_name,
        COALESCE(s.shop_name, 'Double Gee Shop') AS shop_name
      FROM products p
      LEFT JOIN categories c ON c.id = p.category_id
      LEFT JOIN shops s ON s.id = p.shop_id
      ORDER BY p.marketplace_visible DESC, p.product_name ASC
      LIMIT 500
      ''',
    );
    final query = search.trim().toLowerCase();

    return rows.map(_productFromRow).where((product) {
      final matchesSearch = query.isEmpty ||
          product.productName.toLowerCase().contains(query) ||
          product.shopName.toLowerCase().contains(query) ||
          product.category.toLowerCase().contains(query);
      final matchesCategory = category == 'All' || product.category == category;
      final matchesVisibility =
          !marketplaceOnly || product.marketplaceVisible;

      return matchesSearch && matchesCategory && matchesVisibility;
    }).toList();
  }

  Future<List<String>> getCategories() async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT COALESCE(category_name, 'Uncategorized') AS name
      FROM categories
      ORDER BY name ASC
      ''',
    );
    final categories = rows
        .map((row) => (row['name'] ?? 'Uncategorized').toString())
        .toList();

    return ['All', ...categories];
  }

  Future<List<MarketplaceShop>> getNearbyShops() async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        s.id,
        s.shop_name,
        s.owner_name,
        s.whatsapp,
        COUNT(p.id) AS product_count
      FROM shops s
      LEFT JOIN products p ON p.shop_id = s.id
      GROUP BY s.id
      ORDER BY s.shop_name ASC
      LIMIT 100
      ''',
    );

    return rows.map(_shopFromRow).toList();
  }

  Future<MarketplaceShop?> getShopProfile(int shopId) async {
    final shops = await getNearbyShops();

    for (final shop in shops) {
      if (shop.id == shopId) return shop;
    }

    return null;
  }

  Future<List<MarketplaceProduct>> getShopProducts(int shopId) async {
    final products = await getMarketplaceProducts();

    return products.where((product) => product.shopId == shopId).toList();
  }

  Future<List<MarketplaceShop>> getFavoriteShops() async {
    final shops = await getNearbyShops();

    return shops.where((shop) => _favoriteShopIds.contains(shop.id)).toList();
  }

  bool isFavoriteShop(int shopId) => _favoriteShopIds.contains(shopId);

  void toggleFavoriteShop(int shopId) {
    if (_favoriteShopIds.contains(shopId)) {
      _favoriteShopIds.remove(shopId);
    } else {
      _favoriteShopIds.add(shopId);
    }
  }

  void saveComplaint(MarketplaceComplaintDraft complaint) {
    _complaints.add(complaint);
  }

  MarketplaceProduct _productFromRow(Map<String, Object?> row) {
    final id = _asInt(row['id']);

    return MarketplaceProduct(
      id: id,
      shopId: _asInt(row['shop_id']),
      productName: (row['product_name'] ?? 'Unnamed Product').toString(),
      shopName: (row['shop_name'] ?? 'Double Gee Shop').toString(),
      category: (row['category_name'] ?? 'Uncategorized').toString(),
      imagePath: row['image_path']?.toString(),
      sellingPrice: _asDouble(row['selling_price']),
      stockQuantity: _asInt(row['stock_quantity']),
      marketplaceVisible: _asInt(row['marketplace_visible']) == 1,
      promoted: id.isEven,
    );
  }

  MarketplaceShop _shopFromRow(Map<String, Object?> row) {
    return MarketplaceShop(
      id: _asInt(row['id']),
      name: (row['shop_name'] ?? 'Double Gee Shop').toString(),
      ownerName: (row['owner_name'] ?? 'Shop Owner').toString(),
      address: 'Nearby store location pending',
      phone: (row['whatsapp'] ?? 'Phone not configured').toString(),
      productCount: _asInt(row['product_count']),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
