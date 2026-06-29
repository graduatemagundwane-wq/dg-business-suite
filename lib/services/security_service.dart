import '../auth/biometric_login_service.dart';
import '../session/app_session.dart';

class SecuritySettings {
  final Duration autoLogoutTimeout;
  final bool fingerprintLockEnabled;
  final bool secureStoragePrepared;

  const SecuritySettings({
    this.autoLogoutTimeout = const Duration(minutes: 15),
    this.fingerprintLockEnabled = false,
    this.secureStoragePrepared = true,
  });

  SecuritySettings copyWith({
    Duration? autoLogoutTimeout,
    bool? fingerprintLockEnabled,
  }) {
    return SecuritySettings(
      autoLogoutTimeout: autoLogoutTimeout ?? this.autoLogoutTimeout,
      fingerprintLockEnabled:
          fingerprintLockEnabled ?? this.fingerprintLockEnabled,
      secureStoragePrepared: secureStoragePrepared,
    );
  }
}

class SessionValidationResult {
  final bool valid;
  final bool requiresFingerprint;
  final bool timedOut;
  final String message;

  const SessionValidationResult({
    required this.valid,
    required this.requiresFingerprint,
    required this.timedOut,
    required this.message,
  });
}

class SecurityService {
  static final SecurityService instance = SecurityService._internal();

  factory SecurityService() => instance;

  SecurityService._internal();

  SecuritySettings _settings = const SecuritySettings();
  DateTime _lastActivityAt = DateTime.now();

  SecuritySettings get settings => _settings;
  DateTime get lastActivityAt => _lastActivityAt;

  void recordActivity() {
    _lastActivityAt = DateTime.now();
  }

  void configure({
    Duration? autoLogoutTimeout,
    bool? fingerprintLockEnabled,
  }) {
    _settings = SecuritySettings(
      autoLogoutTimeout: autoLogoutTimeout ?? _settings.autoLogoutTimeout,
      fingerprintLockEnabled:
          fingerprintLockEnabled ?? _settings.fingerprintLockEnabled,
      secureStoragePrepared: _settings.secureStoragePrepared,
    );
  }

  Future<SessionValidationResult> validateSession(AppSession session) async {
    if (!session.isAuthenticated) {
      return const SessionValidationResult(
        valid: false,
        requiresFingerprint: false,
        timedOut: false,
        message: 'No authenticated session.',
      );
    }

    final timedOut =
        DateTime.now().difference(_lastActivityAt) > _settings.autoLogoutTimeout;
    if (timedOut) {
      return const SessionValidationResult(
        valid: false,
        requiresFingerprint: false,
        timedOut: true,
        message: 'Session timed out.',
      );
    }

    if (_settings.fingerprintLockEnabled) {
      final biometricAvailable =
          await const BiometricLoginService().isAvailable;

      return SessionValidationResult(
        valid: !biometricAvailable,
        requiresFingerprint: biometricAvailable,
        timedOut: false,
        message: biometricAvailable
            ? 'Fingerprint unlock required.'
            : 'Fingerprint package not installed yet.',
      );
    }

    return const SessionValidationResult(
      valid: true,
      requiresFingerprint: false,
      timedOut: false,
      message: 'Session is valid.',
    );
  }
}
