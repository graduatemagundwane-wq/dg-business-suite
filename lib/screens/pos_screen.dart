import 'package:flutter/material.dart';

import '../database/local_db.dart';

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
    final data = await LocalDatabase.instance
        .getAllProducts(widget.shopId);

    setState(() {
      products = data;
      isLoading = false;
    });
  }

  double get totalAmount {
    double total = 0;

    for (final item in cartItems) {
      total +=
          (item['selling_price'] as num)
                  .toDouble() *
              (item['quantity'] as int);
    }

    return total;
  }

  void addToCart(
      Map<String, dynamic> product) {
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

    final receiptNumber =
        await LocalDatabase.instance
            .generateReceiptNumber();

    final saleId =
        await LocalDatabase.instance
            .createSale({
      'shop_id': widget.shopId,
      'employee_id': widget.employeeId,
      'customer_id': null,
      'receipt_number': receiptNumber,
      'total_amount': totalAmount,
      'total_profit': 0,
      'sale_date':
          DateTime.now().toIso8601String(),
    });

    for (final item in cartItems) {
      await LocalDatabase.instance
          .createSaleItem({
        'sale_id': saleId,
        'product_id': item['id'],
        'product_name':
            item['product_name'],
        'buying_price':
            item['buying_price'],
        'selling_price':
            item['selling_price'],
        'quantity':
            item['quantity'],
        'total':
            (item['selling_price'] as num)
                    .toDouble() *
                item['quantity'],
        'profit':
            ((item['selling_price']
                            as num)
                        .toDouble() -
                    (item['buying_price']
                            as num)
                        .toDouble()) *
                item['quantity'],
      });

      await LocalDatabase.instance
          .deductStock(
        productId: item['id'],
        quantity: item['quantity'],
      );
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          'Sale Completed - $receiptNumber',
        ),
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
          tooltip: "Clear Cart",
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

                    return Card(
                      elevation: 3,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => addToCart(product),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.inventory_2,
                                size: 34,
                                color: Colors.blue,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                product['product_name'],
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "\$${product['selling_price']}",
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              Container(
                height: 300,
                padding: const EdgeInsets.all(10),
                color: Colors.grey.shade200,
                child: Column(
                  children: [
                    const Text(
                      "Cart",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Expanded(
                      child: ListView.builder(
                        itemCount: cartItems.length,
                        itemBuilder: (context, index) {
                          final item = cartItems[index];

                          return Card(
                            child: ListTile(
                              title: Text(
                                item['product_name'],
                              ),