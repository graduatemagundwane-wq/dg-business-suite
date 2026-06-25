import 'package:flutter/material.dart';

class EmployeeDashboard extends StatelessWidget {
  final String employeeName;
  final double todaySales;
  final int transactions;
  final int itemsSold;
  final int rank;

  const EmployeeDashboard({
    super.key,
    required this.employeeName,
    this.todaySales = 0,
    this.transactions = 0,
    this.itemsSold = 0,
    this.rank = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee Dashboard'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person),
                ),
                title: Text(employeeName),
                subtitle: const Text('Employee'),
              ),
            ),

            const SizedBox(height: 16),

            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  _buildCard(
                    'Today Sales',
                    '\$${todaySales.toStringAsFixed(2)}',
                    Icons.attach_money,
                  ),
                  _buildCard(
                    'Transactions',
                    '$transactions',
                    Icons.receipt_long,
                  ),
                  _buildCard(
                    'Items Sold',
                    '$itemsSold',
                    Icons.inventory,
                  ),
                  _buildCard(
                    'Rank',
                    '#$rank',
                    Icons.emoji_events,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(
    String title,
    String value,
    IconData icon,
  ) {
    return Card(
      elevation: 4,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(title),
        ],
      ),
    );
  }
}