import 'package:flutter/material.dart';

import '../services/dashboard_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/loading_widget.dart';
import '../widgets/premium_app_bar.dart';
import '../widgets/premium_state_widgets.dart';
import '../widgets/responsive_layout.dart';

class ReportsScreen extends StatefulWidget {
  final int shopId;

  const ReportsScreen({
    super.key,
    this.shopId = 1,
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final DashboardService _dashboardService = DashboardService.instance;

  late Future<List<ReportSummary>> _reportsFuture;

  @override
  void initState() {
    super.initState();
    _reportsFuture = _dashboardService.getReports(widget.shopId);
  }

  void _reload() {
    setState(() {
      _reportsFuture = _dashboardService.getReports(widget.shopId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PremiumAppBar(
        title: 'Reports',
        subtitle: 'Daily, weekly, monthly and yearly analysis',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<List<ReportSummary>>(
        future: _reportsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingWidget(message: 'Preparing reports');
          }

          if (snapshot.hasError) {
            return PremiumErrorState(
              message: 'Reports could not be loaded.',
              onRetry: _reload,
            );
          }

          final reports = snapshot.data ?? [];

          if (reports.isEmpty) {
            return const PremiumEmptyState(
              icon: Icons.summarize_outlined,
              title: 'No reports yet',
              message: 'Reports appear after sales and expenses are recorded.',
            );
          }

          return ResponsiveLayout(
            child: ListView.separated(
              itemCount: reports.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) {
                return _ReportCard(report: reports[index]);
              },
            ),
          );
        },
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final ReportSummary report;

  const _ReportCard({required this.report});

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
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: Icon(_iconFor(report.period)),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  report.title,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('PDF Soon'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              _ReportPill('Sales', _money(report.sales)),
              _ReportPill('Profit', _money(report.profit)),
              _ReportPill('Expenses', _money(report.expenses)),
              _ReportPill('Net Profit', _money(report.netProfit)),
              _ReportPill('Low Stock', report.lowStockItems.toString()),
              _ReportPill('Out Of Stock', report.outOfStockItems.toString()),
              _ReportPill('Inventory Value', _money(report.inventoryValue)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _DetailRow('Best Employee', report.bestEmployee.name),
          _DetailRow('Best Product', report.bestProduct.name),
        ],
      ),
    );
  }

  IconData _iconFor(ReportPeriod period) {
    switch (period) {
      case ReportPeriod.daily:
        return Icons.today;
      case ReportPeriod.weekly:
        return Icons.date_range;
      case ReportPeriod.monthly:
        return Icons.calendar_month;
      case ReportPeriod.yearly:
        return Icons.bar_chart;
    }
  }
}

class _ReportPill extends StatelessWidget {
  final String label;
  final String value;

  const _ReportPill(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 150,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
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
      padding: const EdgeInsets.only(top: AppSpacing.sm),
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

String _money(double value) => '\$${value.toStringAsFixed(2)}';
