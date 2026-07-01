import 'api_config.dart';
import 'double_gee_api_service.dart';

enum ServerConnectionState {
  connected,
  offline,
}

class ServerHealthStatus {
  final ServerConnectionState state;
  final String message;

  const ServerHealthStatus({
    required this.state,
    required this.message,
  });

  bool get isConnected => state == ServerConnectionState.connected;
}

class ApiHealthService {
  static final ApiHealthService instance = ApiHealthService._internal();

  factory ApiHealthService() => instance;

  ApiHealthService._internal();

  Future<ServerHealthStatus> checkHealth() async {
    try {
      await DoubleGeeApiService.instance.get(ApiConfig.health);
      return const ServerHealthStatus(
        state: ServerConnectionState.connected,
        message: 'Server Connected',
      );
    } on ApiException catch (error) {
      return ServerHealthStatus(
        state: ServerConnectionState.offline,
        message: error.canUseOfflineMode
            ? 'Offline mode active'
            : error.friendlyMessage,
      );
    }
  }
}
