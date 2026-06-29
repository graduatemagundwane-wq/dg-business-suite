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

  const AppUpdateStatus({
    required this.currentVersion,
    this.latestVersion,
    required this.requirement,
    required this.message,
  });

  bool get mustUpdate => requirement == UpdateRequirement.forced;
  bool get canUpdate => requirement == UpdateRequirement.optional || mustUpdate;
}

class UpdateService {
  static const String currentVersion = '1.0.0';
  static const String updateEndpoint =
      'https://doublegeetech.co.zw/api/apps/double-gee-business-suite/version';

  static final UpdateService instance = UpdateService._internal();

  factory UpdateService() => instance;

  UpdateService._internal();

  Future<AppUpdateStatus> checkForUpdates() async {
    return const AppUpdateStatus(
      currentVersion: currentVersion,
      latestVersion: currentVersion,
      requirement: UpdateRequirement.current,
      message: 'Version check endpoint is prepared for production rollout.',
    );
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
