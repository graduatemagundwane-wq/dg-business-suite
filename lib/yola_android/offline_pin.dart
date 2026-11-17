import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'offline_license.dart';

/// Local cashiers must unlock each offline session. Only the owner who
/// authenticated to Master Control during device registration sets this PIN.
class YolaOfflinePin {
  static final instance = YolaOfflinePin._();
  YolaOfflinePin._();
  static const _storage = FlutterSecureStorage();
  final _algorithm = Pbkdf2(macAlgorithm:Hmac.sha256(),iterations:120000,bits:256);

  Future<void> registerPending(String pin) async {
    if (!RegExp(r'^\d{6,12}$').hasMatch(pin)) {
      throw ArgumentError('Set a 6–12 digit offline PIN.');
    }
    final nonce = List<int>.generate(16,(_) => Random.secure().nextInt(256));
    final key = await _algorithm.deriveKeyFromPassword(password:pin,nonce:nonce);
    final digest = await key.extractBytes();
    await _storage.write(key:'yola_android_pending_pin',
      value:'${base64Encode(nonce)}:${base64Encode(digest)}');
  }

  Future<void> activatePending() async {
    await YolaLicence.instance.requireActive();
    final pending = await _storage.read(key:'yola_android_pending_pin');
    if (pending == null) throw StateError('Offline PIN setup is missing.');
    await _storage.write(key:'yola_android_pin',value:pending);
    await _storage.delete(key:'yola_android_pending_pin');
  }

  Future<bool> hasPin() async =>
      (await _storage.read(key:'yola_android_pin')) != null;

  Future<void> verify(String pin) async {
    await YolaLicence.instance.requireActive();
    final stored = await _storage.read(key:'yola_android_pin');
    if (stored == null) throw StateError('Offline owner PIN not provisioned.');
    final until = DateTime.tryParse(await _storage.read(key:'yola_pin_locked_until') ?? '');
    if (until != null && DateTime.now().toUtc().isBefore(until)) {
      throw StateError('Too many PIN attempts. Try later.');
    }
    final parts = stored.split(':');
    if (parts.length != 2) throw StateError('PIN storage is invalid.');
    final nonce = base64Decode(parts.first);
    final expected = base64Decode(parts.last);
    final secret = await _algorithm.deriveKeyFromPassword(password:pin,nonce:nonce);
    final actual = await secret.extractBytes();
    int difference = expected.length ^ actual.length;
    for (int i=0; i<min(expected.length,actual.length); i++) {
      difference |= expected[i]^actual[i];
    }
    if (difference != 0) {
      final failures = int.tryParse(await _storage.read(key:'yola_pin_failures') ?? '0') ?? 0;
      if (failures >= 4) {
        await _storage.write(key:'yola_pin_locked_until',
          value:DateTime.now().toUtc().add(const Duration(minutes:15)).toIso8601String());
        await _storage.write(key:'yola_pin_failures',value:'0');
      } else {
        await _storage.write(key:'yola_pin_failures',value:'${failures+1}');
      }
      throw StateError('Incorrect offline PIN.');
    }
    await _storage.delete(key:'yola_pin_failures');
    await _storage.delete(key:'yola_pin_locked_until');
  }
}
