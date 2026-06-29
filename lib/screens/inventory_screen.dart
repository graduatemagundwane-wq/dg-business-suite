import 'dart:io';

import 'package:flutter/material.dart';

import '../database/local_db.dart';
import '../theme/app_theme.dart';
import 'add_product.dart';

class InventoryScreen extends StatefulWidget {
  final int shopId;

  const InventoryScreen({
    super.key,
    required this.shopId,
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];

  int totalProducts = 0;
  int lowStockProducts = 0;
  int outOfStockProducts = 0;
  double inventoryValue = 0;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final products = await LocalDatabase.instance.getAllProducts(widget.shopId);

    if (!mounted) return;

    setState(() {
      _products = products;
      _filteredProducts = _applySearch(products, _searchController.text);
      _updateStats(products);
      _loading = false;
    });
  }

  void _updateStats(List<Map<String, dynamic>> products) {
    totalProducts = products.length;

    lowStockProducts = products.where((product) {
      final stock = _asInt(product['stock_quantity']);
      final limit = _asInt(product['low_stock_limit'], fallback: 10);
      return stock <= limit && stock > 0;
    }).length;

    outOfStockProducts = products.where((product) {
      return _asInt(product['stock_quantity']) <= 0;
    }).length;

    inventoryValue = products.fold<double>(0, (sum, product) {
      final quantity = _asInt(product['stock_quantity']);
      final buyingPrice = _asDouble(product['buying_price']);
      return sum + quantity * buyingPrice;
    });
  }

  void _search(String value) {
    setState(() {
      _filteredProducts = _applySearch(_products, value);
    });
  }

  List<Map<String, dynamic>> _applySearch(
    List<Map<String, dynamic>> products,
    String value,
  ) {
    final query = value.trim().toLowerCase();

    if (query.isEmpty) {
      return List<Map<String, dynamic>>.from(products);
    }

    return products.where((product) {
      final name = _field(product, 'product_name');
      final barcode = _field(product, 'barcode');
      final category = _field(product, 'category_name').isNotEmpty
          ? _field(product, 'category_name')
          : _field(product, 'category');
      final categoryId = _field(product, 'category_id');

      return name.contains(query) ||
          barcode.contains(query) ||
          category.contains(query) ||
          categoryId.contains(query);
    }).toList();
  }

  Future<void> _deleteProduct(int productId) async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Product'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (delete != true) return;

    await LocalDatabase.instance.deleteProduct(productId);
    await _loadProducts();
  }

  Future<void> _openAddProduct() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddProductScreen(
          shopId: widget.shopId,
        ),
      ),
    );

    if (result == true) {
      await _loadProducts();
    }
  }

  Future<void> _openEditProduct(Map<String, dynamic> product) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddProductScreen(
          shopId: widget.shopId,
          product: product,
        ),
      ),
    );

    if (result == true) {
      await _loadProducts();
    }
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final stock = _asInt(product['stock_quantity']);
    final lowStock = _asInt(product['low_stock_limit'], fallback: 10);
    final isLowStock = stock <= lowStock;
    final imagePath = (product['image_path'] ?? '').toString();

    return Card(
      child: ListTile(
        leading: imagePath.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(imagePath),
                  width: 55,
                  height: 55,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    size: 40,
                  ),
                ),
              )
            : const Icon(
                Icons.inventory_2,
                size: 40,
              ),
        title: InkWell(
          onTap: () => _openEditProduct(product),
          child: Text(
            (product['product_name'] ?? '').toString(),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stock: $stock'),
            Text('Price: \$${product['selling_price']}'),
            if (isLowStock)
              const Text(
                'LOW STOCK',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(
                Icons.edit,
                color: Colors.blue,
              ),
              onPressed: () => _openEditProduct(product),
            ),
            IconButton(
              icon: const Icon(
                Icons.delete,
                color: Colors.red,
              ),
              onPressed: () => _deleteProduct(product['id'] as int),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        backgroundColor: AppTheme.primaryBlue,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        onPressed: _openAddProduct,
        icon: const Icon(Icons.add_box_rounded),
        label: const Text(
          'Add Product',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.8,
                    children: [
                      _dashboardCard(
                        Icons.inventory_2,
                        'Products',
                        totalProducts.toString(),
                        Colors.blue,
                      ),
                      _dashboardCard(
                        Icons.attach_money,
                        'Inventory Value',
                        '\$${inventoryValue.toStringAsFixed(2)}',
                        Colors.green,
                      ),
                      _dashboardCard(
                        Icons.warning_amber,
                        'Low Stock',
                        lowStockProducts.toString(),
                        Colors.orange,
                      ),
                      _dashboardCard(
                        Icons.cancel,
                        'Out Of Stock',
                        outOfStockProducts.toString(),
                        Colors.red,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _search,
                    decoration: const InputDecoration(
                      hintText: 'Search products, barcode or category...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                Expanded(
                  child: _filteredProducts.isEmpty
                      ? const Center(
                          child: Text('No Products Found'),
                        )
                      : ListView.builder(
                          itemCount: _filteredProducts.length,
                          itemBuilder: (context, index) {
                            return _buildProductCard(
                              _filteredProducts[index],
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _dashboardCard(
    IconData icon,
    String title,
    String value,
    Color color,
  ) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: color,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              title,
              style: const TextStyle(
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _field(Map<String, dynamic> product, String key) {
    return (product[key] ?? '').toString().toLowerCase();
  }
}
