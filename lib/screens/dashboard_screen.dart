import 'package:flutter/material.dart';

import '../services/dashboard_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/loading_widget.dart';
import '../widgets/premium_app_bar.dart';
import '../widgets/premium_state_widgets.dart';
import '../widgets/primary_button.dart';
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

  double totalSales = 0;
  double totalProfit = 0;
  int totalProducts = 0;
  int lowStockItems = 0;
  Map<String, dynamic>? topEmployee;
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
      final data = await dashboardService.getDashboardData(widget.shopId);

      if (!mounted) return;

      setState(() {
        totalSales = data['total_sales'] ?? 0;
        totalProfit = data['total_profit'] ?? 0;
        totalProducts = data['product_count'] ?? 0;
        lowStockItems = data['low_stock_count'] ?? 0;
        topEmployee = data['top_employee'];
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
        subtitle: 'Performance overview',
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
            ? const LoadingWidget(message: 'Loading dashboard')
            : errorMessage != null
                ? PremiumErrorState(
                    message: errorMessage!,
                    onRetry: loadDashboard,
                  )
                : ResponsiveLayout(
                    child: ListView(
                      children: [
                        _DashboardHeader(
                          totalSales: totalSales,
                          totalProfit: totalProfit,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        _MetricsGrid(
                          totalSales: totalSales,
                          totalProfit: totalProfit,
                          totalProducts: totalProducts,
                          lowStockItems: lowStockItems,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        _OperationsPanel(
                          topEmployee: topEmployee,
                          lowStockItems: lowStockItems,
                          onOpenReports: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ReportsScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  final double totalSales;
  final double totalProfit;

  const _DashboardHeader({
    required this.totalSales,
    required this.totalProfit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final margin = totalSales == 0 ? 0 : totalProfit / totalSales * 100;

    return DashboardCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Business Health',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Sales, profit, inventory, and staff activity at a glance.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${margin.toStringAsFixed(1)}%',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              Text(
                'Profit margin',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  final double totalSales;
  final double totalProfit;
  final int totalProducts;
  final int lowStockItems;

  const _MetricsGrid({
    required this.totalSales,
    required this.totalProfit,
    required this.totalProducts,
    required this.lowStockItems,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveLayout.isTablet(context);
    final colorScheme = Theme.of(context).colorScheme;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isTablet ? 4 : 2,
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      childAspectRatio: isTablet ? 1.15 : 1,
      children: [
        MetricCard(
          label: 'Sales',
          value: '\$${totalSales.toStringAsFixed(2)}',
          icon: Icons.point_of_sale,
          accentColor: colorScheme.primary,
          helper: 'Recorded revenue',
        ),
        MetricCard(
          label: 'Profit',
          value: '\$${totalProfit.toStringAsFixed(2)}',
          icon: Icons.attach_money,
          accentColor: colorScheme.secondary,
          helper: 'Gross profit',
        ),
        MetricCard(
          label: 'Products',
          value: totalProducts.toString(),
          icon: Icons.inventory_2_outlined,
          accentColor: colorScheme.tertiary,
          helper: 'Active inventory',
        ),
        MetricCard(
          label: 'Low Stock',
          value: lowStockItems.toString(),
          icon: Icons.warning_amber,
          accentColor: lowStockItems > 0 ? colorScheme.error : colorScheme.primary,
          helper: lowStockItems > 0 ? 'Needs attention' : 'Inventory healthy',
        ),
      ],
    );
  }
}

class _OperationsPanel extends StatelessWidget {
  final Map<String, dynamic>? topEmployee;
  final int lowStockItems;
  final VoidCallback onOpenReports;

  const _OperationsPanel({
    required this.topEmployee,
    required this.lowStockItems,
    required this.onOpenReports,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final employeeName =
        (topEmployee?['employee_name'] ?? 'No employee sales yet').toString();
    final employeeProfit =
        ((topEmployee?['profit'] ?? 0) as num).toDouble().toStringAsFixed(2);

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Operations',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              child: Icon(Icons.person_outline),
            ),
            title: Text(employeeName),
            subtitle: Text('Top employee profit: \$$employeeProfit'),
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: lowStockItems > 0
                  ? theme.colorScheme.errorContainer
                  : theme.colorScheme.primaryContainer,
              foregroundColor: lowStockItems > 0
                  ? theme.colorScheme.onErrorContainer
                  : theme.colorScheme.onPrimaryContainer,
              child: Icon(
                lowStockItems > 0 ? Icons.warning_amber : Icons.check,
              ),
            ),
            title: Text(
              lowStockItems > 0
                  ? '$lowStockItems low-stock item${lowStockItems == 1 ? '' : 's'}'
                  : 'Inventory is above alert thresholds',
            ),
            subtitle: const Text('Stock alerts use current local inventory.'),
          ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: PrimaryButton(
              label: 'Open Reports',
              icon: Icons.bar_chart,
              onPressed: onOpenReports,
            ),
          ),
        ],
      ),
    );
  }
}
