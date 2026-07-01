import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiCredentials {
  final String token;
  final Map<String, dynamic> user;
  final String? businessId;
  final String role;

  const ApiCredentials({
    required this.token,
    required this.user,
    required this.role,
    this.businessId,
  });
}

abstract class ApiCredentialStore {
  Future<ApiCredentials?> read();
  Future<String?> readToken();
  Future<void> save(ApiCredentials credentials);
  Future<void> clear();
}

class SecureApiCredentialStore implements ApiCredentialStore {
  static final SecureApiCredentialStore instance =
      SecureApiCredentialStore._internal();

  SecureApiCredentialStore._internal();

  static const String _tokenKey = 'yola_api_token';
  static const String _userKey = 'yola_api_user';
  static const String _businessIdKey = 'yola_api_business_id';
  static const String _roleKey = 'yola_api_role';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  ApiCredentials? _credentials;

  @override
  Future<ApiCredentials?> read() async {
    if (_credentials != null) return _credentials;

    final token = await _storage.read(key: _tokenKey);
    if (token == null || token.isEmpty) return null;

    final encodedUser = await _storage.read(key: _userKey);
    final user = encodedUser == null || encodedUser.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(encodedUser) as Map<String, dynamic>;

    _credentials = ApiCredentials(
      token: token,
      user: user,
      businessId: await _storage.read(key: _businessIdKey),
      role: await _storage.read(key: _roleKey) ?? 'customer',
    );

    return _credentials;
  }

  @override
  Future<String?> readToken() async {
    if (_credentials != null) return _credentials?.token;
    return _storage.read(key: _tokenKey);
  }

  @override
  Future<void> save(ApiCredentials credentials) async {
    _credentials = credentials;
    await _storage.write(key: _tokenKey, value: credentials.token);
    await _storage.write(key: _userKey, value: jsonEncode(credentials.user));
    await _storage.write(key: _businessIdKey, value: credentials.businessId);
    await _storage.write(key: _roleKey, value: credentials.role);
  }

  @override
  Future<void> clear() async {
    _credentials = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
    await _storage.delete(key: _businessIdKey);
    await _storage.delete(key: _roleKey);
  }
}
