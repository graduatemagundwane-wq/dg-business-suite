import 'package:flutter/material.dart';

import '../services/dashboard_service.dart';
import '../widgets/loading_widget.dart';
import '../widgets/premium_app_bar.dart';
import '../widgets/premium_state_widgets.dart';

class SalesHistoryScreen extends StatefulWidget {
  final int shopId;

  const SalesHistoryScreen({
    super.key,
    this.shopId = 1,
  });

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _salesFuture;

  @override
  void initState() {
    super.initState();
    _salesFuture = DashboardService.instance.getRecentSales(widget.shopId);
  }

  void _reload() {
    setState(() {
      _salesFuture = DashboardService.instance.getRecentSales(widget.shopId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PremiumAppBar(
        title: 'Sales History',
        subtitle: 'Recent transactions',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _salesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingWidget(message: 'Loading sales history');
          }

          if (snapshot.hasError) {
            return PremiumErrorState(
              message: 'Sales history could not be loaded.',
              onRetry: _reload,
            );
          }

          final sales = snapshot.data ?? [];

          if (sales.isEmpty) {
            return const PremiumEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No sales yet',
              message: 'Completed POS transactions will appear here.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: sales.length,
            itemBuilder: (context, index) {
              final sale = sales[index];
              final amount = _asDouble(sale['total_amount']);
              final profit = _asDouble(sale['total_profit']);

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.receipt_long),
                  ),
                  title: Text(
                    (sale['receipt_number'] ?? 'Unknown Receipt').toString(),
                  ),
                  subtitle: Text(
                    'Cashier: ${(sale['employee_name'] ?? 'Unknown').toString()}\n${(sale['sale_date'] ?? '').toString()}',
                  ),
                  isThreeLine: true,
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _money(amount),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Profit ${_money(profit)}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _money(double value) => '\$${value.toStringAsFixed(2)}';
}
