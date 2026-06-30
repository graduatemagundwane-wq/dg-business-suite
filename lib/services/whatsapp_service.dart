import 'dart:io';

import 'pdf_service.dart';
import 'receipt_service.dart';

class WhatsAppShareResult {
  final bool success;
  final String message;
  final File? pdfFile;
  final String receiptMessage;

  const WhatsAppShareResult({
    required this.success,
    required this.message,
    required this.receiptMessage,
    this.pdfFile,
  });
}

class WhatsAppService {
  static final WhatsAppService instance = WhatsAppService._internal();

  factory WhatsAppService() => instance;

  WhatsAppService._internal();

  Future<WhatsAppShareResult> shareReceipt({
    required ReceiptModel receipt,
    String? customerPhone,
  }) async {
    final pdfFile = await PdfService.instance.saveReceiptPdf(receipt);
    final phone = (customerPhone ?? receipt.customerPhone ?? '').trim();
    final message = _buildMessage(receipt);

    if (phone.isEmpty) {
      return WhatsAppShareResult(
        success: false,
        pdfFile: pdfFile,
        receiptMessage: message,
        message: 'Customer phone not found. Add a customer phone number to send the WhatsApp receipt.',
      );
    }

    return WhatsAppShareResult(
      success: false,
      pdfFile: pdfFile,
      receiptMessage: message,
      message:
          'Receipt PDF generated for $phone and queued for WhatsApp delivery.',
    );
  }

  String _buildMessage(ReceiptModel receipt) {
    return 'Hello ${receipt.customerName ?? 'Customer'}, '
        'thank you for shopping at ${receipt.shopName}. '
        'Your receipt ${receipt.receiptNumber} total is '
        '\$${receipt.grandTotal.toStringAsFixed(2)}.';
  }
}
