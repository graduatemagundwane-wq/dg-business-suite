import 'package:flutter/material.dart';

class SupplierScreen extends StatelessWidget {
  const SupplierScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suppliers'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
      body: ListView(
        children: const [
          Card(
            child: ListTile(
              leading: Icon(Icons.business),
              title: Text('Supplier A'),
              subtitle: Text('Groceries'),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.business),
              title: Text('Supplier B'),
              subtitle: Text('Beverages'),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.business),
              title: Text('Supplier C'),
              subtitle: Text('Stationery'),
            ),
          ),
        ],
      ),
    );
  }
}