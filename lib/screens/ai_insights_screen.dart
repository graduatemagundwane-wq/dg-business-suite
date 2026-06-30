import 'package:flutter/material.dart';

import '../services/ai_insights_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/loading_widget.dart';
import '../widgets/premium_app_bar.dart';
import '../widgets/premium_state_widgets.dart';
import '../widgets/responsive_layout.dart';

class AiInsightsScreen extends StatefulWidget {
  final int shopId;

  const AiInsightsScreen({
    super.key,
    this.shopId = 1,
  });

  @override
  State<AiInsightsScreen> createState() => _AiInsightsScreenState();
}

class _AiInsightsScreenState extends State<AiInsightsScreen> {
  late Future<List<AiInsight>> _insightsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _insightsFuture = AiInsightsService.instance.generateInsights(
      shopId: widget.shopId,
    );
  }

  void _reload() {
    setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PremiumAppBar(
        title: 'AI Business Assistant',
        subtitle: 'Sales, stock, pricing and marketing advice',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<List<AiInsight>>(
        future: _insightsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingWidget(message: 'Analysing business data');
          }

          if (snapshot.hasError) {
            return PremiumErrorState(
              message: 'AI insights could not be generated.',
              onRetry: _reload,
            );
          }

          final insights = snapshot.data ?? [];
          if (insights.isEmpty) {
            return const PremiumEmptyState(
              icon: Icons.psychology_alt,
              title: 'No insights yet',
              message: 'AI advice will appear as sales and inventory grow.',
            );
          }

          return ResponsiveLayout(
            child: ListView.separated(
              itemCount: insights.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) {
                return _AiInsightCard(insight: insights[index]);
              },
            ),
          );
        },
      ),
    );
  }
}

class _AiInsightCard extends StatelessWidget {
  final AiInsight insight;

  const _AiInsightCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = insight.priority == 1
        ? theme.colorScheme.primary
        : theme.colorScheme.tertiary;

    return DashboardCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.14),
            foregroundColor: color,
            child: const Icon(Icons.auto_awesome),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.category.label,
                  style: theme.textTheme.labelMedium?.copyWith(color: color),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(insight.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(insight.message),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
