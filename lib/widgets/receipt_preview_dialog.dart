import 'package:flutter/material.dart';

class ReceiptPreviewDialog extends StatelessWidget {
  final String shopName;
  final String cashierName;
  final String receiptNumber;
  final List<Map<String, dynamic>> cartItems;
  final double subtotal;
  final double tax;
  final double discount;
  final double total;
  final String paymentMethod;

  final VoidCallback onPrint;
  final VoidCallback onPdf;
  final VoidCallback onWhatsApp;
  final VoidCallback onConfirm;

  const ReceiptPreviewDialog({
    super.key,
    required this.shopName,
    required this.cashierName,
    required this.receiptNumber,
    required this.cartItems,
    required this.subtotal,
    required this.tax,
    required this.discount,
    required this.total,
    required this.paymentMethod,
    required this.onPrint,
    required this.onPdf,
    required this.onWhatsApp,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            const Icon(
              Icons.receipt_long,
              size: 60,
              color: Colors.blue,
            ),

            const SizedBox(height: 10),

            Text(
              shopName,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            Text("Receipt #: $receiptNumber"),
            Text("Cashier: $cashierName"),
            Text(DateTime.now().toString()),

            const Divider(height: 30),

            SizedBox(
              height: 220,
              child: ListView.builder(
                itemCount: cartItems.length,
                itemBuilder: (context, index) {
                  final item = cartItems[index];

                  final qty = item['quantity'];

                  final price =
                      (item['selling_price'] as num)
                          .toDouble();

                  return ListTile(
                    dense: true,
                    title: Text(
                      item['product_name'],
                    ),
                    subtitle:
                        Text("Qty: $qty"),
                    trailing: Text(
                      "\$${(price * qty).toStringAsFixed(2)}",
                    ),
                  );
                },
              ),
            ),

            const Divider(),

            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
                const Text("Subtotal"),
                Text(
                  "\$${subtotal.toStringAsFixed(2)}",
                ),
              ],
            ),

            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
                const Text("Discount"),
                Text(
                  "\$${discount.toStringAsFixed(2)}",
                ),
              ],
            ),

            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
                const Text("Tax"),
                Text(
                  "\$${tax.toStringAsFixed(2)}",
                ),
              ],
            ),

            const Divider(),

            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "TOTAL",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  "\$${total.toStringAsFixed(2)}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.green,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 15),

            Text(
              "Payment: $paymentMethod",
            ),

            const SizedBox(height: 20),

            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [

                FilledButton.icon(
                  onPressed: onPrint,
                  icon:
                      const Icon(Icons.print),
                  label:
                      const Text("Print"),
                ),

                FilledButton.icon(
                  onPressed: onPdf,
                  icon: const Icon(
                    Icons.picture_as_pdf,
                  ),
                  label:
                      const Text("PDF"),
                ),

                FilledButton.icon(
                  onPressed: onWhatsApp,
                  icon:
                      const Icon(Icons.share),
                  label: const Text(
                    "WhatsApp",
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onConfirm,
                child: const Text(
                  "COMPLETE SALE",
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}