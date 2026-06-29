import 'package:flutter/material.dart';

import '../services/customer_service.dart';

class CustomerSpendingScreen extends StatefulWidget {
  const CustomerSpendingScreen({super.key});

  @override
  State<CustomerSpendingScreen> createState() => _CustomerSpendingScreenState();
}

class _CustomerSpendingScreenState extends State<CustomerSpendingScreen> {
  late Future<CustomerSpendingAnalytics> _spendingFuture;

  @override
  void initState() {
    super.initState();
    _spendingFuture = CustomerService.instance.getSpendingAnalytics();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Spending History')),
      body: FutureBuilder<CustomerSpendingAnalytics>(
        future: _spendingFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final spending = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 640;

                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: wide ? 3 : 1,
                    childAspectRatio: wide ? 1.7 : 3.4,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    children: [
                      _SpendingCard(
                        label: 'Total Spent',
                        value: _money(spending.totalSpent),
                        icon: Icons.account_balance_wallet,
                      ),
                      _SpendingCard(
                        label: 'Monthly Spending',
                        value: _money(spending.monthlySpending),
                        icon: Icons.calendar_month,
                      ),
                      _SpendingCard(
                        label: 'Yearly Spending',
                        value: _money(spending.yearlySpending),
                        icon: Icons.insights,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Purchase Insights',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 12),
                      _InsightRow(
                        icon: Icons.storefront,
                        label: 'Most purchased shop',
                        value: spending.mostPurchasedShop,
                      ),
                      _InsightRow(
                        icon: Icons.shopping_bag,
                        label: 'Most purchased product',
                        value: spending.mostPurchasedProduct,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Purchase Timeline',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              if (spending.timeline.isEmpty)
                const _TimelineEmptyState()
              else
                ...spending.timeline.map(
                  (point) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.timeline)),
                      title: Text(_money(point.amount)),
                      subtitle: Text(point.date.toString()),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SpendingCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SpendingCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
              child: Icon(icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InsightRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(label),
      subtitle: Text(value),
    );
  }
}

class _TimelineEmptyState extends StatelessWidget {
  const _TimelineEmptyState();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.timeline,
              size: 52,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 8),
            const Text(
              'Purchase timeline will appear after customer-linked sales.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

String _money(double value) => '\$${value.toStringAsFixed(2)}';
