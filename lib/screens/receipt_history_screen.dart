import 'package:flutter/material.dart';

import '../services/receipt_service.dart';

class ReceiptHistoryScreen extends StatefulWidget {
  final int shopId;
  final String shopName;

  const ReceiptHistoryScreen({
    super.key,
    this.shopId = 1,
    this.shopName = 'Double Gee POS',
  });

  @override
  State<ReceiptHistoryScreen> createState() => _ReceiptHistoryScreenState();
}

class _ReceiptHistoryScreenState extends State<ReceiptHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<ReceiptHistoryEntry> _receipts = [];
  List<ReceiptHistoryEntry> _filteredReceipts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReceipts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadReceipts() async {
    final receipts = await ReceiptService.instance.getReceiptHistory(
      shopId: widget.shopId,
    );

    if (!mounted) return;

    setState(() {
      _receipts = receipts;
      _filteredReceipts = _applySearch(receipts, _searchController.text);
      _loading = false;
    });
  }

  void _search(String value) {
    setState(() {
      _filteredReceipts = _applySearch(_receipts, value);
    });
  }

  List<ReceiptHistoryEntry> _applySearch(
    List<ReceiptHistoryEntry> receipts,
    String value,
  ) {
    final query = value.trim().toLowerCase();

    if (query.isEmpty) return List<ReceiptHistoryEntry>.from(receipts);

    return receipts.where((receipt) {
      final date = receipt.dateTime.toIso8601String().toLowerCase();

      return receipt.receiptNumber.toLowerCase().contains(query) ||
          receipt.customerName.toLowerCase().contains(query) ||
          receipt.cashierName.toLowerCase().contains(query) ||
          date.contains(query);
    }).toList();
  }

  Future<void> _openReceipt(ReceiptHistoryEntry entry) async {
    final receipt = await ReceiptService.instance.getReceiptBySaleId(
      saleId: entry.saleId,
      shopName: widget.shopName,
    );

    if (!mounted || receipt == null) return;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(receipt.receiptNumber),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Shop: ${receipt.shopName}'),
                Text('Cashier: ${receipt.cashierName}'),
                Text('Customer: ${receipt.customerName ?? 'Walk-in Customer'}'),
                Text('Date: ${receipt.dateTime}'),
                const Divider(),
                ...receipt.items.map(
                  (item) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.productName),
                    subtitle: Text('Qty: ${item.quantity}'),
                    trailing: Text(_money(item.total)),
                  ),
                ),
                const Divider(),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Total: ${_money(receipt.grandTotal)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
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
          FilledButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('WhatsApp sharing coming soon'),
                ),
              );
            },
            icon: const Icon(Icons.chat),
            label: const Text('WhatsApp'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt History'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _search,
                    decoration: const InputDecoration(
                      hintText: 'Search receipt, customer, cashier or date...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                Expanded(
                  child: _filteredReceipts.isEmpty
                      ? const Center(
                          child: Text('No receipts found'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filteredReceipts.length,
                          itemBuilder: (context, index) {
                            final receipt = _filteredReceipts[index];

                            return Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.receipt_long),
                                ),
                                title: Text(receipt.receiptNumber),
                                subtitle: Text(
                                  '${receipt.customerName}\n${receipt.dateTime}',
                                ),
                                isThreeLine: true,
                                trailing: Text(
                                  _money(receipt.total),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                onTap: () => _openReceipt(receipt),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

String _money(double value) => '\$${value.toStringAsFixed(2)}';
