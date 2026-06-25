import 'package:flutter/foundation.dart';

class CartItem {
  final int productId;
  final String productName;
  final double buyingPrice;
  final double sellingPrice;

  int quantity;

  CartItem({
    required this.productId,
    required this.productName,
    required this.buyingPrice,
    required this.sellingPrice,
    this.quantity = 1,
  });

  double get total =>
      sellingPrice * quantity;

  double get profit =>
      (sellingPrice - buyingPrice) *
      quantity;
}

class CartController extends ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => _items;

  void addProduct(
      Map<String, dynamic> product) {
    final index = _items.indexWhere(
      (item) =>
          item.productId ==
          product['id'],
    );

    if (index >= 0) {
      _items[index].quantity++;
    } else {
      _items.add(
        CartItem(
          productId: product['id'],
          productName:
              product['product_name'],
          buyingPrice:
              (product['buying_price']
                      as num)
                  .toDouble(),
          sellingPrice:
              (product['selling_price']
                      as num)
                  .toDouble(),
        ),
      );
    }

    notifyListeners();
  }

  void increaseQuantity(
      int productId) {
    final index = _items.indexWhere(
      (item) =>
          item.productId == productId,
    );

    if (index >= 0) {
      _items[index].quantity++;
      notifyListeners();
    }
  }

  void decreaseQuantity(
      int productId) {
    final index = _items.indexWhere(
      (item) =>
          item.productId == productId,
    );

    if (index < 0) return;

    if (_items[index].quantity > 1) {
      _items[index].quantity--;
    } else {
      _items.removeAt(index);
    }

    notifyListeners();
  }

  void removeItem(
      int productId) {
    _items.removeWhere(
      (item) =>
          item.productId == productId,
    );

    notifyListeners();
  }

  double get totalAmount {
    return _items.fold(
      0,
      (sum, item) =>
          sum + item.total,
    );
  }

  double get totalProfit {
    return _items.fold(
      0,
      (sum, item) =>
          sum + item.profit,
    );
  }

  int get totalItems {
    return _items.fold(
      0,
      (sum, item) =>
          sum + item.quantity,
    );
  }

  bool get isEmpty =>
      _items.isEmpty;

  void clearCart() {
    _items.clear();
    notifyListeners();
  }
}