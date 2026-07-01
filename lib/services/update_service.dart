import 'api_config.dart';
import 'double_gee_api_service.dart';

enum UpdateRequirement {
  current,
  optional,
  forced,
  unavailable,
}

class AppUpdateStatus {
  final String currentVersion;
  final String? latestVersion;
  final UpdateRequirement requirement;
  final String message;
  final String whatsNew;
  final String? downloadUrl;

  const AppUpdateStatus({
    required this.currentVersion,
    this.latestVersion,
    required this.requirement,
    required this.message,
    this.whatsNew = '',
    this.downloadUrl,
  });

  bool get mustUpdate => requirement == UpdateRequirement.forced;
  bool get canUpdate => requirement == UpdateRequirement.optional || mustUpdate;
}

class UpdateService {
  static const String currentVersion = '1.0.0';

  static final UpdateService instance = UpdateService._internal();

  factory UpdateService() => instance;

  UpdateService._internal();

  Future<AppUpdateStatus> checkForUpdates() async {
    try {
      final response =
          await DoubleGeeApiService.instance.get(ApiConfig.version);
      final data = response.data;
      final latest = (data['latest_version'] ?? currentVersion).toString();
      final critical = data['critical'] == true || data['force_update'] == true;
      final newer = _isNewer(latest, currentVersion);

      return AppUpdateStatus(
        currentVersion: currentVersion,
        latestVersion: latest,
        requirement: !newer
            ? UpdateRequirement.current
            : critical
                ? UpdateRequirement.forced
                : UpdateRequirement.optional,
        message: newer ? 'Version $latest available' : 'App is up to date.',
        whatsNew: (data['whats_new'] ?? '').toString(),
        downloadUrl: data['download_url']?.toString(),
      );
    } on ApiException catch (error) {
      return AppUpdateStatus(
        currentVersion: currentVersion,
        requirement: UpdateRequirement.unavailable,
        message: error.canUseOfflineMode
            ? 'Version check unavailable. Offline mode is active.'
            : error.friendlyMessage,
      );
    }
  }

  bool _isNewer(String latest, String current) {
    final latestParts =
        latest.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    final currentParts =
        current.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    final length = latestParts.length > currentParts.length
        ? latestParts.length
        : currentParts.length;

    for (var index = 0; index < length; index++) {
      final l = index < latestParts.length ? latestParts[index] : 0;
      final c = index < currentParts.length ? currentParts[index] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }

    return false;
  }
}

extension UpdateRequirementLabel on UpdateRequirement {
  String get label {
    switch (this) {
      case UpdateRequirement.current:
        return 'Current';
      case UpdateRequirement.optional:
        return 'Optional Update';
      case UpdateRequirement.forced:
        return 'Force Update';
      case UpdateRequirement.unavailable:
        return 'Unavailable';
    }
  }
}
