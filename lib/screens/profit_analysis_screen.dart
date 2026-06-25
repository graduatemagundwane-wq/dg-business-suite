import 'package:flutter/material.dart';

class ProfitAnalysisScreen extends StatelessWidget {
  const ProfitAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const revenue = 2500.00;
    const expenses = 800.00;
    const profit = revenue - expenses;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profit Analysis'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _card(
              'Revenue',
              '\$${revenue.toStringAsFixed(2)}',
              Icons.trending_up,
            ),
            _card(
              'Expenses',
              '\$${expenses.toStringAsFixed(2)}',
              Icons.money_off,
            ),
            _card(
              'Net Profit',
              '\$${profit.toStringAsFixed(2)}',
              Icons.account_balance_wallet,
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(
    String title,
    String value,
    IconData icon,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }
}