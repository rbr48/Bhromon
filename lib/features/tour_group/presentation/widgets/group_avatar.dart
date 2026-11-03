import 'package:bhromon/core/media/media_access.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A group's picture: its photo when it has one, otherwise the icon its type uses (a
/// family or a trip). Drawn as a circle [size] pixels across.
class GroupAvatar extends StatelessWidget {
  const GroupAvatar({
    super.key,
    required this.isFamily,
    this.photoUrl,
    this.size = 40,
  });

  /// Whether the group is a family circle (its icon differs from a trip's).
  final bool isFamily;

  /// The group's photo URL, as stored on the group. Null or empty shows the icon.
  final String? photoUrl;

  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.forest.text.withValues(alpha: 0.08),
        shape: BoxShape.circle,
      ),
      child: Icon(
        isFamily ? Icons.family_restroom_rounded : Icons.card_travel_rounded,
        size: size * 0.5,
        color: context.forest.text54,
      ),
    );
    final url = photoUrl;
    if (url == null || url.isEmpty) return icon;
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: CachedNetworkImage(
          imageUrl: signedMediaUrl(url),
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 120),
          // Decode at about twice the size shown, not at full photo size (P6.5).
          memCacheWidth: (size * 2).round(),
          placeholder: (_, __) => icon,
          errorWidget: (_, __, ___) => icon,
        ),
      ),
    );
  }
}
