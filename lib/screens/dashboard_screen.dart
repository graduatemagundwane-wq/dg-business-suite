import 'package:flutter/material.dart';

import '../services/dashboard_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/loading_widget.dart';
import '../widgets/premium_app_bar.dart';
import '../widgets/premium_state_widgets.dart';
import '../widgets/responsive_layout.dart';
import 'reports_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String shopName;
  final int shopId;

  const DashboardScreen({
    super.key,
    required this.shopName,
    required this.shopId,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final dashboardService = DashboardService.instance;

  DashboardAnalytics? analytics;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    loadDashboard();
  }

  Future<void> loadDashboard() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final data = await dashboardService.getDashboardAnalytics(widget.shopId);

      if (!mounted) return;

      setState(() {
        analytics = data;
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        errorMessage = 'Dashboard data could not be loaded.';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PremiumAppBar(
        title: widget.shopName,
        subtitle: 'Business intelligence dashboard',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: loadDashboard,
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: AppDurations.normal,
        child: isLoading
            ? const LoadingWidget(message: 'Loading business intelligence')
            : errorMessage != null
                ? PremiumErrorState(
                    message: errorMessage!,
                    onRetry: loadDashboard,
                  )
                : ResponsiveLayout(
                    child: _DashboardContent(
                      analytics: analytics!,
                      onOpenReports: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReportsScreen(shopId: widget.shopId),
                          ),
                        );
                      },
                    ),
                  ),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  final DashboardAnalytics analytics;
  final VoidCallback onOpenReports;

  const _DashboardContent({
    required this.analytics,
    required this.onOpenReports,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _HealthHeader(
          health: analytics.health,
          onOpenReports: onOpenReports,
        ),
        const SizedBox(height: AppSpacing.xl),
        _MetricsGrid(analytics: analytics),
        const SizedBox(height: AppSpacing.xl),
        _SectionTitle(
          title: 'Best Performers',
          action: TextButton.icon(
            onPressed: onOpenReports,
            icon: const Icon(Icons.bar_chart),
            label: const Text('Reports'),
          ),
        ),
        _PerformerGrid(analytics: analytics),
        const SizedBox(height: AppSpacing.xl),
        const _SectionTitle(title: 'Best Selling Products'),
        _ProductGrid(analytics: analytics),
        const SizedBox(height: AppSpacing.xl),
        _ChartsGrid(analytics: analytics),
      ],
    );
  }
}

class _HealthHeader extends StatelessWidget {
  final BusinessHealth health;
  final VoidCallback onOpenReports;

  const _HealthHeader({
    required this.health,
    required this.onOpenReports,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: const Icon(Icons.monitor_heart_outlined),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Business Health', style: theme.textTheme.titleLarge),
                    Text(
                      'Overall operating score from sales, profit, and inventory.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${health.score}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: health.score / 100,
              minHeight: 10,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _MiniStat('Sales Growth', '${health.salesGrowth.toStringAsFixed(1)}%'),
              _MiniStat('Profit Growth', '${health.profitGrowth.toStringAsFixed(1)}%'),
              _MiniStat('Inventory Health', '${health.inventoryHealth.toStringAsFixed(1)}%'),
              _MiniStat('Stock Value', _money(health.stockValue)),
              _MiniStat('Fast Moving', health.fastMovingProducts.toString()),
              _MiniStat('Slow Moving', health.slowMovingProducts.toString()),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onOpenReports,
              icon: const Icon(Icons.summarize_outlined),
              label: const Text('View Reports'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  final DashboardAnalytics analytics;

  const _MetricsGrid({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveLayout.isTablet(context);
    final colorScheme = Theme.of(context).colorScheme;

    final metrics = [
      _MetricData('Today Sales', _money(analytics.todaySales), Icons.today, colorScheme.primary),
      _MetricData('Today Profit', _money(analytics.todayProfit), Icons.savings, colorScheme.secondary),
      _MetricData('Weekly Sales', _money(analytics.weeklySales), Icons.date_range, colorScheme.primary),
      _MetricData('Weekly Profit', _money(analytics.weeklyProfit), Icons.trending_up, colorScheme.secondary),
      _MetricData('Monthly Sales', _money(analytics.monthlySales), Icons.calendar_month, colorScheme.primary),
      _MetricData('Monthly Profit', _money(analytics.monthlyProfit), Icons.account_balance_wallet, colorScheme.secondary),
      _MetricData('Inventory Value', _money(analytics.totalInventoryValue), Icons.inventory, colorScheme.tertiary),
      _MetricData('Low Stock Items', analytics.lowStockItems.toString(), Icons.warning_amber, colorScheme.error),
      _MetricData('Out Of Stock', analytics.outOfStockItems.toString(), Icons.cancel_outlined, colorScheme.error),
      _MetricData('Customers', analytics.totalCustomers.toString(), Icons.groups_outlined, colorScheme.primary),
      _MetricData('Employees', analytics.totalEmployees.toString(), Icons.badge_outlined, colorScheme.secondary),
      _MetricData('Products', analytics.totalProducts.toString(), Icons.inventory_2_outlined, colorScheme.tertiary),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: metrics.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isTablet ? 4 : 2,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
        childAspectRatio: isTablet ? 1.25 : 1.05,
      ),
      itemBuilder: (context, index) {
        final metric = metrics[index];
        return MetricCard(
          label: metric.label,
          value: metric.value,
          icon: metric.icon,
          accentColor: metric.color,
        );
      },
    );
  }
}

class _PerformerGrid extends StatelessWidget {
  final DashboardAnalytics analytics;

  const _PerformerGrid({required this.analytics});

  @override
  Widget build(BuildContext context) {
    return _ResponsiveCardGrid(
      children: [
        _EmployeeCard(title: 'Best Employee Today', employee: analytics.bestEmployeeToday),
        _EmployeeCard(title: 'Best Employee This Week', employee: analytics.bestEmployeeWeek),
        _EmployeeCard(title: 'Best Employee This Month', employee: analytics.bestEmployeeMonth),
      ],
    );
  }
}

class _ProductGrid extends StatelessWidget {
  final DashboardAnalytics analytics;

  const _ProductGrid({required this.analytics});

  @override
  Widget build(BuildContext context) {
    return _ResponsiveCardGrid(
      children: [
        _ProductCard(title: 'Most Sold Today', product: analytics.mostSoldToday),
        _ProductCard(title: 'Most Sold This Week', product: analytics.mostSoldWeek),
        _ProductCard(title: 'Most Sold This Month', product: analytics.mostSoldMonth),
      ],
    );
  }
}

class _ChartsGrid extends StatelessWidget {
  final DashboardAnalytics analytics;

  const _ChartsGrid({required this.analytics});

  @override
  Widget build(BuildContext context) {
    return _ResponsiveCardGrid(
      children: [
        _ChartCard(
          title: 'Sales Trend',
          child: _BarChart(
            values: analytics.salesTrend.map((point) => point.sales).toList(),
            labels: analytics.salesTrend.map((point) => point.label).toList(),
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        _ChartCard(
          title: 'Profit Trend',
          child: _BarChart(
            values: analytics.salesTrend.map((point) => point.profit).toList(),
            labels: analytics.salesTrend.map((point) => point.label).toList(),
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
        _ChartCard(
          title: 'Top Products',
          child: _RankList(
            items: analytics.topProducts
                .map((product) => '${product.name} • ${product.quantitySold} sold')
                .toList(),
          ),
        ),
        _ChartCard(
          title: 'Top Employees',
          child: _RankList(
            items: analytics.topEmployees
                .map((employee) => '${employee.name} • ${_money(employee.revenue)}')
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  final String title;
  final EmployeePerformance employee;

  const _EmployeeCard({
    required this.title,
    required this.employee,
  });

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          Text(employee.name, style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          _DetailRow('Sales Count', employee.salesCount.toString()),
          _DetailRow('Revenue', _money(employee.revenue)),
          _DetailRow('Profit', _money(employee.profit)),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final String title;
  final ProductPerformance product;

  const _ProductCard({
    required this.title,
    required this.product,
  });

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          Text(product.name, style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          _DetailRow('Quantity Sold', product.quantitySold.toString()),
          _DetailRow('Revenue', _money(product.revenue)),
          _DetailRow('Profit', _money(product.profit)),
        ],
      ),
    );
  }
}

class _ResponsiveCardGrid extends StatelessWidget {
  final List<Widget> children;

  const _ResponsiveCardGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveLayout.isTablet(context);

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isTablet ? 3 : 1,
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      childAspectRatio: isTablet ? 1.35 : 1.75,
      children: children,
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ChartCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final Color color;

  const _BarChart({
    required this.values,
    required this.labels,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final maxValue = values.fold<double>(0, (max, value) => value > max ? value : max);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(values.length, (index) {
        final height = maxValue == 0 ? 0.05 : (values[index] / maxValue).clamp(0.05, 1.0);
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: height,
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  labels[index],
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _RankList extends StatelessWidget {
  final List<String> items;

  const _RankList({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('No data yet'));
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        return ListTile(
          dense: true,
          leading: CircleAvatar(child: Text('${index + 1}')),
          title: Text(items[index]),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final Widget? action;

  const _SectionTitle({
    required this.title,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _MetricData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricData(this.label, this.value, this.icon, this.color);
}

String _money(double value) => '\$${value.toStringAsFixed(2)}';
