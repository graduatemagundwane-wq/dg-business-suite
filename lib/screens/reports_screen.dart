import 'package:flutter/material.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [
            _reportCard(
              'Daily Report',
              Icons.today,
              Colors.blue,
            ),
            _reportCard(
              'Weekly Report',
              Icons.date_range,
              Colors.green,
            ),
            _reportCard(
              'Monthly Report',
              Icons.calendar_month,
              Colors.orange,
            ),
            _reportCard(
              'Yearly Report',
              Icons.bar_chart,
              Colors.purple,
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportCard(
    String title,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: () {},
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 50,
              color: color,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}