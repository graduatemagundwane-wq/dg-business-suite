import 'package:flutter/material.dart';

enum PaymentMethod {
  cash,
  ecocash,
  onemoney,
  card,
  bank,
}

extension PaymentMethodLabel on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.ecocash:
        return 'EcoCash';
      case PaymentMethod.onemoney:
        return 'OneMoney';
      case PaymentMethod.card:
        return 'Card';
      case PaymentMethod.bank:
        return 'Bank Transfer';
    }
  }
}

class PaymentMethodDialog extends StatefulWidget {
  final double totalAmount;

  const PaymentMethodDialog({
    super.key,
    required this.totalAmount,
  });

  @override
  State<PaymentMethodDialog> createState() =>
      _PaymentMethodDialogState();
}

class _PaymentMethodDialogState
    extends State<PaymentMethodDialog> {
  PaymentMethod _selected =
      PaymentMethod.cash;

  Widget _paymentTile(
    PaymentMethod method,
    IconData icon,
    String title,
  ) {
    final selected = _selected == method;

    return Card(
      elevation: selected ? 2 : 0,
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: selected
            ? Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
              )
            : const Icon(Icons.circle_outlined),
        selected: selected,
        onTap: () {
          setState(() {
            _selected = method;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(20),
      ),
      title: const Text(
        "Select Payment Method",
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [

          Text(
            "Total: \$${widget.totalAmount.toStringAsFixed(2)}",
            style: const TextStyle(
              fontSize: 20,
              fontWeight:
                  FontWeight.bold,
            ),
          ),

          const SizedBox(height: 20),

          _paymentTile(
            PaymentMethod.cash,
            Icons.payments,
            "Cash",
          ),

          _paymentTile(
            PaymentMethod.ecocash,
            Icons.phone_android,
            "EcoCash",
          ),

          _paymentTile(
            PaymentMethod.onemoney,
            Icons.account_balance_wallet,
            "OneMoney",
          ),

          _paymentTile(
            PaymentMethod.card,
            Icons.credit_card,
            "Card",
          ),

          _paymentTile(
            PaymentMethod.bank,
            Icons.account_balance,
            "Bank Transfer",
          ),
        ],
      ),
      actions: [

        TextButton(
          onPressed: () =>
              Navigator.pop(context),
          child: const Text("Cancel"),
        ),

        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              _selected,
            );
          },
          child: const Text(
            "Continue",
          ),
        ),
      ],
    );
  }
}
