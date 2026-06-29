import 'package:flutter/foundation.dart';
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
import 'customer_orders_screen.dart';
import 'customer_spending_screen.dart';
import 'employee_management_screen.dart';
import 'expenses_screen.dart';
import 'favorites_screen.dart';
import 'inventory_screen.dart';
import 'ledger_vault.dart';
import 'low_stock_screen.dart';
import 'marketplace_hub.dart';
import 'pos_screen.dart';
import 'profit_analysis_screen.dart';
import 'receipt_history_screen.dart';
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
    final destinations = _destinations(session);
    final filteredDestinations = destinations
        .where(
          (item) => item.label.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList(growable: false);

    return Scaffold(
      appBar: PremiumAppBar(
        title: _modeTitle(session.role ?? AppRole.owner),
        subtitle: '${session.displayName} - ${session.shopName}',
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
              title: _modeTitle(session.role ?? AppRole.owner),
              subtitle: _modeSubtitle(session),
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
    if (session.isCustomer) {
      return [
        const PremiumNavigationItem(
          label: 'Marketplace',
          icon: Icons.storefront,
          builder: _buildMarketplace,
        ),
        const PremiumNavigationItem(
          label: 'My Orders',
          icon: Icons.shopping_bag_outlined,
          builder: _buildCustomerOrders,
        ),
        const PremiumNavigationItem(
          label: 'My Spending',
          icon: Icons.insights,
          builder: _buildCustomerSpending,
        ),
        const PremiumNavigationItem(
          label: 'Favourite Shops',
          icon: Icons.favorite_border,
          builder: _buildFavorites,
        ),
        const PremiumNavigationItem(
          label: 'Receipts',
          icon: Icons.receipt_long_outlined,
          builder: _buildReceipts,
        ),
        const PremiumNavigationItem(
          label: 'Shopping Lists',
          icon: Icons.checklist,
          builder: _buildShoppingLists,
        ),
        const PremiumNavigationItem(
          label: 'Shop List',
          icon: Icons.store_mall_directory_outlined,
          builder: _buildShopList,
        ),
        const PremiumNavigationItem(
          label: 'Reminders',
          icon: Icons.notifications_active_outlined,
          builder: _buildReminders,
        ),
        const PremiumNavigationItem(
          label: 'Complaints / Reports',
          icon: Icons.report_gmailerrorred_outlined,
          builder: _buildComplaints,
        ),
        const PremiumNavigationItem(
          label: 'Switch Mode',
          icon: Icons.swap_horiz,
          builder: _buildSwitchMode,
        ),
        const PremiumNavigationItem(
          label: 'Settings / Logout',
          icon: Icons.settings_outlined,
          builder: _buildCustomerSettings,
        ),
      ];
    }

    if (session.isEmployee) {
      return [
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
        PremiumNavigationItem(
          label: 'Inventory Lookup',
          icon: Icons.search,
          builder: (_) => InventoryScreen(shopId: session.requiredShopId),
        ),
        const PremiumNavigationItem(
          label: 'Receipts',
          icon: Icons.receipt_long_outlined,
          builder: _buildReceipts,
        ),
        PremiumNavigationItem(
          label: 'Dashboard',
          icon: Icons.dashboard_outlined,
          builder: (_) => DashboardScreen(
            shopName: session.shopName,
            shopId: session.requiredShopId,
          ),
        ),
        const PremiumNavigationItem(
          label: 'Switch Mode',
          icon: Icons.swap_horiz,
          builder: _buildSwitchMode,
        ),
      ];
    }

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
        label: 'Receipts',
        icon: Icons.receipt_long_outlined,
        builder: _buildReceipts,
        ownerOnly: true,
      ),
      const PremiumNavigationItem(
        label: 'Sales History',
        icon: Icons.history,
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
        ownerOnly: true,
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

  static Widget _buildCustomerOrders(BuildContext context) {
    return const CustomerOrdersScreen();
  }

  static Widget _buildCustomerSpending(BuildContext context) {
    return const CustomerSpendingScreen();
  }

  static Widget _buildFavorites(BuildContext context) {
    return const FavoritesScreen();
  }

  static Widget _buildReceipts(BuildContext context) {
    return const ReceiptHistoryScreen();
  }

  static Widget _buildShoppingLists(BuildContext context) {
    return const _ShoppingListsScreen();
  }

  static Widget _buildShopList(BuildContext context) {
    return const _ShopListScreen();
  }

  static Widget _buildReminders(BuildContext context) {
    return const _RemindersScreen();
  }

  static Widget _buildComplaints(BuildContext context) {
    return const _CustomerPlaceholderScreen(
      title: 'Complaints / Reports',
      icon: Icons.report_gmailerrorred_outlined,
      message: 'Customer complaints and service reports are prepared.',
    );
  }

  static Widget _buildCustomerSettings(BuildContext context) {
    return const _CustomerSettingsScreen();
  }

  static Widget _buildSwitchMode(BuildContext context) {
    return const _SwitchModeScreen();
  }

  static Widget _buildLedgerVault(BuildContext context) {
    return const LedgerVaultScreen();
  }

  String _modeTitle(AppRole role) {
    switch (role) {
      case AppRole.owner:
        return 'Owner Mode';
      case AppRole.employee:
        return 'Employee Mode';
      case AppRole.customer:
        return 'Customer Mode';
    }
  }

  String _modeSubtitle(AppSession session) {
    if (session.isCustomer) {
      return 'Marketplace, orders, spending and favourite shops.';
    }
    if (session.isEmployee) {
      return 'POS, inventory lookup, receipts and daily workspace.';
    }
    return 'Dashboard, inventory, POS, reports and business controls.';
  }
}

class _HomeHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String displayName;

  const _HomeHeader({
    required this.title,
    required this.subtitle,
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
                  title,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '$subtitle Welcome, $displayName.',
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

class _CustomerPlaceholderScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final String message;

  const _CustomerPlaceholderScreen({
    required this.title,
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: DashboardCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomerSettingsScreen extends StatelessWidget {
  const _CustomerSettingsScreen();

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings / Logout')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          DashboardCard(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(session.displayName),
              subtitle: const Text('Customer Mode'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: () {
              session.signOut();
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}

class _SwitchModeScreen extends StatelessWidget {
  const _SwitchModeScreen();

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Switch Mode')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          DashboardCard(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.swap_horiz)),
              title: const Text('Current Mode'),
              subtitle: Text(_modeLabel(session.role)),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (session.isBusinessAccount && !session.isCustomer)
            FilledButton.icon(
              onPressed: () {
                session.switchToCustomerMode();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.storefront),
              label: const Text('Switch to Customer Mode'),
            ),
          if (session.isBusinessAccount && session.isCustomer)
            FilledButton.icon(
              onPressed: () {
                session.switchToBusinessMode();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.work_outline),
              label: Text(
                session.accountIsOwner
                    ? 'Return to Owner Mode'
                    : 'Return to Employee Mode',
              ),
            ),
          if (session.accountIsCustomer && kDebugMode) ...[
            OutlinedButton.icon(
              onPressed: () {
                session.switchToDemoOwnerMode();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.admin_panel_settings),
              label: const Text('Demo Owner Mode'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () {
                session.switchToDemoEmployeeMode();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.badge),
              label: const Text('Demo Employee Mode'),
            ),
          ],
        ],
      ),
    );
  }

  String _modeLabel(AppRole? role) {
    switch (role) {
      case AppRole.owner:
        return 'Owner Mode';
      case AppRole.employee:
        return 'Employee Mode';
      case AppRole.customer:
        return 'Customer Mode';
      case null:
        return 'Signed out';
    }
  }
}

class _ShoppingListsScreen extends StatefulWidget {
  const _ShoppingListsScreen();

  static final List<_ShoppingListItem> items = [];

  @override
  State<_ShoppingListsScreen> createState() => _ShoppingListsScreenState();
}

class _ShoppingListsScreenState extends State<_ShoppingListsScreen> {
  Future<void> _addItem() async {
    final nameController = TextEditingController();
    final quantityController = TextEditingController(text: '1');
    final notesController = TextEditingController();

    final item = await showDialog<_ShoppingListItem>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Shopping Item'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Item Name'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(
                context,
                _ShoppingListItem(
                  name: name,
                  quantity: quantityController.text.trim().isEmpty
                      ? '1'
                      : quantityController.text.trim(),
                  notes: notesController.text.trim(),
                ),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    nameController.dispose();
    quantityController.dispose();
    notesController.dispose();

    if (item == null) return;
    setState(() => _ShoppingListsScreen.items.insert(0, item));
  }

  @override
  Widget build(BuildContext context) {
    final items = _ShoppingListsScreen.items;

    return Scaffold(
      appBar: AppBar(title: const Text('Shopping Lists')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addItem,
        icon: const Icon(Icons.add),
        label: const Text('Add Item'),
      ),
      body: items.isEmpty
          ? const _SimpleEmptyState(
              icon: Icons.checklist,
              title: 'No shopping items',
              message: 'Create a list item to test shopping lists.',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];

                return Card(
                  child: CheckboxListTile(
                    value: item.bought,
                    onChanged: (value) {
                      setState(() => item.bought = value ?? false);
                    },
                    title: Text(item.name),
                    subtitle: Text(
                      'Qty: ${item.quantity}${item.notes.isEmpty ? '' : '\n${item.notes}'}',
                    ),
                    secondary: IconButton(
                      tooltip: 'Delete',
                      onPressed: () {
                        setState(() => items.removeAt(index));
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _ShopListScreen extends StatefulWidget {
  const _ShopListScreen();

  static final List<_SavedShopVisit> shops = [];

  @override
  State<_ShopListScreen> createState() => _ShopListScreenState();
}

class _ShopListScreenState extends State<_ShopListScreen> {
  Future<void> _addShop() async {
    final nameController = TextEditingController();
    final notesController = TextEditingController();

    final shop = await showDialog<_SavedShopVisit>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Shop To Visit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Shop Name'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(labelText: 'Reason / Notes'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(
                context,
                _SavedShopVisit(
                  name: name,
                  notes: notesController.text.trim(),
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    nameController.dispose();
    notesController.dispose();

    if (shop == null) return;
    setState(() => _ShopListScreen.shops.insert(0, shop));
  }

  @override
  Widget build(BuildContext context) {
    final shops = _ShopListScreen.shops;

    return Scaffold(
      appBar: AppBar(title: const Text('Shop List')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addShop,
        icon: const Icon(Icons.add_business),
        label: const Text('Add Shop'),
      ),
      body: shops.isEmpty
          ? const _SimpleEmptyState(
              icon: Icons.store_mall_directory_outlined,
              title: 'No shops saved',
              message: 'Save shops you want to visit.',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: shops.length,
              itemBuilder: (context, index) {
                final shop = shops[index];

                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.storefront)),
                    title: Text(shop.name),
                    subtitle: Text(
                      'Location: Nearby location pending${shop.notes.isEmpty ? '' : '\n${shop.notes}'}',
                    ),
                    isThreeLine: shop.notes.isNotEmpty,
                    trailing: IconButton(
                      tooltip: 'Remove',
                      onPressed: () => setState(() => shops.removeAt(index)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _RemindersScreen extends StatefulWidget {
  const _RemindersScreen();

  static final List<_ShoppingReminder> reminders = [];

  @override
  State<_RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<_RemindersScreen> {
  Future<void> _addReminder() async {
    final titleController = TextEditingController();
    final itemController = TextEditingController();
    final shopController = TextEditingController();
    final dateController = TextEditingController();

    final reminder = await showDialog<_ShoppingReminder>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Reminder'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: itemController,
                decoration: const InputDecoration(labelText: 'Product / Item'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: shopController,
                decoration: const InputDecoration(labelText: 'Shop Optional'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: dateController,
                decoration: const InputDecoration(
                  labelText: 'Date / Time Optional',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final title = titleController.text.trim();
              if (title.isEmpty) return;
              Navigator.pop(
                context,
                _ShoppingReminder(
                  title: title,
                  item: itemController.text.trim(),
                  shop: shopController.text.trim(),
                  dateTimeText: dateController.text.trim(),
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    titleController.dispose();
    itemController.dispose();
    shopController.dispose();
    dateController.dispose();

    if (reminder == null) return;
    setState(() => _RemindersScreen.reminders.insert(0, reminder));
  }

  @override
  Widget build(BuildContext context) {
    final reminders = _RemindersScreen.reminders;

    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addReminder,
        icon: const Icon(Icons.add_alert),
        label: const Text('Add Reminder'),
      ),
      body: reminders.isEmpty
          ? const _SimpleEmptyState(
              icon: Icons.notifications_active_outlined,
              title: 'No reminders',
              message: 'Create a shopping reminder for testing.',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: reminders.length,
              itemBuilder: (context, index) {
                final reminder = reminders[index];

                return Card(
                  child: CheckboxListTile(
                    value: reminder.done,
                    onChanged: (value) {
                      setState(() => reminder.done = value ?? false);
                    },
                    title: Text(reminder.title),
                    subtitle: Text(reminder.description),
                    secondary: IconButton(
                      tooltip: 'Delete',
                      onPressed: () {
                        setState(() => reminders.removeAt(index));
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _SimpleEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _SimpleEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ShoppingListItem {
  final String name;
  final String quantity;
  final String notes;
  bool bought = false;

  _ShoppingListItem({
    required this.name,
    required this.quantity,
    required this.notes,
  });
}

class _SavedShopVisit {
  final String name;
  final String notes;

  const _SavedShopVisit({
    required this.name,
    required this.notes,
  });
}

class _ShoppingReminder {
  final String title;
  final String item;
  final String shop;
  final String dateTimeText;
  bool done = false;

  _ShoppingReminder({
    required this.title,
    required this.item,
    required this.shop,
    required this.dateTimeText,
  });

  String get description {
    final parts = [
      if (item.isNotEmpty) 'Item: $item',
      if (shop.isNotEmpty) 'Shop: $shop',
      if (dateTimeText.isNotEmpty) 'When: $dateTimeText',
    ];

    return parts.isEmpty ? 'No details added' : parts.join('\n');
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
