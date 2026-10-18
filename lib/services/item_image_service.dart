import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'cache_service.dart';
import 'erp_service.dart';
import 'sync_status_service.dart';

class ItemImageAttachment {
  const ItemImageAttachment({
    required this.name,
    required this.fileName,
    required this.fileUrl,
    required this.contentType,
    required this.localPath,
  });

  final String name;
  final String fileName;
  final String fileUrl;
  final String contentType;
  final String? localPath;
}

class ItemImageService {
  ItemImageService._();

  static const _imageExtensions = {
    '.avif',
    '.bmp',
    '.gif',
    '.heic',
    '.heif',
    '.jpeg',
    '.jpg',
    '.png',
    '.svg',
    '.tif',
    '.tiff',
    '.webp',
  };

  static bool isImageAttachment(Map<String, dynamic> row) {
    final contentType = row['content_type']?.toString().toLowerCase() ?? '';
    if (contentType.startsWith('image/')) return true;
    final fileUrl = row['file_url']?.toString() ?? '';
    final fileName = row['file_name']?.toString() ?? '';
    final extension = p
        .extension(Uri.tryParse(fileName)?.path ?? fileName)
        .toLowerCase();
    final urlExtension = p
        .extension(Uri.tryParse(fileUrl)?.path ?? fileUrl)
        .toLowerCase();
    return _imageExtensions.contains(extension) ||
        _imageExtensions.contains(urlExtension);
  }

  static Future<String?> localOrDownloadPrimaryImage({
    required String itemCode,
    required String imageUrl,
  }) => _localOrDownload(
    itemCode: itemCode,
    name: 'primary',
    fileName: p.basename(Uri.tryParse(imageUrl)?.path ?? imageUrl),
    fileUrl: imageUrl,
    contentType: '',
  );

  static Future<List<ItemImageAttachment>> syncItemImages({
    required String itemCode,
    String? primaryImageUrl,
  }) async {
    List<Map<String, dynamic>> records;
    try {
      final cached = await CacheService.getListCached(
        cacheDoctype: 'Item_image_attachments',
        cacheKey: itemCode,
        fetch: () async {
          final files = await ErpService.getList(
            'File',
            filters: [
              ['attached_to_doctype', '=', 'Item'],
              ['attached_to_name', '=', itemCode],
            ],
            fields: const [
              'name',
              'file_name',
              'file_url',
              'content_type',
              'is_private',
            ],
            orderBy: 'creation desc',
            limit: 500,
          );
          final images = files.where(isImageAttachment).toList();
          if (primaryImageUrl != null && primaryImageUrl.trim().isNotEmpty) {
            final normalizedPrimary = primaryImageUrl.trim();
            final alreadyIncluded = images.any(
              (row) => row['file_url']?.toString() == normalizedPrimary,
            );
            if (!alreadyIncluded) {
              images.insert(0, {
                'name': 'primary:$itemCode',
                'file_name': p.basename(
                  Uri.tryParse(normalizedPrimary)?.path ?? normalizedPrimary,
                ),
                'file_url': normalizedPrimary,
                'content_type': '',
              });
            }
          }
          return images;
        },
      );
      records = cached.rows;
    } catch (_) {
      records = [];
      if (primaryImageUrl != null && primaryImageUrl.trim().isNotEmpty) {
        records.add({
          'name': 'primary:$itemCode',
          'file_name': p.basename(
            Uri.tryParse(primaryImageUrl)?.path ?? primaryImageUrl,
          ),
          'file_url': primaryImageUrl.trim(),
          'content_type': '',
        });
      }
    }

    final images = <ItemImageAttachment>[];
    for (final row in records.where(isImageAttachment)) {
      final fileUrl = row['file_url']?.toString() ?? '';
      if (fileUrl.isEmpty) continue;
      final name = row['name']?.toString() ?? fileUrl;
      final fileName = row['file_name']?.toString() ?? p.basename(fileUrl);
      final contentType = row['content_type']?.toString() ?? '';
      final localPath = await _localOrDownload(
        itemCode: itemCode,
        name: name,
        fileName: fileName,
        fileUrl: fileUrl,
        contentType: contentType,
      );
      images.add(
        ItemImageAttachment(
          name: name,
          fileName: fileName,
          fileUrl: fileUrl,
          contentType: contentType,
          localPath: localPath,
        ),
      );
    }
    return images;
  }

  static Future<String?> _localOrDownload({
    required String itemCode,
    required String name,
    required String fileName,
    required String fileUrl,
    required String contentType,
  }) async {
    final extension = _extension(fileName, fileUrl, contentType);
    final key = _stableHash('$itemCode|$name|$fileUrl');
    final directory = await getApplicationSupportDirectory();
    final imageDirectory = Directory(p.join(directory.path, 'item_images'));
    await imageDirectory.create(recursive: true);
    final destination = p.join(imageDirectory.path, '$key$extension');
    final localFile = File(destination);
    if (await localFile.exists() && await localFile.length() > 0) {
      return destination;
    }
    if (!SyncStatusService().isOnline) return null;

    try {
      await ErpService.downloadFile(
        fileUrl: fileUrl,
        destinationPath: destination,
      );
      if (await localFile.exists() && await localFile.length() > 0) {
        return destination;
      }
    } catch (_) {
      if (await localFile.exists()) await localFile.delete();
    }
    return null;
  }

  static String _extension(
    String fileName,
    String fileUrl,
    String contentType,
  ) {
    final nameExtension = p
        .extension(Uri.tryParse(fileName)?.path ?? fileName)
        .toLowerCase();
    if (_imageExtensions.contains(nameExtension)) return nameExtension;
    final urlExtension = p
        .extension(Uri.tryParse(fileUrl)?.path ?? fileUrl)
        .toLowerCase();
    if (_imageExtensions.contains(urlExtension)) return urlExtension;
    return switch (contentType.toLowerCase()) {
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/gif' => '.gif',
      'image/webp' => '.webp',
      'image/svg+xml' => '.svg',
      'image/bmp' => '.bmp',
      'image/tiff' => '.tiff',
      'image/avif' => '.avif',
      _ => '.img',
    };
  }

  static String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash = ((hash ^ codeUnit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
