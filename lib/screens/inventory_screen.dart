import 'dart:io';

import 'package:flutter/material.dart';

import '../database/local_db.dart';
import '../theme/app_theme.dart';
import 'add_product.dart';

enum _InventoryFilter {
  all,
  lowStock,
  outOfStock,
  marketplace,
}

class InventoryScreen extends StatefulWidget {
  final int shopId;

  const InventoryScreen({
    super.key,
    required this.shopId,
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];

  int totalProducts = 0;
  int lowStockProducts = 0;
  int outOfStockProducts = 0;
  double inventoryValue = 0;

  bool _loading = true;
  _InventoryFilter _selectedFilter = _InventoryFilter.all;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final products = await LocalDatabase.instance.getAllProducts(widget.shopId);

    if (!mounted) return;

    setState(() {
      _products = products;
      _filteredProducts = _applyFilters(products);
      _updateStats(products);
      _loading = false;
    });
  }

  void _updateStats(List<Map<String, dynamic>> products) {
    totalProducts = products.length;

    lowStockProducts = products.where((product) {
      final stock = _asInt(product['stock_quantity']);
      final limit = _asInt(product['low_stock_limit'], fallback: 10);
      return stock <= limit && stock > 0;
    }).length;

    outOfStockProducts = products.where((product) {
      return _asInt(product['stock_quantity']) <= 0;
    }).length;

    inventoryValue = products.fold<double>(0, (sum, product) {
      final quantity = _asInt(product['stock_quantity']);
      final buyingPrice = _asDouble(product['buying_price']);
      return sum + quantity * buyingPrice;
    });
  }

  void _search(String value) {
    setState(() {
      _filteredProducts = _applyFilters(_products);
    });
  }

  void _setFilter(_InventoryFilter filter) {
    setState(() {
      _selectedFilter = filter;
      _filteredProducts = _applyFilters(_products);
    });
  }

  List<Map<String, dynamic>> _applyFilters(
    List<Map<String, dynamic>> products,
  ) {
    final query = _searchController.text.trim().toLowerCase();

    return products.where((product) {
      final stock = _asInt(product['stock_quantity']);
      final lowStockLimit = _asInt(product['low_stock_limit'], fallback: 10);
      final marketplaceVisible = _asBool(product['marketplace_visible']);
      final isLowStock = stock <= lowStockLimit && stock > 0;
      final isOutOfStock = stock <= 0;

      final matchesFilter = switch (_selectedFilter) {
        _InventoryFilter.all => true,
        _InventoryFilter.lowStock => isLowStock,
        _InventoryFilter.outOfStock => isOutOfStock,
        _InventoryFilter.marketplace => marketplaceVisible,
      };

      if (!matchesFilter) return false;

      if (query.isEmpty) return true;

      final name = _field(product, 'product_name');
      final barcode = _field(product, 'barcode');
      final sku = _field(product, 'sku');
      final category = _categoryLabel(product).toLowerCase();

      return name.contains(query) ||
          barcode.contains(query) ||
          sku.contains(query) ||
          category.contains(query);
    }).toList();
  }

  Future<void> _deleteProduct(int productId) async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Product'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (delete != true) return;

    await LocalDatabase.instance.deleteProduct(productId);
    await _loadProducts();
  }

  Future<void> _openAddProduct() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddProductScreen(
          shopId: widget.shopId,
        ),
      ),
    );

    if (result == true) {
      await _loadProducts();
    }
  }

  Future<void> _openEditProduct(Map<String, dynamic> product) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddProductScreen(
          shopId: widget.shopId,
          product: product,
        ),
      ),
    );

    if (result == true) {
      await _loadProducts();
    }
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final stock = _asInt(product['stock_quantity']);
    final lowStock = _asInt(product['low_stock_limit'], fallback: 10);
    final buyingPrice = _asDouble(product['buying_price']);
    final sellingPrice = _asDouble(product['selling_price']);
    final profit = sellingPrice - buyingPrice;
    final isLowStock = stock <= lowStock && stock > 0;
    final isOutOfStock = stock <= 0;
    final marketplaceVisible = _asBool(product['marketplace_visible']);
    final imagePath = (product['image_path'] ?? '').toString();

    return Card(
      elevation: 3,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.16),
      surfaceTintColor: colorScheme.surfaceTint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openEditProduct(product),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProductImage(imagePath: imagePath),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (product['product_name'] ?? 'Unnamed Product')
                              .toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _categoryLabel(product),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (marketplaceVisible)
                              _StatusBadge(
                                label: 'Marketplace',
                                icon: Icons.storefront,
                                color: colorScheme.primary,
                              ),
                            if (isLowStock)
                              _StatusBadge(
                                label: 'Low Stock',
                                icon: Icons.warning_amber,
                                color: Colors.orange,
                              ),
                            if (isOutOfStock)
                              _StatusBadge(
                                label: 'Out of Stock',
                                icon: Icons.cancel_outlined,
                                color: colorScheme.error,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Product actions',
                    onSelected: (value) {
                      if (value == 'edit') {
                        _openEditProduct(product);
                      }

                      if (value == 'delete') {
                        _deleteProduct(product['id'] as int);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _InfoPill(
                    label: 'Barcode',
                    value: _displayValue(product['barcode']),
                  ),
                  _InfoPill(
                    label: 'Supplier',
                    value: _supplierLabel(product),
                  ),
                  _InfoPill(
                    label: 'Buying',
                    value: '\$${buyingPrice.toStringAsFixed(2)}',
                  ),
                  _InfoPill(
                    label: 'Selling',
                    value: '\$${sellingPrice.toStringAsFixed(2)}',
                  ),
                  _InfoPill(
                    label: 'Profit',
                    value: '\$${profit.toStringAsFixed(2)}',
                  ),
                  _InfoPill(
                    label: 'Stock',
                    value: stock.toString(),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openEditProduct(product),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    tooltip: 'Delete product',
                    onPressed: () => _deleteProduct(product['id'] as int),
                    icon: const Icon(Icons.delete_outline),
                    color: colorScheme.error,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        onPressed: _openAddProduct,
        icon: const Icon(Icons.add_box_rounded),
        label: const Text(
          'Add Product',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 820;
                final horizontalPadding = isWide ? 24.0 : 12.0;
                final crossAxisCount = constraints.maxWidth >= 1150
                    ? 3
                    : constraints.maxWidth >= 720
                        ? 2
                        : 1;

                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        16,
                        horizontalPadding,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Inventory Overview',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Manage stock, pricing, and product readiness.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildStatsGrid(crossAxisCount: isWide ? 4 : 2),
                            const SizedBox(height: 16),
                            _buildInventoryHealthCard(),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _searchController,
                              onChanged: _search,
                              decoration: const InputDecoration(
                                hintText:
                                    'Search products, barcode or category...',
                                prefixIcon: Icon(Icons.search),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildFilterChips(),
                          ],
                        ),
                      ),
                    ),
                    if (_filteredProducts.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text('No Products Found'),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          16,
                          horizontalPadding,
                          96,
                        ),
                        sliver: SliverGrid.builder(
                          itemCount: _filteredProducts.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: isWide ? 1.05 : 1.12,
                            mainAxisExtent: 360,
                          ),
                          itemBuilder: (context, index) {
                            return _buildProductCard(_filteredProducts[index]);
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildStatsGrid({required int crossAxisCount}) {
    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: crossAxisCount == 4 ? 1.55 : 1.45,
      children: [
        _dashboardCard(
          Icons.inventory_2,
          'Products',
          totalProducts.toString(),
          Colors.blue,
        ),
        _dashboardCard(
          Icons.attach_money,
          'Inventory Value',
          '\$${inventoryValue.toStringAsFixed(2)}',
          Colors.green,
        ),
        _dashboardCard(
          Icons.warning_amber,
          'Low Stock',
          lowStockProducts.toString(),
          Colors.orange,
        ),
        _dashboardCard(
          Icons.cancel,
          'Out Of Stock',
          outOfStockProducts.toString(),
          Colors.red,
        ),
      ],
    );
  }

  Widget _buildInventoryHealthCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final health = totalProducts == 0
        ? 0
        : (((totalProducts - lowStockProducts - outOfStockProducts) /
                    totalProducts) *
                100)
            .clamp(0, 100)
            .round();

    return Card(
      elevation: 4,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                  child: const Icon(Icons.monitor_heart_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Inventory Health',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '$health%',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: health / 100,
                minHeight: 8,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _HealthChip(
                  label: 'Low Stock Count',
                  value: lowStockProducts.toString(),
                ),
                const _HealthChip(
                  label: 'Best Selling Product',
                  value: 'Coming soon',
                ),
                const _HealthChip(
                  label: 'Highest Profit Product',
                  value: 'Coming soon',
                ),
                const _HealthChip(
                  label: 'Slow Moving Product',
                  value: 'Coming soon',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filterChip('All', _InventoryFilter.all),
          _filterChip('Low Stock', _InventoryFilter.lowStock),
          _filterChip('Out Of Stock', _InventoryFilter.outOfStock),
          _filterChip('Marketplace', _InventoryFilter.marketplace),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _InventoryFilter filter) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: _selectedFilter == filter,
        onSelected: (_) => _setFilter(filter),
      ),
    );
  }

  Widget _dashboardCard(
    IconData icon,
    String title,
    String value,
    Color color,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 4,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: color.withValues(alpha: 0.14),
              foregroundColor: color,
              child: Icon(icon),
            ),
            const SizedBox(height: 14),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value == 1;
    final text = value?.toString().toLowerCase();
    return text == 'true' || text == '1';
  }

  String _field(Map<String, dynamic> product, String key) {
    return (product[key] ?? '').toString().toLowerCase();
  }

  String _displayValue(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? 'Not set' : text;
  }

  String _categoryLabel(Map<String, dynamic> product) {
    final categoryName = product['category_name']?.toString().trim();
    if (categoryName != null && categoryName.isNotEmpty) {
      return categoryName;
    }

    final category = product['category']?.toString().trim();
    if (category != null && category.isNotEmpty) {
      return category;
    }

    final categoryId = product['category_id']?.toString().trim();
    if (categoryId != null && categoryId.isNotEmpty) {
      return 'Category #$categoryId';
    }

    return 'Uncategorized';
  }

  String _supplierLabel(Map<String, dynamic> product) {
    return _displayValue(product['supplier_name'] ?? product['supplier']);
  }
}

class _ProductImage extends StatelessWidget {
  final String imagePath;

  const _ProductImage({
    required this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (imagePath.isEmpty) {
      return _ImageFallback(colorScheme: colorScheme);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.file(
        File(imagePath),
        width: 82,
        height: 82,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _ImageFallback(colorScheme: colorScheme),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  final ColorScheme colorScheme;

  const _ImageFallback({
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 82,
      height: 82,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        Icons.inventory_2_outlined,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _StatusBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final String value;

  const _InfoPill({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 112,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthChip extends StatelessWidget {
  final String label;
  final String value;

  const _HealthChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
