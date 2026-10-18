import 'package:flutter/material.dart';

import '../services/item_catalog_service.dart';
import '../theme/app_theme.dart';
import '../widgets/item_image_gallery.dart';
import '../widgets/loading_indicator.dart';

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key});

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  bool _syncing = false;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result = await ItemCatalogService.load(
        onCacheHit: (cached) {
          if (!mounted) return;
          setState(() {
            _items = cached.rows;
            _loading = false;
            _error = null;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _items = result.rows;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _error = null;
    });
    try {
      final result = await ItemCatalogService.sync();
      if (!mounted) return;
      setState(() => _items = result.rows);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${result.rows.length} items synced to this device'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  List<Map<String, dynamic>> get _visibleItems {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _items;
    return _items.where((item) {
      final name = (item['item_name'] ?? '').toString().toLowerCase();
      final code = (item['name'] ?? '').toString().toLowerCase();
      return name.contains(query) || code.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _visibleItems;
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        title: const Text('Items'),
        actions: [
          IconButton(
            tooltip: 'Sync item catalog',
            onPressed: _syncing ? null : _syncNow,
            icon: _syncing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  hintText: 'Search items...',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.accent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    TextButton(onPressed: _syncNow, child: const Text('Retry')),
                  ],
                ),
              ),
            Expanded(
              child: _loading && _items.isEmpty
                  ? const LoadingIndicator()
                  : items.isEmpty
                  ? Center(
                      child: Text(
                        _items.isEmpty
                            ? 'No items synced yet'
                            : 'No matching items',
                        style: const TextStyle(color: AppColors.midGray),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 720 ? 4 : 2;
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 0.72,
                              ),
                          itemCount: items.length,
                          itemBuilder: (context, index) =>
                              _ItemTile(item: items[index]),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final itemCode = item['name']?.toString() ?? '';
    final itemName = (item['item_name'] ?? itemCode).toString();
    final price = item['selling_price'];
    final stock = item['stock_qty'];
    final imageUrl = item['image']?.toString();

    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(AppRadius.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showItemImageGallery(
          context,
          itemCode: itemCode,
          itemName: itemName,
          primaryImageUrl: imageUrl,
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ItemImageThumbnail(
                        itemCode: itemCode,
                        imageUrl: imageUrl,
                        size: 160,
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Material(
                        color: AppColors.white.withValues(alpha: 0.92),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'View and sync item images',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => showItemImageGallery(
                            context,
                            itemCode: itemCode,
                            itemName: itemName,
                            primaryImageUrl: imageUrl,
                          ),
                          icon: const Icon(
                            Icons.photo_library_outlined,
                            color: AppColors.accent,
                            size: 19,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                itemName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                price is num
                    ? '${price.toStringAsFixed(2)} EGP'
                    : 'Price unavailable',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.black, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                stock is num
                    ? 'Stock: ${stock.toStringAsFixed(0)}'
                    : 'Stock unavailable',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.midGray, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
