import 'dart:math' as math;
import 'dart:ui';

import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:flutter_test/flutter_test.dart';

// WCAG 2.x contrast ratio between two opaque colours. Text needs 4.5:1 (section 9.5, P6.3).
double _luminance(Color color) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  final r = channel(color.r);
  final g = channel(color.g);
  final b = channel(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // Each pair is text drawn on a surface on the groups screens. The palette lives in
  // forest_palette.dart; these are the surfaces the new widgets use.
  for (final entry
      in {'dark': ForestPalette.dark, 'light': ForestPalette.light}.entries) {
    final palette = entry.value;
    test(
        '${entry.key}: primary and accent text reach 4.5:1 on the card and the page',
        () {
      for (final surface in [palette.card, palette.background]) {
        expect(_contrast(palette.text, surface), greaterThanOrEqualTo(4.5));
        expect(_contrast(palette.text70, surface), greaterThanOrEqualTo(4.5));
        expect(
            _contrast(palette.accentText, surface), greaterThanOrEqualTo(4.5));
      }
    });

    test(
        '${entry.key}: secondary text used for subtitles reaches 4.5:1 on the card',
        () {
      expect(_contrast(palette.text54, palette.card), greaterThanOrEqualTo(4.5),
          reason: 'subtitles, kind labels and the SOS line use text54');
    });
  }

  test(
      'dark green text on mint, used for initials and the selected chip, reaches 4.5:1',
      () {
    expect(_contrast(AppColors.darkGreen, AppColors.mintGreen),
        greaterThanOrEqualTo(4.5));
  });
}
