import 'package:flutter/material.dart';

class CustomerDashboardScreen
    extends StatefulWidget {
  const CustomerDashboardScreen({
    super.key,
  });

  @override
  State<CustomerDashboardScreen>
      createState() =>
          _CustomerDashboardScreenState();
}

class _CustomerDashboardScreenState
    extends State<
        CustomerDashboardScreen> {

  double totalSpent = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text("Customer Dashboard"),
      ),
      body: Padding(
        padding:
            const EdgeInsets.all(16),
        child: Column(
          children: [

            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.account_balance_wallet,
                ),
                title: const Text(
                  "Total Spending",
                ),
                subtitle: Text(
                  "\$${totalSpent.toStringAsFixed(2)}",
                ),
              ),
            ),

            const SizedBox(height: 20),

            const Card(
              child: ListTile(
                leading: Icon(
                  Icons.history,
                ),
                title: Text(
                  "Purchase History",
                ),
                subtitle: Text(
                  "View all purchases",
                ),
              ),
            ),

            const Card(
              child: ListTile(
                leading: Icon(
                  Icons.store,
                ),
                title: Text(
                  "Favourite Shops",
                ),
                subtitle: Text(
                  "Most visited stores",
                ),
              ),
            ),

            const Card(
              child: ListTile(
                leading: Icon(
                  Icons.shopping_bag,
                ),
                title: Text(
                  "Marketplace",
                ),
                subtitle: Text(
                  "Browse products",
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }
}