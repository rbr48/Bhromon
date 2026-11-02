import 'package:bhromon/core/media/media_access.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../domain/models/tour_post_models.dart';

/// A robust network image loader that guarantees reliable image rendering across
/// Flutter Web and Mobile platforms.
///
/// On Web: delegates directly to [Image.network] to avoid XHR CORS restrictions,
/// IndexedDB storage quotas, and CanvasKit tainting caused by [flutter_cache_manager].
///
/// On Mobile: uses [CachedNetworkImage] for fast offline caching with automatic
/// fallback to [Image.network] if the local cache fails.
///
/// If loading fails on either platform, displays a clean, user-friendly error UI
/// with an interactive retry button to re-fetch the image without restarting the app.
class TourSafeNetworkImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Alignment alignment;
  final Widget? placeholder;
  final Widget? errorWidget;
  final ColorFilter? colorFilter;

  const TourSafeNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.placeholder,
    this.errorWidget,
    this.colorFilter,
  });

  @override
  State<TourSafeNetworkImage> createState() => _TourSafeNetworkImageState();
}

class _TourSafeNetworkImageState extends State<TourSafeNetworkImage> {
  int _retryCount = 0;

  bool _isValidUrl(String url) {
    if (url.trim().isEmpty) return false;
    if (isRemoteMediaUrl(url)) return true;
    if (kIsWeb && (url.startsWith('blob:') || url.startsWith('data:'))) {
      return true;
    }
    return false;
  }

  void _retry() {
    setState(() {
      _retryCount++;
    });
  }

  Widget _buildPlaceholder() {
    if (widget.placeholder != null) return widget.placeholder!;
    return Container(
      width: widget.width,
      height: widget.height,
      color: context.forest.feedSurface,
      child: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(context.forest.text38),
        ),
      ),
    );
  }

  Widget _buildErrorUI(BuildContext context, {String? customMessage}) {
    if (widget.errorWidget != null) return widget.errorWidget!;
    final l10n = context.l10n;
    final message = customMessage ?? l10n.translate('ig_image_load_failed');

    return Container(
      width: widget.width,
      height: widget.height,
      color: context.forest.feedSurface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image_outlined,
              color: context.forest.text54,
              size: 34,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.forest.text70,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: _retry,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: context.forest.divider12,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: context.forest.text24, width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded,
                        color: context.forest.text, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      l10n.translate('ig_image_retry'),
                      style: TextStyle(
                        color: context.forest.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isValidUrl(widget.imageUrl)) {
      return _buildErrorUI(
        context,
        customMessage: context.l10n.translate('ig_invalid_media_url'),
      );
    }

    final effectiveKey = ValueKey('${widget.imageUrl}#retry_$_retryCount');

    Widget imageWidget;
    if (kIsWeb) {
      // Direct Web HTML/Browser image decoding with hardware downsampling
      imageWidget = Image.network(
        signedMediaUrl(widget.imageUrl),
        key: effectiveKey,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        alignment: widget.alignment,
        cacheWidth: 1080,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildPlaceholder();
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildErrorUI(context);
        },
      );
    } else {
      // Mobile: CachedNetworkImage with memory downsampling & fallback
      imageWidget = CachedNetworkImage(
        key: effectiveKey,
        imageUrl: signedMediaUrl(widget.imageUrl),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        alignment: widget.alignment,
        memCacheWidth: 1080,
        maxWidthDiskCache: 1440,
        fadeInDuration: const Duration(milliseconds: 120),
        fadeOutDuration: const Duration(milliseconds: 120),
        placeholder: (context, _) => _buildPlaceholder(),
        errorWidget: (context, _, __) {
          return Image.network(
            signedMediaUrl(widget.imageUrl),
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            alignment: widget.alignment,
            cacheWidth: 1080,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return _buildPlaceholder();
            },
            errorBuilder: (context, error, stackTrace) {
              return _buildErrorUI(context);
            },
          );
        },
      );
    }

    if (widget.colorFilter != null) {
      return ColorFiltered(
        colorFilter: widget.colorFilter!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }
}
