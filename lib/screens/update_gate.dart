import 'package:flutter/material.dart';

import '../services/api_health_service.dart';
import '../services/update_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/dashboard_card.dart';
import 'auth_gate.dart';

class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  late Future<_StartupStatus> _startupFuture;
  bool _skipped = false;

  @override
  void initState() {
    super.initState();
    _startupFuture = _loadStartupStatus();
  }

  @override
  Widget build(BuildContext context) {
    if (_skipped) return const AuthGate();

    return FutureBuilder<_StartupStatus>(
      future: _startupFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final startup = snapshot.data!;
        final status = startup.updateStatus;
        if (!status.canUpdate ||
            status.requirement == UpdateRequirement.unavailable) {
          return _StartupStatusBanner(
            healthStatus: startup.healthStatus,
            child: const AuthGate(),
          );
        }

        return _UpdateScreen(
          status: status,
          onLater:
              status.mustUpdate ? null : () => setState(() => _skipped = true),
        );
      },
    );
  }

  Future<_StartupStatus> _loadStartupStatus() async {
    final health = await ApiHealthService.instance.checkHealth();
    final update = await UpdateService.instance.checkForUpdates();
    return _StartupStatus(
      healthStatus: health,
      updateStatus: update,
    );
  }
}

class _StartupStatus {
  final ServerHealthStatus healthStatus;
  final AppUpdateStatus updateStatus;

  const _StartupStatus({
    required this.healthStatus,
    required this.updateStatus,
  });
}

class _StartupStatusBanner extends StatefulWidget {
  final ServerHealthStatus healthStatus;
  final Widget child;

  const _StartupStatusBanner({
    required this.healthStatus,
    required this.child,
  });

  @override
  State<_StartupStatusBanner> createState() => _StartupStatusBannerState();
}

class _StartupStatusBannerState extends State<_StartupStatusBanner> {
  bool _visible = true;

  @override
  Widget build(BuildContext context) {
    if (!_visible) return widget.child;

    final connected = widget.healthStatus.isConnected;

    return Scaffold(
      body: Column(
        children: [
          MaterialBanner(
            leading: Icon(
              connected ? Icons.cloud_done : Icons.cloud_off,
              color: connected
                  ? Theme.of(context).colorScheme.secondary
                  : Theme.of(context).colorScheme.tertiary,
            ),
            content: Text(widget.healthStatus.message),
            actions: [
              TextButton(
                onPressed: () => setState(() => _visible = false),
                child: const Text('Dismiss'),
              ),
            ],
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

class _UpdateScreen extends StatelessWidget {
  final AppUpdateStatus status;
  final VoidCallback? onLater;

  const _UpdateScreen({
    required this.status,
    required this.onLater,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: AppInsets.screen,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: DashboardCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.system_update,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Version ${status.latestVersion ?? ''} available',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      status.mustUpdate
                          ? 'This update is required to continue.'
                          : 'A new version of Double Gee Business Suite is ready.',
                      textAlign: TextAlign.center,
                    ),
                    if (status.whatsNew.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        "What's New",
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(status.whatsNew),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Opening the secure Double Gee update channel.'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.download),
                      label: const Text('Update Now'),
                    ),
                    if (onLater != null)
                      TextButton(
                        onPressed: onLater,
                        child: const Text('Later'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
