import 'dart:io';

import 'package:flutter/material.dart';

class ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onTap;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final image =
        product['image_path'] ?? '';

    final stock =
        product['stock_quantity'] ?? 0;

    final price =
        product['selling_price'] ?? 0;

    return Card(
      child: InkWell(
        borderRadius:
            BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [

              if (image.isNotEmpty)
                ClipRRect(
                  borderRadius:
                      BorderRadius.circular(
                          12),
                  child: Image.file(
                    File(image),
                    height: 70,
                    width: 70,
                    fit: BoxFit.cover,
                  ),
                )
              else
                const CircleAvatar(
                  radius: 32,
                  child: Icon(
                    Icons.inventory_2,
                    size: 32,
                  ),
                ),

              const SizedBox(height: 10),

              Text(
                product['product_name'],
                maxLines: 2,
                overflow:
                    TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                "\$$price",
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.green,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                "Stock : $stock",
                style: TextStyle(
                  color: stock <= 5
                      ? Colors.red
                      : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}