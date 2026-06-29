import 'package:flutter/material.dart';

import '../services/customer_service.dart';
import '../services/marketplace_service.dart';
import 'customer_orders_screen.dart';
import 'customer_spending_screen.dart';
import 'favorites_screen.dart';
import 'marketplace_hub.dart';
import 'shop_profile_screen.dart';

class CustomerDashboardScreen extends StatefulWidget {
  const CustomerDashboardScreen({super.key});

  @override
  State<CustomerDashboardScreen> createState() =>
      _CustomerDashboardScreenState();
}

class _CustomerDashboardScreenState extends State<CustomerDashboardScreen> {
  late Future<_CustomerHomeData> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  Future<_CustomerHomeData> _load() async {
    final summary = await CustomerService.instance.getCustomerSummary();
    final shops = await MarketplaceService.instance.getNearbyShops();

    return _CustomerHomeData(summary: summary, nearbyShops: shops);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Dashboard'),
      ),
      body: FutureBuilder<_CustomerHomeData>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!;
          final summary = data.summary;

          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _loadFuture = _load());
              await _loadFuture;
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _WelcomePanel(summary: summary),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 620;

                    return GridView.count(
                      crossAxisCount: wide ? 4 : 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: wide ? 1.6 : 1.25,
                      children: [
                        _MetricCard(
                          icon: Icons.payments,
                          label: 'Lifetime Spending',
                          value: _money(summary.lifetimeSpending),
                        ),
                        _MetricCard(
                          icon: Icons.shopping_bag,
                          label: 'Orders Placed',
                          value: summary.ordersPlaced.toString(),
                        ),
                        _MetricCard(
                          icon: Icons.favorite,
                          label: 'Favourite Shops',
                          value: summary.favouriteShops.toString(),
                        ),
                        _MetricCard(
                          icon: Icons.calendar_month,
                          label: 'This Month',
                          value: _money(summary.spending.monthlySpending),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                _ShortcutGrid(
                  onMarketplace: () => _push(const MarketplaceHubScreen()),
                  onOrders: () => _push(const CustomerOrdersScreen()),
                  onSpending: () => _push(const CustomerSpendingScreen()),
                  onFavorites: () => _push(const FavoritesScreen()),
                ),
                const SizedBox(height: 18),
                _SectionHeader(
                  title: 'Recent Purchases',
                  actionLabel: 'View spending',
                  onAction: () => _push(const CustomerSpendingScreen()),
                ),
                const SizedBox(height: 8),
                if (summary.recentPurchases.isEmpty)
                  const _EmptyCard(
                    icon: Icons.receipt_long,
                    title: 'No purchases yet',
                    message: 'Your spending and purchase timeline will appear here.',
                  )
                else
                  ...summary.recentPurchases.map(
                    (purchase) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.receipt_long),
                        ),
                        title: Text(purchase.productName),
                        subtitle: Text('${purchase.shopName}\n${purchase.date}'),
                        isThreeLine: true,
                        trailing: Text(
                          _money(purchase.total),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                _SectionHeader(
                  title: 'Nearby Shops',
                  actionLabel: 'Marketplace',
                  onAction: () => _push(const MarketplaceHubScreen()),
                ),
                const SizedBox(height: 8),
                if (data.nearbyShops.isEmpty)
                  const _EmptyCard(
                    icon: Icons.storefront,
                    title: 'No shops found',
                    message: 'Activated nearby shops will appear here.',
                  )
                else
                  ...data.nearbyShops.take(5).map(
                        (shop) => Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.storefront),
                            ),
                            title: Text(shop.name),
                            subtitle: Text(
                              '${shop.productCount} products • 2.4 km • ${shop.rating.toStringAsFixed(1)} rating',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _push(ShopProfileScreen(shopId: shop.id)),
                          ),
                        ),
                      ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _push(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

class _CustomerHomeData {
  final CustomerSummary summary;
  final List<MarketplaceShop> nearbyShops;

  const _CustomerHomeData({
    required this.summary,
    required this.nearbyShops,
  });
}

class _WelcomePanel extends StatelessWidget {
  final CustomerSummary summary;

  const _WelcomePanel({required this.summary});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome, ${summary.customerName}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Track your spending, favourite shops and local marketplace orders.',
            style: TextStyle(color: colorScheme.onPrimary),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: colorScheme.tertiaryContainer,
              foregroundColor: colorScheme.onTertiaryContainer,
              child: Icon(icon),
            ),
            const Spacer(),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _ShortcutGrid extends StatelessWidget {
  final VoidCallback onMarketplace;
  final VoidCallback onOrders;
  final VoidCallback onSpending;
  final VoidCallback onFavorites;

  const _ShortcutGrid({
    required this.onMarketplace,
    required this.onOrders,
    required this.onSpending,
    required this.onFavorites,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.5,
      children: [
        _ShortcutTile(Icons.store_mall_directory, 'Marketplace', onMarketplace),
        _ShortcutTile(Icons.list_alt, 'Orders', onOrders),
        _ShortcutTile(Icons.insights, 'Spending', onSpending),
        _ShortcutTile(Icons.favorite_border, 'Favourites', onFavorites),
      ],
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ShortcutTile(this.icon, this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
        TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(icon, size: 42, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

String _money(double value) => '\$${value.toStringAsFixed(2)}';
