import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';

import 'offline_license.dart';
import 'offline_pin.dart';
import 'offline_store.dart';

/// One device-local authenticated cashier session. Constructors are private so
/// the caller cannot supply an arbitrary name or claim the owner role.
class SagroCashierSession {
  final String businessId;
  final int? workerId;
  final String name;
  final bool isAdmin;

  const SagroCashierSession._({
    required this.businessId,
    required this.workerId,
    required this.name,
    required this.isAdmin,
  });
}

/// SAGRO Android offline-only worker accounts. Cloud Yola roles must be
/// enforced separately by the cloud API, never by hiding browser links.
class SagroStaffAccess {
  static final SagroStaffAccess instance = SagroStaffAccess._();
  SagroStaffAccess._();

  final Pbkdf2 _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 150000,
    bits: 256,
  );

  Future<Database> _database() async {
    final db = await YolaOfflineStore.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sagro_workers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id TEXT NOT NULL,
        username TEXT NOT NULL COLLATE NOCASE,
        name TEXT NOT NULL,
        password_salt TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        failed_attempts INTEGER NOT NULL DEFAULT 0,
        locked_until TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(business_id, username)
      )
    ''');
    return db;
  }

  Future<SagroCashierSession> loginAdmin(String pin) async {
    await YolaOfflinePin.instance.verify(pin);
    final license = await YolaLicence.instance.requireActive();
    return SagroCashierSession._(
      businessId: license.businessId,
      workerId: null,
      name: 'Owner',
      isAdmin: true,
    );
  }

  Future<SagroCashierSession> loginWorker(
      String username, String password) async {
    final license = await YolaLicence.instance.requireActive();
    final db = await _database();
    final rows = await db.query('sagro_workers',
      where: 'business_id=? AND username=?',
      whereArgs: [license.businessId, username.trim().toLowerCase()],
      limit: 1);
    if (rows.isEmpty) throw StateError('Incorrect worker credentials.');
    final worker = rows.first;
    if (worker['active'] != 1) {
      throw StateError('Worker account is inactive. Contact the administrator.');
    }
    final until = DateTime.tryParse((worker['locked_until'] ?? '').toString());
    if (until != null && DateTime.now().toUtc().isBefore(until.toUtc())) {
      throw StateError('Too many attempts. Try again later.');
    }
    final salt = base64Decode(worker['password_salt'] as String);
    final expected = base64Decode(worker['password_hash'] as String);
    final key = await _kdf.deriveKeyFromPassword(password: password, nonce: salt);
    final actual = await key.extractBytes();
    var difference = actual.length ^ expected.length;
    for (var i = 0; i < min(actual.length, expected.length); i++) {
      difference |= actual[i] ^ expected[i];
    }
    if (difference != 0) {
      final attempts = (worker['failed_attempts'] as int) + 1;
      await db.update('sagro_workers', {
        'failed_attempts': attempts >= 5 ? 0 : attempts,
        'locked_until': attempts >= 5
          ? DateTime.now().toUtc().add(const Duration(minutes: 15)).toIso8601String()
          : null,
      }, where: 'id=? AND business_id=?',
        whereArgs: [worker['id'], license.businessId]);
      throw StateError('Incorrect worker credentials.');
    }
    await db.update('sagro_workers', {
      'failed_attempts': 0, 'locked_until': null,
    }, where: 'id=? AND business_id=?',
       whereArgs: [worker['id'], license.businessId]);
    return SagroCashierSession._(
      businessId: license.businessId,
      workerId: worker['id'] as int,
      name: worker['name'] as String,
      isAdmin: false,
    );
  }

  Future<void> requireAdmin(SagroCashierSession session) async {
    final license = await YolaLicence.instance.requireActive();
    if (!session.isAdmin || session.businessId != license.businessId) {
      throw StateError('Only the SAGRO administrator can access this feature.');
    }
  }

  Future<void> requireCanSell(SagroCashierSession session) async {
    final license = await YolaLicence.instance.requireActive();
    if (session.businessId != license.businessId) {
      throw StateError('Cashier account belongs to another business.');
    }
    if (session.isAdmin) return;
    final id = session.workerId;
    if (id == null) throw StateError('Sign in before selling.');
    final db = await _database();
    final workers = await db.query('sagro_workers',
      columns: ['active'], where: 'id=? AND business_id=?',
      whereArgs: [id, license.businessId], limit: 1);
    if (workers.isEmpty || workers.first['active'] != 1) {
      throw StateError('Worker account is inactive. Contact the administrator.');
    }
  }

  Future<void> createWorker(SagroCashierSession admin, {
    required String name,
    required String username,
    required String password,
  }) async {
    await requireAdmin(admin);
    final cleanName = name.trim();
    final cleanUsername = username.trim().toLowerCase();
    if (cleanName.length < 2 || cleanName.length > 80) {
      throw ArgumentError('Enter the worker name (2-80 characters).');
    }
    if (!RegExp(r'^[a-z0-9._-]{3,32}$').hasMatch(cleanUsername)) {
      throw ArgumentError('Use a username of 3-32 letters, numbers, dots, underscores or hyphens.');
    }
    if (password.length < 8 || password.length > 128) {
      throw ArgumentError('Use a worker password of 8-128 characters.');
    }
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final key = await _kdf.deriveKeyFromPassword(password: password, nonce: salt);
    final hash = await key.extractBytes();
    final db = await _database();
    try {
      await db.insert('sagro_workers', {
        'business_id': admin.businessId,
        'username': cleanUsername,
        'name': cleanName,
        'password_salt': base64Encode(salt),
        'password_hash': base64Encode(hash),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } on DatabaseException {
      throw StateError('This worker username already exists.');
    }
  }

  Future<List<Map<String, Object?>>> workers(
      SagroCashierSession admin) async {
    await requireAdmin(admin);
    return (await _database()).query('sagro_workers',
      columns: ['id', 'username', 'name', 'active', 'created_at'],
      where: 'business_id=?', whereArgs: [admin.businessId],
      orderBy: 'name COLLATE NOCASE ASC');
  }

  Future<void> setWorkerActive(
      SagroCashierSession admin, int workerId, bool active) async {
    await requireAdmin(admin);
    final count = await (await _database()).update(
      'sagro_workers', {
        'active': active ? 1 : 0,
        'failed_attempts': 0,
        'locked_until': null,
      },
      where: 'id=? AND business_id=?',
      whereArgs: [workerId, admin.businessId]);
    if (count != 1) throw StateError('Worker account not found.');
  }

  /// Aggregation is device-local. Cloud reports require per-worker server
  /// identities and role-protected server endpoints.
  Future<List<Map<String, Object?>>> performance(
      SagroCashierSession admin) async {
    await requireAdmin(admin);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day)
        .toUtc().toIso8601String();
    final week = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6)).toUtc().toIso8601String();
    final month = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 29)).toUtc().toIso8601String();
    return (await _database()).rawQuery('''
      SELECT w.id, w.name, w.username, w.active,
        COUNT(s.id) AS sales_count,
        COALESCE(SUM(s.total), 0) AS sales_total,
        COALESCE(SUM(CASE WHEN s.created_at >= ? THEN 1 ELSE 0 END), 0) AS today_count,
        COALESCE(SUM(CASE WHEN s.created_at >= ? THEN s.total ELSE 0 END), 0) AS today_total,
        COALESCE(SUM(CASE WHEN s.created_at >= ? THEN 1 ELSE 0 END), 0) AS week_count,
        COALESCE(SUM(CASE WHEN s.created_at >= ? THEN s.total ELSE 0 END), 0) AS week_total,
        COALESCE(SUM(CASE WHEN s.created_at >= ? THEN 1 ELSE 0 END), 0) AS month_count,
        COALESCE(SUM(CASE WHEN s.created_at >= ? THEN s.total ELSE 0 END), 0) AS month_total,
        MAX(s.created_at) AS last_sale
      FROM sagro_workers w
      LEFT JOIN sales s
        ON s.staff_id = w.id AND s.business_id = w.business_id
      WHERE w.business_id=?
      GROUP BY w.id
      ORDER BY today_total DESC, w.name COLLATE NOCASE ASC
    ''', [today, today, week, week, month, month, admin.businessId]);
  }
}
