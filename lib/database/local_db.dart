import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  static final LocalDatabase instance =
      LocalDatabase._internal();

  factory LocalDatabase() => instance;

  LocalDatabase._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _initializeDatabase();
    return _database!;
  }

  Future<Database> _initializeDatabase() async {
    final dbPath = await getDatabasesPath();

    final path = join(
      dbPath,
      'double_gee_tech.db',
    );

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createTables,
    );
  }

  Future<void> _createTables(
    Database db,
    int version,
  ) async {

    // SHOPS
    await db.execute('''
      CREATE TABLE shops(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_code TEXT UNIQUE,
        shop_name TEXT,
        owner_name TEXT,
        whatsapp TEXT,
        activation_code TEXT,
        activated INTEGER,
        created_at TEXT
      )
    ''');

    // EMPLOYEES
    await db.execute('''
      CREATE TABLE employees(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id INTEGER,
        employee_name TEXT,
        employee_code TEXT UNIQUE,
        active INTEGER,
        sales_count INTEGER DEFAULT 0,
        revenue REAL DEFAULT 0,
        profit REAL DEFAULT 0,
        created_at TEXT
      )
    ''');

    // CATEGORIES
    await db.execute('''
      CREATE TABLE categories(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id INTEGER,
        category_name TEXT
      )
    ''');

    // PRODUCTS
    await db.execute('''
      CREATE TABLE products(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id INTEGER,
        category_id INTEGER,
        product_name TEXT,
        barcode TEXT,
        image_path TEXT,
        buying_price REAL,
        selling_price REAL,
        stock_quantity INTEGER,
        low_stock_limit INTEGER,
        marketplace_visible INTEGER DEFAULT 0
      )
    ''');

    // SALES
    await db.execute('''
      CREATE TABLE sales(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id INTEGER,
        employee_id INTEGER,
        customer_id INTEGER,
        receipt_number TEXT,
        total_amount REAL,
        total_profit REAL,
        sale_date TEXT
      )
    ''');

    // SALE ITEMS
    await db.execute('''
      CREATE TABLE sale_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER,
        product_id INTEGER,
        product_name TEXT,
        buying_price REAL,
        selling_price REAL,
        quantity INTEGER,
        total REAL,
        profit REAL
      )
    ''');

    // CUSTOMERS
    await db.execute('''
      CREATE TABLE customers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_name TEXT,
        phone_number TEXT,
        total_spent REAL DEFAULT 0,
        purchase_count INTEGER DEFAULT 0,
        created_at TEXT
      )
    ''');

    // CUSTOMER PURCHASE HISTORY
    await db.execute('''
      CREATE TABLE customer_purchases(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER,
        sale_id INTEGER,
        purchase_date TEXT,
        total_amount REAL
      )
    ''');

    // INVENTORY ALERTS
    await db.execute('''
      CREATE TABLE inventory_alerts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER,
        product_name TEXT,
        current_stock INTEGER,
        alert_date TEXT
      )
    ''');

    await db.execute('''
CREATE TABLE expenses(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  shop_id INTEGER,
  title TEXT,
  amount REAL,
  description TEXT,
  expense_date TEXT
)
''');
  }
  Future<int> createCategory({
    required int shopId,
    required String categoryName,
  }) async {
    final db = await database;

    return await db.insert(
      'categories',
      {
        'shop_id': shopId,
        'category_name': categoryName,
      },
    );
  }

  Future<List<Map<String, dynamic>>> getCategories(
      int shopId) async {
    final db = await database;

    return await db.query(
      'categories',
      where: 'shop_id = ?',
      whereArgs: [shopId],
      orderBy: 'category_name ASC',
    );
  }

  Future<int> renameCategory({
    required int categoryId,
    required String newName,
  }) async {
    final db = await database;

    return await db.update(
      'categories',
      {
        'category_name': newName,
      },
      where: 'id = ?',
      whereArgs: [categoryId],
    );
  }

  Future<int> deleteCategory(
      int categoryId) async {
    final db = await database;

    return await db.delete(
      'categories',
      where: 'id = ?',
      whereArgs: [categoryId],
    );
  }
  Future<int> createProduct(
      Map<String, dynamic> product) async {
    final db = await database;

    return await db.insert(
      'products',
      product,
    );
  }

  Future<List<Map<String, dynamic>>>
      getAllProducts(int shopId) async {
    final db = await database;

    return await db.query(
      'products',
      where: 'shop_id = ?',
      whereArgs: [shopId],
      orderBy: 'product_name ASC',
    );
  }
  Future<Map<String, dynamic>?> getProductById(
    int productId) async {

  final db = await database;

  final result = await db.query(
    'products',
    where: 'id = ?',
    whereArgs: [productId],
    limit: 1,
  );

  if (result.isEmpty) {
    return null;
  }

  return result.first;
}

  Future<List<Map<String, dynamic>>>
      searchProducts({
    required int shopId,
    required String keyword,
  }) async {
    final db = await database;

    return await db.query(
      'products',
      where:
          'shop_id = ? AND product_name LIKE ?',
      whereArgs: [
        shopId,
        '%$keyword%',
      ],
    );
  }

  Future<int> updateProduct(
      Map<String, dynamic> product) async {
    final db = await database;

    return await db.update(
      'products',
      product,
      where: 'id = ?',
      whereArgs: [product['id']],
    );
  }

  Future<int> deleteProduct(
      int productId) async {
    final db = await database;

    return await db.delete(
      'products',
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<int> reduceStock({
    required int productId,
    required int quantity,
  }) async {
    final db = await database;

    final product = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [productId],
    );

    if (product.isEmpty) {
      return 0;
    }

    final currentStock =
        product.first['stock_quantity'] as int;

    return await db.update(
      'products',
      {
        'stock_quantity':
            currentStock - quantity,
      },
      where: 'id = ?',
      whereArgs: [productId],
    );
  }
  Future<int> createEmployee(
      Map<String, dynamic> employee) async {
    final db = await database;

    return await db.insert(
      'employees',
      employee,
    );
  }

  Future<List<Map<String, dynamic>>>
      getEmployees(int shopId) async {
    final db = await database;

    return await db.query(
      'employees',
      where: 'shop_id = ?',
      whereArgs: [shopId],
      orderBy: 'employee_name ASC',
    );
  }

  Future<Map<String, dynamic>?>
      getEmployeeByCode(
          String employeeCode) async {
    final db = await database;

    final result = await db.query(
      'employees',
      where: 'employee_code = ?',
      whereArgs: [employeeCode],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return result.first;
  }

  Future<int> activateEmployee(
      int employeeId) async {
    final db = await database;

    return await db.update(
      'employees',
      {
        'active': 1,
      },
      where: 'id = ?',
      whereArgs: [employeeId],
    );
  }

  Future<int> deactivateEmployee(
      int employeeId) async {
    final db = await database;

    return await db.update(
      'employees',
      {
        'active': 0,
      },
      where: 'id = ?',
      whereArgs: [employeeId],
    );
  }
  Future<String> generateReceiptNumber() async {
    final db = await database;

    final result = await db.rawQuery(
      'SELECT COUNT(*) as total FROM sales',
    );

    final count =
        (result.first['total'] as int?) ?? 0;

    final nextNumber = count + 1;

    return 'DG-${nextNumber.toString().padLeft(6, '0')}';
  }
  Future<void> deductStock({
  required int productId,
  required int quantity,
}) async {
  final db = await database;

  final product =
      await getProductById(productId);

  if (product == null) return;

  final currentStock =
      product['stock_quantity'];

  await db.update(
    'products',
    {
      'stock_quantity':
          currentStock - quantity,
    },
    where: 'id = ?',
    whereArgs: [productId],
  );
}
Future<int> createSale(
  Map<String, dynamic> sale,
) async {
  final db = await database;

  return await db.insert(
    'sales',
    sale,
  );
}

Future<int> createSaleItem(
  Map<String, dynamic> item,
) async {
  final db = await database;

  return await db.insert(
    'sale_items',
    item,
  );
}

Future<void> updateEmployeeStats({
  required int employeeId,
  required double revenue,
  required double profit,
}) async {
  final db = await database;

  final employee = await db.query(
    'employees',
    where: 'id = ?',
    whereArgs: [employeeId],
    limit: 1,
  );

  if (employee.isEmpty) return;

  final currentRevenue =
      (employee.first['revenue'] as num?)
              ?.toDouble() ??
          0;

  final currentProfit =
      (employee.first['profit'] as num?)
              ?.toDouble() ??
          0;

  final currentSales =
      (employee.first['sales_count'] as int?) ??
          0;

  await db.update(
    'employees',
    {
      'revenue':
          currentRevenue + revenue,
      'profit':
          currentProfit + profit,
      'sales_count':
          currentSales + 1,
    },
    where: 'id = ?',
    whereArgs: [employeeId],
  );
}

Future<double> getTotalSales(
    int shopId) async {
  final db = await database;

  final result =
      await db.rawQuery(
    '''
    SELECT SUM(total_amount)
    AS total
    FROM sales
    WHERE shop_id = ?
    ''',
    [shopId],
  );

  return (result.first['total']
              as num?)
          ?.toDouble() ??
      0;
}

Future<double> getTotalProfit(
    int shopId) async {
  final db = await database;

  final result =
      await db.rawQuery(
    '''
    SELECT SUM(total_profit)
    AS total
    FROM sales
    WHERE shop_id = ?
    ''',
    [shopId],
  );

  return (result.first['total']
              as num?)
          ?.toDouble() ??
      0;
}

Future<int> getProductCount(
    int shopId) async {
  final db = await database;

  final result =
      await db.rawQuery(
    '''
    SELECT COUNT(*)
    AS total
    FROM products
    WHERE shop_id = ?
    ''',
    [shopId],
  );

  return (result.first['total']
          as int?) ??
      0;
}

Future<List<Map<String, dynamic>>>
    getLowStockProducts(
        int shopId) async {
  final db = await database;

  return await db.rawQuery(
    '''
    SELECT *
    FROM products
    WHERE shop_id = ?
    AND stock_quantity <= low_stock_limit
    ''',
    [shopId],
  );
}

Future<Map<String, dynamic>?>
    getTopEmployee(
        int shopId) async {
  final db = await database;

  final result = await db.query(
    'employees',
    where: 'shop_id = ?',
    whereArgs: [shopId],
    orderBy: 'profit DESC',
    limit: 1,
  );

  if (result.isEmpty) {
    return null;
  }

  return result.first;
}
Future<List<Map<String, dynamic>>> getAllSales(
    int shopId,
) async {
  final db = await database;

  return await db.query(
    'sales',
    where: 'shop_id = ?',
    whereArgs: [shopId],
    orderBy: 'sale_date DESC',
  );
}
Future<int> addExpense(
    Map<String, dynamic> expense) async {
  final db = await database;

  return await db.insert(
    'expenses',
    expense,
  );
}

Future<List<Map<String, dynamic>>>
    getExpenses(int shopId) async {
  final db = await database;

  return await db.query(
    'expenses',
    where: 'shop_id = ?',
    whereArgs: [shopId],
    orderBy: 'expense_date DESC',
  );
}

Future<double> getTotalExpenses(
    int shopId) async {
  final db = await database;

  final result = await db.rawQuery(
    '''
    SELECT SUM(amount)
    AS total
    FROM expenses
    WHERE shop_id = ?
    ''',
    [shopId],
  );

  return (result.first['total'] as num?)
          ?.toDouble() ??
      0;
}
  
}
