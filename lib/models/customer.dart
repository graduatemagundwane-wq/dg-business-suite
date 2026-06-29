class Customer {
  final int? id;
  final String customerName;
  final String phoneNumber;
  final double totalSpent;
  final int purchaseCount;
  final String createdAt;

  Customer({
    this.id,
    required this.customerName,
    required this.phoneNumber,
    this.totalSpent = 0,
    this.purchaseCount = 0,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer_name': customerName,
      'phone_number': phoneNumber,
      'total_spent': totalSpent,
      'purchase_count': purchaseCount,
      'created_at': createdAt,
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] as int?,
      customerName: (map['customer_name'] ?? '').toString(),
      phoneNumber: (map['phone_number'] ?? '').toString(),
      totalSpent: ((map['total_spent'] ?? 0) as num).toDouble(),
      purchaseCount: (map['purchase_count'] as int?) ?? 0,
      createdAt: (map['created_at'] ?? '').toString(),
    );
  }
}
