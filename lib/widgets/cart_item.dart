import 'package:flutter/material.dart';

class CartItemWidget extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onDelete;

  const CartItemWidget({
    super.key,
    required this.item,
    required this.onIncrease,
    required this.onDecrease,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final quantity = item['quantity'] as int;
    final price =
        (item['selling_price'] as num).toDouble();

    final total = price * quantity;

    return Card(
      margin: const EdgeInsets.symmetric(
        vertical: 4,
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [

                  Text(
                    item['product_name'],
                    style: const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    "\$${total.toStringAsFixed(2)}",
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            IconButton(
              onPressed: onDecrease,
              icon: const Icon(
                Icons.remove_circle,
                color: Colors.red,
              ),
            ),

            Text(
              "$quantity",
              style: const TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            IconButton(
              onPressed: onIncrease,
              icon: const Icon(
                Icons.add_circle,
                color: Colors.green,
              ),
            ),

            IconButton(
              onPressed: onDelete,
              icon: const Icon(
                Icons.delete,
                color: Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }
}