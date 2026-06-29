import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../auth/activation_service.dart';
import '../auth/auth_repository.dart';
import '../session/app_session.dart';
import '../theme/app_tokens.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/primary_button.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final TextEditingController _activationCodeController =
      TextEditingController();
  final AuthRepository _authRepository = const AuthRepository();

  bool _checking = false;
  String? _message;

  @override
  void dispose() {
    _activationCodeController.dispose();
    super.dispose();
  }

  Future<void> _verify(AppSession session) async {
    if (session.shopCode.isEmpty) {
      setState(() => _message = 'Shop code is missing. Please log in again.');
      return;
    }

    setState(() {
      _checking = true;
      _message = null;
    });

    final activated = await _authRepository.activateShop(
      shopCode: session.shopCode,
      activationCode: _activationCodeController.text,
    );

    if (!mounted) return;

    if (activated) {
      session.updateActivation(status: ActivationStatus.activated);
      return;
    }

    setState(() {
      _checking = false;
      _message = 'Activation could not be verified yet.';
    });
  }

  Future<void> _refreshStatus(AppSession session) async {
    setState(() {
      _checking = true;
      _message = null;
    });

    final shop = await _authRepository.getShopById(session.requiredShopId);
    final status = await _authRepository.resolveActivationStatus(shop);

    if (!mounted) return;

    session.updateActivation(status: status);
    setState(() {
      _checking = false;
      _message = 'Current status: ${status.label}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final status = session.activationStatus;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: AppInsets.screen,
              child: DashboardCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                      child: const Icon(Icons.verified_user, size: 34),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Business Activation Required',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Double Gee Tech must activate business accounts before POS, inventory, reports and shop tools can be used.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _StatusTile(status: status),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _activationCodeController,
                      decoration: const InputDecoration(
                        labelText: 'Activation Code',
                        prefixIcon: Icon(Icons.key),
                      ),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(
                      label: 'Verify Activation',
                      icon: Icons.cloud_sync,
                      isLoading: _checking,
                      onPressed: () => _verify(session),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: _checking ? null : () => _refreshStatus(session),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Check Server Status'),
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: () {
                          session.signInOwner(
                            shopId: session.requiredShopId,
                            ownerName: 'Demo Owner',
                            shopName: session.shopName.isEmpty
                                ? 'Double Gee Demo Shop'
                                : session.shopName,
                            activated: true,
                            activationStatus: ActivationStatus.activated,
                            shopCode: session.shopCode.isEmpty
                                ? 'DG-DEMO-OWNER'
                                : session.shopCode,
                          );
                        },
                        icon: const Icon(Icons.developer_mode),
                        label: const Text('Continue as Demo Owner'),
                      ),
                    ],
                    TextButton(
                      onPressed: session.signOut,
                      child: const Text('Log out'),
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

class _StatusTile extends StatelessWidget {
  final ActivationStatus status;

  const _StatusTile({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ActivationStatus.activated => Colors.green,
      ActivationStatus.offlineGrace => Colors.blue,
      ActivationStatus.pending => Colors.orange,
      ActivationStatus.suspended => Colors.red,
      ActivationStatus.expired => Colors.red,
    };

    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      leading: Icon(Icons.circle, color: color),
      title: Text(status.label),
      subtitle: Text(
        status.allowsBusinessAccess
            ? 'Business access is allowed.'
            : 'Business features are blocked.',
      ),
    );
  }
}
