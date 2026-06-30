import 'package:flutter/material.dart';

import 'printer_service.dart';
import 'receipt_service.dart';
import 'whatsapp_service.dart';

class ReceiptAutomationSettings {
  final bool autoPrint;
  final bool askBeforePrinting;
  final bool autoWhatsApp;
  final bool askBeforeSend;
  final String? defaultPrinterId;

  const ReceiptAutomationSettings({
    this.autoPrint = false,
    this.askBeforePrinting = true,
    this.autoWhatsApp = false,
    this.askBeforeSend = true,
    this.defaultPrinterId,
  });

  ReceiptAutomationSettings copyWith({
    bool? autoPrint,
    bool? askBeforePrinting,
    bool? autoWhatsApp,
    bool? askBeforeSend,
    String? defaultPrinterId,
  }) {
    return ReceiptAutomationSettings(
      autoPrint: autoPrint ?? this.autoPrint,
      askBeforePrinting: askBeforePrinting ?? this.askBeforePrinting,
      autoWhatsApp: autoWhatsApp ?? this.autoWhatsApp,
      askBeforeSend: askBeforeSend ?? this.askBeforeSend,
      defaultPrinterId: defaultPrinterId ?? this.defaultPrinterId,
    );
  }
}

class ReceiptAutomationService {
  static final ReceiptAutomationService instance =
      ReceiptAutomationService._internal();

  factory ReceiptAutomationService() => instance;

  ReceiptAutomationService._internal();

  ReceiptAutomationSettings _settings = const ReceiptAutomationSettings();

  ReceiptAutomationSettings get settings => _settings;

  void updateSettings(ReceiptAutomationSettings settings) {
    _settings = settings;
    final defaultPrinterId = settings.defaultPrinterId;
    if (defaultPrinterId != null) {
      PrinterService.instance.setDefaultPrinter(defaultPrinterId);
    }
  }

  Future<void> handleCompletedSale({
    required BuildContext context,
    required ReceiptModel receipt,
  }) async {
    if (_settings.autoPrint) {
      final shouldPrint = !_settings.askBeforePrinting ||
          await _confirm(
            context,
            title: 'Print Receipt?',
            message: 'Print receipt ${receipt.receiptNumber} now?',
          );

      if (shouldPrint && context.mounted) {
        await PrinterService.instance.printReceipt(receipt);
      }
    }

    if (!_settings.autoWhatsApp || !context.mounted) return;

    final phone = receipt.customerPhone?.trim() ?? '';
    if (phone.isEmpty) {
      await _showMissingPhone(context);
      return;
    }

    final shouldSend = !_settings.askBeforeSend ||
        await _confirm(
          context,
          title: 'Send WhatsApp Receipt?',
          message: 'Send receipt ${receipt.receiptNumber} to $phone?',
        );

    if (!shouldSend || !context.mounted) return;

    final result = await WhatsAppService.instance.shareReceipt(
      receipt: receipt,
      customerPhone: phone,
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<void> _showMissingPhone(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Customer phone not found'),
        content: const Text('Would you like to add it?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not Now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Add Later'),
          ),
        ],
      ),
    );
  }
}
