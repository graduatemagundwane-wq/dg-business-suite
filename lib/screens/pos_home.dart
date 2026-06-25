import 'package:flutter/material.dart';

import '../database/local_db.dart';

class PosHome extends StatefulWidget {
  final int shopId;

  const PosHome({
    super.key,
    required this.shopId,
  });

  @override
  State<PosHome> createState() => _PosHomeState();
}

class _PosHomeState extends State<PosHome> {
  final TextEditingController _searchController =
      TextEditingController();

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];

  final List<Map<String, dynamic>> _cart = [];

  bool _loading = true;

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

  void _searchProducts(String value) {
    setState(() {
      _filteredProducts = _products.where((product) {
        return product['product_name']
            .toString()
            .toLowerCase()
            .contains(value.toLowerCase());
      }).toList();
    });
  }

  void _addToCart(
      Map<String, dynamic> product) {
    final index = _cart.indexWhere(
      (item) => item['id'] == product['id'],
    );

    if (index >= 0) {
      _cart[index]['quantity']++;
    } else {
      _cart.add({
        ...product,
        'quantity': 1,
      });
    }

    setState(() {});
  }

  void _increaseQty(int index) {
    setState(() {
      _cart[index]['quantity']++;
    });
  }

  void _decreaseQty(int index) {
    setState(() {
      if (_cart[index]['quantity'] > 1) {
        _cart[index]['quantity']--;
      } else {
        _cart.removeAt(index);
      }
    });
  }

  double get totalAmount {
    double total = 0;

    for (var item in _cart) {
      total +=
          (item['selling_price'] ?? 0) *
          item['quantity'];
    }

    return total;
  }

  double get totalProfit {
    double total = 0;

    for (var item in _cart) {
      final selling =
          (item['selling_price'] ?? 0)
              .toDouble();

      final buying =
          (item['buying_price'] ?? 0)
              .toDouble();

      total +=
          (selling - buying) *
          item['quantity'];
    }

    return total;
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;

    for (var item in _cart) {
      await LocalDatabase.instance
          .deductStock(
        productId: item['id'],
        quantity: item['quantity'],
      );
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      const SnackBar(
        content: Text(
          'Sale completed successfully',
        ),
      ),
    );

    setState(() {
      _cart.clear();
    });

    _loadProducts();
  }

  Widget _buildProductsPanel() {
    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.all(12),
          child: TextField(
            controller:
                _searchController,
            onChanged:
                _searchProducts,
            decoration:
                const InputDecoration(
              hintText:
                  'Search Products',
              prefixIcon:
                  Icon(Icons.search),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount:
                _filteredProducts.length,
            itemBuilder:
                (context, index) {
              final product =
                  _filteredProducts[index];

              return Card(
                child: ListTile(
                  title: Text(
                    product[
                        'product_name'],
                  ),
                  subtitle: Text(
                    'Stock: ${product['stock_quantity']}',
                  ),
                  trailing: Text(
                    '\$${product['selling_price']}',
                  ),
                  onTap: () =>
                      _addToCart(
                    product,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCartPanel() {
    return Column(
      children: [
        Container(
          padding:
              const EdgeInsets.all(12),
          child: const Text(
            'Cart',
            style: TextStyle(
              fontSize: 20,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _cart.length,
            itemBuilder:
                (context, index) {
              final item =
                  _cart[index];

              return Card(
                child: ListTile(
                  title: Text(
                    item[
                        'product_name'],
                  ),
                  subtitle: Text(
                    'Qty: ${item['quantity']}',
                  ),
                  trailing: Row(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      IconButton(
                        icon:
                            const Icon(
                          Icons.remove,
                        ),
                        onPressed: () =>
                            _decreaseQty(
                                index),
                      ),
                      IconButton(
                        icon:
                            const Icon(
                          Icons.add,
                        ),
                        onPressed: () =>
                            _increaseQty(
                                index),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          padding:
              const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                'Total: \$${totalAmount.toStringAsFixed(2)}',
                style:
                    const TextStyle(
                  fontSize: 20,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              const SizedBox(
                height: 8,
              ),
              Text(
                'Profit: \$${totalProfit.toStringAsFixed(2)}',
              ),
              const SizedBox(
                height: 12,
              ),
              SizedBox(
                width:
                    double.infinity,
                child:
                    ElevatedButton(
                  onPressed:
                      _checkout,
                  child: const Text(
                    'CHECKOUT',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(
      BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('DG POS'),
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : LayoutBuilder(
              builder:
                  (context,
                      constraints) {
                if (constraints
                        .maxWidth >
                    700) {
                  return Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child:
                            _buildProductsPanel(),
                      ),
                      const VerticalDivider(),
                      Expanded(
                        child:
                            _buildCartPanel(),
                      ),
                    ],
                  );
                }

                return Column(
                  children: [
                    Expanded(
                      child:
                          _buildProductsPanel(),
                    ),
                    SizedBox(
                      height: 300,
                      child:
                          _buildCartPanel(),
                    ),
                  ],
                );
              },
            ),
    );
  }
}