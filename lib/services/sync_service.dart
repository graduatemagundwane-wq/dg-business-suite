import '../database/local_db.dart';

enum SyncEntity {
  products,
  inventory,
  sales,
  customers,
  marketplace,
  employees,
}

enum SyncState {
  idle,
  syncing,
  success,
  offline,
  failed,
}

class SyncEntityStatus {
  final SyncEntity entity;
  final SyncState state;
  final DateTime? lastSyncAt;
  final int pendingChanges;
  final String message;

  const SyncEntityStatus({
    required this.entity,
    required this.state,
    this.lastSyncAt,
    this.pendingChanges = 0,
    this.message = 'Waiting for cloud sync',
  });
}

class SyncSnapshot {
  final SyncState state;
  final DateTime generatedAt;
  final List<SyncEntityStatus> entities;

  const SyncSnapshot({
    required this.state,
    required this.generatedAt,
    required this.entities,
  });

  DateTime? get lastSyncAt {
    final synced = entities
        .where((entity) => entity.lastSyncAt != null)
        .map((entity) => entity.lastSyncAt!)
        .toList();

    if (synced.isEmpty) return null;
    synced.sort();
    return synced.last;
  }
}

class SyncService {
  static final SyncService instance = SyncService._internal();

  factory SyncService() => instance;

  SyncService._internal();

  final Map<SyncEntity, SyncEntityStatus> _cache = {};

  Future<SyncSnapshot> getSnapshot({int shopId = 1}) async {
    final db = await LocalDatabase.instance.database;
    final productCount = await _count(db, 'products', shopId: shopId);
    final saleCount = await _count(db, 'sales', shopId: shopId);
    final customerCount = await _count(db, 'customers');
    final employeeCount = await _count(db, 'employees', shopId: shopId);
    final marketplaceCount = await _marketplaceCount(db, shopId);
    final inventoryCount = productCount;
    final generatedAt = DateTime.now();

    final entities = [
      _status(SyncEntity.products, productCount, generatedAt),
      _status(SyncEntity.inventory, inventoryCount, generatedAt),
      _status(SyncEntity.sales, saleCount, generatedAt),
      _status(SyncEntity.customers, customerCount, generatedAt),
      _status(SyncEntity.marketplace, marketplaceCount, generatedAt),
      _status(SyncEntity.employees, employeeCount, generatedAt),
    ];

    return SyncSnapshot(
      state: SyncState.idle,
      generatedAt: generatedAt,
      entities: entities,
    );
  }

  Future<SyncSnapshot> syncNow({int shopId = 1}) async {
    final snapshot = await getSnapshot(shopId: shopId);
    final syncedAt = DateTime.now();

    for (final entity in snapshot.entities) {
      _cache[entity.entity] = SyncEntityStatus(
        entity: entity.entity,
        state: SyncState.success,
        lastSyncAt: syncedAt,
        pendingChanges: entity.pendingChanges,
        message: 'Local data prepared for cloud upload',
      );
    }

    return SyncSnapshot(
      state: SyncState.success,
      generatedAt: syncedAt,
      entities: _cache.values.toList(),
    );
  }

  SyncEntityStatus _status(
    SyncEntity entity,
    int pendingChanges,
    DateTime generatedAt,
  ) {
    final cached = _cache[entity];

    return SyncEntityStatus(
      entity: entity,
      state: cached?.state ?? SyncState.idle,
      lastSyncAt: cached?.lastSyncAt,
      pendingChanges: pendingChanges,
      message: cached?.message ?? 'Offline-first data ready for sync',
    );
  }

  Future<int> _count(
    dynamic db,
    String table, {
    int? shopId,
  }) async {
    final rows = shopId == null
        ? await db.rawQuery('SELECT COUNT(*) AS total FROM $table')
        : await db.rawQuery(
            'SELECT COUNT(*) AS total FROM $table WHERE shop_id = ?',
            [shopId],
          );

    return _asInt(rows.first['total']);
  }

  Future<int> _marketplaceCount(dynamic db, int shopId) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM products
      WHERE shop_id = ? AND marketplace_visible = 1
      ''',
      [shopId],
    );

    return _asInt(rows.first['total']);
  }
}

extension SyncEntityLabel on SyncEntity {
  String get label {
    switch (this) {
      case SyncEntity.products:
        return 'Products';
      case SyncEntity.inventory:
        return 'Inventory';
      case SyncEntity.sales:
        return 'Sales';
      case SyncEntity.customers:
        return 'Customers';
      case SyncEntity.marketplace:
        return 'Marketplace';
      case SyncEntity.employees:
        return 'Employees';
    }
  }
}

extension SyncStateLabel on SyncState {
  String get label {
    switch (this) {
      case SyncState.idle:
        return 'Ready';
      case SyncState.syncing:
        return 'Syncing';
      case SyncState.success:
        return 'Synced';
      case SyncState.offline:
        return 'Offline';
      case SyncState.failed:
        return 'Failed';
    }
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
