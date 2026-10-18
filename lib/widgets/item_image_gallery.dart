import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/item_image_service.dart';
import '../theme/app_theme.dart';

Future<void> showItemImageGallery(
  BuildContext context, {
  required String itemCode,
  required String itemName,
  String? primaryImageUrl,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _ItemImageGallerySheet(
      itemCode: itemCode,
      itemName: itemName,
      primaryImageUrl: primaryImageUrl,
    ),
  );
}

class ItemImageThumbnail extends StatefulWidget {
  const ItemImageThumbnail({
    super.key,
    required this.itemCode,
    required this.imageUrl,
    this.size = 76,
  });

  final String itemCode;
  final String? imageUrl;
  final double size;

  @override
  State<ItemImageThumbnail> createState() => _ItemImageThumbnailState();
}

class _ItemImageThumbnailState extends State<ItemImageThumbnail> {
  late Future<String?> _imagePath;

  @override
  void initState() {
    super.initState();
    _imagePath = _loadImage();
  }

  @override
  void didUpdateWidget(covariant ItemImageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCode != widget.itemCode ||
        oldWidget.imageUrl != widget.imageUrl) {
      _imagePath = _loadImage();
    }
  }

  Future<String?> _loadImage() {
    final url = widget.imageUrl;
    if (url == null || url.trim().isEmpty) return Future.value(null);
    return ItemImageService.cachedPrimaryImagePath(
      itemCode: widget.itemCode,
      imageUrl: url,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FutureBuilder<String?>(
          future: _imagePath,
          builder: (context, snapshot) {
            final path = snapshot.data;
            if (path == null) return _imagePlaceholder();
            return _buildImage(path, BoxFit.cover, _imagePlaceholder());
          },
        ),
      ),
    );
  }
}

class _ItemImageGallerySheet extends StatefulWidget {
  const _ItemImageGallerySheet({
    required this.itemCode,
    required this.itemName,
    this.primaryImageUrl,
  });

  final String itemCode;
  final String itemName;
  final String? primaryImageUrl;

  @override
  State<_ItemImageGallerySheet> createState() => _ItemImageGallerySheetState();
}

class _ItemImageGallerySheetState extends State<_ItemImageGallerySheet> {
  List<ItemImageAttachment> _images = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final images = await ItemImageService.syncItemImages(
        itemCode: widget.itemCode,
        primaryImageUrl: widget.primaryImageUrl,
      );
      if (!mounted) return;
      setState(() {
        _images = images;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this item’s images.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableOffline = _images
        .where((image) => image.localPath != null)
        .length;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.itemName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _loading
                              ? 'Syncing images...'
                              : '$availableOffline of ${_images.length} images available offline',
                          style: const TextStyle(
                            color: AppColors.midGray,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sync images to this device',
                    onPressed: _loading ? null : _loadImages,
                    icon: const Icon(Icons.sync_rounded),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: AppColors.accent)),
      );
    }
    if (_images.isEmpty) {
      return const Center(
        child: Text(
          'No image attachments for this item',
          style: TextStyle(color: AppColors.midGray),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: _images.length,
      itemBuilder: (context, index) {
        final image = _images[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Material(
                  color: AppColors.lightGray,
                  child: InkWell(
                    onTap: image.localPath == null
                        ? null
                        : () => _showFullScreenImage(context, image),
                    child: image.localPath == null
                        ? _imagePlaceholder()
                        : _buildImage(
                            image.localPath!,
                            BoxFit.contain,
                            _imagePlaceholder(),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              image.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        );
      },
    );
  }
}

void _showFullScreenImage(BuildContext context, ItemImageAttachment image) {
  final path = image.localPath;
  if (path == null) return;
  showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    builder: (context) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: _buildImage(path, BoxFit.contain, _imagePlaceholder()),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildImage(String path, BoxFit fit, Widget fallback) {
  if (path.toLowerCase().endsWith('.svg')) {
    return SvgPicture.file(
      File(path),
      fit: fit,
      placeholderBuilder: (_) => fallback,
    );
  }
  return Image.file(File(path), fit: fit, errorBuilder: (_, _, _) => fallback);
}

Widget _imagePlaceholder() => ColoredBox(
  color: AppColors.lightGray,
  child: const Center(
    child: Icon(Icons.image_outlined, color: AppColors.midGray, size: 28),
  ),
);
