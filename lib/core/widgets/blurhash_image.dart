import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import '../../core/theme/theme_context.dart';

class BlurHashImage extends StatelessWidget {
  final String imageUrl;
  final String? hash;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const BlurHashImage({
    super.key,
    required this.imageUrl,
    this.hash,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    Widget imageWidget = CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      placeholder: (context, url) => hash != null
          ? BlurHash(
              hash: hash!,
              imageFit: fit,
            )
          : Container(
              color: context.surfaceElevated,
              child: const Center(
                child:
                    Icon(Icons.image_outlined, color: Colors.white10, size: 24),
              ),
            ),
      errorWidget: (context, url, error) => Container(
        color: context.surfaceElevated,
        child: const Center(
          child: Icon(Icons.image_not_supported_outlined,
              color: Colors.white24, size: 28),
        ),
      ),
    );

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }
}
