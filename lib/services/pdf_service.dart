import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'dashboard_service.dart';
import 'receipt_service.dart';

class PdfService {
  static final PdfService instance = PdfService._internal();

  factory PdfService() => instance;

  PdfService._internal();

  Future<Uint8List> buildReceiptPdf(
    ReceiptModel receipt, {
    ReceiptPaperSize? paperSize,
    ReceiptDocumentType? documentType,
  }) async {
    final effectivePaperSize = paperSize ?? receipt.paperSize;
    final effectiveDocumentType = documentType ?? receipt.documentType;
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: _pageFormat(effectivePaperSize),
        margin: _pageMargin(effectivePaperSize),
        build: (_) => [
          _brandHeader(receipt, effectiveDocumentType),
          pw.SizedBox(height: 10),
          _receiptMeta(receipt),
          pw.SizedBox(height: 12),
          _productTable(receipt, effectivePaperSize),
          pw.SizedBox(height: 12),
          _totals(receipt),
          pw.SizedBox(height: 14),
          if (receipt.showQrCode) _qrPlaceholder(),
          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Text(
              receipt.footerMessage,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(child: pw.Text('Powered by Double Gee Tech')),
        ],
      ),
    );

    return pdf.save();
  }

  Future<File> saveReceiptPdf(
    ReceiptModel receipt, {
    ReceiptPaperSize? paperSize,
    ReceiptDocumentType? documentType,
  }) async {
    final bytes = await buildReceiptPdf(
      receipt,
      paperSize: paperSize,
      documentType: documentType,
    );
    final safeReceiptNumber = receipt.receiptNumber.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '_',
    );
    final file = File('${Directory.systemTemp.path}/$safeReceiptNumber.pdf');
    return file.writeAsBytes(bytes, flush: true);
  }

  Future<void> shareReceiptPdf(
    ReceiptModel receipt, {
    ReceiptPaperSize? paperSize,
    ReceiptDocumentType? documentType,
  }) async {
    final bytes = await buildReceiptPdf(
      receipt,
      paperSize: paperSize,
      documentType: documentType,
    );

    await Printing.sharePdf(
      bytes: bytes,
      filename: '${receipt.receiptNumber}.pdf',
    );
  }

  Future<void> printReceiptPdf(
    ReceiptModel receipt, {
    ReceiptPaperSize? paperSize,
    ReceiptDocumentType? documentType,
  }) async {
    final bytes = await buildReceiptPdf(
      receipt,
      paperSize: paperSize,
      documentType: documentType,
    );

    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<Uint8List> buildInvoicePdf(
    ReceiptModel receipt, {
    ReceiptDocumentType documentType = ReceiptDocumentType.invoice,
  }) {
    return buildReceiptPdf(
      receipt,
      paperSize: ReceiptPaperSize.a4Invoice,
      documentType: documentType,
    );
  }

  Future<Uint8List> buildReportPdf(ReportSummary report) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18 * PdfPageFormat.mm),
        build: (_) => [
          pw.Text(
            'Double Gee Tech Business Suite',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            report.title,
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.Divider(),
          _reportRow('Sales', _money(report.sales)),
          _reportRow('Profit', _money(report.profit)),
          _reportRow('Expenses', _money(report.expenses)),
          _reportRow('Net Profit', _money(report.netProfit)),
          _reportRow('Low Stock Items', report.lowStockItems.toString()),
          _reportRow('Out Of Stock Items', report.outOfStockItems.toString()),
          _reportRow('Inventory Value', _money(report.inventoryValue)),
          pw.SizedBox(height: 12),
          _reportRow('Best Employee', report.bestEmployee.name),
          _reportRow('Best Product', report.bestProduct.name),
          pw.SizedBox(height: 24),
          pw.Text('Generated locally from offline SQLite data.'),
        ],
      ),
    );

    return pdf.save();
  }

  Future<void> shareReportPdf(ReportSummary report) async {
    final bytes = await buildReportPdf(report);
    final filename = report.title.toLowerCase().replaceAll(' ', '_');

    await Printing.sharePdf(
      bytes: bytes,
      filename: '$filename.pdf',
    );
  }

  PdfPageFormat _pageFormat(ReceiptPaperSize paperSize) {
    switch (paperSize) {
      case ReceiptPaperSize.mm58:
        return const PdfPageFormat(58 * PdfPageFormat.mm, 220 * PdfPageFormat.mm);
      case ReceiptPaperSize.mm80:
        return const PdfPageFormat(80 * PdfPageFormat.mm, 260 * PdfPageFormat.mm);
      case ReceiptPaperSize.a4Invoice:
        return PdfPageFormat.a4;
    }
  }

  pw.EdgeInsets _pageMargin(ReceiptPaperSize paperSize) {
    switch (paperSize) {
      case ReceiptPaperSize.mm58:
        return const pw.EdgeInsets.all(4 * PdfPageFormat.mm);
      case ReceiptPaperSize.mm80:
        return const pw.EdgeInsets.all(5 * PdfPageFormat.mm);
      case ReceiptPaperSize.a4Invoice:
        return const pw.EdgeInsets.all(18 * PdfPageFormat.mm);
    }
  }

  pw.Widget _brandHeader(
    ReceiptModel receipt,
    ReceiptDocumentType documentType,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(
          child: pw.Text(
            'Double Gee Tech Business Suite',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
            ),
          ),
        ),
        pw.SizedBox(height: 6),
        if (receipt.showLogo)
          pw.Center(
            child: pw.Container(
              width: 46,
              height: 46,
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.green700),
                shape: pw.BoxShape.circle,
              ),
              child: pw.Text('LOGO', style: const pw.TextStyle(fontSize: 9)),
            ),
          ),
        pw.SizedBox(height: 6),
        pw.Text(
          receipt.shopName,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(receipt.shopAddress, textAlign: pw.TextAlign.center),
        pw.Text('Phone: ${receipt.phoneNumber}', textAlign: pw.TextAlign.center),
        pw.Text('Tax No: ${receipt.taxNumber}', textAlign: pw.TextAlign.center),
        pw.SizedBox(height: 6),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 5),
          alignment: pw.Alignment.center,
          color: PdfColors.green700,
          child: pw.Text(
            documentType.label.toUpperCase(),
            style: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _receiptMeta(ReceiptModel receipt) {
    return pw.Column(
      children: [
        _pdfInfoRow('Receipt Number', receipt.receiptNumber),
        _pdfInfoRow('Date & Time', receipt.dateTime.toString()),
        _pdfInfoRow('Cashier', receipt.cashierName),
        _pdfInfoRow('Customer', receipt.customerName ?? 'Walk-in Customer'),
        _pdfInfoRow('Payment Method', receipt.paymentMethod),
      ],
    );
  }

  pw.Widget _productTable(ReceiptModel receipt, ReceiptPaperSize paperSize) {
    final compact = paperSize != ReceiptPaperSize.a4Invoice;

    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: const pw.BorderSide(color: PdfColors.grey300),
        bottom: const pw.BorderSide(color: PdfColors.grey500),
        top: const pw.BorderSide(color: PdfColors.grey500),
      ),
      columnWidths: {
        0: const pw.FlexColumnWidth(4),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blue50),
          children: [
            _tableCell('Product', bold: true),
            _tableCell('Qty', bold: true, alignRight: compact),
            _tableCell('Unit', bold: true, alignRight: true),
            _tableCell('Total', bold: true, alignRight: true),
          ],
        ),
        ...receipt.items.map(
          (item) => pw.TableRow(
            children: [
              _tableCell(item.productName),
              _tableCell('${item.quantity}', alignRight: compact),
              _tableCell(_money(item.unitPrice), alignRight: true),
              _tableCell(_money(item.total), alignRight: true),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _totals(ReceiptModel receipt) {
    return pw.Column(
      children: [
        _pdfInfoRow('Subtotal', _money(receipt.subtotal)),
        _pdfInfoRow('Discount', '-${_money(receipt.discount)}'),
        _pdfInfoRow('Tax', _money(receipt.tax)),
        pw.Divider(color: PdfColors.grey500),
        _pdfInfoRow('Grand Total', _money(receipt.grandTotal), bold: true),
      ],
    );
  }

  pw.Widget _qrPlaceholder() {
    return pw.Center(
      child: pw.Container(
        width: 64,
        height: 64,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey700),
        ),
        child: pw.Text('QR', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      ),
    );
  }

  pw.Widget _pdfInfoRow(String label, String value, {bool bold = false}) {
    final style = bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null;

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: pw.Text(label, style: style)),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: style,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _tableCell(
    String value, {
    bool bold = false,
    bool alignRight = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 3),
      child: pw.Text(
        value,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
      ),
    );
  }

  pw.Widget _reportRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label),
          pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }
}

String _money(double value) => '\$${value.toStringAsFixed(2)}';
