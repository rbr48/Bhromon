import 'package:flutter/material.dart';

import '../../../../../features/tour_group/domain/services/reel_fit.dart';
import 'tour_safe_network_image.dart';

/// The size a reel's video is laid out at when its own size is not known yet.
const Size _unknownPictureSize = Size(360, 640);

BoxFit _boxFitFor(ReelFill fill) => switch (fill) {
      ReelFill.fill => BoxFit.cover,
      ReelFill.fitInside => BoxFit.contain,
    };

/// Shows a reel's video in the space it is given.
///
/// [pictureSize] is the video's size as it plays, or null while it is not known.
/// With [wholePicture] set, a landscape reel is shown whole with bars above and
/// below, instead of being cut to fill a portrait screen. Without it, the video
/// fills the space as before.
class ReelFittedVideo extends StatelessWidget {
  const ReelFittedVideo({
    super.key,
    required this.pictureSize,
    required this.child,
    required this.wholePicture,
  });

  final Size? pictureSize;
  final Widget child;
  final bool wholePicture;

  @override
  Widget build(BuildContext context) {
    final known =
        pictureSize != null && pictureSize!.width > 0 && pictureSize!.height > 0
            ? pictureSize
            : null;
    final picture = known ?? _unknownPictureSize;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fill = wholePicture
            ? reelFillFor(
                pictureAspect: known?.aspectRatio,
                spaceAspect: constraints.biggest.aspectRatio,
              )
            : ReelFill.fill;
        return SizedBox.expand(
          child: FittedBox(
            fit: _boxFitFor(fill),
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: picture.width,
              height: picture.height,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// A reel's poster image, filled or fitted to the space the same way its video is.
///
/// [pictureAspect] is the width over the height of the reel as it was uploaded.
/// Null means the shape is not known, and the poster fills the space.
class ReelPoster extends StatelessWidget {
  const ReelPoster({
    super.key,
    required this.imageUrl,
    required this.pictureAspect,
    required this.wholePicture,
    this.placeholder,
    this.errorWidget,
  });

  final String imageUrl;
  final double? pictureAspect;
  final bool wholePicture;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fill = wholePicture
            ? reelFillFor(
                pictureAspect: pictureAspect,
                spaceAspect: constraints.biggest.aspectRatio,
              )
            : ReelFill.fill;
        return TourSafeNetworkImage(
          imageUrl: imageUrl,
          fit: _boxFitFor(fill),
          placeholder: placeholder,
          errorWidget: errorWidget,
        );
      },
    );
  }
}
