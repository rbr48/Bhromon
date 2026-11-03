import 'package:bhromon/core/media/media_access.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// A member's picture: their photo, or their initial on mint. Text on mint is dark green.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.size = 40,
  });

  final String name;
  final String? photoUrl;
  final double size;

  /// The letter a member without a photo is shown with.
  static String initialOf(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    // The initial is decoration: the label is the name, read once.
    return Semantics(
      label: name,
      image: true,
      excludeSemantics: true,
      child: _avatar(context),
    );
  }

  Widget _avatar(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.mintGreen,
        shape: BoxShape.circle,
      ),
      child: Text(
        initialOf(name),
        style: TextStyle(
          color: AppColors.darkGreen,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.4,
        ),
      ),
    );
    final url = photoUrl;
    if (url == null || url.isEmpty) return placeholder;
    if (kIsWeb) {
      return ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: Image.network(
            signedMediaUrl(url),
            width: size,
            height: size,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : placeholder,
            errorBuilder: (_, __, ___) => placeholder,
          ),
        ),
      );
    }
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: CachedNetworkImage(
          imageUrl: signedMediaUrl(url),
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 120),
          // Decode at about twice the size shown, not at full photo size (P6.5).
          memCacheWidth: (size * 2).round(),
          placeholder: (_, __) => placeholder,
          errorWidget: (_, __, ___) => placeholder,
        ),
      ),
    );
  }
}
