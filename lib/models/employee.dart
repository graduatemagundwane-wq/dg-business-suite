class Employee {
  final int? id;
  final int shopId;
  final String employeeName;
  final String employeeCode;
  final bool active;
  final int salesCount;
  final double revenue;
  final double profit;
  final String createdAt;
  final String phone;
  final String password;

  Employee({
    this.id,
    required this.shopId,
    required this.employeeName,
    required this.employeeCode,
    this.active = true,
    this.salesCount = 0,
    double revenue = 0,
    this.profit = 0,
    required this.createdAt,
    this.phone = '',
    this.password = '',
    double? totalSales,
  }) : revenue = totalSales ?? revenue;

  double get totalSales => revenue;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shop_id': shopId,
      'employee_name': employeeName,
      'employee_code': employeeCode,
      'active': active ? 1 : 0,
      'sales_count': salesCount,
      'revenue': revenue,
      'profit': profit,
      'created_at': createdAt,
    };
  }

  factory Employee.fromMap(Map<String, dynamic> map) {
    return Employee(
      id: map['id'] as int?,
      shopId: (map['shop_id'] as int?) ?? 1,
      employeeName: (map['employee_name'] ?? '').toString(),
      employeeCode: (map['employee_code'] ?? '').toString(),
      active: map['active'] == 1,
      salesCount: (map['sales_count'] as int?) ?? 0,
      revenue: ((map['revenue'] ?? map['total_sales'] ?? 0) as num).toDouble(),
      profit: ((map['profit'] ?? 0) as num).toDouble(),
      createdAt: (map['created_at'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      password: (map['password'] ?? '').toString(),
    );
  }
}
