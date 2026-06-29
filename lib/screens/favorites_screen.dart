import 'package:flutter/material.dart';

import '../services/marketplace_service.dart';
import 'shop_profile_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  late Future<List<MarketplaceShop>> _favoritesFuture;

  @override
  void initState() {
    super.initState();
    _favoritesFuture = MarketplaceService.instance.getFavoriteShops();
  }

  void _refresh() {
    setState(() {
      _favoritesFuture = MarketplaceService.instance.getFavoriteShops();
    });
  }

  void _removeFavorite(int shopId) {
    MarketplaceService.instance.toggleFavoriteShop(shopId);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favourite Shops')),
      body: FutureBuilder<List<MarketplaceShop>>(
        future: _favoritesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final shops = snapshot.data!;

          if (shops.isEmpty) {
            return const _FavoritesEmptyState();
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: shops.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final shop = shops[index];

              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.storefront)),
                  title: Text(
                    shop.name,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    '${shop.productCount} products • ${shop.rating.toStringAsFixed(1)} rating',
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove favourite',
                    icon: const Icon(Icons.favorite),
                    onPressed: () => _removeFavorite(shop.id),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ShopProfileScreen(shopId: shop.id),
                      ),
                    ).then((_) => _refresh());
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _FavoritesEmptyState extends StatelessWidget {
  const _FavoritesEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.favorite_border,
              size: 68,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'No favourite shops yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Save shops from marketplace or shop profiles for quick access.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
