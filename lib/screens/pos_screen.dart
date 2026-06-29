import 'package:flutter/material.dart';

import '../database/local_db.dart';
import '../widgets/premium_product_card.dart';
import '../widgets/premium_cart_item.dart';
import '../widgets/checkout_summary.dart';
class POSScreen extends StatefulWidget {
  final int shopId;
  final int employeeId;
  final String cashierName;
  final String shopName;

  const POSScreen({
    super.key,
    required this.shopId,
    required this.employeeId,
    required this.cashierName,
    required this.shopName,
  });

  @override
  State<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends State<POSScreen> {
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> cartItems = [];

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadProducts();
  }

  Future<void> loadProducts() async {
    final data = await LocalDatabase.instance.getAllProducts(widget.shopId);

    if (!mounted) return;

    setState(() {
      products = data;
      isLoading = false;
    });
  }

  double get totalAmount {
    return cartItems.fold<double>(
      0,
      (sum, item) =>
          sum +
          (item['selling_price'] as num).toDouble() *
              (item['quantity'] as int),
    );
  }

  double get totalProfit {
    return cartItems.fold<double>(
      0,
      (sum, item) =>
          sum +
          ((item['selling_price'] as num).toDouble() -
                  (item['buying_price'] as num).toDouble()) *
              (item['quantity'] as int),
    );
  }

  void addToCart(Map<String, dynamic> product) {
    final index = cartItems.indexWhere(
      (item) => item['id'] == product['id'],
    );

    setState(() {
      if (index >= 0) {
        cartItems[index]['quantity']++;
      } else {
        cartItems.add({
          ...product,
          'quantity': 1,
        });
      }
    });
  }

  void increaseQuantity(int index) {
    setState(() {
      cartItems[index]['quantity']++;
    });
  }

  void decreaseQuantity(int index) {
    setState(() {
      if (cartItems[index]['quantity'] > 1) {
        cartItems[index]['quantity']--;
      } else {
        cartItems.removeAt(index);
      }
    });
  }

  void removeItem(int index) {
    setState(() {
      cartItems.removeAt(index);
    });
  }

  void clearCart() {
    setState(() {
      cartItems.clear();
    });
  }

  Future<void> checkout() async {
    if (cartItems.isEmpty) return;

    final receiptNumber = await LocalDatabase.instance.generateReceiptNumber();

    final saleId = await LocalDatabase.instance.createSale({
      'shop_id': widget.shopId,
      'employee_id': widget.employeeId,
      'customer_id': null,
      'receipt_number': receiptNumber,
      'total_amount': totalAmount,
      'total_profit': totalProfit,
      'sale_date': DateTime.now().toIso8601String(),
    });

    for (final item in cartItems) {
      final quantity = item['quantity'] as int;
      final sellingPrice = (item['selling_price'] as num).toDouble();
      final buyingPrice = (item['buying_price'] as num).toDouble();

      await LocalDatabase.instance.createSaleItem({
        'sale_id': saleId,
        'product_id': item['id'],
        'product_name': item['product_name'],
        'buying_price': buyingPrice,
        'selling_price': sellingPrice,
        'quantity': quantity,
        'total': sellingPrice * quantity,
        'profit': (sellingPrice - buyingPrice) * quantity,
      });

      await LocalDatabase.instance.deductStock(
        productId: item['id'],
        quantity: quantity,
      );
    }

    await LocalDatabase.instance.updateEmployeeStats(
      employeeId: widget.employeeId,
      revenue: totalAmount,
      profit: totalProfit,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sale Completed - $receiptNumber'),
      ),
    );

    clearCart();
    await loadProducts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.shopName),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear Cart',
            onPressed: cartItems.isEmpty ? null : clearCart,
          ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : Column(
              children: [
                Expanded(
                  flex: 2,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 1.4,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];

                     return PremiumProductCard(
  product: product,
  onTap: () => addToCart(product),
);
                    },
                  ),
                ),
                Container(
                  height: 320,
                  padding: const EdgeInsets.all(10),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Column(
                    children: [
                      const Text(
                        'Cart',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: cartItems.isEmpty
                            ? const Center(
                                child: Text('Cart is empty'),
                              )
                            : ListView.builder(
                                itemCount: cartItems.length,
                                itemBuilder: (context, index) {
                                  final item = cartItems[index];

                                  return PremiumCartItem(
  item: item,
  onIncrease: () => increaseQuantity(index),
  onDecrease: () => decreaseQuantity(index),
  onDelete: () => removeItem(index),
);
                                },
                              ),
                      ),
                      const SizedBox(height: 8),
                     CheckoutSummary(
  subtotal: totalAmount,
  discount: 0,
  tax: 0,
  profit: totalProfit,
  totalItems: cartItems.length,
  onCheckout: () async {
    checkout();
  },
  onClearCart: clearCart,
),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
