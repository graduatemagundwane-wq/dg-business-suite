import 'package:flutter/material.dart';

import '../services/pdf_service.dart';
import '../services/printer_service.dart';
import '../services/receipt_service.dart';
import '../services/whatsapp_service.dart';

enum _ReceiptFilter {
  all,
  today,
  thisWeek,
  thisMonth,
}

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
  _ReceiptFilter _filter = _ReceiptFilter.all;

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
      _filteredReceipts = _applyFilters(receipts, _searchController.text);
      _loading = false;
    });
  }

  void _search(String value) {
    setState(() {
      _filteredReceipts = _applyFilters(_receipts, value);
    });
  }

  void _setFilter(_ReceiptFilter filter) {
    setState(() {
      _filter = filter;
      _filteredReceipts = _applyFilters(_receipts, _searchController.text);
    });
  }

  List<ReceiptHistoryEntry> _applyFilters(
    List<ReceiptHistoryEntry> receipts,
    String value,
  ) {
    final query = value.trim().toLowerCase();
    final now = DateTime.now();
    final filteredByDate = receipts.where((receipt) {
      final date = receipt.dateTime;

      switch (_filter) {
        case _ReceiptFilter.all:
          return true;
        case _ReceiptFilter.today:
          return date.year == now.year &&
              date.month == now.month &&
              date.day == now.day;
        case _ReceiptFilter.thisWeek:
          return now.difference(date).inDays < 7;
        case _ReceiptFilter.thisMonth:
          return date.year == now.year && date.month == now.month;
      }
    });

    if (query.isEmpty) return filteredByDate.toList();

    return filteredByDate.where((receipt) {
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
          OutlinedButton.icon(
            onPressed: () => _reprintReceipt(receipt),
            icon: const Icon(Icons.print),
            label: const Text('Reprint'),
          ),
          OutlinedButton.icon(
            onPressed: () => _exportReceipt(receipt),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('PDF'),
          ),
          FilledButton.icon(
            onPressed: () => _shareReceipt(receipt),
            icon: const Icon(Icons.chat),
            label: const Text('WhatsApp'),
          ),
        ],
      ),
    );
  }

  Future<void> _reprintReceipt(ReceiptModel receipt) async {
    await PrinterService.instance.printReceipt(receipt);
  }

  Future<void> _exportReceipt(ReceiptModel receipt) async {
    await PdfService.instance.shareReceiptPdf(receipt);
  }

  Future<void> _shareReceipt(ReceiptModel receipt) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await WhatsAppService.instance.shareReceipt(
      receipt: receipt,
      customerPhone: receipt.customerPhone,
    );

    messenger.showSnackBar(SnackBar(content: Text(result.message)));
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
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        onChanged: _search,
                        decoration: const InputDecoration(
                          hintText: 'Search receipt, customer, cashier or date...',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _filterChip('All', _ReceiptFilter.all),
                            _filterChip('Today', _ReceiptFilter.today),
                            _filterChip('7 Days', _ReceiptFilter.thisWeek),
                            _filterChip('This Month', _ReceiptFilter.thisMonth),
                          ],
                        ),
                      ),
                    ],
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

  Widget _filterChip(String label, _ReceiptFilter filter) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: _filter == filter,
        onSelected: (_) => _setFilter(filter),
      ),
    );
  }
}

String _money(double value) => '\$${value.toStringAsFixed(2)}';
