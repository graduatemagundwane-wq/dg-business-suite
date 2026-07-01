import 'pdf_service.dart';
import 'receipt_service.dart';

class SavedPrinterProfile {
  final String id;
  final String name;
  final PrinterConnectionType type;
  final ReceiptPaperSize paperSize;
  final String address;
  final bool enabled;
  final bool isDefault;

  const SavedPrinterProfile({
    required this.id,
    required this.name,
    required this.type,
    required this.paperSize,
    this.address = '',
    this.enabled = true,
    this.isDefault = false,
  });

  SavedPrinterProfile copyWith({
    bool? isDefault,
  }) {
    return SavedPrinterProfile(
      id: id,
      name: name,
      type: type,
      paperSize: paperSize,
      address: address,
      enabled: enabled,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}

class PrinterService {
  static final PrinterService instance = PrinterService._internal();

  factory PrinterService() => instance;

  PrinterService._internal();

  final List<SavedPrinterProfile> _profiles = const [
    SavedPrinterProfile(
      id: 'bluetooth-default',
      name: 'Bluetooth Receipt Printer',
      type: PrinterConnectionType.bluetooth,
      paperSize: ReceiptPaperSize.mm58,
      address: 'Bluetooth pairing pending',
      isDefault: true,
    ),
    SavedPrinterProfile(
      id: 'usb-default',
      name: 'USB Receipt Printer',
      type: PrinterConnectionType.usb,
      paperSize: ReceiptPaperSize.mm80,
      address: 'USB driver pending',
    ),
    SavedPrinterProfile(
      id: 'otg-default',
      name: 'USB/OTG Receipt Printer',
      type: PrinterConnectionType.otg,
      paperSize: ReceiptPaperSize.mm80,
      address: 'Android OTG bridge pending',
    ),
    SavedPrinterProfile(
      id: 'network-default',
      name: 'Network Office Printer',
      type: PrinterConnectionType.network,
      paperSize: ReceiptPaperSize.a4Invoice,
      address: 'Network printer address pending',
    ),
  ];

  List<SavedPrinterProfile> get profiles => List.unmodifiable(_profiles);

  SavedPrinterProfile? get defaultPrinter {
    for (final profile in _profiles) {
      if (profile.isDefault) return profile;
    }

    return _profiles.isEmpty ? null : _profiles.first;
  }

  void setDefaultPrinter(String printerId) {
    for (var index = 0; index < _profiles.length; index++) {
      final profile = _profiles[index];
      _profiles[index] = profile.copyWith(isDefault: profile.id == printerId);
    }
  }

  Future<void> printReceipt(
    ReceiptModel receipt, {
    SavedPrinterProfile? printer,
  }) async {
    final selectedPrinter = printer ?? defaultPrinter;

    await PdfService.instance.printReceiptPdf(
      receipt,
      paperSize: selectedPrinter?.paperSize ?? receipt.paperSize,
      documentType: receipt.documentType,
    );
  }
}
