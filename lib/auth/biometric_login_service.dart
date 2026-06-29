class BiometricLoginService {
  const BiometricLoginService();

  Future<bool> get isAvailable async {
    return false;
  }

  Future<bool> get isPrepared async {
    return true;
  }

  Future<bool> authenticate() async {
    return false;
  }

  String get integrationStatus {
    return 'Fingerprint architecture is prepared. Add a biometric package to enable device unlock.';
  }
}
