import 'package:flutter/material.dart';

class SupplierScreen extends StatefulWidget {
  const SupplierScreen({super.key});

  @override
  State<SupplierScreen> createState() => _SupplierScreenState();
}

class _SupplierScreenState extends State<SupplierScreen> {
  final List<_Supplier> _suppliers = [
    const _Supplier(name: 'Supplier A', category: 'Groceries'),
    const _Supplier(name: 'Supplier B', category: 'Beverages'),
    const _Supplier(name: 'Supplier C', category: 'Stationery'),
  ];

  Future<void> _addSupplier() async {
    final nameController = TextEditingController();
    final categoryController = TextEditingController();
    final phoneController = TextEditingController();

    final supplier = await showDialog<_Supplier>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Supplier'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Supplier Name',
                  prefixIcon: Icon(Icons.business),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: categoryController,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  prefixIcon: Icon(Icons.category),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;

              Navigator.pop(
                context,
                _Supplier(
                  name: name,
                  category: categoryController.text.trim().isEmpty
                      ? 'General'
                      : categoryController.text.trim(),
                  phone: phoneController.text.trim(),
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    nameController.dispose();
    categoryController.dispose();
    phoneController.dispose();

    if (supplier == null) return;

    setState(() => _suppliers.insert(0, supplier));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suppliers'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSupplier,
        icon: const Icon(Icons.add),
        label: const Text('Add Supplier'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _suppliers.length,
        itemBuilder: (context, index) {
          final supplier = _suppliers[index];

          return Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.business)),
              title: Text(supplier.name),
              subtitle: Text(
                supplier.phone.isEmpty
                    ? supplier.category
                    : '${supplier.category}\n${supplier.phone}',
              ),
              isThreeLine: supplier.phone.isNotEmpty,
            ),
          );
        },
      ),
    );
  }
}

class _Supplier {
  final String name;
  final String category;
  final String phone;

  const _Supplier({
    required this.name,
    required this.category,
    this.phone = '',
  });
}
