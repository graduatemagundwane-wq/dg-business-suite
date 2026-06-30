import '../database/local_db.dart';

enum ReportPeriod {
  daily,
  weekly,
  monthly,
  yearly,
}

class PeriodRange {
  final DateTime start;
  final DateTime end;

  const PeriodRange({
    required this.start,
    required this.end,
  });
}

class EmployeePerformance {
  final String name;
  final int salesCount;
  final double revenue;
  final double profit;

  const EmployeePerformance({
    required this.name,
    required this.salesCount,
    required this.revenue,
    required this.profit,
  });

  static const empty = EmployeePerformance(
    name: 'No sales yet',
    salesCount: 0,
    revenue: 0,
    profit: 0,
  );
}

class ProductPerformance {
  final String name;
  final int quantitySold;
  final double revenue;
  final double profit;

  const ProductPerformance({
    required this.name,
    required this.quantitySold,
    required this.revenue,
    required this.profit,
  });

  static const empty = ProductPerformance(
    name: 'No product sales yet',
    quantitySold: 0,
    revenue: 0,
    profit: 0,
  );
}

class TrendPoint {
  final String label;
  final double sales;
  final double profit;

  const TrendPoint({
    required this.label,
    required this.sales,
    required this.profit,
  });
}

class BusinessHealth {
  final double salesGrowth;
  final double profitGrowth;
  final double inventoryHealth;
  final double stockValue;
  final int fastMovingProducts;
  final int slowMovingProducts;
  final int score;

  const BusinessHealth({
    required this.salesGrowth,
    required this.profitGrowth,
    required this.inventoryHealth,
    required this.stockValue,
    required this.fastMovingProducts,
    required this.slowMovingProducts,
    required this.score,
  });
}

class ReportSummary {
  final ReportPeriod period;
  final String title;
  final double sales;
  final double profit;
  final double expenses;
  final double netProfit;
  final EmployeePerformance bestEmployee;
  final ProductPerformance bestProduct;
  final int lowStockItems;
  final int outOfStockItems;
  final double inventoryValue;

  const ReportSummary({
    required this.period,
    required this.title,
    required this.sales,
    required this.profit,
    required this.expenses,
    required this.netProfit,
    required this.bestEmployee,
    required this.bestProduct,
    required this.lowStockItems,
    required this.outOfStockItems,
    required this.inventoryValue,
  });
}

class DashboardAnalytics {
  final double todaySales;
  final double todayProfit;
  final double weeklySales;
  final double weeklyProfit;
  final double monthlySales;
  final double monthlyProfit;
  final double totalInventoryValue;
  final int lowStockItems;
  final int outOfStockItems;
  final int totalCustomers;
  final int totalEmployees;
  final int totalProducts;
  final EmployeePerformance bestEmployeeToday;
  final EmployeePerformance bestEmployeeWeek;
  final EmployeePerformance bestEmployeeMonth;
  final ProductPerformance mostSoldToday;
  final ProductPerformance mostSoldWeek;
  final ProductPerformance mostSoldMonth;
  final BusinessHealth health;
  final List<TrendPoint> salesTrend;
  final List<ProductPerformance> topProducts;
  final List<EmployeePerformance> topEmployees;

  const DashboardAnalytics({
    required this.todaySales,
    required this.todayProfit,
    required this.weeklySales,
    required this.weeklyProfit,
    required this.monthlySales,
    required this.monthlyProfit,
    required this.totalInventoryValue,
    required this.lowStockItems,
    required this.outOfStockItems,
    required this.totalCustomers,
    required this.totalEmployees,
    required this.totalProducts,
    required this.bestEmployeeToday,
    required this.bestEmployeeWeek,
    required this.bestEmployeeMonth,
    required this.mostSoldToday,
    required this.mostSoldWeek,
    required this.mostSoldMonth,
    required this.health,
    required this.salesTrend,
    required this.topProducts,
    required this.topEmployees,
  });
}

class _DashboardCacheEntry {
  final DateTime createdAt;
  final DashboardAnalytics data;

  const _DashboardCacheEntry({
    required this.createdAt,
    required this.data,
  });
}

class DashboardService {
  static final DashboardService instance = DashboardService._internal();

  factory DashboardService() => instance;

  DashboardService._internal();

  final Map<int, _DashboardCacheEntry> _analyticsCache = {};

  Future<Map<String, dynamic>> getDashboardData(int shopId) async {
    final analytics = await getDashboardAnalytics(shopId);

    return {
      'total_sales': analytics.monthlySales,
      'total_profit': analytics.monthlyProfit,
      'product_count': analytics.totalProducts,
      'low_stock_count': analytics.lowStockItems,
      'top_employee': {
        'employee_name': analytics.bestEmployeeMonth.name,
        'sales_count': analytics.bestEmployeeMonth.salesCount,
        'revenue': analytics.bestEmployeeMonth.revenue,
        'profit': analytics.bestEmployeeMonth.profit,
      },
    };
  }

  Future<DashboardAnalytics> getDashboardAnalytics(int shopId) async {
    final cached = _analyticsCache[shopId];
    if (cached != null &&
        DateTime.now().difference(cached.createdAt).inSeconds < 30) {
      return cached.data;
    }

    final today = _rangeFor(ReportPeriod.daily);
    final week = _rangeFor(ReportPeriod.weekly);
    final month = _rangeFor(ReportPeriod.monthly);
    final previousWeek = _previousRange(week);
    final previousMonth = _previousRange(month);

    final todayTotals = await _salesTotals(shopId, today);
    final weekTotals = await _salesTotals(shopId, week);
    final monthTotals = await _salesTotals(shopId, month);
    final previousWeekTotals = await _salesTotals(shopId, previousWeek);
    final previousMonthTotals = await _salesTotals(shopId, previousMonth);
    final inventory = await _inventoryStats(shopId);

    final health = _buildHealth(
      currentSales: weekTotals.sales,
      previousSales: previousWeekTotals.sales,
      currentProfit: monthTotals.profit,
      previousProfit: previousMonthTotals.profit,
      totalProducts: inventory.totalProducts,
      lowStock: inventory.lowStockItems,
      outOfStock: inventory.outOfStockItems,
      stockValue: inventory.value,
      fastMovingProducts: await _productMovementCount(shopId, month, fast: true),
      slowMovingProducts: await _productMovementCount(shopId, month, fast: false),
    );

    final analytics = DashboardAnalytics(
      todaySales: todayTotals.sales,
      todayProfit: todayTotals.profit,
      weeklySales: weekTotals.sales,
      weeklyProfit: weekTotals.profit,
      monthlySales: monthTotals.sales,
      monthlyProfit: monthTotals.profit,
      totalInventoryValue: inventory.value,
      lowStockItems: inventory.lowStockItems,
      outOfStockItems: inventory.outOfStockItems,
      totalCustomers: await _countRows('customers'),
      totalEmployees: await _countRows(
        'employees',
        where: 'shop_id = ?',
        whereArgs: [shopId],
      ),
      totalProducts: inventory.totalProducts,
      bestEmployeeToday: await _bestEmployee(shopId, today),
      bestEmployeeWeek: await _bestEmployee(shopId, week),
      bestEmployeeMonth: await _bestEmployee(shopId, month),
      mostSoldToday: await _bestProduct(shopId, today),
      mostSoldWeek: await _bestProduct(shopId, week),
      mostSoldMonth: await _bestProduct(shopId, month),
      health: health,
      salesTrend: await _trend(shopId),
      topProducts: await _topProducts(shopId, month),
      topEmployees: await _topEmployees(shopId, month),
    );

    _analyticsCache[shopId] = _DashboardCacheEntry(
      createdAt: DateTime.now(),
      data: analytics,
    );

    return analytics;
  }

  Future<List<ReportSummary>> getReports(int shopId) async {
    final periods = [
      ReportPeriod.daily,
      ReportPeriod.weekly,
      ReportPeriod.monthly,
      ReportPeriod.yearly,
    ];

    final reports = <ReportSummary>[];

    for (final period in periods) {
      reports.add(await getReport(shopId: shopId, period: period));
    }

    return reports;
  }

  Future<ReportSummary> getReport({
    required int shopId,
    required ReportPeriod period,
  }) async {
    final range = _rangeFor(period);
    final totals = await _salesTotals(shopId, range);
    final expenses = await _expensesTotal(shopId, range);
    final inventory = await _inventoryStats(shopId);

    return ReportSummary(
      period: period,
      title: _periodTitle(period),
      sales: totals.sales,
      profit: totals.profit,
      expenses: expenses,
      netProfit: totals.profit - expenses,
      bestEmployee: await _bestEmployee(shopId, range),
      bestProduct: await _bestProduct(shopId, range),
      lowStockItems: inventory.lowStockItems,
      outOfStockItems: inventory.outOfStockItems,
      inventoryValue: inventory.value,
    );
  }

  Future<List<Map<String, dynamic>>> getRecentSales(int shopId) async {
    await LocalDatabase.instance.ensureSalesCashierColumns();
    final db = await LocalDatabase.instance.database;

    return db.rawQuery(
      '''
      SELECT
        s.*,
        COALESCE(s.cashier_name, e.employee_name) AS employee_name
      FROM sales s
      LEFT JOIN employees e ON e.id = s.employee_id
      WHERE s.shop_id = ?
      ORDER BY s.sale_date DESC
      LIMIT 100
      ''',
      [shopId],
    );
  }

  Future<List<Map<String, dynamic>>> getLowStockItems(int shopId) async {
    return await LocalDatabase.instance.getLowStockProducts(shopId);
  }

  Future<Map<String, dynamic>?> getBestEmployee(int shopId) async {
    return await LocalDatabase.instance.getTopEmployee(shopId);
  }

  PeriodRange _rangeFor(ReportPeriod period) {
    final now = DateTime.now();

    switch (period) {
      case ReportPeriod.daily:
        final start = DateTime(now.year, now.month, now.day);
        return PeriodRange(start: start, end: start.add(const Duration(days: 1)));
      case ReportPeriod.weekly:
        final today = DateTime(now.year, now.month, now.day);
        final start = today.subtract(Duration(days: today.weekday - 1));
        return PeriodRange(start: start, end: start.add(const Duration(days: 7)));
      case ReportPeriod.monthly:
        final start = DateTime(now.year, now.month);
        return PeriodRange(start: start, end: DateTime(now.year, now.month + 1));
      case ReportPeriod.yearly:
        final start = DateTime(now.year);
        return PeriodRange(start: start, end: DateTime(now.year + 1));
    }
  }

  PeriodRange _previousRange(PeriodRange range) {
    final duration = range.end.difference(range.start);
    final start = range.start.subtract(duration);
    return PeriodRange(start: start, end: range.start);
  }

  String _periodTitle(ReportPeriod period) {
    switch (period) {
      case ReportPeriod.daily:
        return 'Daily Report';
      case ReportPeriod.weekly:
        return 'Weekly Report';
      case ReportPeriod.monthly:
        return 'Monthly Report';
      case ReportPeriod.yearly:
        return 'Yearly Report';
    }
  }

  Future<_SalesTotals> _salesTotals(int shopId, PeriodRange range) async {
    final db = await LocalDatabase.instance.database;
    final result = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(total_amount), 0) AS sales,
        COALESCE(SUM(total_profit), 0) AS profit
      FROM sales
      WHERE shop_id = ?
      AND sale_date >= ?
      AND sale_date < ?
      ''',
      [shopId, range.start.toIso8601String(), range.end.toIso8601String()],
    );

    return _SalesTotals(
      sales: _asDouble(result.first['sales']),
      profit: _asDouble(result.first['profit']),
    );
  }

  Future<double> _expensesTotal(int shopId, PeriodRange range) async {
    final db = await LocalDatabase.instance.database;
    final result = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM expenses
      WHERE shop_id = ?
      AND expense_date >= ?
      AND expense_date < ?
      ''',
      [shopId, range.start.toIso8601String(), range.end.toIso8601String()],
    );

    return _asDouble(result.first['total']);
  }

  Future<_InventoryStats> _inventoryStats(int shopId) async {
    final db = await LocalDatabase.instance.database;
    final result = await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS total_products,
        COALESCE(SUM(stock_quantity * buying_price), 0) AS inventory_value,
        SUM(CASE WHEN stock_quantity <= low_stock_limit AND stock_quantity > 0 THEN 1 ELSE 0 END) AS low_stock,
        SUM(CASE WHEN stock_quantity <= 0 THEN 1 ELSE 0 END) AS out_of_stock
      FROM products
      WHERE shop_id = ?
      ''',
      [shopId],
    );

    final row = result.first;
    return _InventoryStats(
      totalProducts: _asInt(row['total_products']),
      value: _asDouble(row['inventory_value']),
      lowStockItems: _asInt(row['low_stock']),
      outOfStockItems: _asInt(row['out_of_stock']),
    );
  }

  Future<int> _countRows(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await LocalDatabase.instance.database;
    final result = await db.query(
      table,
      columns: const ['COUNT(*) AS total'],
      where: where,
      whereArgs: whereArgs,
    );

    return _asInt(result.first['total']);
  }

  Future<EmployeePerformance> _bestEmployee(
    int shopId,
    PeriodRange range,
  ) async {
    final db = await LocalDatabase.instance.database;
    final result = await db.rawQuery(
      '''
      SELECT
        COALESCE(e.employee_name, 'Unknown Employee') AS employee_name,
        COUNT(s.id) AS sales_count,
        COALESCE(SUM(s.total_amount), 0) AS revenue,
        COALESCE(SUM(s.total_profit), 0) AS profit
      FROM sales s
      LEFT JOIN employees e ON e.id = s.employee_id
      WHERE s.shop_id = ?
      AND s.sale_date >= ?
      AND s.sale_date < ?
      GROUP BY s.employee_id
      ORDER BY profit DESC, revenue DESC, sales_count DESC
      LIMIT 1
      ''',
      [shopId, range.start.toIso8601String(), range.end.toIso8601String()],
    );

    if (result.isEmpty) return EmployeePerformance.empty;
    final row = result.first;
    return EmployeePerformance(
      name: row['employee_name'].toString(),
      salesCount: _asInt(row['sales_count']),
      revenue: _asDouble(row['revenue']),
      profit: _asDouble(row['profit']),
    );
  }

  Future<ProductPerformance> _bestProduct(
    int shopId,
    PeriodRange range,
  ) async {
    final db = await LocalDatabase.instance.database;
    final result = await db.rawQuery(
      '''
      SELECT
        si.product_name,
        COALESCE(SUM(si.quantity), 0) AS quantity_sold,
        COALESCE(SUM(si.total), 0) AS revenue,
        COALESCE(SUM(si.profit), 0) AS profit
      FROM sale_items si
      INNER JOIN sales s ON s.id = si.sale_id
      WHERE s.shop_id = ?
      AND s.sale_date >= ?
      AND s.sale_date < ?
      GROUP BY si.product_id, si.product_name
      ORDER BY quantity_sold DESC, revenue DESC
      LIMIT 1
      ''',
      [shopId, range.start.toIso8601String(), range.end.toIso8601String()],
    );

    if (result.isEmpty) return ProductPerformance.empty;
    final row = result.first;
    return ProductPerformance(
      name: row['product_name'].toString(),
      quantitySold: _asInt(row['quantity_sold']),
      revenue: _asDouble(row['revenue']),
      profit: _asDouble(row['profit']),
    );
  }

  Future<List<ProductPerformance>> _topProducts(
    int shopId,
    PeriodRange range,
  ) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        si.product_name,
        COALESCE(SUM(si.quantity), 0) AS quantity_sold,
        COALESCE(SUM(si.total), 0) AS revenue,
        COALESCE(SUM(si.profit), 0) AS profit
      FROM sale_items si
      INNER JOIN sales s ON s.id = si.sale_id
      WHERE s.shop_id = ?
      AND s.sale_date >= ?
      AND s.sale_date < ?
      GROUP BY si.product_id, si.product_name
      ORDER BY quantity_sold DESC, revenue DESC
      LIMIT 5
      ''',
      [shopId, range.start.toIso8601String(), range.end.toIso8601String()],
    );

    return rows
        .map(
          (row) => ProductPerformance(
            name: row['product_name'].toString(),
            quantitySold: _asInt(row['quantity_sold']),
            revenue: _asDouble(row['revenue']),
            profit: _asDouble(row['profit']),
          ),
        )
        .toList();
  }

  Future<List<EmployeePerformance>> _topEmployees(
    int shopId,
    PeriodRange range,
  ) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(e.employee_name, 'Unknown Employee') AS employee_name,
        COUNT(s.id) AS sales_count,
        COALESCE(SUM(s.total_amount), 0) AS revenue,
        COALESCE(SUM(s.total_profit), 0) AS profit
      FROM sales s
      LEFT JOIN employees e ON e.id = s.employee_id
      WHERE s.shop_id = ?
      AND s.sale_date >= ?
      AND s.sale_date < ?
      GROUP BY s.employee_id
      ORDER BY profit DESC, revenue DESC, sales_count DESC
      LIMIT 5
      ''',
      [shopId, range.start.toIso8601String(), range.end.toIso8601String()],
    );

    return rows
        .map(
          (row) => EmployeePerformance(
            name: row['employee_name'].toString(),
            salesCount: _asInt(row['sales_count']),
            revenue: _asDouble(row['revenue']),
            profit: _asDouble(row['profit']),
          ),
        )
        .toList();
  }

  Future<int> _productMovementCount(
    int shopId,
    PeriodRange range, {
    required bool fast,
  }) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT p.id, COALESCE(SUM(si.quantity), 0) AS sold
      FROM products p
      LEFT JOIN sale_items si ON si.product_id = p.id
      LEFT JOIN sales s ON s.id = si.sale_id
        AND s.sale_date >= ?
        AND s.sale_date < ?
      WHERE p.shop_id = ?
      GROUP BY p.id
      ''',
      [range.start.toIso8601String(), range.end.toIso8601String(), shopId],
    );

    return rows.where((row) {
      final sold = _asInt(row['sold']);
      return fast ? sold >= 5 : sold == 0;
    }).length;
  }

  Future<List<TrendPoint>> _trend(int shopId) async {
    final db = await LocalDatabase.instance.database;
    final start = DateTime.now().subtract(const Duration(days: 6));
    final startDay = DateTime(start.year, start.month, start.day);
    final rows = await db.rawQuery(
      '''
      SELECT
        substr(sale_date, 1, 10) AS day,
        COALESCE(SUM(total_amount), 0) AS sales,
        COALESCE(SUM(total_profit), 0) AS profit
      FROM sales
      WHERE shop_id = ?
      AND sale_date >= ?
      GROUP BY substr(sale_date, 1, 10)
      ''',
      [shopId, startDay.toIso8601String()],
    );

    final byDay = {
      for (final row in rows)
        row['day'].toString(): TrendPoint(
          label: row['day'].toString().substring(5),
          sales: _asDouble(row['sales']),
          profit: _asDouble(row['profit']),
        ),
    };

    return List.generate(7, (index) {
      final day = startDay.add(Duration(days: index));
      final key = day.toIso8601String().substring(0, 10);
      return byDay[key] ??
          TrendPoint(
            label: key.substring(5),
            sales: 0,
            profit: 0,
          );
    });
  }

  BusinessHealth _buildHealth({
    required double currentSales,
    required double previousSales,
    required double currentProfit,
    required double previousProfit,
    required int totalProducts,
    required int lowStock,
    required int outOfStock,
    required double stockValue,
    required int fastMovingProducts,
    required int slowMovingProducts,
  }) {
    final salesGrowth = _growth(currentSales, previousSales);
    final profitGrowth = _growth(currentProfit, previousProfit);
    final inventoryHealth = totalProducts == 0
        ? 0.0
        : ((totalProducts - lowStock - outOfStock) / totalProducts * 100)
            .clamp(0, 100)
            .toDouble();
    final score = ((inventoryHealth * 0.45) +
            ((salesGrowth.clamp(-100, 100) + 100) / 2 * 0.25) +
            ((profitGrowth.clamp(-100, 100) + 100) / 2 * 0.2) +
            (fastMovingProducts > 0 ? 10 : 0))
        .round()
        .clamp(0, 100);

    return BusinessHealth(
      salesGrowth: salesGrowth,
      profitGrowth: profitGrowth,
      inventoryHealth: inventoryHealth,
      stockValue: stockValue,
      fastMovingProducts: fastMovingProducts,
      slowMovingProducts: slowMovingProducts,
      score: score,
    );
  }

  double _growth(double current, double previous) {
    if (previous == 0) {
      return current > 0 ? 100 : 0;
    }

    return ((current - previous) / previous) * 100;
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _SalesTotals {
  final double sales;
  final double profit;

  const _SalesTotals({
    required this.sales,
    required this.profit,
  });
}

class _InventoryStats {
  final int totalProducts;
  final double value;
  final int lowStockItems;
  final int outOfStockItems;

  const _InventoryStats({
    required this.totalProducts,
    required this.value,
    required this.lowStockItems,
    required this.outOfStockItems,
  });
}
