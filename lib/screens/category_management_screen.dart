import 'package:flutter/material.dart';

import '../database/local_db.dart';
import '../theme/app_theme.dart';

class CategoryManagementScreen extends StatefulWidget {
  final int shopId;

  const CategoryManagementScreen({
    super.key,
    required this.shopId,
  });

  @override
  State<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState
    extends State<CategoryManagementScreen> {
  final TextEditingController
      _categoryController =
      TextEditingController();

  List<Map<String, dynamic>>
      _categories = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final categories =
        await LocalDatabase.instance
            .getCategories(widget.shopId);

    setState(() {
      _categories = categories;
      _loading = false;
    });
  }

  Future<void> _addCategory() async {
    final name =
        _categoryController.text.trim();

    if (name.isEmpty) return;

    await LocalDatabase.instance
        .createCategory(
      shopId: widget.shopId,
      categoryName: name,
    );

    _categoryController.clear();

    _loadCategories();
  }

  Future<void> _deleteCategory(
      int categoryId) async {
    await LocalDatabase.instance
        .deleteCategory(categoryId);

    _loadCategories();
  }

  Future<void> _renameCategory(
      Map<String, dynamic> category) async {
    final controller =
        TextEditingController(
      text: category['category_name'],
    );

    final result =
        await showDialog<String>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text(
              "Rename Category"),
          content: TextField(
            controller: controller,
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context),
              child: const Text(
                  "Cancel"),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                controller.text.trim(),
              ),
              child:
                  const Text("Save"),
            ),
          ],
        );
      },
    );

    if (result == null ||
        result.isEmpty) {
      return;
    }

    await LocalDatabase.instance
        .renameCategory(
      categoryId: category['id'],
      newName: result,
    );

    _loadCategories();
  }

  @override
  Widget build(
      BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Categories",
        ),
        backgroundColor:
            AppTheme.primaryBlue,
      ),
      body: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.all(
                    16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller:
                        _categoryController,
                    decoration:
                        const InputDecoration(
                      hintText:
                          "Category Name",
                    ),
                  ),
                ),
                const SizedBox(
                    width: 10),
                ElevatedButton(
                  onPressed:
                      _addCategory,
                  child: const Text(
                      "ADD"),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child:
                        CircularProgressIndicator(),
                  )
                : _categories
                        .isEmpty
                    ? const Center(
                        child: Text(
                          "No Categories",
                        ),
                      )
                    : ListView.builder(
                        itemCount:
                            _categories
                                .length,
                        itemBuilder:
                            (context,
                                index) {
                          final category =
                              _categories[
                                  index];

                          return Card(
                            margin:
                                const EdgeInsets
                                    .symmetric(
                              horizontal:
                                  12,
                              vertical:
                                  4,
                            ),
                            child:
                                ListTile(
                              title: Text(
                                category[
                                    'category_name'],
                              ),
                              trailing:
                                  Row(
                                mainAxisSize:
                                    MainAxisSize
                                        .min,
                                children: [
                                  IconButton(
                                    icon:
                                        const Icon(
                                      Icons
                                          .edit,
                                    ),
                                    onPressed:
                                        () =>
                                            _renameCategory(
                                      category,
                                    ),
                                  ),
                                  IconButton(
                                    icon:
                                        const Icon(
                                      Icons
                                          .delete,
                                      color: Colors
                                          .red,
                                    ),
                                    onPressed:
                                        () =>
                                            _deleteCategory(
                                      category[
                                          'id'],
                                    ),
                                  ),
                                ],
                              ),
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