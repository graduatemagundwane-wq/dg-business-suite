import 'dart:io';

import 'package:flutter/material.dart';

import '../database/local_db.dart';
import '../services/barcode_service.dart';
import '../theme/app_theme.dart';
import 'add_product.dart';
import 'barcode_scan.dart';

enum _InventoryFilter {
  all,
  lowStock,
  outOfStock,
  marketplace,
}

enum _StockAdjustmentReason {
  manualCount,
  damaged,
  expired,
  returned,
  supplierRestock,
  correction,
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
  bool _stockTakingMode = false;
  _InventoryFilter _selectedFilter = _InventoryFilter.all;
  final Map<int, TextEditingController> _countControllers = {};
  final List<_StockAdjustmentRecord> _adjustmentHistory = [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final controller in _countControllers.values) {
      controller.dispose();
    }
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

  Future<void> _openAddProductWithBarcode(String barcode) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddProductScreen(
          shopId: widget.shopId,
          initialBarcode: barcode,
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

  Future<void> _scanBarcode() async {
    final barcode = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const BarcodeScanScreen(),
      ),
    );

    if (barcode == null || barcode.trim().isEmpty) return;

    final product = await BarcodeService.instance.findProductByBarcode(
      shopId: widget.shopId,
      barcode: barcode,
    );

    if (!mounted) return;

    if (product != null) {
      _searchController.text = barcode;
      _search(barcode);
      await _showQuickStockUpdate(product);
      return;
    }

    final create = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Barcode Not Found'),
        content: Text('Create a new product with barcode $barcode?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create Product'),
          ),
        ],
      ),
    );

    if (create == true) {
      await _openAddProductWithBarcode(barcode);
    }
  }

  Future<void> _showQuickStockUpdate(Map<String, dynamic> product) async {
    final stockController = TextEditingController(
      text: _asInt(product['stock_quantity']).toString(),
    );
    var reason = _StockAdjustmentReason.manualCount;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text((product['product_name'] ?? 'Product').toString()),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Current Stock: ${product['stock_quantity'] ?? 0}'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: stockController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'New Stock Count',
                      prefixIcon: Icon(Icons.inventory),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<_StockAdjustmentReason>(
                    initialValue: reason,
                    decoration: const InputDecoration(labelText: 'Reason'),
                    items: _StockAdjustmentReason.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(_reasonLabel(value)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => reason = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) {
      stockController.dispose();
      return;
    }

    final previous = _asInt(product['stock_quantity']);
    final next = int.tryParse(stockController.text.trim()) ?? previous;
    stockController.dispose();

    await _saveStockAdjustment(
      product: product,
      previousQuantity: previous,
      newQuantity: next,
      reason: reason,
    );
  }

  Future<void> _saveStockAdjustment({
    required Map<String, dynamic> product,
    required int previousQuantity,
    required int newQuantity,
    required _StockAdjustmentReason reason,
    bool reload = true,
  }) async {
    final updatedProduct = Map<String, dynamic>.from(product);
    updatedProduct['stock_quantity'] = newQuantity;
    await LocalDatabase.instance.updateProduct(updatedProduct);

    _adjustmentHistory.insert(
      0,
      _StockAdjustmentRecord(
        productName: (product['product_name'] ?? 'Unknown Product').toString(),
        previousQuantity: previousQuantity,
        newQuantity: newQuantity,
        reason: _reasonLabel(reason),
        employee: 'Current User',
        createdAt: DateTime.now(),
      ),
    );

    if (reload) {
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
                            _StatusBadge(
                              label: _stockStatus(stock, lowStock),
                              icon: Icons.insights,
                              color: stock > lowStock * 3
                                  ? Colors.green
                                  : colorScheme.primary,
                            ),
                            _StatusBadge(
                              label: stock > lowStock * 3
                                  ? 'Fast-moving'
                                  : 'Slow-moving',
                              icon: Icons.speed,
                              color: stock > lowStock * 3
                                  ? Colors.green
                                  : Colors.blueGrey,
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
                  const _InfoPill(
                    label: 'Restocked',
                    value: 'Not recorded',
                  ),
                  const _InfoPill(
                    label: 'Last Sold',
                    value: 'Not recorded',
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
        title: Text(_stockTakingMode ? 'Stock Taking' : 'Inventory'),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Scan Barcode',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _scanBarcode,
          ),
          IconButton(
            tooltip: _stockTakingMode ? 'Inventory' : 'Stock Taking',
            icon: Icon(
              _stockTakingMode ? Icons.inventory_2 : Icons.fact_check,
            ),
            onPressed: () {
              setState(() {
                _stockTakingMode = !_stockTakingMode;
                _syncCountControllers();
              });
            },
          ),
        ],
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
          : _stockTakingMode
              ? _buildStockTakingMode()
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

  Widget _buildStockTakingMode() {
    _syncCountControllers();

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth >= 820 ? 24.0 : 12.0;

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                16,
                horizontalPadding,
                8,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Easy Stock Taking',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Count multiple products, review differences, then save all adjustments.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: _search,
                            decoration: const InputDecoration(
                              hintText: 'Search products or barcode...',
                              prefixIcon: Icon(Icons.search),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _saveBulkStockAdjustments,
                          icon: const Icon(Icons.save),
                          label: const Text('Save'),
                        ),
                      ],
                    ),
                    if (_adjustmentHistory.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _AdjustmentHistoryCard(records: _adjustmentHistory),
                    ],
                  ],
                ),
              ),
            ),
            if (_filteredProducts.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('No products found')),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  8,
                  horizontalPadding,
                  96,
                ),
                sliver: SliverList.builder(
                  itemCount: _filteredProducts.length,
                  itemBuilder: (context, index) {
                    final product = _filteredProducts[index];
                    final id = product['id'] as int;

                    return _StockTakingCard(
                      product: product,
                      controller: _countControllers[id]!,
                      currentStock: _asInt(product['stock_quantity']),
                      buyingPrice: _asDouble(product['buying_price']),
                      sellingPrice: _asDouble(product['selling_price']),
                      onChanged: () => setState(() {}),
                      onIncrease: () {
                        final current =
                            int.tryParse(_countControllers[id]!.text) ??
                                _asInt(product['stock_quantity']);
                        _countControllers[id]!.text = (current + 1).toString();
                        setState(() {});
                      },
                      onDecrease: () {
                        final current =
                            int.tryParse(_countControllers[id]!.text) ??
                                _asInt(product['stock_quantity']);
                        _countControllers[id]!.text =
                            (current - 1).clamp(0, 999999).toString();
                        setState(() {});
                      },
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  void _syncCountControllers() {
    for (final product in _products) {
      final id = product['id'];
      if (id is! int) continue;
      _countControllers.putIfAbsent(
        id,
        () => TextEditingController(
          text: _asInt(product['stock_quantity']).toString(),
        ),
      );
    }
  }

  Future<void> _saveBulkStockAdjustments() async {
    var saved = 0;

    for (final product in _products) {
      final id = product['id'];
      if (id is! int) continue;

      final controller = _countControllers[id];
      if (controller == null) continue;

      final previous = _asInt(product['stock_quantity']);
      final next = int.tryParse(controller.text.trim()) ?? previous;
      if (previous == next) continue;

      await _saveStockAdjustment(
        product: product,
        previousQuantity: previous,
        newQuantity: next,
        reason: _StockAdjustmentReason.manualCount,
        reload: false,
      );
      saved++;
    }

    await _loadProducts();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$saved stock adjustment${saved == 1 ? '' : 's'} saved')),
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

  String _stockStatus(int stock, int lowStockLimit) {
    if (stock <= 0) return 'Out';
    if (stock <= lowStockLimit) return 'Low';
    return 'Healthy';
  }

  static String _reasonLabel(_StockAdjustmentReason reason) {
    switch (reason) {
      case _StockAdjustmentReason.manualCount:
        return 'Manual Count';
      case _StockAdjustmentReason.damaged:
        return 'Damaged';
      case _StockAdjustmentReason.expired:
        return 'Expired';
      case _StockAdjustmentReason.returned:
        return 'Returned';
      case _StockAdjustmentReason.supplierRestock:
        return 'Supplier Restock';
      case _StockAdjustmentReason.correction:
        return 'Correction';
    }
  }
}

class _StockTakingCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final TextEditingController controller;
  final int currentStock;
  final double buyingPrice;
  final double sellingPrice;
  final VoidCallback onChanged;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;

  const _StockTakingCard({
    required this.product,
    required this.controller,
    required this.currentStock,
    required this.buyingPrice,
    required this.sellingPrice,
    required this.onChanged,
    required this.onIncrease,
    required this.onDecrease,
  });

  @override
  Widget build(BuildContext context) {
    final counted = int.tryParse(controller.text.trim()) ?? currentStock;
    final difference = counted - currentStock;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (product['product_name'] ?? 'Unnamed Product').toString(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                Chip(
                  label: Text(
                    difference >= 0 ? '+$difference' : '$difference',
                  ),
                  backgroundColor: difference == 0
                      ? colorScheme.surfaceContainerHighest
                      : difference > 0
                          ? Colors.green.withValues(alpha: 0.16)
                          : colorScheme.errorContainer,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Text('Barcode: ${(product['barcode'] ?? 'Not set')}'),
                Text('Current Stock: $currentStock'),
                Text('Buying: \$${buyingPrice.toStringAsFixed(2)}'),
                Text('Selling: \$${sellingPrice.toStringAsFixed(2)}'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: onDecrease,
                  icon: const Icon(Icons.remove),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(
                      labelText: 'Counted Stock',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: onIncrease,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AdjustmentHistoryCard extends StatelessWidget {
  final List<_StockAdjustmentRecord> records;

  const _AdjustmentHistoryCard({required this.records});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.history),
        title: Text('Stock Adjustment History (${records.length})'),
        children: records.take(8).map((record) {
          return ListTile(
            dense: true,
            title: Text(record.productName),
            subtitle: Text(
              '${record.reason} • ${record.employee} • ${record.createdAt}',
            ),
            trailing: Text(
              '${record.previousQuantity} → ${record.newQuantity} (${record.difference >= 0 ? '+' : ''}${record.difference})',
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StockAdjustmentRecord {
  final String productName;
  final int previousQuantity;
  final int newQuantity;
  final String reason;
  final String employee;
  final DateTime createdAt;

  const _StockAdjustmentRecord({
    required this.productName,
    required this.previousQuantity,
    required this.newQuantity,
    required this.reason,
    required this.employee,
    required this.createdAt,
  });

  int get difference => newQuantity - previousQuantity;
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
