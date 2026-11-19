import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import '../services/pdf_service.dart';
import '../services/receipt_service.dart';
import 'offline_license.dart';
import 'sagro_brand.dart';

bool licenceBusinessMatchesSagro(String id) =>
    id == SagroBrand.existingBusinessId;

class YolaOfflineStore {
  static final instance = YolaOfflineStore._();
  YolaOfflineStore._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final root = await getDatabasesPath();
    _db = await openDatabase(path.join(root, 'yola_android_offline_v1.db'),
      version: 1, onCreate: (db, _) async {
      await db.execute('''CREATE TABLE products (
        business_id TEXT NOT NULL, product_id TEXT NOT NULL,
        name TEXT NOT NULL, sku TEXT, barcode TEXT, category TEXT,
        price_cents INTEGER NOT NULL, cost_cents INTEGER NOT NULL,
        tax_bps INTEGER NOT NULL DEFAULT 0, stock_qty INTEGER NOT NULL,
        min_stock INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (business_id, product_id))''');
      await db.execute('''CREATE INDEX products_barcode ON products
        (business_id, barcode)''');
      await db.execute('''CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT, business_id TEXT NOT NULL,
        device_id TEXT NOT NULL, idempotency_key TEXT NOT NULL UNIQUE,
        receipt_no TEXT UNIQUE, cashier TEXT NOT NULL,
        customer_name TEXT NOT NULL, payment_method TEXT NOT NULL,
        subtotal INTEGER NOT NULL, tax INTEGER NOT NULL,
        discount INTEGER NOT NULL, total INTEGER NOT NULL,
        created_at TEXT NOT NULL)''');
      await db.execute('''CREATE TABLE sale_items (
        sale_id INTEGER NOT NULL, product_id TEXT NOT NULL,
        name TEXT NOT NULL, qty INTEGER NOT NULL,
        unit_price_cents INTEGER NOT NULL, cost_cents INTEGER NOT NULL,
        line_tax_cents INTEGER NOT NULL, line_total_cents INTEGER NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales(id))''');
      await db.execute('''CREATE TABLE outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT, business_id TEXT NOT NULL,
        event_key TEXT NOT NULL UNIQUE, event_type TEXT NOT NULL,
        payload TEXT NOT NULL, created_at TEXT NOT NULL,
        synced_at TEXT, attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT)''');
    });
    return _db!;
  }

  static int _integer(dynamic x, [int otherwise = 0]) =>
      x is num ? x.toInt() : int.tryParse(x?.toString() ?? '') ?? otherwise;
  static String _newId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2,'0')).join();
  }

  Future<int> pending() async {
    final info = await YolaLicence.instance.requireActive();
    final db = await database;
    final res = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM outbox WHERE business_id=? AND synced_at IS NULL',
      [info.businessId]);
    return _integer(res.first['n']);
  }

  Future<List<Map<String, Object?>>> products({String filter = ''}) async {
    final info = await YolaLicence.instance.requireActive();
    final db = await database;
    final search = '%${filter.trim()}%';
    return db.query('products',
      where: 'business_id = ? AND (name LIKE ? OR sku LIKE ? OR barcode LIKE ?)',
      whereArgs: [info.businessId, search, search, search],
      orderBy: 'name ASC');
  }

  Future<void> importOnlineCatalog({
    required String onlineBusinessId,
    required String onlineRole,
    required List<dynamic> onlineProducts,
  }) async {
    final license = await YolaLicence.instance.requireActive();
    if (license.businessId != onlineBusinessId) {
      throw StateError('Online account and this device licence belong to different businesses.');
    }
    if (!['owner','manager'].contains(onlineRole)) {
      throw StateError('Only an authorised Yola owner or manager can prepare offline inventory.');
    }
    final db = await database;
    await db.transaction((txn) async {
      final pending = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM outbox WHERE business_id=? AND synced_at IS NULL',
        [license.businessId])) ?? 0;
      if (pending > 0) {
        throw StateError('$pending offline changes need cloud reconciliation first. Stock refresh blocked to avoid overselling.');
      }
      // Keep this business isolated from any other licence/account.
      await txn.delete('products', where: 'business_id=?',
        whereArgs: [license.businessId]);
      final seen = <String>{};
      for (final raw in onlineProducts) {
        if (raw is! Map) throw StateError('Unexpected online inventory entry.');
        final p = raw.cast<String, dynamic>();
        final id = p['id']?.toString() ?? '';
        final name = p['name']?.toString() ?? '';
        final price = _integer(p['price_cents'], -1);
        final stock = _integer(p['stock_qty'], -1);
        if (id.isEmpty || name.isEmpty || price < 0 || stock < 0 || !seen.add(id)) {
          throw StateError('Online catalog contains invalid or duplicate product data.');
        }
        await txn.insert('products', {
          'business_id': license.businessId,
          'product_id': id, 'name': name, 'sku': p['sku']?.toString() ?? '',
          'barcode': p['barcode']?.toString() ?? '',
          'category': p['category']?.toString() ?? 'General',
          'price_cents': price,
          'cost_cents': max(0, _integer(p['cost_cents'])),
          'tax_bps': _integer(p['tax_bps']).clamp(0,10000),
          'stock_qty': stock,
          'min_stock': max(0, _integer(p['min_stock'])),
        });
      }
    });
  }

  Future<Map<String, dynamic>> checkout({
    required Map<String, int> quantities,
    required String cashier,
    String customer = '',
    String payment = 'cash',
    int discountCents = 0,
    String? checkoutKey,
  }) async {
    // Offline electronic payments cannot be verified. Only physically received
    // cash can be marked paid; do not manufacture card/mobile-money confirmation.
    final info = await YolaLicence.instance.requireActive();
    if (payment != 'cash') throw ArgumentError('Offline checkout supports cash only.');
    if (cashier.trim().isEmpty || quantities.isEmpty || quantities.length > 200) {
      throw ArgumentError('Enter cashier and at least one valid sale item.');
    }
    if (discountCents < 0) throw ArgumentError('Negative discounts are not allowed.');
    final key = checkoutKey ?? _newId();
    if (key.length < 16) throw ArgumentError('Invalid checkout idempotency key.');
    final db = await database;
    return db.transaction((txn) async {
      final previous = await txn.query('sales', where: 'idempotency_key=?',
        whereArgs: [key], limit: 1);
      if (previous.isNotEmpty) {
        if (previous.first['business_id'] != info.businessId) {
          throw StateError('Checkout key already belongs to another business.');
        }
        return previous.first.cast<String, dynamic>();
      }
      int subtotal = 0, rawTax = 0;
      final lines = <Map<String, dynamic>>[];
      for (final item in quantities.entries) {
        if (item.key.isEmpty || item.value < 1 || item.value > 100000) {
          throw ArgumentError('Invalid item quantity.');
        }
        final rows = await txn.query('products',
          where: 'business_id=? AND product_id=?',
          whereArgs: [info.businessId, item.key], limit: 1);
        if (rows.isEmpty) throw StateError('Product not in local inventory.');
        final p = rows.first;
        if (_integer(p['stock_qty']) < item.value) {
          throw StateError('Insufficient stock for ${p['name']}.');
        }
        final unit = _integer(p['price_cents']);
        final net = unit * item.value;
        final tax = (net * _integer(p['tax_bps']) / 10000).round();
        subtotal += net;
        rawTax += tax;
        lines.add({
          'product_id': item.key, 'name': p['name'],
          'qty': item.value, 'unit_price_cents': unit,
          'cost_cents': p['cost_cents'], 'line_tax_cents': tax,
          'line_total_cents': net,
        });
      }
      if (discountCents > subtotal) throw StateError('Discount exceeds sale subtotal.');
      final tax = subtotal == 0 ? 0 : (rawTax * (subtotal-discountCents) / subtotal).round();
      final total = subtotal - discountCents + tax;
      if (total < 0) throw StateError('Invalid sale total.');
      for (final l in lines) {
        final count = await txn.rawUpdate('''
          UPDATE products SET stock_qty=stock_qty-?
          WHERE business_id=? AND product_id=? AND stock_qty>=?''', [
          l['qty'], info.businessId, l['product_id'], l['qty']]);
        if (count != 1) throw StateError('Stock changed during checkout. Nothing was charged.');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final saleId = await txn.insert('sales',{
        'business_id': info.businessId, 'device_id': info.deviceId,
        'idempotency_key': key, 'cashier': cashier.trim(),
        'customer_name': customer.trim(), 'payment_method': payment,
        'subtotal': subtotal, 'tax': tax, 'discount': discountCents,
        'total': total, 'created_at': now,
      });
      final receipt = 'YA-${info.deviceId.split(':').last.substring(0, min(8,info.deviceId.split(':').last.length)).toUpperCase()}-${saleId.toString().padLeft(7,'0')}';
      await txn.update('sales', {'receipt_no': receipt},
        where: 'id=?', whereArgs: [saleId]);
      for (final l in lines) {
        await txn.insert('sale_items', {...l,'sale_id':saleId});
      }
      final payload = <String, dynamic>{
        'id': saleId, 'source':'yola-android',
        'idempotency_key':key, 'receipt_no':receipt,
        'total':total/100, 'subtotal':subtotal/100,
        'discount':discountCents/100, 'tax':tax/100,
        'payment_method':'cash', 'user_name':cashier.trim(),
        'customer_name':customer.trim(),
        'device_id':info.deviceId,
        'items': lines.map((l) => {
          'product_id':l['product_id'],'name':l['name'],
          'quantity':l['qty'],'total':(l['line_total_cents'] as int)/100,
        }).toList(),
      };
      await txn.insert('outbox',{
        'business_id': info.businessId,'event_key':'sale:$receipt',
        'event_type':'sale.completed','payload':jsonEncode(payload),
        'created_at':now,
      });
      return {'id':saleId,'receipt_no':receipt,'total':total,
        'subtotal':subtotal,'tax':tax,'discount':discountCents,
        'created_at':now,'payment_method':payment,'cashier':cashier.trim()};
    });
  }

  Future<List<Map<String, Object?>>> sales() async {
    final info = await YolaLicence.instance.requireActive();
    return (await database).query('sales',
      where:'business_id=?',whereArgs:[info.businessId],
      orderBy:'id DESC',limit:100);
  }

  Future<ReceiptModel> receipt(int saleId, {ReceiptPaperSize size = ReceiptPaperSize.mm80}) async {
    final license = await YolaLicence.instance.requireActive();
    final db = await database;
    final records = await db.query('sales',
      where:'id=? AND business_id=?',whereArgs:[saleId,license.businessId],limit:1);
    if (records.isEmpty) throw StateError('Receipt not found for this business.');
    final sale = records.first;
    final items = await db.query('sale_items',
      where:'sale_id=?',whereArgs:[saleId]);
    final branded = SagroBrand.existingBusinessId.isNotEmpty &&
        licenceBusinessMatchesSagro(license.businessId);
    return ReceiptModel(
      receiptNumber:sale['receipt_no']?.toString() ?? '',
      shopName: branded ? SagroBrand.displayName : license.businessName,
      shopAddress: branded ? SagroBrand.documentAddress : '',
      phoneNumber: branded ? SagroBrand.phone : '',
      logoPath: branded ? SagroBrand.logoAsset : null,
      cashierName:sale['cashier']?.toString() ?? '',
      paymentMethod:'cash',
      dateTime:DateTime.parse(sale['created_at'].toString()).toLocal(),
      items: items.map((i) => ReceiptItem(
        productName:i['name'].toString(),
        quantity:_integer(i['qty']),
        unitPrice:_integer(i['unit_price_cents'])/100,
        total:_integer(i['line_total_cents'])/100)).toList(),
      subtotal:_integer(sale['subtotal'])/100,
      discount:_integer(sale['discount'])/100,
      tax:_integer(sale['tax'])/100,
      grandTotal:_integer(sale['total'])/100,
      footerMessage: branded ? 'Thank you for choosing SAGRO.' :
          'Yola — Powered by Double Gee Tech',
      taxNumber:'',showLogo:branded,showQrCode:false,paperSize:size);
  }

  Future<void> printReceipt(int id, {ReceiptPaperSize size = ReceiptPaperSize.mm80}) async {
    final value = await receipt(id,size:size);
    await PdfService.instance.printReceiptPdf(value,paperSize:size);
  }

  Future<Map<String, dynamic>> syncPending() async {
    final license = await YolaLicence.instance.requireActive();
    final db = await database;
    final rows = await db.query('outbox',
      where:'business_id=? AND synced_at IS NULL',
      whereArgs:[license.businessId],orderBy:'id ASC',limit:100);
    int reconciled=0;
    String? error;
    for (final row in rows) {
      try {
        final res = await http.post(
          Uri.parse('https://yola-onboarding.vercel.app/api/sync/event'),
          headers: {'Content-Type':'application/json'},
          body: jsonEncode({
            'device_id':license.deviceId,
            'license_token':license.licenseToken,
            'event_key':row['event_key'],
            'event_type':row['event_type'],
            'branch_id':null,
            'payload':jsonDecode(row['payload'].toString()),
            'created_at':row['created_at'],
          })).timeout(const Duration(seconds:12));
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw StateError('Cloud HTTP ${res.statusCode}');
        }
        final ack = jsonDecode(res.body) as Map<String,dynamic>;
        if (ack['reconciled'] != true) {
          throw StateError('Cloud has not confirmed stock and accounting reconciliation.');
        }
        await db.update('outbox', {
          'synced_at':DateTime.now().toUtc().toIso8601String(),
          'last_error':null,
        },where:'id=?',whereArgs:[row['id']]);
        reconciled++;
      } catch (e) {
        error=e.toString();
        await db.rawUpdate('''UPDATE outbox
          SET attempts=attempts+1,last_error=? WHERE id=?''',[
          error.substring(0,min(400,error.length)),row['id']]);
        break; // strict event order, no false success and no data loss
      }
    }
    return {'reconciled':reconciled, 'remaining':await pending(),
      'error':error};
  }
}
