class Employee {
  final int id;
  final int shopId;
  final String employeeName;
  final String employeeCode;
  final String phone;
  final String password;
  final bool active;
  final String createdAt;
  final double totalSales;

  Employee({
    required this.id,
    required this.shopId,
    required this.employeeName,
    required this.employeeCode,
    required this.phone,
    required this.password,
    required this.active,
    required this.createdAt,
    required this.totalSales,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shop_id': shopId,
      'employee_name': employeeName,
      'employee_code': employeeCode,
      'phone': phone,
      'password': password,
      'active': active ? 1 : 0,
      'created_at': createdAt,
      'total_sales': totalSales,
    };
  }

  factory Employee.fromMap(Map<String, dynamic> map) {
    return Employee(
      id: map['id'],
      shopId: map['shop_id'],
      employeeName: map['employee_name'],
      employeeCode: map['employee_code'],
      phone: map['phone'] ?? '',
      password: map['password'] ?? '',
      active: map['active'] == 1,
      createdAt: map['created_at'],
      totalSales: (map['total_sales'] ?? 0).toDouble(),
    );
  }
}