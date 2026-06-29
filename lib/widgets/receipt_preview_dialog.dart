import 'package:flutter/material.dart';

import '../services/pdf_service.dart';
import '../services/printer_service.dart';
import '../services/receipt_service.dart';
import '../services/whatsapp_service.dart';

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
  final String? customerName;
  final ReceiptSettings? settings;

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
    this.customerName,
    this.settings,
    required this.onPrint,
    required this.onPdf,
    required this.onWhatsApp,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final receipt = ReceiptModel.fromCart(
      receiptNumber: receiptNumber,
      shopName: shopName,
      cashierName: cashierName,
      paymentMethod: paymentMethod,
      cartItems: cartItems,
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      total: total,
      settings: settings,
      customerName: customerName,
    );

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _ReceiptTemplate(receipt: receipt),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _printReceipt(context, receipt),
                    icon: const Icon(Icons.print),
                    label: const Text('Print'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _exportPdf(context, receipt),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _shareWhatsApp(context, receipt),
                    icon: const Icon(Icons.chat),
                    label: const Text('WhatsApp'),
                  ),
                  FilledButton.icon(
                    onPressed: onConfirm,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Complete Sale'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _printReceipt(BuildContext context, ReceiptModel receipt) async {
    await PrinterService.instance.printReceipt(receipt);
    onPrint();
  }

  Future<void> _exportPdf(BuildContext context, ReceiptModel receipt) async {
    await PdfService.instance.shareReceiptPdf(receipt);
    onPdf();
  }

  Future<void> _shareWhatsApp(BuildContext context, ReceiptModel receipt) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await WhatsAppService.instance.shareReceipt(receipt: receipt);

    messenger.showSnackBar(SnackBar(content: Text(result.message)));
    onWhatsApp();
  }
}

class _ReceiptTemplate extends StatelessWidget {
  final ReceiptModel receipt;

  const _ReceiptTemplate({
    required this.receipt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Column(
            children: [
              if (receipt.showLogo)
                CircleAvatar(
                  radius: 28,
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                  child: const Icon(Icons.storefront),
                ),
              const SizedBox(height: 10),
              Text(
                'Double Gee Tech Business Suite',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                receipt.shopName,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                receipt.shopAddress,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              Text(
                receipt.phoneNumber,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              Text(
                'Tax No: ${receipt.taxNumber}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const Divider(height: 28),
        _InfoRow('Receipt Number', receipt.receiptNumber),
        _InfoRow('Cashier', receipt.cashierName),
        _InfoRow('Date & Time', receipt.dateTime.toString()),
        _InfoRow('Customer', receipt.customerName ?? 'Walk-in Customer'),
        _InfoRow('Payment Method', receipt.paymentMethod),
        const Divider(height: 28),
        Row(
          children: const [
            Expanded(flex: 4, child: Text('Product')),
            Expanded(child: Text('Qty', textAlign: TextAlign.center)),
            Expanded(flex: 2, child: Text('Unit', textAlign: TextAlign.right)),
            Expanded(flex: 2, child: Text('Total', textAlign: TextAlign.right)),
          ],
        ),
        const SizedBox(height: 8),
        ...receipt.items.map(
          (item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(flex: 4, child: Text(item.productName)),
                Expanded(
                  child: Text(
                    item.quantity.toString(),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    _money(item.unitPrice),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    _money(item.total),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 28),
        _InfoRow('Subtotal', _money(receipt.subtotal)),
        _InfoRow('Discount', '-${_money(receipt.discount)}'),
        _InfoRow('Tax', _money(receipt.tax)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: _InfoRow(
            'Grand Total',
            _money(receipt.grandTotal),
            bold: true,
          ),
        ),
        const SizedBox(height: 18),
        if (receipt.showQrCode)
          Center(
            child: Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.qr_code_2, size: 56),
            ),
          ),
        const SizedBox(height: 18),
        Text(
          receipt.footerMessage,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _InfoRow(
    this.label,
    this.value, {
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

String _money(double value) => '\$${value.toStringAsFixed(2)}';
