import 'package:flutter/material.dart';

class MarketplaceHubScreen extends StatefulWidget {
  const MarketplaceHubScreen({
    super.key,
  });

  @override
  State<MarketplaceHubScreen> createState() =>
      _MarketplaceHubScreenState();
}

class _MarketplaceHubScreenState
    extends State<MarketplaceHubScreen> {
  final TextEditingController
      _searchController =
      TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Marketplace",
        ),
      ),
      body: Column(
        children: [

          Padding(
            padding:
                const EdgeInsets.all(12),
            child: TextField(
              controller:
                  _searchController,
              decoration:
                  const InputDecoration(
                hintText:
                    "Search products...",
                prefixIcon:
                    Icon(Icons.search),
              ),
            ),
          ),

          Expanded(
            child: GridView.builder(
              padding:
                  const EdgeInsets.all(12),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.8,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: 8,
              itemBuilder:
                  (context, index) {
                return Card(
                  child: Column(
                    children: [

                      Expanded(
                        child: Container(
                          color: Colors.grey.shade300,
                          child: const Center(
                            child: Icon(
                              Icons.image,
                              size: 60,
                            ),
                          ),
                        ),
                      ),

                      const Padding(
                        padding:
                            EdgeInsets.all(8),
                        child: Text(
                          "Product Name",
                          style: TextStyle(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),

                      const Text(
                        "\$10.00",
                      ),

                      const SizedBox(
                        height: 5,
                      ),

                      ElevatedButton(
                        onPressed: () {},
                        child: const Text(
                          "View",
                        ),
                      ),

                      const SizedBox(
                        height: 5,
                      ),
                    ],
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