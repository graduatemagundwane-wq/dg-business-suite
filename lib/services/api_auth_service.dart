import 'api_config.dart';
import 'api_credential_store.dart';
import 'double_gee_api_service.dart';

class ApiAuthService {
  static final ApiAuthService instance = ApiAuthService._internal();

  factory ApiAuthService() => instance;

  ApiAuthService._internal();

  final DoubleGeeApiService _api = DoubleGeeApiService.instance;
  final ApiCredentialStore _credentialStore = SecureApiCredentialStore.instance;

  Future<ApiCredentials> login({
    required String email,
    required String password,
    String? role,
    String? identifier,
  }) async {
    final response = await _api.post(ApiConfig.login, {
      'email': email.trim(),
      'password': password,
      if (role != null && role.isNotEmpty) 'role': role,
      if (identifier != null && identifier.isNotEmpty) 'identifier': identifier,
    });

    final credentials = _credentialsFromResponse(
      _payload(response.data),
      fallbackRole: role ?? 'customer',
    );
    await _credentialStore.save(credentials);
    return credentials;
  }

  Future<ApiCredentials> loginWithIdentifier({
    required String role,
    required String identifier,
    String? password,
  }) async {
    final response = await _api.post(ApiConfig.login, {
      'role': role,
      'identifier': identifier,
      if (password != null && password.isNotEmpty) 'password': password,
    });

    final credentials = _credentialsFromResponse(
      _payload(response.data),
      fallbackRole: role,
    );
    await _credentialStore.save(credentials);
    return credentials;
  }

  Future<ApiCredentials?> register({
    required String accountType,
    required Map<String, dynamic> payload,
  }) async {
    final response = await _api.post(ApiConfig.register, {
      'account_type': accountType,
      ...payload,
    });

    final data = _payload(response.data);
    final token = _readString(data, ['token', 'access_token', 'jwt']);
    if (token == null || token.isEmpty) return null;

    final credentials = _credentialsFromResponse(
      data,
      fallbackRole: accountType,
    );
    await _credentialStore.save(credentials);
    return credentials;
  }

  Future<Map<String, dynamic>?> currentUser() async {
    final response = await _api.get(ApiConfig.user);
    final data = _payload(response.data);
    final user = data['user'];
    if (user is Map<String, dynamic>) return user;
    return data;
  }

  Future<ApiCredentials?> restoreSession() async {
    final existing = await _credentialStore.read();
    if (existing == null) return null;

    try {
      final user = await currentUser();
      if (user == null) return existing;

      final credentials = ApiCredentials(
        token: existing.token,
        user: user,
        businessId: _readString(user, ['business_id']) ?? existing.businessId,
        role: _readString(user, ['role']) ?? existing.role,
      );
      await _credentialStore.save(credentials);
      return credentials;
    } on ApiException catch (error) {
      if (error.type == ApiErrorType.unauthorized ||
          error.type == ApiErrorType.forbidden) {
        await _credentialStore.clear();
        return null;
      }

      if (error.canUseOfflineMode) return existing;
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await _api.post(ApiConfig.logout);
    } on ApiException catch (error) {
      if (!error.canUseOfflineMode &&
          error.type != ApiErrorType.unauthorized &&
          error.type != ApiErrorType.forbidden) {
        rethrow;
      }
    } finally {
      await _credentialStore.clear();
    }
  }

  ApiCredentials _credentialsFromResponse(
    Map<String, dynamic> data, {
    required String fallbackRole,
  }) {
    final user = data['user'] is Map<String, dynamic>
        ? data['user'] as Map<String, dynamic>
        : <String, dynamic>{};
    final token = _readString(data, ['token', 'access_token', 'jwt']) ?? '';
    final businessId = _readString(data, [
      'business_id',
      'shop_id',
      'company_id',
    ]);
    final role = _readString(data, ['role', 'account_type']) ?? fallbackRole;

    return ApiCredentials(
      token: token,
      user: user,
      businessId: businessId,
      role: role,
    );
  }

  Map<String, dynamic> _payload(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is Map<String, dynamic>) return data;
    return response;
  }

  String? _readString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value != null && value.toString().isNotEmpty) {
        return value.toString();
      }
    }
    return null;
  }
}
