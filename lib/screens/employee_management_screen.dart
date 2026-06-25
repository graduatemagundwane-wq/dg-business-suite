import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../database/employee_services.dart';

class EmployeeManagementScreen extends StatefulWidget {
  const EmployeeManagementScreen({super.key});

  @override
  State<EmployeeManagementScreen> createState() =>
      _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState
    extends State<EmployeeManagementScreen> {
  final EmployeeService _employeeService =
      EmployeeService.instance;

  List<Employee> employees = [];

  @override
  void initState() {
    super.initState();
    loadEmployees();
  }

  Future<void> loadEmployees() async {
    final data = await _employeeService.getEmployees();

    setState(() {
      employees = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Employee Management"),
        centerTitle: true,
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // TODO: Add Employee Screen
        },
        icon: const Icon(Icons.person_add),
        label: const Text("Add Employee"),
      ),

      body: employees.isEmpty
          ? const Center(
              child: Text(
                "No employees found",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: employees.length,
              itemBuilder: (context, index) {
                final employee = employees[index];

                return Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue,
                      child: Text(
                        employee.employeeName[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    title: Text(
                      employee.employeeName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    subtitle: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 5),

                        Text(
                          "Code: ${employee.employeeCode}",
                        ),

                        Text(
                          "Sales: \$${employee.totalSales.toStringAsFixed(2)}",
                        ),

                        Text(
                          employee.active
                              ? "Status: Active"
                              : "Status: Inactive",
                        ),
                      ],
                    ),

                    trailing: PopupMenuButton(
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: "activate",
                          child: Text("Activate"),
                        ),
                        const PopupMenuItem(
                          value: "deactivate",
                          child: Text("Deactivate"),
                        ),
                        const PopupMenuItem(
                          value: "delete",
                          child: Text("Delete"),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}