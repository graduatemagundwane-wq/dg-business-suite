import 'package:flutter/material.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final List<Map<String, dynamic>> expenses = [];

  final TextEditingController _titleController =
      TextEditingController();

  final TextEditingController _amountController =
      TextEditingController();

  double get totalExpenses {
    double total = 0;

    for (final expense in expenses) {
      total += expense['amount'];
    }

    return total;
  }

  void addExpense() {
    if (_titleController.text.isEmpty ||
        _amountController.text.isEmpty) {
      return;
    }

    setState(() {
      expenses.add({
        'title': _titleController.text,
        'amount':
            double.tryParse(_amountController.text) ?? 0,
      });
    });

    _titleController.clear();
    _amountController.clear();

    Navigator.pop(context);
  }

  void showAddExpenseDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Expense'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Expense Name',
                ),
              ),
              TextField(
                controller: _amountController,
                keyboardType:
                    TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: addExpense,
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: showAddExpenseDialog,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: ListTile(
              leading: const Icon(
                Icons.money_off,
              ),
              title:
                  const Text('Total Expenses'),
              subtitle: Text(
                '\$${totalExpenses.toStringAsFixed(2)}',
              ),
            ),
          ),
          Expanded(
            child: expenses.isEmpty
                ? const Center(
                    child: Text(
                      'No Expenses Added',
                    ),
                  )
                : ListView.builder(
                    itemCount: expenses.length,
                    itemBuilder:
                        (context, index) {
                      final expense =
                          expenses[index];

                      return ListTile(
                        leading:
                            const Icon(
                          Icons.receipt,
                        ),
                        title: Text(
                          expense['title'],
                        ),
                        trailing: Text(
                          '\$${expense['amount']}',
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}