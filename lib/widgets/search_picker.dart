import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'item_image_gallery.dart';
import 'loading_indicator.dart';

/// A record shown in [showSearchPicker]'s results list.
class PickedRecord {
  const PickedRecord({
    required this.name,
    required this.label,
    this.subtitle,
    this.enabled = true,
    this.imageUrl,
    this.price,
    this.stock,
    this.isStockItem,
    this.quantity = 0,
    this.onImageTap,
  });

  /// The DocType record's `name` (its ID) — what gets sent back to the API.
  final String name;

  /// Primary display text.
  final String label;

  final String? subtitle;

  /// Disabled results stay visible to explain why they cannot be selected.
  final bool enabled;

  final String? imageUrl;
  final num? price;
  final num? stock;
  /// Whether ERPNext requires a source warehouse for this item.
  final bool? isStockItem;
  final int quantity;
  final Future<void> Function(BuildContext context)? onImageTap;
}

/// Full-screen searchable picker used for Customer/Item/Vehicle selection
/// across the Sales Order/Invoice/Payment/Vehicle Log screens. [search] is
/// called (debounced) with the current query — callers decide what
/// DocType/fields to search via [ErpService.getList].
///
/// [actionsBuilder], when given, renders extra AppBar actions (e.g. a
/// territory-filter gear icon) — it's handed this picker screen's own
/// `BuildContext` (so a nested `showSearchPicker` call pushes correctly)
/// and a `refresh` callback to re-run the current search after an action
/// changes some filter state the caller's [search] closure reads. The
/// filter value itself isn't plumbed through here — it lives in a local
/// variable in the caller's own method, shared by both closures the way
/// Dart closures naturally share captured variables.
Future<PickedRecord?> showSearchPicker({
  required BuildContext context,
  required String title,
  required Future<List<PickedRecord>> Function(String query) search,
  Future<List<PickedRecord>> Function(String query)? backgroundSearch,
  String hintText = 'Search by name...',
  List<Widget> Function(BuildContext context, VoidCallback refresh)?
  actionsBuilder,
}) {
  return Navigator.of(context).push<PickedRecord>(
    MaterialPageRoute(
      builder: (context) => _SearchPickerScreen(
        title: title,
        search: search,
        backgroundSearch: backgroundSearch,
        hintText: hintText,
        actionsBuilder: actionsBuilder,
      ),
    ),
  );
}

Future<List<PickedRecord>?> showMultiItemPicker({
  required BuildContext context,
  required String title,
  required Future<List<PickedRecord>> Function(String query) search,
  Future<List<PickedRecord>> Function(String query)? backgroundSearch,
  required List<String> brands,
  required void Function(String? brand) onBrandChanged,
  required String? selectedBrand,
}) {
  return Navigator.of(context).push<List<PickedRecord>>(
    MaterialPageRoute(
      builder: (context) => _SearchPickerScreen(
        title: title,
        search: search,
        backgroundSearch: backgroundSearch,
        hintText: 'Search items...',
        multiSelect: true,
        brands: brands,
        selectedBrand: selectedBrand,
        onBrandChanged: onBrandChanged,
      ),
    ),
  );
}

class _SearchPickerScreen extends StatefulWidget {
  const _SearchPickerScreen({
    required this.title,
    required this.search,
    required this.hintText,
    this.backgroundSearch,
    this.actionsBuilder,
    this.multiSelect = false,
    this.brands = const [],
    this.selectedBrand,
    this.onBrandChanged,
  });

  final String title;
  final Future<List<PickedRecord>> Function(String query) search;
  final Future<List<PickedRecord>> Function(String query)? backgroundSearch;
  final String hintText;
  final List<Widget> Function(BuildContext context, VoidCallback refresh)?
  actionsBuilder;
  final bool multiSelect;
  final List<String> brands;
  final String? selectedBrand;
  final void Function(String? brand)? onBrandChanged;

  @override
  State<_SearchPickerScreen> createState() => _SearchPickerScreenState();
}

class _SearchPickerScreenState extends State<_SearchPickerScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<PickedRecord> _results = [];
  bool _loading = false;
  String? _error;
  bool _searchedOnce = false;
  final Map<String, int> _quantities = {};
  final Map<String, PickedRecord> _selectedRecords = {};
  int _searchGeneration = 0;
  int _thumbnailGeneration = 0;

  @override
  void initState() {
    super.initState();
    _runSearch('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _searchGeneration++;
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _runSearch(query),
    );
  }

  Future<void> _runSearch(String query) async {
    final generation = ++_searchGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.search(query);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = results;
        for (final record in results) {
          _selectedRecords[record.name] = record;
        }
        _loading = false;
        _searchedOnce = true;
      });
      if (widget.backgroundSearch != null) {
        unawaited(_refreshResultsInBackground(query, generation));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _searchedOnce = true;
        _error = e.toString();
      });
    }
  }

  Future<void> _refreshResultsInBackground(String query, int generation) async {
    try {
      final results = await widget.backgroundSearch!(query);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = results;
        for (final record in results) {
          _selectedRecords[record.name] = record;
        }
      });
    } catch (_) {
      // Keep displaying cached matches if the server refresh fails.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        title: Text(widget.title),
        actions: widget.actionsBuilder?.call(
          context,
          () => _runSearch(_controller.text),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
              ),
            ),
            if (widget.multiSelect && widget.brands.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: DropdownButtonFormField<String?>(
                  value: widget.selectedBrand,
                  decoration: const InputDecoration(labelText: 'Brand'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All brands'),
                    ),
                    ...widget.brands.map(
                      (b) =>
                          DropdownMenuItem<String?>(value: b, child: Text(b)),
                    ),
                  ],
                  onChanged: (value) {
                    widget.onBrandChanged?.call(value);
                    _runSearch(_controller.text);
                  },
                ),
              ),
            Expanded(child: _buildBody()),
            if (widget.multiSelect)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _quantities.values.any((q) => q > 0)
                          ? () => Navigator.of(context).pop(
                              _quantities.entries
                                  .where((entry) => entry.value > 0)
                                  .map((entry) {
                                    final record = _selectedRecords[entry.key]!;
                                    return PickedRecord(
                                      name: record.name,
                                      label: record.label,
                                      quantity: entry.value,
                                      price: record.price,
                                      stock: record.stock,
                                      isStockItem: record.isStockItem,
                                      imageUrl: record.imageUrl,
                                    );
                                  })
                                  .toList(),
                            )
                          : null,
                      child: Text(
                        'Add selected (${_quantities.values.fold<int>(0, (a, b) => a + b)})',
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && !_searchedOnce) {
      return const LoadingIndicator();
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.accent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.accent),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return const Center(
        child: Text(
          'No results found',
          style: TextStyle(color: AppColors.midGray),
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900
        ? 3
        : width >= 600
        ? 2
        : 1;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        mainAxisExtent: columns == 1 ? 122 : 150,
      ),
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final record = _results[i];
        final quantity = _quantities[record.name] ?? 0;
        return Material(
          color: record.enabled
              ? AppColors.white
              : AppColors.midGray.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.card),
            onTap: widget.multiSelect
                ? null
                : record.enabled
                ? () => Navigator.of(context).pop(record)
                : null,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if ((record.imageUrl != null &&
                          record.imageUrl!.isNotEmpty) ||
                      widget.multiSelect)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: record.onImageTap == null
                            ? null
                            : () async {
                                await record.onImageTap!(context);
                                if (!mounted) return;
                                setState(() => _thumbnailGeneration++);
                              },
                        child: ItemImageThumbnail(
                          key: ValueKey('${record.name}-$_thumbnailGeneration'),
                          itemCode: record.name,
                          imageUrl: record.imageUrl,
                          size: widget.multiSelect ? 68 : 54,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.label,
                          style: TextStyle(
                            color: record.enabled
                                ? AppColors.black
                                : AppColors.midGray,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                        if (record.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            record.subtitle!,
                            style: TextStyle(
                              color: record.enabled
                                  ? AppColors.midGray
                                  : AppColors.accent,
                              fontWeight: record.enabled
                                  ? FontWeight.w400
                                  : FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (widget.multiSelect) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Price: ${record.price?.toStringAsFixed(2) ?? '—'}',
                          ),
                          Text('Stock: ${record.stock?.toString() ?? '—'}'),
                        ],
                      ],
                    ),
                  ),
                  if (widget.multiSelect)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 34,
                            height: 34,
                          ),
                          onPressed: () => setState(
                            () => _quantities[record.name] = quantity + 1,
                          ),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                        Text(
                          '$quantity',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 34,
                            height: 34,
                          ),
                          onPressed: quantity == 0
                              ? null
                              : () => setState(
                                  () => _quantities[record.name] = quantity - 1,
                                ),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ],
                    )
                  else
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.midGray,
                    ),
                  if (!record.enabled) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.block_rounded,
                      color: AppColors.midGray,
                      size: 20,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
