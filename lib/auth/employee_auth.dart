import '../database/local_db.dart';
import 'activation_service.dart';

class EmployeeAuth {
  static final EmployeeAuth instance =
      EmployeeAuth._internal();

  factory EmployeeAuth() => instance;

  EmployeeAuth._internal();

  Future<String> createEmployee({
    required int shopId,
    required String employeeName,
  }) async {
    final employeeCode =
        ActivationService.instance
            .generateEmployeeCode();

    await LocalDatabase.instance
        .createEmployee({
      'shop_id': shopId,
      'employee_name': employeeName,
      'employee_code': employeeCode,
      'active': 1,
      'sales_count': 0,
      'revenue': 0,
      'profit': 0,
      'created_at':
          DateTime.now().toIso8601String(),
    });

    return employeeCode;
  }

  Future<Map<String, dynamic>?>
      loginEmployee(
          String employeeCode) async {
    final employee =
        await LocalDatabase.instance
            .getEmployeeByCode(
      employeeCode.trim(),
    );

    if (employee == null) {
      return null;
    }

    if (employee['active'] != 1) {
      return null;
    }

    return employee;
  }

  Future<bool> deactivateEmployee(
      int employeeId) async {
    final result =
        await LocalDatabase.instance
            .deactivateEmployee(
      employeeId,
    );

    return result > 0;
  }

  Future<bool> activateEmployee(
      int employeeId) async {
    final result =
        await LocalDatabase.instance
            .activateEmployee(
      employeeId,
    );

    return result > 0;
  }

  Future<List<Map<String, dynamic>>>
      getEmployees(
          int shopId) async {
    return await LocalDatabase.instance
        .getEmployees(shopId);
  }
}