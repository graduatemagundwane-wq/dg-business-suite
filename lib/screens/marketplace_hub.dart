import 'dart:io';

import 'package:flutter/material.dart';

import '../services/marketplace_service.dart';
import 'favorites_screen.dart';
import 'shop_profile_screen.dart';

class MarketplaceHubScreen extends StatefulWidget {
  const MarketplaceHubScreen({super.key});

  @override
  State<MarketplaceHubScreen> createState() => _MarketplaceHubScreenState();
}

class _MarketplaceHubScreenState extends State<MarketplaceHubScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';
  bool _marketplaceOnly = false;
  late Future<void> _loadFuture;
  List<String> _categories = const ['All'];
  List<MarketplaceProduct> _products = [];
  List<MarketplaceShop> _nearbyShops = [];

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadMarketplace();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMarketplace() async {
    final categories = await MarketplaceService.instance.getCategories();
    final products = await MarketplaceService.instance.getMarketplaceProducts(
      search: _searchController.text,
      category: _selectedCategory,
      marketplaceOnly: _marketplaceOnly,
    );
    final nearbyShops = await MarketplaceService.instance.getNearbyShops();

    if (!mounted) return;

    setState(() {
      _categories = categories;
      _products = products;
      _nearbyShops = nearbyShops;
    });
  }

  void _refresh() {
    setState(() {
      _loadFuture = _loadMarketplace();
    });
  }

  void _openShop(int shopId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShopProfileScreen(shopId: shopId),
      ),
    ).then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketplace'),
        actions: [
          IconButton(
            tooltip: 'Favourite shops',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FavoritesScreen()),
              ).then((_) => _refresh());
            },
            icon: const Icon(Icons.favorite_border),
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _products.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: _loadMarketplace,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MarketplaceHeader(
                          productCount: _products.length,
                          shopCount: _nearbyShops.length,
                        ),
                        const SizedBox(height: 14),
                        SearchBar(
                          controller: _searchController,
                          hintText: 'Search products, shops or categories...',
                          leading: const Icon(Icons.search),
                          trailing: [
                            IconButton(
                              tooltip: 'Search',
                              onPressed: _refresh,
                              icon: const Icon(Icons.tune),
                            ),
                          ],
                          onChanged: (_) => _refresh(),
                        ),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              FilterChip(
                                label: const Text('Marketplace'),
                                selected: _marketplaceOnly,
                                onSelected: (value) {
                                  setState(() => _marketplaceOnly = value);
                                  _refresh();
                                },
                              ),
                              const SizedBox(width: 8),
                              ..._categories.map(
                                (category) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(category),
                                    selected: _selectedCategory == category,
                                    onSelected: (_) {
                                      setState(() {
                                        _selectedCategory = category;
                                      });
                                      _refresh();
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        _SectionTitle(
                          title: 'Promotions',
                          subtitle: 'Featured marketplace-ready deals',
                          icon: Icons.local_offer,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(height: 10),
                        _PromotionStrip(
                          products: _products
                              .where((product) => product.promoted)
                              .take(5)
                              .toList(),
                          onOpenShop: _openShop,
                        ),
                        const SizedBox(height: 18),
                        _SectionTitle(
                          title: 'Nearby Shops',
                          subtitle: 'Distance and ratings use verified marketplace data',
                          icon: Icons.near_me,
                          color: colorScheme.tertiary,
                        ),
                        const SizedBox(height: 10),
                        _NearbyShopStrip(
                          shops: _nearbyShops,
                          onOpenShop: _openShop,
                        ),
                        const SizedBox(height: 18),
                        _SectionTitle(
                          title: 'New Arrivals',
                          subtitle: 'Products from connected local stores',
                          icon: Icons.auto_awesome,
                          color: colorScheme.secondary,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_products.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyMarketplace(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.crossAxisExtent;
                        final columns = width >= 900 ? 4 : width >= 620 ? 3 : 2;

                        return SliverGrid.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            childAspectRatio: width >= 620 ? 0.76 : 0.68,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _products.length,
                          itemBuilder: (context, index) {
                            final product = _products[index];

                            return _MarketplaceProductCard(
                              product: product,
                              onTap: () => _openShop(product.shopId),
                            );
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MarketplaceHeader extends StatelessWidget {
  final int productCount;
  final int shopCount;

  const _MarketplaceHeader({
    required this.productCount,
    required this.shopCount,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Shop nearby with Double Gee',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: colorScheme.onPrimaryContainer,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '$productCount products available from $shopCount local shops',
            style: TextStyle(color: colorScheme.onPrimaryContainer),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _SectionTitle({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          foregroundColor: color,
          child: Icon(icon),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _PromotionStrip extends StatelessWidget {
  final List<MarketplaceProduct> products;
  final ValueChanged<int> onOpenShop;

  const _PromotionStrip({
    required this.products,
    required this.onOpenShop,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const _InlineEmptyState(message: 'Promotions will appear here.');
    }

    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final product = products[index];

          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => onOpenShop(product.shopId),
            child: Container(
              width: 220,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.local_offer),
                  const Spacer(),
                  Text(
                    product.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text('${_money(product.sellingPrice)} • ${product.shopName}'),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NearbyShopStrip extends StatelessWidget {
  final List<MarketplaceShop> shops;
  final ValueChanged<int> onOpenShop;

  const _NearbyShopStrip({
    required this.shops,
    required this.onOpenShop,
  });

  @override
  Widget build(BuildContext context) {
    if (shops.isEmpty) {
      return const _InlineEmptyState(message: 'Nearby shops will appear here.');
    }

    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: shops.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final shop = shops[index];

          return SizedBox(
            width: 230,
            child: Card(
              child: ListTile(
                onTap: () => onOpenShop(shop.id),
                leading: const CircleAvatar(child: Icon(Icons.storefront)),
                title: Text(
                  shop.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${shop.productCount} products • 2.4 km\n${shop.rating.toStringAsFixed(1)} rating',
                ),
                isThreeLine: true,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MarketplaceProductCard extends StatelessWidget {
  final MarketplaceProduct product;
  final VoidCallback onTap;

  const _MarketplaceProductCard({
    required this.product,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1.5,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ProductImage(path: product.imagePath),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _Badge(
                      label: product.available ? 'Available' : 'Out',
                      color: product.available
                          ? colorScheme.tertiary
                          : colorScheme.error,
                    ),
                  ),
                  if (product.marketplaceVisible)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _Badge(
                        label: 'Marketplace',
                        color: colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _money(product.sellingPrice),
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.shopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${product.category} • 2.4 km • 4.8 rating',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
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

class _ProductImage extends StatelessWidget {
  final String? path;

  const _ProductImage({this.path});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (path != null && path!.isNotEmpty && File(path!).existsSync()) {
      return Image.file(File(path!), fit: BoxFit.cover);
    }

    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.shopping_bag,
        size: 58,
        color: colorScheme.primary,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  final String message;

  const _InlineEmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text(message),
    );
  }
}

class _EmptyMarketplace extends StatelessWidget {
  const _EmptyMarketplace();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.store_mall_directory,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'No marketplace products yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Products marked for marketplace visibility will appear here.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

String _money(double value) => '\$${value.toStringAsFixed(2)}';
