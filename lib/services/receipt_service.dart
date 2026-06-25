import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ReceiptService {
  static final ReceiptService instance =
      ReceiptService._internal();

  factory ReceiptService() => instance;

  ReceiptService._internal();

  Future<pw.Document> generateReceipt({
    required String receiptNumber,
    required String shopName,
    required String cashierName,
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    required double totalProfit,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Column(
            crossAxisAlignment:
                pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  "DOUBLE GEE TECH",
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight:
                        pw.FontWeight.bold,
                  ),
                ),
              ),

              pw.SizedBox(height: 10),

              pw.Text(
                "Receipt #: $receiptNumber",
              ),

              pw.Text(
                "Shop: $shopName",
              ),

              pw.Text(
                "Cashier: $cashierName",
              ),

              pw.Text(
                "Date: ${DateTime.now()}",
              ),

              pw.Divider(),

              pw.Row(
                mainAxisAlignment:
                    pw.MainAxisAlignment
                        .spaceBetween,
                children: [
                  pw.Text("Item"),
                  pw.Text("Qty"),
                  pw.Text("Price"),
                ],
              ),

              pw.Divider(),

              ...items.map(
                (item) => pw.Row(
                  mainAxisAlignment:
                      pw.MainAxisAlignment
                          .spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        item['product_name'],
                      ),
                    ),
                    pw.Text(
                      item['quantity']
                          .toString(),
                    ),
                    pw.Text(
                      item['selling_price']
                          .toString(),
                    ),
                  ],
                ),
              ),

              pw.Divider(),

              pw.SizedBox(height: 15),

              pw.Text(
                "Total: \$${totalAmount.toStringAsFixed(2)}",
                style: pw.TextStyle(
                  fontWeight:
                      pw.FontWeight.bold,
                ),
              ),

              pw.Text(
                "Profit: \$${totalProfit.toStringAsFixed(2)}",
              ),

              pw.SizedBox(height: 20),

              pw.Center(
                child: pw.Text(
                  "Thank You For Shopping",
                ),
              ),

              pw.Center(
                child: pw.Text(
                  "Powered By Double Gee Tech",
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }
}