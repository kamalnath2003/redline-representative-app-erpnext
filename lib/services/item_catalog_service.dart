import 'cache_service.dart';
import 'erp_service.dart';

class ItemCatalogService {
  ItemCatalogService._();

  static const _cacheDoctype = 'Item_master';
  static const _cacheKey = 'master';

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
        'is_stock_item',
        'has_batch_no',
        'has_serial_no',
      ],
      limit: 5000,
    );

    final priceByItem = <String, num>{};
    final priceList = await ErpService.getSellingSettingsPriceList();
    if (priceList != null && items.isNotEmpty) {
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
        for (final price in prices) {
          final code = price['item_code']?.toString();
          final rate = price['price_list_rate'];
          if (code != null && rate is num) {
            priceByItem.putIfAbsent(code, () => rate);
          }
        }
      } catch (_) {
        // Prices remain unavailable if the account cannot read Item Price.
      }
    }

    final stockByItem = <String, num>{};
    var stockAvailable = false;
    try {
      final bins = await ErpService.getList(
        'Bin',
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

    return items.map((item) {
      final code = item['name']?.toString();
      return <String, dynamic>{
        ...item,
        'price_list': ?priceList,
        'selling_price': code == null ? null : priceByItem[code],
        'stock_qty': !stockAvailable || code == null
            ? null
            : stockByItem[code] ?? 0,
      };
    }).toList();
  }
}
