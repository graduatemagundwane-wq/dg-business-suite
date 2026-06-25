class Customer {
  final int? id;
  final String customerName;
  final String phoneNumber;
  final double totalSpent;
  final int purchaseCount;

  Customer({
    this.id,
    required this.customerName,
    required this.phoneNumber,
    required this.totalSpent,
    required this.purchaseCount,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer_name': customerName,
      'phone_number': phoneNumber,
      'total_spent': totalSpent,
      'purchase_count': purchaseCount,
    };
  }

  factory Customer.fromMap(
    Map<String, dynamic> map,
  ) {
    return Customer(
      id: map['id'],
      customerName: map['customer_name'],
      phoneNumber: map['phone_number'],
      totalSpent:
          (map['total_spent'] as num).toDouble(),
      purchaseCount: map['purchase_count'],
    );
  }
}