import 'api_config.dart';
import 'double_gee_api_service.dart';

enum LicenseState {
  active,
  expired,
  trial,
  unavailable,
}

class LicenseStatus {
  final LicenseState state;
  final int? daysRemaining;
  final String message;

  const LicenseStatus({
    required this.state,
    required this.message,
    this.daysRemaining,
  });

  bool get isActive {
    return state == LicenseState.active || state == LicenseState.trial;
  }
}

class LicenseService {
  static final LicenseService instance = LicenseService._internal();

  factory LicenseService() => instance;

  LicenseService._internal();

  Future<LicenseStatus> checkLicense() async {
    try {
      final response =
          await DoubleGeeApiService.instance.get(ApiConfig.license);
      final data = response.data;
      final status = (data['status'] ?? data['license_status'] ?? '')
          .toString()
          .toLowerCase();
      final days = int.tryParse(
        (data['days_remaining'] ?? data['remaining_days'] ?? '').toString(),
      );

      if (status.contains('trial')) {
        return LicenseStatus(
          state: LicenseState.trial,
          daysRemaining: days,
          message: _message('Trial', days),
        );
      }

      if (status.contains('expired')) {
        return LicenseStatus(
          state: LicenseState.expired,
          daysRemaining: days,
          message: 'License expired',
        );
      }

      return LicenseStatus(
        state: LicenseState.active,
        daysRemaining: days,
        message: _message('License active', days),
      );
    } on ApiException catch (error) {
      return LicenseStatus(
        state: LicenseState.unavailable,
        message: error.canUseOfflineMode
            ? 'License check unavailable. Offline mode is active.'
            : error.friendlyMessage,
      );
    }
  }

  String _message(String label, int? days) {
    if (days == null) return label;
    return '$label - $days day${days == 1 ? '' : 's'} remaining';
  }
}
