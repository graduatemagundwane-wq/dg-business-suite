class Shop {
  final int? id;
  final String shopCode;
  final String shopName;
  final String ownerName;
  final String whatsapp;
  final bool activated;
  final String activationCode;
  final String createdAt;

  Shop({
    this.id,
    required this.shopCode,
    required this.shopName,
    required this.ownerName,
    required this.whatsapp,
    required this.activated,
    required this.activationCode,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shop_code': shopCode,
      'shop_name': shopName,
      'owner_name': ownerName,
      'whatsapp': whatsapp,
      'activated': activated ? 1 : 0,
      'activation_code': activationCode,
      'created_at': createdAt,
    };
  }

  factory Shop.fromMap(Map<String, dynamic> map) {
    return Shop(
      id: map['id'],
      shopCode: map['shop_code'],
      shopName: map['shop_name'],
      ownerName: map['owner_name'],
      whatsapp: map['whatsapp'],
      activated: map['activated'] == 1,
      activationCode: map['activation_code'],
      createdAt: map['created_at'],
    );
  }
}