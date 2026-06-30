import 'package:flutter/material.dart';

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
  late Future<AppUpdateStatus> _updateFuture;
  bool _skipped = false;

  @override
  void initState() {
    super.initState();
    _updateFuture = UpdateService.instance.checkForUpdates();
  }

  @override
  Widget build(BuildContext context) {
    if (_skipped) return const AuthGate();

    return FutureBuilder<AppUpdateStatus>(
      future: _updateFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final status = snapshot.data!;
        if (!status.canUpdate || status.requirement == UpdateRequirement.unavailable) {
          return const AuthGate();
        }

        return _UpdateScreen(
          status: status,
          onLater: status.mustUpdate ? null : () => setState(() => _skipped = true),
        );
      },
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
                            content: Text('Opening the secure Double Gee update channel.'),
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
