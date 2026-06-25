import 'package:flutter/material.dart';
import '../services/dashboard_service.dart';

class DashboardScreen extends StatefulWidget {
  final String shopName;

  const DashboardScreen({
    super.key,
    required this.shopName,
  });

  @override
  State<DashboardScreen> createState() =>
      _DashboardScreenState();
}

class _DashboardScreenState
    extends State<DashboardScreen> {
  double totalSales = 0;
  double totalProfit = 0;
  int totalProducts = 0;
  int lowStockItems = 0;

  final dashboardService = DashboardService.instance;

  Future<void> loadDashboard() async {
  final data =
      await dashboardService.getDashboardData(1);

  setState(() {
    totalSales = data['total_sales'] ?? 0;
    totalProfit = data['total_profit'] ?? 0;
    totalProducts = data['product_count'] ?? 0;
    lowStockItems = data['low_stock_count'] ?? 0;
  });
}

@override
void initState() {
  super.initState();
  loadDashboard();
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.shopName),
      ),

      body: SingleChildScrollView(
        padding:
            const EdgeInsets.all(16),
        child: Column(
          children: [

            Row(
              children: [

                Expanded(
                  child: _statCard(
                    title: "Sales",
                    value:
                        "\$${totalSales.toStringAsFixed(2)}",
                    icon:
                        Icons.point_of_sale,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: _statCard(
                    title: "Profit",
                    value:
                        "\$${totalProfit.toStringAsFixed(2)}",
                    icon:
                        Icons.attach_money,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [

                Expanded(
                  child: _statCard(
                    title: "Products",
                    value:
                        totalProducts.toString(),
                    icon:
                        Icons.inventory,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: _statCard(
                    title:
                        "Low Stock",
                    value:
                        lowStockItems
                            .toString(),
                    icon:
                        Icons.warning,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.person,
                ),
                title: const Text(
                  "Top Employee",
                ),
                subtitle: const Text(
                  "Will appear here",
                ),
              ),
            ),

            const SizedBox(height: 10),

            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.star,
                ),
                title: const Text(
                  "Best Selling Product",
                ),
                subtitle: const Text(
                  "Will appear here",
                ),
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(
                  Icons.picture_as_pdf,
                ),
                label: const Text(
                  "Generate Report",
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(16),
        child: Column(
          children: [

            Icon(
              icon,
              size: 40,
            ),

            const SizedBox(height: 10),

            Text(
              title,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              value,
              style:
                  const TextStyle(
                fontSize: 22,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}