import 'package:flutter/material.dart';

class PosSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onScanBarcode;

  const PosSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onScanBarcode,
  });

  @override
  Widget build(BuildContext context) {
    return SearchBar(
      controller: controller,
      hintText: 'Search products or barcode',
      leading: const Icon(Icons.search),
      trailing: [
        IconButton(
          tooltip: 'Scan barcode',
          icon: const Icon(Icons.qr_code_scanner),
          onPressed: onScanBarcode,
        ),
      ],
      onChanged: onChanged,
      elevation: const WidgetStatePropertyAll(0),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
    );
  }
}
