import '../database/local_db.dart';
import 'dashboard_service.dart';

class AiInsight {
  final String title;
  final String message;
  final AiInsightCategory category;
  final int priority;

  const AiInsight({
    required this.title,
    required this.message,
    required this.category,
    this.priority = 2,
  });
}

enum AiInsightCategory {
  sales,
  pricing,
  stock,
  marketing,
  customerBehaviour,
  ownerAlert,
}

class AiSettings {
  final bool enabled;
  final bool dailyAdvice;
  final bool weeklyAdvice;
  final bool monthlySummary;

  const AiSettings({
    this.enabled = true,
    this.dailyAdvice = true,
    this.weeklyAdvice = true,
    this.monthlySummary = true,
  });

  AiSettings copyWith({
    bool? enabled,
    bool? dailyAdvice,
    bool? weeklyAdvice,
    bool? monthlySummary,
  }) {
    return AiSettings(
      enabled: enabled ?? this.enabled,
      dailyAdvice: dailyAdvice ?? this.dailyAdvice,
      weeklyAdvice: weeklyAdvice ?? this.weeklyAdvice,
      monthlySummary: monthlySummary ?? this.monthlySummary,
    );
  }
}

class AiInsightsService {
  static final AiInsightsService instance = AiInsightsService._internal();

  factory AiInsightsService() => instance;

  AiInsightsService._internal();

  AiSettings _settings = const AiSettings();

  AiSettings get settings => _settings;

  void updateSettings(AiSettings settings) {
    _settings = settings;
  }

  Future<List<AiInsight>> generateInsights({int shopId = 1}) async {
    if (!_settings.enabled) {
      return const [
        AiInsight(
          title: 'AI Insights Disabled',
          message: 'Enable AI Insights in Settings to see advice.',
          category: AiInsightCategory.ownerAlert,
        ),
      ];
    }

    final analytics = await DashboardService.instance.getDashboardAnalytics(shopId);
    final db = await LocalDatabase.instance.database;
    final deadStockRows = await db.rawQuery(
      '''
      SELECT product_name, stock_quantity
      FROM products
      WHERE shop_id = ?
      AND id NOT IN (SELECT DISTINCT product_id FROM sale_items)
      ORDER BY stock_quantity DESC
      LIMIT 1
      ''',
      [shopId],
    );

    final insights = <AiInsight>[
      AiInsight(
        title: 'Fast Selling Products',
        message: analytics.mostSoldWeek.quantitySold > 0
            ? '${analytics.mostSoldWeek.name} is moving quickly this week.'
            : 'No fast selling product detected yet.',
        category: AiInsightCategory.sales,
      ),
      AiInsight(
        title: 'Slow Products',
        message: analytics.health.slowMovingProducts > 0
            ? '${analytics.health.slowMovingProducts} products are moving slowly.'
            : 'No slow moving pattern detected yet.',
        category: AiInsightCategory.sales,
      ),
      AiInsight(
        title: 'Dead Stock',
        message: deadStockRows.isEmpty
            ? 'No dead stock detected from current sales data.'
            : '${deadStockRows.first['product_name']} has stock but no sales yet.',
        category: AiInsightCategory.stock,
        priority: 1,
      ),
      const AiInsight(
        title: 'Marketplace Pricing',
        message:
            'Anonymous marketplace comparison protects nearby shop identities.',
        category: AiInsightCategory.pricing,
      ),
      const AiInsight(
        title: 'Restock Timing',
        message: 'Restock alerts will estimate run-out dates from sales velocity.',
        category: AiInsightCategory.stock,
      ),
      const AiInsight(
        title: 'Marketing Suggestion',
        message: 'Bundle complementary products and promote fast movers on weekends.',
        category: AiInsightCategory.marketing,
      ),
      const AiInsight(
        title: 'Customer Behaviour',
        message:
            'Repeat customer, favourite product and buying-time analysis is ready for customer-linked sales.',
        category: AiInsightCategory.customerBehaviour,
      ),
      AiInsight(
        title: 'Owner Alert',
        message: analytics.health.profitGrowth < 0
            ? 'Profit dropped by ${analytics.health.profitGrowth.abs().toStringAsFixed(1)}%.'
            : 'Profit increased by ${analytics.health.profitGrowth.toStringAsFixed(1)}%.',
        category: AiInsightCategory.ownerAlert,
        priority: 1,
      ),
    ];

    insights.sort((a, b) => a.priority.compareTo(b.priority));
    return insights;
  }
}

extension AiInsightCategoryLabel on AiInsightCategory {
  String get label {
    switch (this) {
      case AiInsightCategory.sales:
        return 'Sales';
      case AiInsightCategory.pricing:
        return 'Pricing';
      case AiInsightCategory.stock:
        return 'Stock';
      case AiInsightCategory.marketing:
        return 'Marketing';
      case AiInsightCategory.customerBehaviour:
        return 'Customer Behaviour';
      case AiInsightCategory.ownerAlert:
        return 'Owner Alert';
    }
  }
}
