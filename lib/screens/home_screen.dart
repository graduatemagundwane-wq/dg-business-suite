import 'package:flutter/material.dart';

import '../session/app_session.dart';
import '../theme/app_tokens.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/premium_app_bar.dart';
import '../widgets/premium_navigation_drawer.dart';
import '../widgets/premium_state_widgets.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/search_box.dart';
import 'dashboard_screen.dart';
import 'employee_management_screen.dart';
import 'expenses_screen.dart';
import 'inventory_screen.dart';
import 'ledger_vault.dart';
import 'low_stock_screen.dart';
import 'marketplace_hub.dart';
import 'pos_screen.dart';
import 'profit_analysis_screen.dart';
import 'reports_screen.dart';
import 'sales_history_screen.dart';
import 'settings_screen.dart';
import 'supplier_screen.dart';

class HomeScreen extends StatefulWidget {
  final bool isOwner;

  const HomeScreen({
    super.key,
    this.isOwner = true,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final destinations = _destinations(session)
        .where((item) => !item.ownerOnly || widget.isOwner && session.isOwner)
        .toList(growable: false);
    final filteredDestinations = destinations
        .where(
          (item) => item.label.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList(growable: false);

    return Scaffold(
      appBar: PremiumAppBar(
        title: session.shopName,
        subtitle: '${session.displayName} • ${_roleLabel(session.role ?? AppRole.owner,)}',
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
          ),
        ],
      ),
      drawer: PremiumNavigationDrawer(
        session: session,
        items: destinations,
      ),
      body: ResponsiveLayout(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HomeHeader(
              shopName: session.shopName,
              displayName: session.displayName,
            ),
            const SizedBox(height: AppSpacing.xl),
            SearchBox(
              controller: _searchController,
              hintText: 'Search workspace',
              onChanged: (value) => setState(() => _query = value),
              onClear: _query.isEmpty
                  ? null
                  : () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
            ),
            const SizedBox(height: AppSpacing.xl),
            Expanded(
              child: AnimatedSwitcher(
                duration: AppDurations.normal,
                child: filteredDestinations.isEmpty
                    ? const PremiumEmptyState(
                        icon: Icons.search_off,
                        title: 'No workspace tools found',
                        message: 'Try a different search term.',
                      )
                    : _WorkspaceGrid(items: filteredDestinations),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<PremiumNavigationItem> _destinations(AppSession session) {
    return [
      PremiumNavigationItem(
        label: 'Dashboard',
        icon: Icons.dashboard_outlined,
        builder: (_) => DashboardScreen(
          shopName: session.shopName,
          shopId: session.requiredShopId,
        ),
      ),
      PremiumNavigationItem(
        label: 'Inventory',
        icon: Icons.inventory_2_outlined,
        builder: (_) => InventoryScreen(shopId: session.requiredShopId),
      ),
      PremiumNavigationItem(
        label: 'POS',
        icon: Icons.point_of_sale,
        builder: (_) => POSScreen(
          shopId: session.requiredShopId,
          employeeId: session.requiredEmployeeId,
          cashierName: session.displayName,
          shopName: session.shopName,
        ),
      ),
      const PremiumNavigationItem(
        label: 'Employees',
        icon: Icons.people_outline,
        builder: _buildEmployees,
        ownerOnly: true,
      ),
      const PremiumNavigationItem(
        label: 'Sales History',
        icon: Icons.receipt_long_outlined,
        builder: _buildSalesHistory,
        ownerOnly: true,
      ),
      const PremiumNavigationItem(
        label: 'Reports',
        icon: Icons.bar_chart,
        builder: _buildReports,
        ownerOnly: true,
      ),
      const PremiumNavigationItem(
        label: 'Low Stock',
        icon: Icons.warning_amber,
        builder: _buildLowStock,
        ownerOnly: true,
      ),
      const PremiumNavigationItem(
        label: 'Expenses',
        icon: Icons.money_off_outlined,
        builder: _buildExpenses,
        ownerOnly: true,
      ),
      const PremiumNavigationItem(
        label: 'Profit Analysis',
        icon: Icons.trending_up,
        builder: _buildProfitAnalysis,
        ownerOnly: true,
      ),
      const PremiumNavigationItem(
        label: 'Settings',
        icon: Icons.settings_outlined,
        builder: _buildSettings,
        ownerOnly: true,
      ),
      const PremiumNavigationItem(
        label: 'Suppliers',
        icon: Icons.business_outlined,
        builder: _buildSuppliers,
        ownerOnly: true,
      ),
      const PremiumNavigationItem(
        label: 'Marketplace',
        icon: Icons.storefront,
        builder: _buildMarketplace,
      ),
      const PremiumNavigationItem(
        label: 'Ledger Vault',
        icon: Icons.account_balance_wallet_outlined,
        builder: _buildLedgerVault,
      ),
    ];
  }

  static Widget _buildEmployees(BuildContext context) {
    return const EmployeeManagementScreen();
  }

  static Widget _buildSalesHistory(BuildContext context) {
    return const SalesHistoryScreen();
  }

  static Widget _buildReports(BuildContext context) {
    return const ReportsScreen();
  }

  static Widget _buildLowStock(BuildContext context) {
    return const LowStockScreen();
  }

  static Widget _buildExpenses(BuildContext context) {
    return const ExpensesScreen();
  }

  static Widget _buildProfitAnalysis(BuildContext context) {
    return const ProfitAnalysisScreen();
  }

  static Widget _buildSettings(BuildContext context) {
    return const SettingsScreen();
  }

  static Widget _buildSuppliers(BuildContext context) {
    return const SupplierScreen();
  }

  static Widget _buildMarketplace(BuildContext context) {
    return const MarketplaceHubScreen();
  }

  static Widget _buildLedgerVault(BuildContext context) {
    return const LedgerVaultScreen();
  }

  String _roleLabel(AppRole role) {
    switch (role) {
      case AppRole.owner:
        return 'Owner';
      case AppRole.employee:
        return 'Employee';
      case AppRole.customer:
        return 'Customer';
    }
  }
}

class _HomeHeader extends StatelessWidget {
  final String shopName;
  final String displayName;

  const _HomeHeader({
    required this.shopName,
    required this.displayName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DashboardCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Operations Workspace',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '$shopName is ready for today, $displayName.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Icon(
              Icons.storefront,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceGrid extends StatelessWidget {
  final List<PremiumNavigationItem> items;

  const _WorkspaceGrid({
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveLayout.isTablet(context);

    return GridView.builder(
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isTablet ? 4 : 2,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
        childAspectRatio: isTablet ? 1.35 : 1.12,
      ),
      itemBuilder: (context, index) {
        final item = items[index];

        return _WorkspaceTile(
          item: item,
        );
      },
    );
  }
}

class _WorkspaceTile extends StatelessWidget {
  final PremiumNavigationItem item;

  const _WorkspaceTile({
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DashboardCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: item.builder,
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(
                item.icon,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            Text(
              item.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
