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
  State<InventoryScreen> createState() =>
      _InventoryScreenState();
}

class _InventoryScreenState
    extends State<InventoryScreen> {
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];

  bool _loading = true;

  final TextEditingController
      _searchController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final products =
        await LocalDatabase.instance
            .getAllProducts(widget.shopId);

    setState(() {
      _products = products;
      _filteredProducts = products;
      _loading = false;
    });
  }

  void _search(String value) {
    setState(() {
      _filteredProducts = _products
          .where(
            (product) => product[
                    'product_name']
                .toString()
                .toLowerCase()
                .contains(
                  value.toLowerCase(),
                ),
          )
          .toList();
    });
  }

  Future<void> _deleteProduct(
    int productId) async {

  final delete =
      await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text(
        "Delete Product",
      ),
      content: const Text(
        "Are you sure?",
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(
            context,
            false,
          ),
          child: const Text(
            "Cancel",
          ),
        ),
        ElevatedButton(
          onPressed: () =>
              Navigator.pop(
            context,
            true,
          ),
          child: const Text(
            "Delete",
          ),
        ),
      ],
    ),
  );

  if (delete != true) return;

  await LocalDatabase.instance
      .deleteProduct(productId);

  _loadProducts();
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
    _loadProducts();
  }
}

Future<void> _openEditProduct(
    Map<String, dynamic> product) async {

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
    _loadProducts();
  }
}

  Widget _buildProductCard(
      Map<String, dynamic> product) {
    final stock =
        product['stock_quantity'] ?? 0;

    final lowStock =
        product['low_stock_limit'] ?? 10;

    final isLowStock =
        stock <= lowStock;

    return Card(
      child: ListTile(
        leading: product['image_path'] !=
                    null &&
                product['image_path']
                    .toString()
                    .isNotEmpty
            ? ClipRRect(
                borderRadius:
                    BorderRadius.circular(
                        8),
                child: Image.file(
                  File(product[
                      'image_path']),
                  width: 55,
                  height: 55,
                  fit: BoxFit.cover,
                ),
              )
            : const Icon(
                Icons.inventory_2,
                size: 40,
              ),
        title: InkWell(
  onTap: () =>
      _openEditProduct(
    product,
  ),
  child: Text(
    product['product_name'],
  ),
),
        subtitle: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              "Stock: $stock",
            ),
            Text(
              "Price: \$${product['selling_price']}",
            ),
            if (isLowStock)
              const Text(
                "⚠ LOW STOCK",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight:
                      FontWeight.bold,
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
      onPressed: () =>
          _openEditProduct(
        product,
      ),
    ),

    IconButton(
      icon: const Icon(
        Icons.delete,
        color: Colors.red,
      ),
      onPressed: () =>
          _deleteProduct(
        product['id'],
      ),
    ),
  ],
),
      ),
    );
  }

  @override
  Widget build(
      BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Inventory",
        ),
        backgroundColor:
            AppTheme.primaryBlue,
      ),
      floatingActionButton:
          FloatingActionButton(
        backgroundColor:
            AppTheme.primaryBlue,
        onPressed: _openAddProduct,
        child: const Icon(
          Icons.add,
        ),
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.all(
                          12),
                  child: TextField(
                    controller:
                        _searchController,
                    onChanged: _search,
                    decoration:
                        const InputDecoration(
                      hintText:
                          "Search Product...",
                      prefixIcon:
                          Icon(Icons.search),
                    ),
                  ),
                ),
                Expanded(
                  child:
                      _filteredProducts
                              .isEmpty
                          ? const Center(
                              child: Text(
                                "No Products Found",
                              ),
                            )
                          : ListView.builder(
                              itemCount:
                                  _filteredProducts
                                      .length,
                              itemBuilder:
                                  (context,
                                      index) {
                                return _buildProductCard(
                                  _filteredProducts[
                                      index],
                                );
                              },
                            ),
                ),
              ],
            ),
    );
  }
}