import 'package:flutter/material.dart';

class SearchBox extends StatelessWidget {
  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  const SearchBox({
    super.key,
    this.controller,
    this.hintText = 'Search',
    this.onChanged,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return SearchBar(
      controller: controller,
      hintText: hintText,
      leading: const Icon(Icons.search),
      trailing: [
        if (onClear != null)
          IconButton(
            tooltip: 'Clear search',
            icon: const Icon(Icons.close),
            onPressed: onClear,
          ),
      ],
      onChanged: onChanged,
      elevation: const WidgetStatePropertyAll(0),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
    );
  }
}
