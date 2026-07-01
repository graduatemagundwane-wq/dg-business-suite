class ApiConfig {
  static const String host = 'https://api.doublegeetech.co.zw';
  static const String hostName = 'api.doublegeetech.co.zw';
  static const String baseUrl = '$host/api';
  static const Duration timeout = Duration(seconds: 12);

  static const String health = '/health';
  static const String register = '/register';
  static const String login = '/login';
  static const String logout = '/logout';
  static const String user = '/user';
  static const String license = '/license';
  static const String version = '/version';

  static String activationStatus(String shopCode) {
    return '/activation/status/$shopCode';
  }

  static const String activationVerify = '/activation/verify';

  const ApiConfig._();
}
