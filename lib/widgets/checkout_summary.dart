import 'package:flutter/material.dart';

class CheckoutSummary extends StatelessWidget {
  final double subtotal;
  final double discount;
  final double tax;
  final double profit;
  final int totalItems;
  final VoidCallback onCheckout;
  final VoidCallback onClearCart;

  const CheckoutSummary({
    super.key,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.profit,
    required this.totalItems,
    required this.onCheckout,
    required this.onClearCart,
  });

  double get grandTotal =>
      subtotal - discount + tax;

  Widget _row(
    String title,
    String value, {
    bool bold = false,
    Color? color,
  }) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: bold
                  ? FontWeight.bold
                  : FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold
                  ? FontWeight.bold
                  : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(20),
      ),
      child: Padding(
        padding:
            const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [

            const Text(
              "Checkout Summary",
              style: TextStyle(
                fontSize: 20,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 16),

            _row(
              "Items",
              "$totalItems",
            ),

            _row(
              "Subtotal",
              "\$${subtotal.toStringAsFixed(2)}",
            ),

            _row(
              "Discount",
              "-\$${discount.toStringAsFixed(2)}",
              color: Colors.orange,
            ),

            _row(
              "Tax",
              "\$${tax.toStringAsFixed(2)}",
            ),

            _row(
              "Expected Profit",
              "\$${profit.toStringAsFixed(2)}",
              color: Colors.green,
            ),

            const Divider(height: 28),

            _row(
              "TOTAL",
              "\$${grandTotal.toStringAsFixed(2)}",
              bold: true,
              color: Colors.blue,
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: onCheckout,
                icon: const Icon(
                  Icons.payments,
                ),
                label: const Text(
                  "Proceed to Payment",
                ),
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: onClearCart,
                icon: const Icon(
                  Icons.delete_sweep,
                ),
                label: const Text(
                  "Clear Cart",
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}