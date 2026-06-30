import 'dart:io';

import 'package:flutter/material.dart';

import '../services/marketplace_service.dart';

class ShopProfileScreen extends StatefulWidget {
  final int shopId;

  const ShopProfileScreen({
    super.key,
    required this.shopId,
  });

  @override
  State<ShopProfileScreen> createState() => _ShopProfileScreenState();
}

class _ShopProfileScreenState extends State<ShopProfileScreen> {
  late Future<_ShopProfileData> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  Future<_ShopProfileData> _load() async {
    final shop = await MarketplaceService.instance.getShopProfile(widget.shopId);
    final products = await MarketplaceService.instance.getShopProducts(widget.shopId);

    return _ShopProfileData(shop: shop, products: products);
  }

  void _toggleFavorite() {
    MarketplaceService.instance.toggleFavoriteShop(widget.shopId);
    setState(() => _loadFuture = _load());
  }

  void _showPlaceholder(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature is ready for backend integration.')),
    );
  }

  void _showComplaintDialog() {
    final subjectController = TextEditingController();
    final detailsController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report an issue'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: subjectController,
              decoration: const InputDecoration(labelText: 'Subject'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: detailsController,
              minLines: 3,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Details'),
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
              MarketplaceService.instance.saveComplaint(
                MarketplaceComplaintDraft(
                  subject: subjectController.text.trim(),
                  details: detailsController.text.trim(),
                  createdAt: DateTime.now(),
                ),
              );
              Navigator.pop(context);
              _showPlaceholder('Complaint submission');
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ShopProfileData>(
      future: _loadFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final shop = data?.shop;

        return Scaffold(
          appBar: AppBar(
            title: Text(shop?.name ?? 'Shop Profile'),
            actions: [
              IconButton(
                tooltip: 'Favourite shop',
                onPressed: _toggleFavorite,
                icon: Icon(
                  MarketplaceService.instance.isFavoriteShop(widget.shopId)
                      ? Icons.favorite
                      : Icons.favorite_border,
                ),
              ),
            ],
          ),
          body: !snapshot.hasData
              ? const Center(child: CircularProgressIndicator())
              : shop == null
                  ? const Center(child: Text('Shop profile not found'))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _ShopHeader(shop: shop),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _showPlaceholder('Contact'),
                                icon: const Icon(Icons.chat),
                                label: const Text('Contact'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _showPlaceholder('Order'),
                                icon: const Icon(Icons.shopping_cart),
                                label: const Text('Order'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _showComplaintDialog,
                          icon: const Icon(Icons.report_gmailerrorred),
                          label: const Text('Report bad service'),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Available Products',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 8),
                        if (data!.products.isEmpty)
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(18),
                              child: Text('No available products yet.'),
                            ),
                          )
                        else
                          ...data.products.map(
                            (product) => Card(
                              child: ListTile(
                                leading: _ProductThumb(path: product.imagePath),
                                title: Text(product.productName),
                                subtitle: Text(
                                  '${product.category} • ${product.stockQuantity} in stock',
                                ),
                                trailing: Text(
                                  _money(product.sellingPrice),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 18),
                        _RatingPreparationCard(
                          onRateShop: () => _showPlaceholder('Shop rating'),
                          onRateProduct: () => _showPlaceholder('Product rating'),
                        ),
                      ],
                    ),
        );
      },
    );
  }
}

class _ShopProfileData {
  final MarketplaceShop? shop;
  final List<MarketplaceProduct> products;

  const _ShopProfileData({
    required this.shop,
    required this.products,
  });
}

class _ShopHeader extends StatelessWidget {
  final MarketplaceShop shop;

  const _ShopHeader({required this.shop});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                child: const Icon(Icons.storefront, size: 34),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shop.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    Text('Owned by ${shop.ownerName}'),
                    Text('${shop.rating.toStringAsFixed(1)} rating • 2.4 km'),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 26),
          _InfoLine(Icons.location_on, shop.address),
          _InfoLine(Icons.phone, shop.phone),
          const _InfoLine(Icons.schedule, 'Open today • 08:00 - 18:00'),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoLine(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ProductThumb extends StatelessWidget {
  final String? path;

  const _ProductThumb({this.path});

  @override
  Widget build(BuildContext context) {
    if (path != null && path!.isNotEmpty && File(path!).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(path!),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
        ),
      );
    }

    return const CircleAvatar(child: Icon(Icons.shopping_bag));
  }
}

class _RatingPreparationCard extends StatelessWidget {
  final VoidCallback onRateShop;
  final VoidCallback onRateProduct;

  const _RatingPreparationCard({
    required this.onRateShop,
    required this.onRateProduct,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ratings & Feedback',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            const Text('Shop ratings, product ratings and complaints are available for customer feedback.'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onRateShop,
                  icon: const Icon(Icons.star_rate),
                  label: const Text('Rate Shop'),
                ),
                OutlinedButton.icon(
                  onPressed: onRateProduct,
                  icon: const Icon(Icons.reviews),
                  label: const Text('Rate Product'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _money(double value) => '\$${value.toStringAsFixed(2)}';
