import 'dart:io';

import 'package:flutter/material.dart';

class PremiumCartItem extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onDelete;

  const PremiumCartItem({
    super.key,
    required this.item,
    required this.onIncrease,
    required this.onDecrease,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final imagePath = item['image_path']?.toString() ?? '';
    final quantity = item['quantity'] ?? 1;
    final price =
        (item['selling_price'] as num).toDouble();

    final total = price * quantity;

    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(
        vertical: 6,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [

            ClipRRect(
              borderRadius:
                  BorderRadius.circular(12),
              child: imagePath.isNotEmpty
                  ? Image.file(
                      File(imagePath),
                      width: 65,
                      height: 65,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 65,
                        height: 65,
                        color: Colors.blue.shade50,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.blue,
                        ),
                      ),
                    )
                  : Container(
                      width: 65,
                      height: 65,
                      color: Colors.blue.shade50,
                      child: const Icon(
                        Icons.inventory_2,
                        color: Colors.blue,
                        size: 34,
                      ),
                    ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [

                  Text(
                    item['product_name'],
                    maxLines: 2,
                    overflow:
                        TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    "\$${price.toStringAsFixed(2)}",
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Row(
                    children: [

                      IconButton(
                        onPressed: onDecrease,
                        icon: const Icon(
                          Icons.remove_circle,
                        ),
                      ),

                      Text(
                        "$quantity",
                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),

                      IconButton(
                        onPressed: onIncrease,
                        icon: const Icon(
                          Icons.add_circle,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Column(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [

                Text(
                  "\$${total.toStringAsFixed(2)}",
                  style: const TextStyle(
                    fontWeight:
                        FontWeight.bold,
                    fontSize: 18,
                  ),
                ),

                const SizedBox(height: 10),

                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(
                    Icons.delete_forever,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
