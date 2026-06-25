import 'package:flutter/material.dart';

class SalesHistoryScreen extends StatelessWidget {
  const SalesHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales History'),
      ),
      body: ListView.builder(
        itemCount: 10,
        itemBuilder: (context, index) {
          return Card(
            margin: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.receipt_long),
              ),
              title: Text(
                'Receipt DG-${(index + 1).toString().padLeft(6, '0')}',
              ),
              subtitle: Text(
                'Cashier: Employee ${index + 1}',
              ),
              trailing: Text(
                '\$${((index + 1) * 12.50).toStringAsFixed(2)}',
                style: const TextStyle(
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