import 'package:flutter/material.dart';

class BarcodeScanScreen extends StatelessWidget {
  const BarcodeScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode'),
      ),
      body: const Center(
        child: Text(
          'Barcode Scanner Coming Next',
          style: TextStyle(
            fontSize: 20,
          ),
        ),
      ),
    );
  }
}