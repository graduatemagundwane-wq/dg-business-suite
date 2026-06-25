import 'package:flutter/material.dart';

class LowStockScreen extends StatelessWidget {
  const LowStockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final products = [
      {'name': 'Bread', 'stock': 2},
      {'name': 'Milk', 'stock': 3},
      {'name': 'Sugar', 'stock': 1},
      {'name': 'Cooking Oil', 'stock': 4},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Low Stock Alerts'),
      ),
      body: ListView.builder(
        itemCount: products.length,
        itemBuilder: (context, index) {
          final item = products[index];

          return Card(
            margin: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            child: ListTile(
              leading: const Icon(
                Icons.warning,
                color: Colors.orange,
              ),
              title: Text(
                item['name'].toString(),
              ),
              subtitle: Text(
                'Stock Left: ${item['stock']}',
              ),
              trailing: const Text(
                'LOW',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}