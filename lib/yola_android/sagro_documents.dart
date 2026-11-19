import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../services/pdf_service.dart';
import '../services/receipt_service.dart';
import 'offline_license.dart';
import 'offline_store.dart';
import 'sagro_brand.dart';

/// Documents are not paid sales; they do not affect stock or the sales ledger.
class SagroDocuments extends StatefulWidget {
  const SagroDocuments({super.key});
  @override
  State<SagroDocuments> createState() => _SagroDocumentsState();
}

class _SagroDocumentsState extends State<SagroDocuments> {
  final _customer = TextEditingController();
  final _item = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _price = TextEditingController();
  final List<_SagroLine> _lines = [];
  List<Map<String, Object?>> _saved = [];
  bool _busy = false;
  String? _error, _notice;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() {
    for (final c in [_customer, _item, _qty, _price]) { c.dispose(); }
    super.dispose();
  }

  Future<Database> _db() async {
    final db = await YolaOfflineStore.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sagro_documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id TEXT NOT NULL,
        number TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    return db;
  }

  Future<void> _load() async {
    try {
      final licence = await YolaLicence.instance.requireActive();
      SagroBrand.requireAuthorisedBusiness(licence.businessId);
      final db = await _db();
      final saved = await db.query('sagro_documents',
        where: 'business_id=?', whereArgs: [licence.businessId],
        orderBy: 'id DESC', limit: 100);
      if (mounted) setState(() => _saved = saved);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _addItem() {
    final qty = int.tryParse(_qty.text.trim());
    final price = double.tryParse(_price.text.trim());
    if (_item.text.trim().isEmpty || qty == null || qty < 1 ||
        price == null || !price.isFinite || price < 0) {
      setState(() => _error = 'Enter an item, quantity and valid unit price.');
      return;
    }
    setState(() {
      _lines.add(_SagroLine(_item.text.trim(), qty, (price*100).round()));
      _item.clear(); _qty.text = '1'; _price.clear(); _error = null;
    });
  }

  int get _total => _lines.fold(0, (int sum, _SagroLine line) =>
      sum + line.qty * line.cents);
  String _money(int cents) => String.fromCharCode(36) +
      (cents/100).toStringAsFixed(2);

  ReceiptModel _model(String number, ReceiptDocumentType type,
      String customer, DateTime date, List<_SagroLine> lines) {
    final total = lines.fold(0, (int sum, _SagroLine line) =>
      sum + line.qty * line.cents);
    return ReceiptModel(
      receiptNumber: number,
      shopName: SagroBrand.displayName,
      shopAddress: SagroBrand.documentAddress,
      phoneNumber: SagroBrand.phone,
      logoPath: SagroBrand.logoAsset,
      cashierName: 'SAGRO',
      customerName: customer,
      paymentMethod: type == ReceiptDocumentType.quotation
          ? 'Not a payment receipt' : 'Not marked as paid',
      dateTime: date,
      items: lines.map((line) => ReceiptItem(
        productName: line.name, quantity: line.qty,
        unitPrice: line.cents/100,
        total: line.qty*line.cents/100)).toList(),
      subtotal: total/100, grandTotal: total/100,
      footerMessage: 'Thank you for choosing SAGRO.',
      taxNumber: '', showLogo: true, showQrCode: false,
      paperSize: ReceiptPaperSize.a4Invoice,
      documentType: type,
    );
  }

  Future<void> _create(ReceiptDocumentType type) async {
    if (_busy) return;
    if (_customer.text.trim().isEmpty || _lines.isEmpty) {
      setState(() => _error = 'Add a customer and at least one line item.');
      return;
    }
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      final licence = await YolaLicence.instance.requireActive();
      SagroBrand.requireAuthorisedBusiness(licence.businessId);
      final db = await _db();
      final now = DateTime.now().toUtc();
      final number = 'SGR-' + (type == ReceiptDocumentType.quotation ? 'Q-' : 'I-') +
          now.microsecondsSinceEpoch.toString();
      final customer = _customer.text.trim();
      final lines = List<_SagroLine>.of(_lines);
      await db.insert('sagro_documents', {
        'business_id': licence.businessId,
        'number': number,
        'type': type.name,
        'payload': jsonEncode({
          'customer': customer,
          'lines': lines.map((l) => l.toJson()).toList(),
        }),
        'created_at': now.toIso8601String(),
      });
      if (mounted) {
        setState(() {
          _customer.clear(); _lines.clear();
          _notice = number + ' saved on this device.';
        });
      }
      await _load();
      final doc = _model(number, type, customer, now.toLocal(), lines);
      await PdfService.instance.shareReceiptPdf(doc,
          paperSize: ReceiptPaperSize.a4Invoice, documentType: type);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ReceiptModel _read(Map<String, Object?> row) {
    final data = (jsonDecode(row['payload'].toString()) as Map)
        .cast<String, dynamic>();
    final lines = (data['lines'] as List).map((v) =>
        _SagroLine.fromJson((v as Map).cast<String, dynamic>())).toList();
    final type = row['type'] == 'quotation' ?
        ReceiptDocumentType.quotation : ReceiptDocumentType.invoice;
    return _model(row['number'].toString(), type,
        data['customer'].toString(),
        DateTime.parse(row['created_at'].toString()).toLocal(), lines);
  }

  Future<void> _export(Map<String, Object?> row, {bool print = false}) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final licence = await YolaLicence.instance.requireActive();
      SagroBrand.requireAuthorisedBusiness(licence.businessId);
      if (row['business_id'] != licence.businessId) {
        throw StateError('Document belongs to another business.');
      }
      final doc = _read(row);
      if (print) {
        await PdfService.instance.printReceiptPdf(doc,
            paperSize: ReceiptPaperSize.a4Invoice,
            documentType: doc.documentType);
      } else {
        await PdfService.instance.shareReceiptPdf(doc,
            paperSize: ReceiptPaperSize.a4Invoice,
            documentType: doc.documentType);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController c, String label,
      {TextInputType? inputType}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(controller: c, keyboardType: inputType,
      decoration: InputDecoration(labelText: label,
        border: const OutlineInputBorder(),
        isDense: true, filled: true, fillColor: Colors.white)),
  );

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(8), children: [
      const Text('SAGRO Documents',
        style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
      const Text('Quotations and invoices do not deduct stock or record payment.'),
      const SizedBox(height: 12),
      if (_error != null) Text(_error!,
          style: const TextStyle(color: Colors.red)),
      if (_notice != null) Text(_notice!,
          style: const TextStyle(color: Color(0xFF087A71))),
      _field(_customer, 'Customer / company'),
      _field(_item, 'Product / service'),
      Row(children: [
        Expanded(child: _field(_qty, 'Quantity',
            inputType: TextInputType.number)),
        const SizedBox(width: 10),
        Expanded(child: _field(_price, 'Unit price (USD)',
            inputType: const TextInputType.numberWithOptions(decimal:true))),
      ]),
      OutlinedButton.icon(
        onPressed: _busy ? null : _addItem,
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
      for (var i = 0; i < _lines.length; i++)
        ListTile(dense:true,
          title: Text(_lines[i].name),
          subtitle: Text(_lines[i].qty.toString() +
              ' x ' + _money(_lines[i].cents)),
          trailing: IconButton(
            onPressed: _busy ? null : () => setState(() => _lines.removeAt(i)),
            icon: const Icon(Icons.remove_circle_outline),
          )),
      const Divider(),
      Text('Total: ' + _money(_total),
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _busy ? null : () => _create(ReceiptDocumentType.quotation),
        icon: const Icon(Icons.request_quote),
        label: const Text('Create Quotation / Share PDF'),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: _busy ? null : () => _create(ReceiptDocumentType.invoice),
        icon: const Icon(Icons.description),
        label: const Text('Create Invoice / Share PDF'),
      ),
      const SizedBox(height: 20),
      const Text('Saved Quotations & Invoices',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      const Text('Local to this device; cloud sync is not yet supported.',
        style: TextStyle(fontSize: 12)),
      if (_saved.isEmpty)
        const Padding(padding: EdgeInsets.all(14),
          child: Text('No saved documents yet.')),
      for (final row in _saved) Card(child: ListTile(
        title: Text(row['number'].toString()),
        subtitle: Text(row['type'].toString() + ' • ' +
            row['created_at'].toString()),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'Print',
            icon: const Icon(Icons.print),
            onPressed: _busy ? null : () => _export(row, print:true),
          ),
          IconButton(
            tooltip: 'Share PDF',
            icon: const Icon(Icons.share),
            onPressed: _busy ? null : () => _export(row),
          ),
        ]),
      )),
    ],
  );
}

class _SagroLine {
  final String name;
  final int qty;
  final int cents;
  const _SagroLine(this.name, this.qty, this.cents);
  Map<String, dynamic> toJson() =>
      {'name': name, 'qty': qty, 'cents': cents};
  factory _SagroLine.fromJson(Map<String, dynamic> m) =>
      _SagroLine(m['name'].toString(),
        (m['qty'] as num).toInt(), (m['cents'] as num).toInt());
}
