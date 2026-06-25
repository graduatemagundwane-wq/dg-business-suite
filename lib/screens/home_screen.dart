import 'package:flutter/material.dart';

import 'dashboard_screen.dart';
import 'inventory_screen.dart';
import 'pos_screen.dart'; // ADD THIS
import 'employee_management_screen.dart';
import 'sales_history_screen.dart';
import 'reports_screen.dart';
import 'low_stock_screen.dart';
import 'expenses_screen.dart';
import 'profit_analysis_screen.dart';
import 'settings_screen.dart';
import 'supplier_screen.dart';
import 'marketplace_hub.dart';
import 'ledger_vault.dart';

class HomeScreen extends StatelessWidget {
  final bool isOwner;

  const HomeScreen({
    super.key,
    this.isOwner = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Double Gee POS'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [

            _menuCard(
              context,
              "Dashboard",
              Icons.dashboard,
              DashboardScreen(
                shopName: "Double Gee POS",
              ),
            ),

            _menuCard(
              context,
              "Inventory",
              Icons.inventory,
              const InventoryScreen(shopId: 1),
            ),

            // NEW POS CARD
            _menuCard(
              context,
              "POS",
              Icons.point_of_sale,
              const POSScreen(
                shopId: 1,
                employeeId: 1,
                cashierName: "Owner",
                shopName: "Double Gee POS",
               ),
              
            ),

            if (isOwner)
              _menuCard(
                context,
                "Employees",
                Icons.people,
                const EmployeeManagementScreen(),
              ),

            if (isOwner)
              _menuCard(
                context,
                "Sales History",
                Icons.receipt_long,
                const SalesHistoryScreen(),
              ),

            if (isOwner)
              _menuCard(
                context,
                "Reports",
                Icons.bar_chart,
                const ReportsScreen(),
              ),

            if (isOwner)
              _menuCard(
                context,
                "Low Stock",
                Icons.warning,
                const LowStockScreen(),
              ),

            if (isOwner)
              _menuCard(
                context,
                "Expenses",
                Icons.money_off,
                const ExpensesScreen(),
              ),

            if (isOwner)
              _menuCard(
                context,
                "Profit Analysis",
                Icons.trending_up,
                const ProfitAnalysisScreen(),
              ),

            if (isOwner)
              _menuCard(
                context,
                "Settings",
                Icons.settings,
                const SettingsScreen(),
              ),

            if (isOwner)
              _menuCard(
                context,
                "Suppliers",
                Icons.business,
                const SupplierScreen(),
              ),

            _menuCard(
              context,
              "Marketplace",
              Icons.store,
              const MarketplaceHubScreen(),
            ),

            _menuCard(
              context,
              "Ledger Vault",
              Icons.account_balance_wallet,
              const LedgerVaultScreen(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuCard(
    BuildContext context,
    String title,
    IconData icon,
    Widget screen,
  ) {
    return Card(
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => screen,
            ),
          );
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 40,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}