import 'package:flutter/material.dart';

import 'profit_analysis_screen.dart';
import 'reports_screen.dart';
import 'sales_history_screen.dart';

class LedgerVaultScreen extends StatefulWidget {
  const LedgerVaultScreen({super.key});

  @override
  State<LedgerVaultScreen> createState() =>
      _LedgerVaultScreenState();
}

class _LedgerVaultScreenState
    extends State<LedgerVaultScreen> {

  double totalSales = 0;
  double totalProfit = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Ledger Vault",
        ),
      ),
      body: Padding(
        padding:
            const EdgeInsets.all(16),
        child: Column(
          children: [

            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.attach_money,
                ),
                title: const Text(
                  "Total Sales",
                ),
                subtitle: Text(
                  "\$${totalSales.toStringAsFixed(2)}",
                ),
              ),
            ),

            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.trending_up,
                ),
                title: const Text(
                  "Total Profit",
                ),
                subtitle: Text(
                  "\$${totalProfit.toStringAsFixed(2)}",
                ),
              ),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: ListView(
                children: [

                  ListTile(
                    leading:
                        const Icon(Icons.receipt),
                    title:
                        const Text("Sales History"),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(const SalesHistoryScreen()),
                  ),

                  ListTile(
                    leading:
                        const Icon(Icons.today),
                    title:
                        const Text("Daily Reports"),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(const ReportsScreen()),
                  ),

                  ListTile(
                    leading:
                        const Icon(Icons.date_range),
                    title:
                        const Text("Weekly Reports"),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(const ReportsScreen()),
                  ),

                  ListTile(
                    leading:
                        const Icon(Icons.bar_chart),
                    title:
                        const Text("Monthly Reports"),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(const ReportsScreen()),
                  ),

                  ListTile(
                    leading:
                        const Icon(Icons.picture_as_pdf),
                    title:
                        const Text("PDF Reports"),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(const ReportsScreen()),
                  ),

                  ListTile(
                    leading:
                        const Icon(Icons.trending_up),
                    title:
                        const Text("Profit Analysis"),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(const ProfitAnalysisScreen()),
                  ),

                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}
