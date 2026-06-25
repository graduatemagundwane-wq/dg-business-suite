import 'dart:math';

class ActivationService {
  static final ActivationService instance =
      ActivationService._internal();

  factory ActivationService() => instance;

  ActivationService._internal();

  final Random _random = Random();

  String generateShopCode() {
    final number =
        (_random.nextInt(9000) + 1000);

    return "DG-SHOP-$number";
  }

  String generateActivationCode() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

    String code = '';

    for (int i = 0; i < 8; i++) {
      code += chars[
          _random.nextInt(chars.length)];
    }

    return "ACT-$code";
  }

  String generateEmployeeCode() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

    String code = '';

    for (int i = 0; i < 5; i++) {
      code += chars[
          _random.nextInt(chars.length)];
    }

    return "DG-EMP-$code";
  }
}