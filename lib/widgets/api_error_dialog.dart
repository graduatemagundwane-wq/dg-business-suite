import 'package:flutter/material.dart';

import '../services/double_gee_api_service.dart';

class ApiErrorDialog {
  const ApiErrorDialog._();

  static Future<void> show(
    BuildContext context, {
    required Object error,
  }) async {
    final message = error is ApiException
        ? error.friendlyMessage
        : error.toString().replaceFirst('Bad state: ', '');

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          icon: Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: const Text('Request could not be completed'),
          content: Text(message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}
