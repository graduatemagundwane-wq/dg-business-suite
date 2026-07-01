import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_credential_store.dart';

enum ApiErrorType {
  unauthorized,
  forbidden,
  notFound,
  validation,
  rateLimited,
  server,
  timeout,
  offline,
  unknown,
}

class ApiException implements Exception {
  final ApiErrorType type;
  final int? statusCode;
  final String message;
  final Map<String, dynamic>? errors;

  const ApiException({
    required this.type,
    required this.message,
    this.statusCode,
    this.errors,
  });

  bool get canUseOfflineMode {
    return type == ApiErrorType.timeout ||
        type == ApiErrorType.offline ||
        type == ApiErrorType.server;
  }

  String get friendlyMessage {
    if (errors != null && errors!.isNotEmpty) {
      final first = errors!.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
      return first.toString();
    }

    return message;
  }

  @override
  String toString() => friendlyMessage;
}

class ApiResponse {
  final int statusCode;
  final Map<String, dynamic> data;

  const ApiResponse({
    required this.statusCode,
    required this.data,
  });
}

class DoubleGeeApiService {
  static const String baseUrl = ApiConfig.baseUrl;

  static final DoubleGeeApiService instance = DoubleGeeApiService._internal();

  factory DoubleGeeApiService() => instance;

  DoubleGeeApiService._internal();

  final ApiCredentialStore _credentialStore = SecureApiCredentialStore.instance;

  Future<ApiResponse> get(String path) {
    return _send('GET', path);
  }

  Future<ApiResponse> post(String path, [Map<String, dynamic>? payload]) {
    return _send('POST', path, payload: payload);
  }

  Future<ApiResponse> put(String path, [Map<String, dynamic>? payload]) {
    return _send('PUT', path, payload: payload);
  }

  Future<ApiResponse> delete(String path, [Map<String, dynamic>? payload]) {
    return _send('DELETE', path, payload: payload);
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    return (await get(path)).data;
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    return (await post(path, payload)).data;
  }

  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    return (await put(path, payload)).data;
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, [
    Map<String, dynamic>? payload,
  ]) async {
    return (await delete(path, payload)).data;
  }

  Future<ApiResponse> _send(
    String method,
    String path, {
    Map<String, dynamic>? payload,
  }) async {
    try {
      final uri = _uri(path);
      final headers = await _headers();
      final body = payload == null ? null : jsonEncode(payload);

      final response = switch (method) {
        'GET' =>
          await http.get(uri, headers: headers).timeout(ApiConfig.timeout),
        'POST' => await http
            .post(uri, headers: headers, body: body)
            .timeout(ApiConfig.timeout),
        'PUT' => await http
            .put(uri, headers: headers, body: body)
            .timeout(ApiConfig.timeout),
        'DELETE' => await http
            .delete(uri, headers: headers, body: body)
            .timeout(ApiConfig.timeout),
        _ => throw const ApiException(
            type: ApiErrorType.unknown,
            message: 'Unsupported API method.',
          ),
      };

      return _decode(response);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        type: ApiErrorType.timeout,
        message: 'The server took too long to respond. Offline mode is active.',
      );
    } on SocketException {
      throw const ApiException(
        type: ApiErrorType.offline,
        message: 'No internet connection. Offline mode is active.',
      );
    } on http.ClientException {
      throw const ApiException(
        type: ApiErrorType.offline,
        message:
            'Could not reach the Double Gee server. Offline mode is active.',
      );
    } catch (error) {
      throw ApiException(
        type: ApiErrorType.unknown,
        message: 'Unexpected API error: $error',
      );
    }
  }

  Uri _uri(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalized');
  }

  Future<Map<String, String>> _headers() async {
    final token = await _credentialStore.readToken();

    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'X-Double-Gee-App': 'yola-suite',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  ApiResponse _decode(http.Response response) {
    final body = response.body.trim().isEmpty ? '{}' : response.body;
    final decoded = jsonDecode(body);
    final data = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'data': decoded};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return ApiResponse(statusCode: response.statusCode, data: data);
    }

    throw ApiException(
      type: _errorType(response.statusCode),
      statusCode: response.statusCode,
      message: _messageFor(response.statusCode, data),
      errors: data['errors'] is Map<String, dynamic>
          ? data['errors'] as Map<String, dynamic>
          : null,
    );
  }

  ApiErrorType _errorType(int statusCode) {
    return switch (statusCode) {
      401 => ApiErrorType.unauthorized,
      403 => ApiErrorType.forbidden,
      404 => ApiErrorType.notFound,
      422 => ApiErrorType.validation,
      429 => ApiErrorType.rateLimited,
      >= 500 => ApiErrorType.server,
      _ => ApiErrorType.unknown,
    };
  }

  String _messageFor(int statusCode, Map<String, dynamic> data) {
    final message = data['message']?.toString();
    if (message != null && message.isNotEmpty) return message;

    return switch (statusCode) {
      401 => 'Your session has expired. Please sign in again.',
      403 => 'You do not have permission to perform this action.',
      404 => 'The requested server resource was not found.',
      422 => 'Please check the form and try again.',
      429 => 'Too many requests. Please wait a moment and try again.',
      >= 500 => 'The Double Gee server is temporarily unavailable.',
      _ => 'The request could not be completed.',
    };
  }
}
