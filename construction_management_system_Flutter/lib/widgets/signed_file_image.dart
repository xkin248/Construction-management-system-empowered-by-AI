import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Renders a server-side image through a short-lived signed URL.
///
/// `Image.network` can only carry a URL, and the raw `/files/{id}/download`
/// endpoint requires an `Authorization` header, so every preview used to fail
/// with 401 and fall back to the broken-image icon. The link is minted once per
/// file (ApiService caches it until just before expiry) and then loaded like any
/// other remote image, so previews also work on Web where headers are impossible.
///
/// [cacheWidth] / [cacheHeight] bound the decoded bitmap (in physical pixels)
/// so a grid full of photos no longer decodes full-resolution originals and
/// exhausts memory while scrolling.
class SignedFileImage extends StatefulWidget {
  const SignedFileImage({
    super.key,
    required this.fileId,
    required this.errorWidget,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
  });

  final int fileId;
  final Widget errorWidget;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;

  @override
  State<SignedFileImage> createState() => _SignedFileImageState();
}

class _SignedFileImageState extends State<SignedFileImage> {
  late Future<String> _urlFuture;

  @override
  void initState() {
    super.initState();
    _urlFuture = ApiService().fetchDownloadLink(widget.fileId);
  }

  @override
  void didUpdateWidget(covariant SignedFileImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileId != widget.fileId) {
      _urlFuture = ApiService().fetchDownloadLink(widget.fileId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _urlFuture,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null || url.isEmpty) {
          if (snapshot.hasError) return widget.errorWidget;
          return Container(
            width: widget.width,
            height: widget.height,
            color: AppColors.bgMain,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        return Image.network(
          url,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          cacheWidth: widget.cacheWidth,
          cacheHeight: widget.cacheHeight,
          // Keep decoded frames small; scrolling a long photo grid should not
          // hold full-size bitmaps in memory.
          filterQuality: FilterQuality.low,
          errorBuilder: (_, __, ___) => widget.errorWidget,
        );
      },
    );
  }
}
