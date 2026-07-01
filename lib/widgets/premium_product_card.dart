import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

class PremiumProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onTap;

  const PremiumProductCard({
    super.key,
    required this.product,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final stock = product['stock_quantity'] ?? 0;
    final bool lowStock = stock <= (product['low_stock_limit'] ?? 10);

    final bool marketplace = product['marketplace_visible'] == 1;

    final imagePath = product['image_path']?.toString() ?? '';

    final theme = Theme.of(context);
    final category = (product['category_name'] ?? product['category'] ?? '')
        .toString()
        .trim();

    return AnimatedContainer(
      duration: AppDurations.fast,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withValues(alpha: 0.09),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.colorScheme.primary.withValues(alpha: 0.06),
                          theme.colorScheme.secondary.withValues(alpha: 0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                    ),
                    child: Center(
                      child: imagePath.isNotEmpty
                          ? Image.file(
                              File(imagePath),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.broken_image_outlined,
                                size: 58,
                              ),
                            )
                          : Icon(
                              Icons.inventory_2_rounded,
                              size: 70,
                              color: theme.colorScheme.primary,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  product['product_name'] ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (category.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Text(
                  "\$${((product['selling_price'] ?? 0) as num).toDouble().toStringAsFixed(2)}",
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 18,
                    color: AppTheme.ink,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    Chip(
                      avatar: const Icon(
                        Icons.inventory,
                        size: 16,
                      ),
                      label: Text("Stock $stock"),
                      visualDensity: VisualDensity.compact,
                    ),
                    if (lowStock)
                      const Chip(
                        avatar: Icon(
                          Icons.warning,
                          size: 16,
                          color: Colors.white,
                        ),
                        label: Text(
                          "LOW",
                          style: TextStyle(
                            color: Colors.white,
                          ),
                        ),
                        backgroundColor: Colors.red,
                        visualDensity: VisualDensity.compact,
                      ),
                    if (marketplace)
                      const Chip(
                        avatar: Icon(
                          Icons.storefront,
                          size: 16,
                          color: Colors.white,
                        ),
                        label: Text(
                          "Marketplace",
                          style: TextStyle(
                            color: Colors.white,
                          ),
                        ),
                        backgroundColor: Colors.green,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
