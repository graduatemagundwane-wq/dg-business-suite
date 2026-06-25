import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.store),
            title: Text('Shop Profile'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.receipt),
            title: Text('Receipt Settings'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.phone),
            title: Text('WhatsApp Number'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.backup),
            title: Text('Backup Data'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.restore),
            title: Text('Restore Data'),
          ),
        ],
      ),
    );
  }
}