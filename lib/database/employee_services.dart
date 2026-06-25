import '../models/employee.dart';

class EmployeeService {
  static final EmployeeService instance =
      EmployeeService._internal();

  factory EmployeeService() => instance;

  EmployeeService._internal();

  final List<Employee> _employees = [];

  String generateEmployeeCode() {
    return "DG-EMP-${(_employees.length + 1).toString().padLeft(3, '0')}";
  }

  Future<Employee> addEmployee({
    required int shopId,
    required String name,
    required String phone,
    required String password,
  }) async {
    final employee = Employee(
      id: DateTime.now().millisecondsSinceEpoch,
      shopId: shopId,
      employeeName: name,
      employeeCode: generateEmployeeCode(),
      phone: phone,
      password: password,
      active: true,
      createdAt: DateTime.now().toIso8601String(),
      totalSales: 0,
    );

    _employees.add(employee);

    return employee;
  }

  Future<List<Employee>> getEmployees() async {
    return _employees;
  }

  Future<Employee?> getEmployeeByCode(
    String employeeCode,
  ) async {
    try {
      return _employees.firstWhere(
        (employee) =>
            employee.employeeCode == employeeCode,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> deactivateEmployee(
    int employeeId,
  ) async {
    final index = _employees.indexWhere(
      (employee) => employee.id == employeeId,
    );

    if (index != -1) {
      final oldEmployee = _employees[index];

      _employees[index] = Employee(
        id: oldEmployee.id,
        shopId: oldEmployee.shopId,
        employeeName: oldEmployee.employeeName,
        employeeCode: oldEmployee.employeeCode,
        phone: oldEmployee.phone,
        password: oldEmployee.password,
        active: false,
        createdAt: oldEmployee.createdAt,
        totalSales: oldEmployee.totalSales,
      );
    }
  }
}