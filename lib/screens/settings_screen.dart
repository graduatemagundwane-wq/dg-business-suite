import 'package:flutter/material.dart';

import '../services/receipt_service.dart';
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
                subtitle: const Text('Coming soon'),
                onTap: _showComingSoon,
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Restore Data'),
                subtitle: const Text('Coming soon'),
                onTap: _showComingSoon,
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Feature coming soon')),
    );
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
