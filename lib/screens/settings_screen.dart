import 'package:flutter/material.dart';

import '../services/backup_service.dart';
import '../services/device_service.dart';
import '../services/diagnostics_service.dart';
import '../services/receipt_service.dart';
import '../services/security_service.dart';
import '../services/subscription_service.dart';
import '../services/sync_service.dart';
import '../services/update_service.dart';
import '../session/app_session.dart';
import 'receipt_history_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _shopNameController =
      TextEditingController(text: 'Double Gee POS');
  final TextEditingController _addressController =
      TextEditingController(text: 'Shop address not configured');
  final TextEditingController _phoneController =
      TextEditingController(text: 'Phone not configured');
  final TextEditingController _footerController =
      TextEditingController(text: 'Thank you for shopping with us.');
  final TextEditingController _taxNumberController =
      TextEditingController(text: 'Tax number not configured');

  bool _showLogo = true;
  bool _showQrCode = true;
  late Future<SyncSnapshot> _syncSnapshotFuture;
  late Future<AppUpdateStatus> _updateStatusFuture;

  @override
  void initState() {
    super.initState();
    _syncSnapshotFuture = SyncService.instance.getSnapshot();
    _updateStatusFuture = UpdateService.instance.checkForUpdates();
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _footerController.dispose();
    _taxNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final printerProfiles = ReceiptService.instance.defaultPrinterProfiles();
    final session = SessionScope.of(context);
    final subscriptionStatus = SubscriptionService.instance
        .resolveFromActivation(session.activationStatus);
    final securitySettings = SecurityService.instance.settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            title: 'Receipt Settings',
            icon: Icons.receipt_long,
            children: [
              _settingField(_shopNameController, 'Shop Name', Icons.store),
              _settingField(_addressController, 'Address', Icons.location_on),
              _settingField(_phoneController, 'Phone', Icons.phone),
              _settingField(_taxNumberController, 'Tax Number', Icons.badge),
              _settingField(_footerController, 'Footer Message', Icons.message),
              SwitchListTile(
                value: _showLogo,
                onChanged: (value) => setState(() => _showLogo = value),
                title: const Text('Show Logo'),
                secondary: const Icon(Icons.image),
              ),
              SwitchListTile(
                value: _showQrCode,
                onChanged: (value) => setState(() => _showQrCode = value),
                title: const Text('Show QR Code'),
                secondary: const Icon(Icons.qr_code_2),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Receipt settings persistence coming soon'),
                    ),
                  );
                },
                icon: const Icon(Icons.save),
                label: const Text('Save Receipt Settings'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Receipt Tools',
            icon: Icons.manage_search,
            children: [
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Receipt History'),
                subtitle: const Text('View and search previous receipts'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReceiptHistoryScreen(
                        shopName: _shopNameController.text.trim(),
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.chat),
                title: const Text('WhatsApp Receipts'),
                subtitle: const Text('Sharing integration placeholder'),
                onTap: _showComingSoon,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Printer Profiles',
            icon: Icons.print,
            children: [
              ...printerProfiles.map(
                (profile) => ListTile(
                  leading: Icon(_printerIcon(profile.type)),
                  title: Text(profile.name),
                  subtitle: Text(_printerDescription(profile.type)),
                  trailing: const Chip(label: Text('Soon')),
                  onTap: _showComingSoon,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _showComingSoon,
                icon: const Icon(Icons.add),
                label: const Text('Add Printer Profile'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Data',
            icon: Icons.storage,
            children: [
              ListTile(
                leading: const Icon(Icons.backup),
                title: const Text('Backup Data'),
                subtitle: const Text('Create a manual SQLite backup package'),
                onTap: _runManualBackup,
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Restore Data'),
                subtitle: const Text('Restore validation is prepared'),
                onTap: () => _showMessage(
                  'Restore requires selecting an exported backup file.',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.file_upload),
                title: const Text('Export Backup'),
                subtitle: const Text('Export products, sales and customers'),
                onTap: _runExportBackup,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Cloud Sync',
            icon: Icons.cloud_sync,
            children: [
              FutureBuilder<SyncSnapshot>(
                future: _syncSnapshotFuture,
                builder: (context, snapshot) {
                  final sync = snapshot.data;

                  if (sync == null) {
                    return const ListTile(
                      leading: CircularProgressIndicator(),
                      title: Text('Checking sync status'),
                    );
                  }

                  return Column(
                    children: [
                      ...sync.entities.map(
                        (entity) => ListTile(
                          leading: const Icon(Icons.sync),
                          title: Text(entity.entity.label),
                          subtitle: Text(
                            '${entity.pendingChanges} local records • ${entity.state.label}',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _runSync,
                        icon: const Icon(Icons.cloud_upload),
                        label: const Text('Prepare Cloud Sync'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Device Management',
            icon: Icons.devices,
            children: [
              ListTile(
                leading: const Icon(Icons.admin_panel_settings),
                title: const Text('Registered Owner Device'),
                subtitle: Text(
                  DeviceService.instance.ownerDevice?.name ??
                      'No owner device registered',
                ),
                trailing: OutlinedButton(
                  onPressed: _registerOwnerDevice,
                  child: const Text('Register'),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.badge),
                title: const Text('Employee Devices'),
                subtitle: Text(
                  '${DeviceService.instance.employeeDevices.length} of ${DeviceService.defaultEmployeeDeviceLimit} registered',
                ),
              ),
              ...DeviceService.instance.registeredDevices.map(
                (device) => ListTile(
                  leading: Icon(
                    device.role == DeviceRole.owner
                        ? Icons.verified_user
                        : Icons.person,
                  ),
                  title: Text(device.name),
                  subtitle: Text(
                    '${device.role.label} • Last sync: ${device.lastSyncAt ?? 'Never'}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove device',
                    onPressed: () => _removeDevice(device.id),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Subscription',
            icon: Icons.workspace_premium,
            children: [
              ListTile(
                leading: const Icon(Icons.verified),
                title: Text(subscriptionStatus.plan.label),
                subtitle: Text(
                  '${subscriptionStatus.state.label} • Offline grace: ${subscriptionStatus.offlineGraceDaysRemaining} days',
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: SubscriptionPlan.values
                    .map(
                      (plan) => ChoiceChip(
                        label: Text(plan.label),
                        selected: subscriptionStatus.plan == plan,
                        onSelected: (_) => _prepareRenewal(plan),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Security',
            icon: Icons.security,
            children: [
              SwitchListTile(
                value: securitySettings.fingerprintLockEnabled,
                onChanged: _setFingerprintLock,
                title: const Text('Fingerprint Lock'),
                subtitle: const Text('Prepared until biometric package is added'),
                secondary: const Icon(Icons.fingerprint),
              ),
              ListTile(
                leading: const Icon(Icons.timer),
                title: const Text('Auto Logout Timeout'),
                subtitle: Text(
                  '${securitySettings.autoLogoutTimeout.inMinutes} minutes',
                ),
                trailing: OutlinedButton(
                  onPressed: _setDefaultAutoLogout,
                  child: const Text('15 min'),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.lock),
                title: const Text('Secure Storage'),
                subtitle: Text(
                  securitySettings.secureStoragePrepared
                      ? 'Placeholder ready'
                      : 'Not prepared',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'App Update',
            icon: Icons.system_update,
            children: [
              FutureBuilder<AppUpdateStatus>(
                future: _updateStatusFuture,
                builder: (context, snapshot) {
                  final update = snapshot.data;

                  return ListTile(
                    leading: const Icon(Icons.update),
                    title: Text(update?.requirement.label ?? 'Checking'),
                    subtitle: Text(
                      update?.message ?? 'Checking app update status...',
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'App Health',
            icon: Icons.health_and_safety,
            children: [
              ListTile(
                leading: const Icon(Icons.monitor_heart),
                title: const Text('Diagnostics'),
                subtitle: const Text(
                  'Database, sync, internet, activation and backup health',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showHealthReport(session),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _settingField(
    TextEditingController controller,
    String label,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
        ),
      ),
    );
  }

  IconData _printerIcon(PrinterConnectionType type) {
    switch (type) {
      case PrinterConnectionType.bluetooth:
        return Icons.bluetooth;
      case PrinterConnectionType.usb:
        return Icons.usb;
      case PrinterConnectionType.otg:
        return Icons.cable;
      case PrinterConnectionType.network:
        return Icons.wifi;
    }
  }

  String _printerDescription(PrinterConnectionType type) {
    switch (type) {
      case PrinterConnectionType.bluetooth:
        return 'Bluetooth thermal printer placeholder';
      case PrinterConnectionType.usb:
        return 'USB printer placeholder';
      case PrinterConnectionType.otg:
        return 'USB/OTG Android printer placeholder';
      case PrinterConnectionType.network:
        return 'Network printer placeholder';
    }
  }

  void _showComingSoon() {
    _showMessage('Feature coming soon');
  }

  Future<void> _runManualBackup() async {
    final result = await BackupService.instance.createManualBackup();
    _showMessage(result.message);
  }

  Future<void> _runExportBackup() async {
    final result = await BackupService.instance.exportBackup();
    _showMessage(result.filePath ?? result.message);
  }

  Future<void> _runSync() async {
    final snapshot = await SyncService.instance.syncNow();

    setState(() {
      _syncSnapshotFuture = Future.value(snapshot);
    });
    _showMessage('Cloud sync package prepared');
  }

  void _registerOwnerDevice() {
    final result = DeviceService.instance.registerOwnerDevice('Owner Device');

    setState(() {});
    _showMessage(result.message);
  }

  void _removeDevice(String deviceId) {
    final removed = DeviceService.instance.removeDevice(deviceId);

    setState(() {});
    _showMessage(removed ? 'Device removed' : 'Device not found');
  }

  void _prepareRenewal(SubscriptionPlan plan) {
    SubscriptionService.instance.prepareRenewal(plan);
    setState(() {});
    _showMessage('${plan.label} subscription prepared');
  }

  void _setFingerprintLock(bool enabled) {
    SecurityService.instance.configure(fingerprintLockEnabled: enabled);
    SessionScope.of(context).configureSecurity(fingerprintLockEnabled: enabled);
    setState(() {});
  }

  void _setDefaultAutoLogout() {
    SecurityService.instance.configure(
      autoLogoutTimeout: const Duration(minutes: 15),
    );
    SessionScope.of(context).configureSecurity(
      autoLogoutTimeout: const Duration(minutes: 15),
    );
    setState(() {});
    _showMessage('Auto logout set to 15 minutes');
  }

  Future<void> _showHealthReport(AppSession session) async {
    final report = await DiagnosticsService.instance.buildReport(
      shopId: session.requiredShopId,
      activationStatus: session.activationStatus,
    );

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => _AppHealthDialog(report: report),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _AppHealthDialog extends StatelessWidget {
  final AppHealthReport report;

  const _AppHealthDialog({
    required this.report,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('App Health • ${report.overallState.label}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...report.items.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_healthIcon(item.state)),
                  title: Text(item.label),
                  subtitle: Text(item.message),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  IconData _healthIcon(HealthState state) {
    switch (state) {
      case HealthState.healthy:
        return Icons.check_circle;
      case HealthState.warning:
        return Icons.warning;
      case HealthState.error:
        return Icons.error;
    }
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Icon(icon)),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}
