import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/profile_palette.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
}

void main() {
  test('dark palette keeps the original profile colours', () {
    const d = ProfilePalette.dark;
    expect(d.background, const Color(0xFF0D1A12));
    expect(d.card, const Color(0xFF14241B));
    expect(d.dialog, const Color(0xFF1B3326));
    expect(d.sheet, const Color(0xFF0F1B24));
    expect(d.chip, const Color(0xFF182630));
    expect(d.inset26, Colors.black26);
    expect(d.inset38, Colors.black38);
    expect(d.accentText, AppColors.mintGreen);
    expect(d.text, Colors.white);
    expect(d.text70, Colors.white70);
    expect(d.text60, Colors.white60);
    expect(d.text54, Colors.white54);
    expect(d.text38, Colors.white38);
    expect(d.text24, Colors.white24);
    expect(d.divider12, Colors.white12);
    expect(d.divider10, Colors.white10);
  });

  group('light palette is readable', () {
    const l = ProfilePalette.light;
    final surfaces = {
      'background': l.background,
      'card': l.card,
      'dialog': l.dialog,
      'sheet': l.sheet,
      'chip': l.chip,
      'inset26 on card': Color.alphaBlend(l.inset26, l.card),
      'inset38 on card': Color.alphaBlend(l.inset38, l.card),
    };
    for (final e in surfaces.entries) {
      test('text on ${e.key}', () {
        expect(contrast(l.text, e.value), greaterThanOrEqualTo(4.5));
        expect(contrast(l.text70, e.value), greaterThanOrEqualTo(4.5));
        expect(contrast(l.accentText, e.value), greaterThanOrEqualTo(4.5));
        for (final c in [l.text60, l.text54]) {
          expect(contrast(c, e.value), greaterThanOrEqualTo(3.0));
        }
      });
    }
    test('hints on cards and sheets meet 3:1', () {
      expect(contrast(l.text38, l.card), greaterThanOrEqualTo(3.0));
    });
    test('per-item accents become readable on cards and sheets', () {
      const accents = [
        AppColors.gold,
        AppColors.mintGreen,
        Colors.amber,
        Colors.amberAccent,
        Colors.cyanAccent,
        Colors.lightBlueAccent,
        Colors.orangeAccent,
        Colors.deepOrangeAccent,
        Colors.pinkAccent,
        Colors.purpleAccent,
        Colors.blueAccent,
        Colors.redAccent,
      ];
      for (final accent in accents) {
        final shade = l.readable(accent);
        expect(contrast(shade, l.card), greaterThanOrEqualTo(4.5),
            reason: '$accent -> $shade');
        expect(HSLColor.fromColor(shade).hue,
            closeTo(HSLColor.fromColor(accent).hue, 1),
            reason: 'keeps the hue of $accent');
      }
    });

    test('dark mode leaves per-item accents unchanged', () {
      expect(
          ProfilePalette.dark.readable(Colors.amberAccent), Colors.amberAccent);
    });

    test('cards stand apart from the page', () {
      expect(l.card, isNot(l.background));
    });
  });
}
