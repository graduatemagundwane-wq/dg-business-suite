import 'dart:convert';

import 'package:http/http.dart' as http;

class DoubleGeeApiService {
  static const String baseUrl = 'https://doublegeetech.co.zw';

  static final DoubleGeeApiService instance = DoubleGeeApiService._internal();

  factory DoubleGeeApiService() => instance;

  DoubleGeeApiService._internal();

  Future<Map<String, dynamic>> getJson(String path) async {
    final response = await http
        .get(_uri(path), headers: _headers())
        .timeout(const Duration(seconds: 8));
    return _decode(response);
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await http
        .post(
          _uri(path),
          headers: _headers(),
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 8));
    return _decode(response);
  }

  Uri _uri(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalized');
  }

  Map<String, String> _headers() {
    return const {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'X-Double-Gee-App': 'business-suite',
    };
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = response.body.trim().isEmpty ? '{}' : response.body;
    final decoded = jsonDecode(body);

    if (decoded is Map<String, dynamic>) {
      return {
        ...decoded,
        '_statusCode': response.statusCode,
      };
    }

    return {
      'data': decoded,
      '_statusCode': response.statusCode,
    };
  }
}
