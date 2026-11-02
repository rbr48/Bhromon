import 'package:flutter/material.dart';

import 'colors.dart';

/// The forest-green colours of the group and profile screens (the group hub,
/// the bottom navigation bar, the profile page and the member profile sheet),
/// for the active theme.
///
/// The dark values are exactly the colours these screens used before they
/// followed the theme, so dark mode looks the same. Use `context.forest`
/// instead of fixed colours. Dark covers, gradients and photos keep their colours
/// in both themes, so text on them stays white.
class ForestPalette {
  const ForestPalette._(this.isDark);

  static const ForestPalette dark = ForestPalette._(true);
  static const ForestPalette light = ForestPalette._(false);

  final bool isDark;

  /// The page behind everything.
  Color get background =>
      isDark ? const Color(0xFF0D1A12) : const Color(0xFFF2F6F3);

  /// Cards and tiles on the page.
  Color get card => isDark ? const Color(0xFF14241B) : Colors.white;

  /// Dialogs and sheets.
  Color get dialog => isDark ? const Color(0xFF1B3326) : Colors.white;

  /// Bottom sheets, such as the member profile sheet.
  Color get sheet => isDark ? const Color(0xFF0F1B24) : Colors.white;

  /// The active group banner's gradient, top-left to bottom-right.
  Color get bannerStart =>
      isDark ? const Color(0xFF1B4332) : const Color(0xFFE4F3EA);

  /// See [bannerStart].
  Color get bannerEnd =>
      isDark ? const Color(0xFF081C15) : const Color(0xFFCDE7D7);

  // The Moments feed uses neutral greys instead of forest green.

  /// The feed page behind the posts.
  Color get feedPage =>
      isDark ? const Color(0xFF0A120D) : const Color(0xFFF2F4F3);

  /// Feed cards, sheets and dialogs.
  Color get feedSurface => isDark ? const Color(0xFF1E1E1E) : Colors.white;

  /// The comments sheet.
  Color get feedSheet => isDark ? const Color(0xFF121212) : Colors.white;

  /// Recessed feed areas.
  Color get feedDeep =>
      isDark ? const Color(0xFF141414) : const Color(0xFFF6F7F7);

  /// Raised chips and tiles on a feed surface.
  Color get feedRaised =>
      isDark ? const Color(0xFF2A2A2A) : const Color(0xFFEDEFEE);

  /// Text fields in the feed.
  Color get feedField =>
      isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF0F2F1);

  /// Story rings and bubbles.
  Color get feedBubble =>
      isDark ? const Color(0xFF242526) : const Color(0xFFF0F2F5);

  /// Placeholders while a photo loads.
  Color get feedPlaceholder =>
      isDark ? const Color(0xFF1B1B1B) : const Color(0xFFE4E7E5);

  /// Circles behind category icons.
  Color get chip => isDark ? const Color(0xFF182630) : const Color(0xFFE6ECE8);

  /// A light inset on a card, at the old black26 strength.
  Color get inset26 => isDark ? Colors.black26 : const Color(0x0D000000);

  /// A light inset on a card, at the old black38 strength.
  Color get inset38 => isDark ? Colors.black38 : const Color(0x14000000);

  /// Mint as a text or icon colour. Mint is too light for text on light
  /// surfaces, so light mode uses a darker green. Buttons keep mint.
  Color get accentText => isDark ? AppColors.mintGreen : AppColors.midGreen;

  /// A per-item colour (amber, cyan, light blue...) used as text or an icon
  /// colour. Dark mode returns it unchanged. Light mode returns a darker shade
  /// of the same hue, dark enough to reach 4.5:1 on a card.
  Color readable(Color color) {
    if (isDark) return color;
    var hsl = HSLColor.fromColor(color.withValues(alpha: 1));
    final cardLuminance = card.computeLuminance();
    double ratio(Color c) =>
        (cardLuminance + 0.05) / (c.computeLuminance() + 0.05);
    while (ratio(hsl.toColor()) < 4.5 && hsl.lightness > 0.05) {
      hsl = hsl.withLightness(hsl.lightness - 0.02);
    }
    return hsl.toColor();
  }

  /// Main text and icons.
  Color get text => isDark ? Colors.white : AppColors.darkText;

  /// Text at the old white70 strength.
  Color get text70 => isDark ? Colors.white70 : const Color(0xFF37444A);

  /// Text at the old white60 strength.
  Color get text60 => isDark ? Colors.white60 : const Color(0xFF4A575D);

  /// Secondary text at the old white54 strength.
  Color get text54 => isDark ? Colors.white54 : AppColors.grayText;

  /// Hints at the old white38 strength.
  Color get text38 => isDark ? Colors.white38 : const Color(0xFF6B787E);

  /// Faint marks at the old white24 strength.
  Color get text24 => isDark ? Colors.white24 : const Color(0x42000000);

  /// Dividers at the old white12 strength.
  Color get divider12 => isDark ? Colors.white12 : const Color(0x1F000000);

  /// Dividers at the old white10 strength.
  Color get divider10 => isDark ? Colors.white10 : const Color(0x14000000);
}

/// `context.forest` is the forest palette for the active theme.
extension ForestPaletteContext on BuildContext {
  ForestPalette get forest => Theme.of(this).brightness == Brightness.dark
      ? ForestPalette.dark
      : ForestPalette.light;
}
