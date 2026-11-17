import 'dart:convert';
import 'package:android_id/android_id.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Android licence format follows the Yola Windows Master Control protocol.
/// Neither a local flag nor a licence-free trial can enable offline checkout.
class YolaLicence {
  static const _root = 'https://yola-onboarding.vercel.app';
  static const _publicKey = '9ohWRX9msowRGb4JRcCos5uEa0mAsD+lzlAb2U6c2BE=';
  static const _storage = FlutterSecureStorage();
  static final YolaLicence instance = YolaLicence._();
  YolaLicence._();

  Future<String> get deviceId async {
    final id = await const AndroidId().getId();
    if (id == null || id.isEmpty) {
      throw StateError('Android device identifier unavailable; activation blocked.');
    }
    return 'yola-android:$id';
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_root$path');
    final response = await http.post(uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    Map<String, dynamic> data;
    try {
      data = (jsonDecode(response.body) as Map).cast<String, dynamic>();
    } catch (_) {
      throw StateError('Yola Master Control returned an unreadable response.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError((data['error'] ?? data['detail'] ??
        'Master Control request failed (HTTP ${response.statusCode}).').toString());
    }
    return data;
  }

  Future<String> requestApproval({
    required String existingBusinessId,
    required String businessName,
    required String ownerName,
    required String phone,
    required String email,
    required String password,
  }) async {
    if (await _storage.read(key: 'yola_android_license') != null) {
      throw StateError('A previous licence exists. Contact Double Gee Tech to transfer this device.');
    }
    if (existingBusinessId.trim().isEmpty || password.length < 12) {
      throw ArgumentError('A registered Yola business ID and online password are required.');
    }
    final result = await _post('/api/activation/request', {
      'device_id': await deviceId,
      'device_name': 'Yola Android',
      'business_name': businessName.trim(),
      'owner_name': ownerName.trim(),
      'phone': phone.trim(),
      'email': email.trim().toLowerCase(),
      'password': password,
      'app_version': 'android-offline-0.2',
      'existing_business_id': existingBusinessId.trim().toUpperCase(),
    });
    final secret = result['claim_secret']?.toString();
    if (secret == null || secret.isEmpty) {
      throw StateError('Master Control did not issue a claim secret. Ask Double Gee Tech to authorise this device.');
    }
    await _storage.write(key: 'yola_android_claim', value: secret);
    final requestCode = result['request_code']?.toString() ?? 'pending';
    await _storage.write(key: 'yola_android_request_code', value: requestCode);
    return requestCode;
  }

  Future<YolaLicenceInfo> claimApproved() async {
    final claim = await _storage.read(key: 'yola_android_claim');
    if (claim == null || claim.isEmpty) {
      throw StateError('Request device approval first.');
    }
    final data = await _post('/api/activation/status', {
      'device_id': await deviceId,
      'claim_secret': claim,
    });
    if (data['status'] != 'active') {
      throw StateError('Master Control approval is still pending.');
    }
    final info = await _verify(data, allowClockWrite: true);
    await _storage.write(key: 'yola_android_license', value: jsonEncode(data));
    await _storage.delete(key: 'yola_android_claim');
    return info;
  }

  /// Renew the short offline lease only after live DG Master Control approves
  /// the existing signed device licence. Never extend a lease locally.
  Future<YolaLicenceInfo> renewOnlineLease() async {
    final saved = await _storage.read(key: 'yola_android_license');
    if (saved == null) throw StateError('This device is not activated yet.');
    final original = (jsonDecode(saved) as Map).cast<String, dynamic>();
    final licenseToken = original['license_token']?.toString() ?? '';
    if (licenseToken.isEmpty) throw StateError('Missing original device licence.');
    final latest = await _post('/api/license/verify', {
      'device_id': await deviceId,
      'license_token': licenseToken,
      'app_version': 'android-offline-0.2',
    });
    if (latest['active'] != true || latest['status'] != 'active') {
      throw StateError('Master Control has declined this licence.');
    }
    final leaseToken = latest['lease_token']?.toString();
    if (leaseToken == null || leaseToken.isEmpty) {
      throw StateError('Master Control did not issue a signed offline lease.');
    }
    final renewed = {...original, 'lease_token': leaseToken};
    final info = await _verify(renewed, allowClockWrite: true);
    await _storage.write(key:'yola_android_license',value:jsonEncode(renewed));
    return info;
  }

  Future<YolaLicenceInfo?> active() async {
    final saved = await _storage.read(key: 'yola_android_license');
    if (saved == null) return null;
    final data = (jsonDecode(saved) as Map).cast<String, dynamic>();
    return _verify(data, allowClockWrite: true);
  }

  Future<YolaLicenceInfo> requireActive() async {
    final info = await active();
    if (info == null) {
      throw StateError('Device not activated by Double Gee Tech Master Control.');
    }
    return info;
  }

  Future<Map<String, dynamic>> _signedClaims(String token) async {
    final parts = token.split('.');
    if (parts.length != 2) throw StateError('Invalid Master Control signed token.');
    final payload = base64Url.decode(base64Url.normalize(parts[0]));
    final signed = base64Url.decode(base64Url.normalize(parts[1]));
    final ok = await Ed25519().verify(payload,
      signature: Signature(signed,
        publicKey: SimplePublicKey(base64Decode(_publicKey),
          type: KeyPairType.ed25519)));
    if (!ok) throw StateError('Master Control signature verification failed.');
    return (jsonDecode(utf8.decode(payload)) as Map).cast<String, dynamic>();
  }

  Future<YolaLicenceInfo> _verify(Map<String, dynamic> response, {required bool allowClockWrite}) async {
    if (response['public_key'] != _publicKey || response['status'] != 'active') {
      throw StateError('Licence is not an approved, trusted Yola Master Control licence.');
    }
    final licenseToken = response['license_token']?.toString() ?? '';
    final leaseToken = response['lease_token']?.toString() ?? '';
    final license = await _signedClaims(licenseToken);
    final lease = await _signedClaims(leaseToken);
    final identifier = await deviceId;
    final businessId = license['business_id']?.toString();
    if (businessId == null || businessId.isEmpty ||
        businessId != response['business_id']?.toString() ||
        license['device_id'] != identifier ||
        lease['device_id'] != identifier ||
        lease['business_id'] != businessId ||
        lease['master_installation_id'] != license['master_installation_id'] ||
        lease['kind'] != 'yola-offline-lease') {
      throw StateError('Licence belongs to another device or business.');
    }
    final expiresAt = DateTime.tryParse(license['valid_until']?.toString() ?? '')?.toUtc();
    final offlineUntil = DateTime.tryParse(lease['offline_until']?.toString() ?? '')?.toUtc();
    final now = DateTime.now().toUtc();
    if (expiresAt == null || offlineUntil == null ||
        !now.isBefore(expiresAt) || !now.isBefore(offlineUntil)) {
      throw StateError('Yola licence or offline lease expired. Reconnect to Master Control.');
    }
    // Prevent an ordinary wall-clock rollback from extending an offline lease.
    final prior = DateTime.tryParse(await _storage.read(key: 'yola_android_latest_utc') ?? '');
    if (prior != null && now.isBefore(prior.subtract(const Duration(minutes: 5)))) {
      throw StateError('Device clock was set backwards. Reconnect for licence verification.');
    }
    if (allowClockWrite) {
      await _storage.write(key: 'yola_android_latest_utc', value: now.toIso8601String());
    }
    return YolaLicenceInfo(
      businessId: businessId,
      businessName: license['business_name']?.toString() ?? 'Yola Business',
      deviceId: identifier,
      validUntil: expiresAt,
      offlineUntil: offlineUntil,
      licenseToken: licenseToken,
    );
  }

  Future<String?> get requestCode => _storage.read(key: 'yola_android_request_code');
}

class YolaLicenceInfo {
  final String businessId;
  final String businessName;
  final String deviceId;
  final DateTime validUntil;
  final DateTime offlineUntil;
  final String licenseToken;
  const YolaLicenceInfo({
    required this.businessId, required this.businessName,
    required this.deviceId, required this.validUntil,
    required this.offlineUntil, required this.licenseToken,
  });
}
