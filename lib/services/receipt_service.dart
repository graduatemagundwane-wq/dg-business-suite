import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../database/local_db.dart';

class ReceiptSettings {
  final String shopName;
  final String address;
  final String phone;
  final String? logoPath;
  final String footerMessage;
  final String taxNumber;
  final bool showLogo;
  final bool showQrCode;
  final ReceiptPaperSize paperSize;
  final ReceiptDocumentType documentType;

  const ReceiptSettings({
    required this.shopName,
    this.address = 'Shop address not configured',
    this.phone = 'Phone not configured',
    this.logoPath,
    this.footerMessage = 'Thank you for shopping with us.',
    this.taxNumber = 'Tax number not configured',
    this.showLogo = true,
    this.showQrCode = true,
    this.paperSize = ReceiptPaperSize.mm80,
    this.documentType = ReceiptDocumentType.receipt,
  });
}

enum ReceiptPaperSize {
  mm58,
  mm80,
  a4Invoice,
}

extension ReceiptPaperSizeLabel on ReceiptPaperSize {
  String get label {
    switch (this) {
      case ReceiptPaperSize.mm58:
        return '58mm Receipt';
      case ReceiptPaperSize.mm80:
        return '80mm Receipt';
      case ReceiptPaperSize.a4Invoice:
        return 'A4 Invoice';
    }
  }
}

enum ReceiptDocumentType {
  receipt,
  invoice,
  quotation,
  proformaInvoice,
}

extension ReceiptDocumentTypeLabel on ReceiptDocumentType {
  String get label {
    switch (this) {
      case ReceiptDocumentType.receipt:
        return 'Receipt';
      case ReceiptDocumentType.invoice:
        return 'Invoice';
      case ReceiptDocumentType.quotation:
        return 'Quotation';
      case ReceiptDocumentType.proformaInvoice:
        return 'Proforma Invoice';
    }
  }
}

class ReceiptItem {
  final String productName;
  final int quantity;
  final double unitPrice;
  final double total;

  const ReceiptItem({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.total,
  });

  factory ReceiptItem.fromMap(Map<String, dynamic> map) {
    final quantity = _asInt(map['quantity']);
    final unitPrice = _asDouble(map['selling_price']);

    return ReceiptItem(
      productName: (map['product_name'] ?? 'Unknown Product').toString(),
      quantity: quantity,
      unitPrice: unitPrice,
      total: _asDouble(map['total'], fallback: unitPrice * quantity),
    );
  }
}

class ReceiptModel {
  final String receiptNumber;
  final String shopName;
  final String shopAddress;
  final String phoneNumber;
  final String? logoPath;
  final String cashierName;
  final String? customerName;
  final String? customerPhone;
  final String paymentMethod;
  final DateTime dateTime;
  final List<ReceiptItem> items;
  final double subtotal;
  final double discount;
  final double tax;
  final double grandTotal;
  final String footerMessage;
  final String taxNumber;
  final bool showLogo;
  final bool showQrCode;
  final ReceiptPaperSize paperSize;
  final ReceiptDocumentType documentType;

  const ReceiptModel({
    required this.receiptNumber,
    required this.shopName,
    required this.shopAddress,
    required this.phoneNumber,
    this.logoPath,
    required this.cashierName,
    this.customerName,
    this.customerPhone,
    required this.paymentMethod,
    required this.dateTime,
    required this.items,
    required this.subtotal,
    this.discount = 0,
    this.tax = 0,
    required this.grandTotal,
    required this.footerMessage,
    required this.taxNumber,
    this.showLogo = true,
    this.showQrCode = true,
    this.paperSize = ReceiptPaperSize.mm80,
    this.documentType = ReceiptDocumentType.receipt,
  });

  factory ReceiptModel.fromCart({
    required String receiptNumber,
    required String shopName,
    required String cashierName,
    required String paymentMethod,
    required List<Map<String, dynamic>> cartItems,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    ReceiptSettings? settings,
    String? customerName,
    String? customerPhone,
  }) {
    final receiptSettings = settings ?? ReceiptSettings(shopName: shopName);

    return ReceiptModel(
      receiptNumber: receiptNumber,
      shopName: receiptSettings.shopName,
      shopAddress: receiptSettings.address,
      phoneNumber: receiptSettings.phone,
      logoPath: receiptSettings.logoPath,
      cashierName: cashierName,
      customerName: customerName,
      customerPhone: customerPhone,
      paymentMethod: paymentMethod,
      dateTime: DateTime.now(),
      items: cartItems.map(ReceiptItem.fromMap).toList(),
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      grandTotal: total,
      footerMessage: receiptSettings.footerMessage,
      taxNumber: receiptSettings.taxNumber,
      showLogo: receiptSettings.showLogo,
      showQrCode: receiptSettings.showQrCode,
      paperSize: receiptSettings.paperSize,
      documentType: receiptSettings.documentType,
    );
  }
}

class ReceiptHistoryEntry {
  final int saleId;
  final String receiptNumber;
  final String cashierName;
  final String customerName;
  final String? customerPhone;
  final DateTime dateTime;
  final double total;
  final double profit;

  const ReceiptHistoryEntry({
    required this.saleId,
    required this.receiptNumber,
    required this.cashierName,
    required this.customerName,
    this.customerPhone,
    required this.dateTime,
    required this.total,
    required this.profit,
  });
}

class PrinterProfile {
  final String name;
  final PrinterConnectionType type;
  final bool enabled;

  const PrinterProfile({
    required this.name,
    required this.type,
    this.enabled = false,
  });
}

enum PrinterConnectionType {
  bluetooth,
  usb,
  otg,
  network,
}

class ReceiptService {
  static final ReceiptService instance = ReceiptService._internal();

  factory ReceiptService() => instance;

  ReceiptService._internal();

  List<PrinterProfile> defaultPrinterProfiles() {
    return const [
      PrinterProfile(name: 'Bluetooth Printer', type: PrinterConnectionType.bluetooth),
      PrinterProfile(name: 'USB Printer', type: PrinterConnectionType.usb),
      PrinterProfile(name: 'OTG Printer', type: PrinterConnectionType.otg),
      PrinterProfile(name: 'Network Printer', type: PrinterConnectionType.network),
    ];
  }

  Future<List<ReceiptHistoryEntry>> getReceiptHistory({
    required int shopId,
  }) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        s.id,
        s.receipt_number,
        s.total_amount,
        s.total_profit,
        s.sale_date,
        COALESCE(e.employee_name, 'Unknown Cashier') AS cashier_name,
        COALESCE(c.customer_name, 'Walk-in Customer') AS customer_name,
        c.phone AS customer_phone
      FROM sales s
      LEFT JOIN employees e ON e.id = s.employee_id
      LEFT JOIN customers c ON c.id = s.customer_id
      WHERE s.shop_id = ?
      ORDER BY s.sale_date DESC
      LIMIT 200
      ''',
      [shopId],
    );

    return rows.map((row) {
      return ReceiptHistoryEntry(
        saleId: _asInt(row['id']),
        receiptNumber: (row['receipt_number'] ?? '').toString(),
        cashierName: (row['cashier_name'] ?? 'Unknown Cashier').toString(),
        customerName: (row['customer_name'] ?? 'Walk-in Customer').toString(),
        customerPhone: row['customer_phone']?.toString(),
        dateTime: DateTime.tryParse((row['sale_date'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        total: _asDouble(row['total_amount']),
        profit: _asDouble(row['total_profit']),
      );
    }).toList();
  }

  Future<ReceiptModel?> getReceiptBySaleId({
    required int saleId,
    required String shopName,
  }) async {
    final db = await LocalDatabase.instance.database;
    final saleRows = await db.rawQuery(
      '''
      SELECT
        s.*,
        COALESCE(e.employee_name, 'Unknown Cashier') AS cashier_name,
        c.customer_name,
        c.phone AS customer_phone
      FROM sales s
      LEFT JOIN employees e ON e.id = s.employee_id
      LEFT JOIN customers c ON c.id = s.customer_id
      WHERE s.id = ?
      LIMIT 1
      ''',
      [saleId],
    );

    if (saleRows.isEmpty) return null;

    final itemRows = await db.query(
      'sale_items',
      where: 'sale_id = ?',
      whereArgs: [saleId],
    );
    final sale = saleRows.first;
    final total = _asDouble(sale['total_amount']);

    return ReceiptModel(
      receiptNumber: (sale['receipt_number'] ?? '').toString(),
      shopName: shopName,
      shopAddress: 'Shop address not configured',
      phoneNumber: 'Phone not configured',
      cashierName: (sale['cashier_name'] ?? 'Unknown Cashier').toString(),
      customerName: sale['customer_name']?.toString(),
      customerPhone: sale['customer_phone']?.toString(),
      paymentMethod: 'Not recorded',
      dateTime: DateTime.tryParse((sale['sale_date'] ?? '').toString()) ??
          DateTime.now(),
      items: itemRows.map(ReceiptItem.fromMap).toList(),
      subtotal: total,
      grandTotal: total,
      footerMessage: 'Thank you for shopping with us.',
      taxNumber: 'Tax number not configured',
    );
  }

  Future<pw.Document> generateReceipt({
    required String receiptNumber,
    required String shopName,
    required String cashierName,
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    required double totalProfit,
  }) async {
    final receipt = ReceiptModel.fromCart(
      receiptNumber: receiptNumber,
      shopName: shopName,
      cashierName: cashierName,
      paymentMethod: 'Not recorded',
      cartItems: items,
      subtotal: totalAmount,
      discount: 0,
      tax: 0,
      total: totalAmount,
    );

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  'Double Gee Tech Business Suite',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text('Receipt #: ${receipt.receiptNumber}'),
              pw.Text('Shop: ${receipt.shopName}'),
              pw.Text('Cashier: ${receipt.cashierName}'),
              pw.Text('Date: ${receipt.dateTime}'),
              pw.Divider(),
              ...receipt.items.map(
                (item) => pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(child: pw.Text(item.productName)),
                    pw.Text('x${item.quantity}'),
                    pw.Text('\$${item.total.toStringAsFixed(2)}'),
                  ],
                ),
              ),
              pw.Divider(),
              pw.Text(
                'Total: \$${receipt.grandTotal.toStringAsFixed(2)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text('Profit: \$${totalProfit.toStringAsFixed(2)}'),
              pw.SizedBox(height: 20),
              pw.Center(child: pw.Text(receipt.footerMessage)),
              pw.Center(child: pw.Text('Powered By Double Gee Tech')),
            ],
          );
        },
      ),
    );

    return pdf;
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(dynamic value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}
