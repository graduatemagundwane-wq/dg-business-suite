import 'package:flutter/material.dart';

import '../database/local_db.dart';
import '../services/receipt_automation_service.dart';
import '../services/receipt_service.dart';
import '../widgets/checkout_summary.dart';
import '../widgets/payment_method_dialog.dart';
import '../widgets/pos_search_bar.dart';
import '../widgets/premium_cart_item.dart';
import '../widgets/premium_product_card.dart';
import '../widgets/receipt_preview_dialog.dart';
import 'barcode_scan.dart';

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
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> filteredProducts = [];
  List<Map<String, dynamic>> cartItems = [];

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> loadProducts() async {
    final data = await LocalDatabase.instance.getAllProducts(widget.shopId);

    if (!mounted) return;

    setState(() {
      products = data;
      filteredProducts = _filterProducts(data, _searchController.text);
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

  int get totalCartQuantity {
    return cartItems.fold<int>(
      0,
      (sum, item) => sum + (item['quantity'] as int),
    );
  }

  void searchProducts(String value) {
    setState(() {
      filteredProducts = _filterProducts(products, value);
    });
  }

  Future<void> _scanBarcode() async {
    final barcode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    );

    if (barcode == null || barcode.trim().isEmpty) return;

    _searchController.text = barcode.trim();
    searchProducts(barcode);

    final match = products.where((product) {
      return (product['barcode'] ?? '').toString().trim() == barcode.trim();
    }).toList();

    if (match.length == 1) {
      addToCart(match.first);
    }
  }

  List<Map<String, dynamic>> _filterProducts(
    List<Map<String, dynamic>> source,
    String query,
  ) {
    final normalized = query.trim().toLowerCase();

    if (normalized.isEmpty) {
      return List<Map<String, dynamic>>.from(source);
    }

    return source.where((product) {
      final name = (product['product_name'] ?? '').toString().toLowerCase();
      final barcode = (product['barcode'] ?? '').toString().toLowerCase();
      return name.contains(normalized) || barcode.contains(normalized);
    }).toList();
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

    final paymentMethod = await showDialog<PaymentMethod>(
      context: context,
      builder: (_) => PaymentMethodDialog(totalAmount: totalAmount),
    );

    if (paymentMethod == null) return;

    final receiptNumber = await LocalDatabase.instance.generateReceiptNumber();

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ReceiptPreviewDialog(
        shopName: widget.shopName,
        cashierName: widget.cashierName,
        receiptNumber: receiptNumber,
        cartItems: cartItems,
        subtotal: totalAmount,
        tax: 0,
        discount: 0,
        total: totalAmount,
        paymentMethod: paymentMethod.label,
        onPrint: () => _showStatus('Receipt sent to printer service'),
        onPdf: () => _showStatus('Receipt PDF generated'),
        onWhatsApp: () => _showStatus('WhatsApp receipt workflow started'),
        onConfirm: () => Navigator.pop(context, true),
      ),
    );

    if (confirmed != true) return;

    await _completeSale(receiptNumber);
  }

  Future<void> _completeSale(String receiptNumber) async {
    final saleId = await LocalDatabase.instance.createSale({
      'shop_id': widget.shopId,
      'employee_id': widget.employeeId,
      'customer_id': null,
      'receipt_number': receiptNumber,
      'cashier_name': widget.cashierName,
      'cashier_role': 'cashier',
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

    final receipt = ReceiptModel.fromCart(
      receiptNumber: receiptNumber,
      shopName: widget.shopName,
      cashierName: widget.cashierName,
      paymentMethod: 'Recorded',
      cartItems: cartItems,
      subtotal: totalAmount,
      discount: 0,
      tax: 0,
      total: totalAmount,
    );

    if (!mounted) return;

    await ReceiptAutomationService.instance.handleCompletedSale(
      context: context,
      receipt: receipt,
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

  void _showStatus(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showMobileCart() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.78,
            child: _CartPanel(
              cartItems: cartItems,
              subtotal: totalAmount,
              profit: totalProfit,
              totalItems: totalCartQuantity,
              onCheckout: checkout,
              onClearCart: clearCart,
              onIncrease: increaseQuantity,
              onDecrease: decreaseQuantity,
              onDelete: removeItem,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isSplitLayout = width >= 760;

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
      floatingActionButton: isSplitLayout || cartItems.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _showMobileCart,
              icon: const Icon(Icons.shopping_cart_checkout),
              label: Text(
                '$totalCartQuantity • \$${totalAmount.toStringAsFixed(2)}',
              ),
            ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : SafeArea(
              child: isSplitLayout
                  ? Row(
                      children: [
                        Expanded(
                          flex: 7,
                          child: _ProductsPanel(
                            products: filteredProducts,
                            searchController: _searchController,
                            onSearch: searchProducts,
                            onScanBarcode: _scanBarcode,
                            onAddProduct: addToCart,
                          ),
                        ),
                        VerticalDivider(
                          width: 1,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        SizedBox(
                          width: width >= 1100 ? 420 : 360,
                          child: _CartPanel(
                            cartItems: cartItems,
                            subtotal: totalAmount,
                            profit: totalProfit,
                            totalItems: totalCartQuantity,
                            onCheckout: checkout,
                            onClearCart: clearCart,
                            onIncrease: increaseQuantity,
                            onDecrease: decreaseQuantity,
                            onDelete: removeItem,
                          ),
                        ),
                      ],
                    )
                  : _ProductsPanel(
                      products: filteredProducts,
                      searchController: _searchController,
                      onSearch: searchProducts,
                      onScanBarcode: _scanBarcode,
                      onAddProduct: addToCart,
                    ),
            ),
    );
  }
}

class _ProductsPanel extends StatelessWidget {
  final List<Map<String, dynamic>> products;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final VoidCallback onScanBarcode;
  final ValueChanged<Map<String, dynamic>> onAddProduct;

  const _ProductsPanel({
    required this.products,
    required this.searchController,
    required this.onSearch,
    required this.onScanBarcode,
    required this.onAddProduct,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 1100
            ? 4
            : width >= 820
                ? 3
                : width >= 520
                    ? 2
                    : 1;

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Point of Sale',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    PosSearchBar(
                      controller: searchController,
                      onChanged: onSearch,
                      onScanBarcode: onScanBarcode,
                    ),
                  ],
                ),
              ),
            ),
            if (products.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text('No products found'),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverGrid.builder(
                  itemCount: products.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: 260,
                  ),
                  itemBuilder: (context, index) {
                    final product = products[index];

                    return PremiumProductCard(
                      product: product,
                      onTap: () => onAddProduct(product),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CartPanel extends StatelessWidget {
  final List<Map<String, dynamic>> cartItems;
  final double subtotal;
  final double profit;
  final int totalItems;
  final VoidCallback onCheckout;
  final VoidCallback onClearCart;
  final ValueChanged<int> onIncrease;
  final ValueChanged<int> onDecrease;
  final ValueChanged<int> onDelete;

  const _CartPanel({
    required this.cartItems,
    required this.subtotal,
    required this.profit,
    required this.totalItems,
    required this.onCheckout,
    required this.onClearCart,
    required this.onIncrease,
    required this.onDecrease,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text(
                  'Cart',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                Text('$totalItems item${totalItems == 1 ? '' : 's'}'),
              ],
            ),
          ),
          Expanded(
            child: cartItems.isEmpty
                ? const Center(
                    child: Text('Cart is empty'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: cartItems.length,
                    itemBuilder: (context, index) {
                      final item = cartItems[index];

                      return PremiumCartItem(
                        item: item,
                        onIncrease: () => onIncrease(index),
                        onDecrease: () => onDecrease(index),
                        onDelete: () => onDelete(index),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: CheckoutSummary(
              subtotal: subtotal,
              discount: 0,
              tax: 0,
              profit: profit,
              totalItems: totalItems,
              onCheckout: onCheckout,
              onClearCart: onClearCart,
            ),
          ),
        ],
      ),
    );
  }
}
