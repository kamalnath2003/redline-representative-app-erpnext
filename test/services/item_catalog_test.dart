import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_erp/local_db/app_database.dart';
import 'package:red_erp/services/cache_service.dart';
import 'package:red_erp/services/erp_service.dart';
import 'package:red_erp/services/item_image_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    CacheService.debugOverrideDatabase(database);
  });

  tearDown(() async {
    await database.close();
    CacheService.debugOverrideDatabase(AppDatabase.instance);
  });

  test('online item search merges rich fields into the offline master cache', () async {
    await CacheService.getListCached(
      cacheDoctype: 'Item_master',
      cacheKey: 'master',
      fetch: () async => [
        {
          'name': 'ITEM-001',
          'item_name': 'Widget',
          'image': '/files/widget.webp',
          'selling_price': 12.5,
        },
      ],
    );

    await CacheService.getSearchListCached(
      cacheDoctype: 'Item_master',
      fetch: () async => [
        {'name': 'ITEM-001', 'item_name': 'Widget'},
      ],
      searchFilter: (_) => true,
    );

    final offlineRows = await CacheService.getSearchListCached(
      cacheDoctype: 'Item_master',
      fetch: () async => throw const ErpException('offline'),
      searchFilter: (_) => true,
    );

    expect(offlineRows, hasLength(1));
    expect(offlineRows.single['image'], '/files/widget.webp');
    expect(offlineRows.single['selling_price'], 12.5);
  });

  test('image attachments include MIME types and common file extensions', () {
    expect(
      ItemImageService.isImageAttachment({
        'content_type': 'image/svg+xml',
        'file_name': 'diagram.svg',
      }),
      isTrue,
    );
    expect(
      ItemImageService.isImageAttachment({
        'content_type': 'application/octet-stream',
        'file_name': 'photo.HEIC',
      }),
      isTrue,
    );
    expect(
      ItemImageService.isImageAttachment({
        'file_type': 'Image',
        'file_name': 'item.img',
      }),
      isTrue,
    );
    expect(
      ItemImageService.isImageAttachment({
        'content_type': 'application/pdf',
        'file_name': 'specification.pdf',
      }),
      isFalse,
    );
  });
}
