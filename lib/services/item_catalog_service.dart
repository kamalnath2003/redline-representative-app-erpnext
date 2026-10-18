import 'cache_service.dart';
import 'erp_service.dart';

class ItemCatalogService {
  ItemCatalogService._();

  static const _cacheDoctype = 'Item_master';
  static const _cacheKey = 'master';

  static Future<CachedListResult?> readCached() =>
      CacheService.readCached(_cacheDoctype, _cacheKey);

  static Future<List<String>> cachedBrands() async {
    final cached = await readCached();
    final brands =
        cached?.rows
            .map((row) => row['brand']?.toString() ?? '')
            .where((brand) => brand.isNotEmpty)
            .toSet()
            .toList() ??
        <String>[];
    final brandCache = await CacheService.readCached('Brand_master', 'master');
    brands.addAll(
      (brandCache?.rows ?? const <Map<String, dynamic>>[])
          .map((row) => row['name']?.toString() ?? '')
          .where((brand) => brand.isNotEmpty),
    );
    final uniqueBrands = brands.toSet().toList();
    uniqueBrands.sort();
    return uniqueBrands;
  }

  static Future<List<Map<String, dynamic>>> searchCached({
    required String query,
    String? brand,
  }) async {
    final cached = await readCached();
    final q = query.trim().toLowerCase();
    return (cached?.rows ?? const <Map<String, dynamic>>[])
        .where((row) {
          final code = row['name']?.toString().toLowerCase() ?? '';
          final name = row['item_name']?.toString().toLowerCase() ?? '';
          return (q.isEmpty || code.contains(q) || name.contains(q)) &&
              (brand == null || row['brand'] == brand);
        })
        .take(300)
        .toList();
  }

  static Future<CachedListResult> load({
    required void Function(CachedListResult cached) onCacheHit,
  }) {
    return CacheService.getListStaleWhileRevalidate(
      cacheDoctype: _cacheDoctype,
      cacheKey: _cacheKey,
      fetch: _fetchCatalog,
      onCacheHit: onCacheHit,
    );
  }

  static Future<CachedListResult> sync() {
    return CacheService.getListCached(
      cacheDoctype: _cacheDoctype,
      cacheKey: _cacheKey,
      fetch: _fetchCatalog,
    );
  }

  static Future<List<Map<String, dynamic>>> _fetchCatalog() async {
    final items = await ErpService.getList(
      'Item',
      filters: const [
        ['disabled', '=', 0],
      ],
      fields: const [
        'name',
        'item_name',
        'image',
        'brand',
        'is_stock_item',
        'has_batch_no',
        'has_serial_no',
      ],
      limit: 5000,
    );
    try {
      final brands = await ErpService.getList(
        'Brand',
        fields: const ['name'],
        limit: 500,
      );
      await CacheService.getListCached(
        cacheDoctype: 'Brand_master',
        cacheKey: 'master',
        fetch: () async => brands,
      );
    } catch (_) {}

    final pricesByList = <String, Map<String, num>>{};
    String? sellingPriceList;
    try {
      sellingPriceList = await ErpService.getSellingSettingsPriceList();
    } catch (_) {}
    final priceLists = <String?>{sellingPriceList};
    for (final cachedList
        in (await CacheService.readCached(
              'Price List_master',
              'master',
            ))?.rows ??
            const <Map<String, dynamic>>[]) {
      final name = cachedList['name']?.toString();
      if (name != null && name.isNotEmpty) priceLists.add(name);
    }
    await Future.wait(
      priceLists.whereType<String>().map((priceList) async {
        try {
          final prices = await ErpService.getList(
            'Item Price',
            filters: [
              ['price_list', '=', priceList],
              ['selling', '=', 1],
            ],
            fields: const ['item_code', 'price_list_rate'],
            orderBy: 'valid_from desc',
            limit: 10000,
          );
          pricesByList[priceList] = {};
          for (final price in prices) {
            final code = price['item_code']?.toString();
            final rate = price['price_list_rate'];
            if (code != null && rate is num) {
              pricesByList[priceList]!.putIfAbsent(code, () => rate);
            }
          }
        } catch (_) {}
      }),
    );
    final stockByItem = <String, num>{};
    final availableWarehouses = <String>[];
    var stockAvailable = false;
    try {
      availableWarehouses.addAll(
        await ErpService.getCurrentRepSellingWarehouses(),
      );
      final bins = availableWarehouses.isEmpty
          ? <Map<String, dynamic>>[]
          : await ErpService.getList(
              'Bin',
              filters: [
                ['warehouse', 'in', availableWarehouses],
              ],
              fields: const ['item_code', 'actual_qty'],
              limit: 20000,
            );
      stockAvailable = true;
      for (final bin in bins) {
        final code = bin['item_code']?.toString();
        final quantity = bin['actual_qty'];
        if (code != null && quantity is num) {
          stockByItem.update(
            code,
            (current) => current + quantity,
            ifAbsent: () => quantity,
          );
        }
      }
    } catch (_) {
      // Keep stock null instead of reporting a misleading zero.
    }

    final defaultPrices =
        pricesByList[sellingPriceList] ?? const <String, num>{};
    return items.map((item) {
      final code = item['name']?.toString();
      return <String, dynamic>{
        ...item,
        'selling_price_list': sellingPriceList,
        'available_warehouses': availableWarehouses,
        'selling_price': code == null ? null : defaultPrices[code],
        'selling_price_by_list': code == null
            ? <String, num>{}
            : {
                for (final entry in pricesByList.entries)
                  if (entry.value[code] != null) entry.key: entry.value[code]!,
              },
        'stock_qty': !stockAvailable || code == null
            ? null
            : stockByItem[code] ?? 0,
      };
    }).toList();
  }
}
