import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../database/local_db.dart';
import '../theme/app_theme.dart';

class AddProductScreen extends StatefulWidget {
  final int shopId;
  final Map<String, dynamic>? product;
  final String? initialBarcode;

  const AddProductScreen({
    super.key,
    required this.shopId,
    this.product,
    this.initialBarcode,
  });

  @override
  State<AddProductScreen> createState() =>
      _AddProductScreenState();
}

class _AddProductScreenState
    extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController =
      TextEditingController();

  final _barcodeController =
      TextEditingController();

  final _buyingController =
      TextEditingController();

  final _sellingController =
      TextEditingController();

  final _stockController =
      TextEditingController();

  final _lowStockController =
      TextEditingController(text: "10");

  final ImagePicker _picker =
      ImagePicker();

  List<Map<String, dynamic>>
      _categories = [];

  String? _selectedCategory;

  String _imagePath = '';

  bool _saving = false;

  @override
void initState() {
  super.initState();
  _loadCategories();

  if (widget.product != null) {
    final product = widget.product!;

    _nameController.text =
        product['product_name'] ?? '';

    _barcodeController.text =
        product['barcode'] ?? '';

    _buyingController.text =
        product['buying_price'].toString();

    _sellingController.text =
        product['selling_price'].toString();

    _stockController.text =
        product['stock_quantity'].toString();

    _lowStockController.text =
        product['low_stock_limit'].toString();

    _imagePath =
        product['image_path'] ?? '';

    if (product['category_id'] != null) {
      _selectedCategory =
          product['category_id'].toString();
    }
  } else if (widget.initialBarcode != null) {
    _barcodeController.text = widget.initialBarcode!;
  }
}

  Future<void> _loadCategories() async {
    final categories =
        await LocalDatabase.instance
            .getCategories(widget.shopId);

    setState(() {
      _categories = categories;

      if (widget.product != null &&
          widget.product!['category_id'] != null) {
        _selectedCategory = widget.product!['category_id'].toString();
      } else if (_categories.isNotEmpty) {
        _selectedCategory =
            _categories.first['id']
                .toString();
      }
    });
  }

  Future<void> _pickFromGallery()
      async {
    final image =
        await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (image == null) return;

    setState(() {
      _imagePath = image.path;
    });
  }

  Future<void> _takePhoto() async {
    final image =
        await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );

    if (image == null) return;

    setState(() {
      _imagePath = image.path;
    });
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!
        .validate()) {
      return;
    }

    final categoryId = await _resolveCategoryId();

    setState(() {
      _saving = true;
    });

    final productData = {
      'shop_id': widget.shopId,
      'category_id': categoryId,
      'product_name':
          _nameController.text.trim(),
      'barcode':
          _barcodeController.text.trim(),
      'image_path': _imagePath,
      'buying_price':
          double.parse(
        _buyingController.text.trim(),
      ),
      'selling_price':
          double.parse(
        _sellingController.text.trim(),
      ),
      'stock_quantity':
          int.parse(
        _stockController.text.trim(),
      ),
      'low_stock_limit':
          int.parse(
        _lowStockController.text.trim(),
      ),
      'marketplace_visible':
    widget.product == null
        ? 0
        : widget.product!['marketplace_visible'],
};

if (widget.product == null) {
  await LocalDatabase.instance
      .createProduct(productData);
} else {
  productData['id'] =
      widget.product!['id'];

  await LocalDatabase.instance
      .updateProduct(productData);
}

    setState(() {
      _saving = false;
    });

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<int> _resolveCategoryId() async {
    if (_selectedCategory != null) {
      return int.parse(_selectedCategory!);
    }

    for (final category in _categories) {
      final name = (category['category_name'] ?? '').toString().toLowerCase();
      if (name == 'general') {
        return category['id'] as int;
      }
    }

    final id = await LocalDatabase.instance.createCategory(
      shopId: widget.shopId,
      categoryName: 'General',
    );

    if (mounted) {
      setState(() {
        _categories = [
          ..._categories,
          {'id': id, 'category_name': 'General'},
        ];
        _selectedCategory = id.toString();
      });
    }

    return id;
  }

  Widget _buildImagePreview() {
    if (_imagePath.isEmpty) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          borderRadius:
              BorderRadius.circular(16),
          border: Border.all(),
        ),
        child: const Center(
          child: Icon(
            Icons.image_outlined,
            size: 70,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius:
          BorderRadius.circular(16),
      child: Image.file(
        File(_imagePath),
        height: 180,
        width: double.infinity,
        fit: BoxFit.cover,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(
  widget.product == null
      ? "Add Product"
      : "Edit Product",
),
        backgroundColor:
            AppTheme.primaryBlue,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildImagePreview(),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed:
                          _takePhoto,
                      icon: const Icon(
                          Icons.camera_alt),
                      label:
                          const Text(
                              "Camera"),
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child:
                        ElevatedButton.icon(
                      onPressed:
                          _pickFromGallery,
                      icon: const Icon(
                          Icons.photo),
                      label:
                          const Text(
                              "Gallery"),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              TextFormField(
                controller:
                    _nameController,
                decoration:
                    const InputDecoration(
                  labelText:
                      "Product Name",
                ),
                validator: (value) {
                  if (value == null ||
                      value
                          .trim()
                          .isEmpty) {
                    return "Required";
                  }
                  return null;
                },
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller:
                    _barcodeController,
                decoration:
                    const InputDecoration(
                  labelText:
                      "Barcode (Optional)",
                ),
              ),

              const SizedBox(height: 12),

              DropdownButtonFormField<
                  String>(
                initialValue:
                    _selectedCategory,
                items: _categories
                    .map(
                      (cat) =>
                          DropdownMenuItem(
                        value: cat['id']
                            .toString(),
                        child: Text(
                          cat[
                              'category_name'],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCategory =
                        value;
                  });
                },
                decoration:
                    const InputDecoration(
                  labelText:
                      "Category",
                ),
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller:
                    _buyingController,
                keyboardType:
                    TextInputType.number,
                decoration:
                    const InputDecoration(
                  labelText:
                      "Buying Price",
                ),
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller:
                    _sellingController,
                keyboardType:
                    TextInputType.number,
                decoration:
                    const InputDecoration(
                  labelText:
                      "Selling Price",
                ),
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller:
                    _stockController,
                keyboardType:
                    TextInputType.number,
                decoration:
                    const InputDecoration(
                  labelText:
                      "Stock Quantity",
                ),
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller:
                    _lowStockController,
                keyboardType:
                    TextInputType.number,
                decoration:
                    const InputDecoration(
                  labelText:
                      "Low Stock Alert",
                ),
              ),

              const SizedBox(height: 30),

              SizedBox(
                width:
                    double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed:
                      _saving
                          ? null
                          : _saveProduct,
                  child: _saving
                      ? const CircularProgressIndicator()
                      : Text(
                        widget.product == null
                        ? "SAVE PRODUCT"
                        : "UPDATE PRODUCT",
                        )
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
