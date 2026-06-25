import 'package:flutter/material.dart';

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
                children: const [

                  ListTile(
                    leading:
                        Icon(Icons.receipt),
                    title:
                        Text("Sales History"),
                  ),

                  ListTile(
                    leading:
                        Icon(Icons.bar_chart),
                    title:
                        Text("Monthly Reports"),
                  ),

                  ListTile(
                    leading:
                        Icon(Icons.picture_as_pdf),
                    title:
                        Text("PDF Reports"),
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