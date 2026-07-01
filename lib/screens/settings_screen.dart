import 'package:flutter/material.dart';

import '../services/backup_service.dart';
import '../services/device_service.dart';
import '../services/diagnostics_service.dart';
import '../services/ai_insights_service.dart';
import '../services/marketplace_intelligence_service.dart';
import '../services/printer_service.dart';
import '../services/receipt_service.dart';
import '../services/receipt_automation_service.dart';
import '../services/report_automation_service.dart';
import '../services/security_service.dart';
import '../services/subscription_service.dart';
import '../services/sync_service.dart';
import '../services/update_service.dart';
import '../session/app_session.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/premium_app_bar.dart';
import '../widgets/yola_branding.dart';
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
    final receiptAutomation = ReceiptAutomationService.instance.settings;
    final aiSettings = AiInsightsService.instance.settings;
    final reportAutomation = ReportAutomationService.instance.settings;
    final marketIntelligence = MarketplaceIntelligenceService.instance.settings;

    return Scaffold(
      appBar: const PremiumAppBar(
        title: 'System Settings',
        subtitle: 'Manage preferences, security, sync and updates.',
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          YolaGradientPanel(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                const YolaLogoLockup(
                  compact: true,
                  captionColor: Colors.white,
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Text(
                    'Premium business controls by Double Gee Tech',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Switch Mode',
            icon: Icons.swap_horiz,
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Active Mode'),
                subtitle: Text(_modeLabel(session.role)),
              ),
              if (session.isBusinessAccount && !session.isCustomer)
                FilledButton.icon(
                  onPressed: () {
                    session.switchToCustomerMode();
                    _showMessage('Switched to Customer Mode');
                  },
                  icon: const Icon(Icons.storefront),
                  label: const Text('Switch to Customer Mode'),
                ),
              if (session.isBusinessAccount && session.isCustomer)
                FilledButton.icon(
                  onPressed: () {
                    session.switchToBusinessMode();
                    _showMessage(
                      session.accountIsOwner
                          ? 'Returned to Owner Mode'
                          : 'Returned to Employee Mode',
                    );
                  },
                  icon: const Icon(Icons.work_outline),
                  label: Text(
                    session.accountIsOwner
                        ? 'Return to Owner Mode'
                        : 'Return to Employee Mode',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Language & Region',
            icon: Icons.language,
            children: const [
              ListTile(
                leading: Icon(Icons.translate),
                title: Text('App Language'),
                subtitle: Text('Language selector prepared for rollout'),
                trailing: LanguageSelectorPlaceholder(),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
                      content: Text(
                          'Receipt settings saved for this device session'),
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
            title: 'Receipt Automation',
            icon: Icons.receipt_long,
            children: [
              SwitchListTile(
                value: receiptAutomation.autoPrint,
                onChanged: (value) => _updateReceiptAutomation(
                  receiptAutomation.copyWith(autoPrint: value),
                ),
                title: const Text('Auto Print Receipt'),
                secondary: const Icon(Icons.print),
              ),
              SwitchListTile(
                value: receiptAutomation.askBeforePrinting,
                onChanged: (value) => _updateReceiptAutomation(
                  receiptAutomation.copyWith(askBeforePrinting: value),
                ),
                title: const Text('Ask Before Printing'),
                secondary: const Icon(Icons.help_outline),
              ),
              SwitchListTile(
                value: receiptAutomation.autoWhatsApp,
                onChanged: (value) => _updateReceiptAutomation(
                  receiptAutomation.copyWith(autoWhatsApp: value),
                ),
                title: const Text('Auto WhatsApp Receipt'),
                secondary: const Icon(Icons.chat),
              ),
              SwitchListTile(
                value: receiptAutomation.askBeforeSend,
                onChanged: (value) => _updateReceiptAutomation(
                  receiptAutomation.copyWith(askBeforeSend: value),
                ),
                title: const Text('Ask Before Send'),
                secondary: const Icon(Icons.mark_chat_read_outlined),
              ),
              DropdownButtonFormField<String>(
                initialValue: receiptAutomation.defaultPrinterId ??
                    PrinterService.instance.defaultPrinter?.id,
                decoration: const InputDecoration(
                  labelText: 'Default Printer',
                  prefixIcon: Icon(Icons.print),
                ),
                items: PrinterService.instance.profiles
                    .map(
                      (printer) => DropdownMenuItem(
                        value: printer.id,
                        child: Text(printer.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  _updateReceiptAutomation(
                    receiptAutomation.copyWith(defaultPrinterId: value),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'AI',
            icon: Icons.psychology_alt,
            children: [
              SwitchListTile(
                value: aiSettings.enabled,
                onChanged: (value) => _updateAiSettings(
                  aiSettings.copyWith(enabled: value),
                ),
                title: const Text('Enable AI Insights'),
                secondary: const Icon(Icons.auto_awesome),
              ),
              SwitchListTile(
                value: aiSettings.dailyAdvice,
                onChanged: (value) => _updateAiSettings(
                  aiSettings.copyWith(dailyAdvice: value),
                ),
                title: const Text('Daily Advice'),
              ),
              SwitchListTile(
                value: aiSettings.weeklyAdvice,
                onChanged: (value) => _updateAiSettings(
                  aiSettings.copyWith(weeklyAdvice: value),
                ),
                title: const Text('Weekly Advice'),
              ),
              SwitchListTile(
                value: aiSettings.monthlySummary,
                onChanged: (value) => _updateAiSettings(
                  aiSettings.copyWith(monthlySummary: value),
                ),
                title: const Text('Monthly Summary'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Reports Automation',
            icon: Icons.schedule_send,
            children: [
              ListTile(
                leading: const Icon(Icons.today),
                title: const Text('Daily Report Time'),
                subtitle: Text(reportAutomation.dailyReportTime),
              ),
              ListTile(
                leading: const Icon(Icons.date_range),
                title: const Text('Weekly Report Day'),
                subtitle: Text(reportAutomation.weeklyReportDay),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month),
                title: const Text('Monthly Report Date'),
                subtitle: Text('Day ${reportAutomation.monthlyReportDate}'),
              ),
              ListTile(
                leading: const Icon(Icons.chat),
                title: const Text('Auto-send Channel'),
                subtitle: Text(
                  reportAutomation.channels.map((c) => c.label).join(', '),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Marketplace Intelligence',
            icon: Icons.hub,
            children: [
              SwitchListTile(
                value: marketIntelligence.anonymousContributionEnabled,
                onChanged: (value) {
                  MarketplaceIntelligenceService.instance.updateSettings(
                    MarketplaceIntelligenceSettings(
                      anonymousContributionEnabled: value,
                      shareSellingPrices: marketIntelligence.shareSellingPrices,
                      shareProductPopularity:
                          marketIntelligence.shareProductPopularity,
                      shareDemand: marketIntelligence.shareDemand,
                      shareInventoryAvailability:
                          marketIntelligence.shareInventoryAvailability,
                    ),
                  );
                  setState(() {});
                },
                title: const Text('Anonymous Market Intelligence'),
                subtitle: const Text('Never exposes another shop identity'),
                secondary: const Icon(Icons.privacy_tip_outlined),
              ),
              ListTile(
                leading: const Icon(Icons.analytics),
                title: const Text('Prepared Signals'),
                subtitle: const Text(
                  'Prices, popularity, demand and inventory availability',
                ),
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
                subtitle: const Text('Configure automatic receipt sending'),
                onTap: () => _showMessage(
                    'Use Receipt Automation to control WhatsApp receipts.'),
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
                subtitle: const Text('Validate a backup before restoring'),
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
                subtitle:
                    const Text('Prepared until biometric package is added'),
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
                      ? 'Secure storage adapter configured'
                      : 'Secure storage adapter unavailable',
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

                  return AppVersionUpdateRoom(update: update);
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
        return 'Bluetooth thermal printer profile';
      case PrinterConnectionType.usb:
        return 'USB printer profile';
      case PrinterConnectionType.otg:
        return 'USB/OTG Android printer profile';
      case PrinterConnectionType.network:
        return 'Network printer profile';
    }
  }

  void _showComingSoon() {
    _showMessage(
        'Feature is available through its production settings section');
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
    _showMessage('Cloud sync request queued for the Double Gee server');
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
    _showMessage('${plan.label} subscription selected');
  }

  void _updateReceiptAutomation(ReceiptAutomationSettings settings) {
    ReceiptAutomationService.instance.updateSettings(settings);
    setState(() {});
    _showMessage('Receipt automation updated');
  }

  void _updateAiSettings(AiSettings settings) {
    AiInsightsService.instance.updateSettings(settings);
    setState(() {});
    _showMessage('AI settings updated');
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

  String _modeLabel(AppRole? role) {
    switch (role) {
      case AppRole.owner:
        return 'Owner Mode';
      case AppRole.employee:
        return 'Employee Mode';
      case AppRole.customer:
        return 'Customer Mode';
      case null:
        return 'Signed out';
    }
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
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      shadowColor: AppTheme.primaryBlue.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary.withValues(alpha: 0.14),
                        theme.colorScheme.secondary.withValues(alpha: 0.12),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                  ),
                  child: Icon(icon, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            ...children,
          ],
        ),
      ),
    );
  }
}
