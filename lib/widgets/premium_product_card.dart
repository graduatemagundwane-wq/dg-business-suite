import 'dart:io';

import 'package:flutter/material.dart';

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
    final bool lowStock =
        stock <= (product['low_stock_limit'] ?? 10);

    final bool marketplace =
        product['marketplace_visible'] == 1;

    final imagePath =
        product['image_path']?.toString() ?? '';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [

              Expanded(
                child: Center(
                  child: imagePath.isNotEmpty
                      ? Image.file(
                          File(imagePath),
                          fit: BoxFit.contain,
                        )
                      : const Icon(
                          Icons.inventory_2_rounded,
                          size: 70,
                          color: Colors.blue,
                        ),
                ),
              ),

              const SizedBox(height: 10),

              Text(
                product['product_name'] ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                "\$${product['selling_price']}",
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [

                  Chip(
                    avatar: const Icon(
                      Icons.inventory,
                      size: 16,
                    ),
                    label: Text("Stock $stock"),
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
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}