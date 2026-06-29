import 'package:flutter/material.dart';
import '../database/employee_services.dart';

class AddEmployeeScreen extends StatefulWidget {
  final int shopId;

  const AddEmployeeScreen({
    super.key,
    required this.shopId,
  });

  @override
  State<AddEmployeeScreen> createState() =>
      _AddEmployeeScreenState();
}

class _AddEmployeeScreenState
    extends State<AddEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  final EmployeeService _employeeService =
      EmployeeService.instance;

  bool isLoading = false;

  Future<void> saveEmployee() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
    });

    await _employeeService.addEmployee(
      shopId: widget.shopId,
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      password: _passwordController.text.trim(),
    );

    setState(() {
      isLoading = false;
    });

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Add Employee"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Employee Name",
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Enter employee name";
                  }
                  return null;
                },
              ),

              const SizedBox(height: 15),

              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: "Phone Number",
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Enter phone number";
                  }
                  return null;
                },
              ),

              const SizedBox(height: 15),

              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Password",
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.length < 4) {
                    return "Password too short";
                  }
                  return null;
                },
              ),

              const SizedBox(height: 25),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed:
                      isLoading ? null : saveEmployee,
                  child: isLoading
                      ? const CircularProgressIndicator()
                      : const Text(
                          "Create Employee",
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
