import 'dart:math' as math;

/// How a reel's picture is drawn in the space it is shown in.
enum ReelFill {
  /// Fills the space and cuts the picture's edges to do it.
  fill,

  /// Shows the whole picture, with bars where it does not reach the edges.
  fitInside,
}

/// The most of a picture that may be cut to make it fill its space.
const double kMaxReelCropShare = 0.2;

/// Chooses between filling and fitting a reel.
///
/// A reel fills the space when that cuts at most [kMaxReelCropShare] of the
/// picture, which keeps a portrait reel on a phone looking as it always has. A
/// landscape reel in a portrait space would lose most of its width, so it is
/// fitted and shown whole. A picture whose shape is not known fills the space,
/// as reels always have.
ReelFill reelFillFor({
  required double? pictureAspect,
  required double spaceAspect,
}) {
  if (pictureAspect == null || !(pictureAspect > 0) || !(spaceAspect > 0)) {
    return ReelFill.fill;
  }
  final cropShare = 1 -
      math.min(pictureAspect, spaceAspect) /
          math.max(pictureAspect, spaceAspect);
  return cropShare <= kMaxReelCropShare ? ReelFill.fill : ReelFill.fitInside;
}
