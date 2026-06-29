import 'package:flutter/material.dart';

import '../services/dashboard_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/loading_widget.dart';
import '../widgets/premium_app_bar.dart';
import '../widgets/premium_state_widgets.dart';
import '../widgets/responsive_layout.dart';

class ProfitAnalysisScreen extends StatefulWidget {
  final int shopId;

  const ProfitAnalysisScreen({
    super.key,
    this.shopId = 1,
  });

  @override
  State<ProfitAnalysisScreen> createState() => _ProfitAnalysisScreenState();
}

class _ProfitAnalysisScreenState extends State<ProfitAnalysisScreen> {
  late Future<ReportSummary> _monthlyReport;

  @override
  void initState() {
    super.initState();
    _monthlyReport = DashboardService.instance.getReport(
      shopId: widget.shopId,
      period: ReportPeriod.monthly,
    );
  }

  void _reload() {
    setState(() {
      _monthlyReport = DashboardService.instance.getReport(
        shopId: widget.shopId,
        period: ReportPeriod.monthly,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PremiumAppBar(
        title: 'Profit Analysis',
        subtitle: 'Monthly revenue, expenses and net profit',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<ReportSummary>(
        future: _monthlyReport,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingWidget(message: 'Loading profit analysis');
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return PremiumErrorState(
              message: 'Profit analysis could not be loaded.',
              onRetry: _reload,
            );
          }

          final report = snapshot.data!;

          return ResponsiveLayout(
            child: ListView(
              children: [
                _ProfitHeader(report: report),
                const SizedBox(height: AppSpacing.xl),
                _ProfitCards(report: report),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProfitHeader extends StatelessWidget {
  final ReportSummary report;

  const _ProfitHeader({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final margin = report.sales == 0 ? 0 : report.netProfit / report.sales * 100;

    return DashboardCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: theme.colorScheme.secondaryContainer,
            foregroundColor: theme.colorScheme.onSecondaryContainer,
            child: const Icon(Icons.account_balance_wallet_outlined),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Net Profit', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _money(report.netProfit),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Text('${margin.toStringAsFixed(1)}% margin'),
        ],
      ),
    );
  }
}

class _ProfitCards extends StatelessWidget {
  final ReportSummary report;

  const _ProfitCards({required this.report});

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveLayout.isTablet(context);

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isTablet ? 3 : 1,
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      childAspectRatio: isTablet ? 1.3 : 2.8,
      children: [
        MetricCard(
          label: 'Sales',
          value: _money(report.sales),
          icon: Icons.trending_up,
          accentColor: Colors.blue,
        ),
        MetricCard(
          label: 'Gross Profit',
          value: _money(report.profit),
          icon: Icons.savings,
          accentColor: Colors.green,
        ),
        MetricCard(
          label: 'Expenses',
          value: _money(report.expenses),
          icon: Icons.money_off,
          accentColor: Colors.orange,
        ),
      ],
    );
  }
}

String _money(double value) => '\$${value.toStringAsFixed(2)}';
