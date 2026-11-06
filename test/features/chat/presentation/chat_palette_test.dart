import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/chat/presentation/chat_palette.dart';

/// WCAG contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// [fg] drawn over [bg], for translucent foregrounds.
Color over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

void main() {
  group('dark palette keeps the original chat colours', () {
    const d = ChatPalette.dark;
    test('surfaces', () {
      expect(d.wallpaper, const Color(0xFF0D1A12));
      expect(d.bar, const Color(0xFF14241B));
      expect(d.panel, const Color(0xFF1B2E23));
      expect(d.field, const Color(0xFF233D2F));
      expect(d.recessed, const Color(0xFF16241C));
      expect(d.recessedDeep, const Color(0xFF121E17));
      expect(d.outgoing, const Color(0xFF1B4332));
      expect(d.outgoingRecessed, const Color(0xFF143325));
      expect(d.grey, const Color(0xFF8696A0));
      expect(d.wallpaperDoodle, Colors.white.withValues(alpha: 0.015));
    });
    test('text', () {
      expect(d.text, Colors.white);
      expect(d.text70, Colors.white70);
      expect(d.text60, Colors.white60);
      expect(d.text54, Colors.white54);
      expect(d.text38, Colors.white38);
      expect(d.text30, Colors.white30);
      expect(d.text24, Colors.white24);
      expect(d.divider12, Colors.white12);
      expect(d.divider10, Colors.white10);
    });
  });

  group('light palette is readable', () {
    const l = ChatPalette.light;
    final surfaces = {
      'wallpaper': l.wallpaper,
      'bar': l.bar,
      'panel': l.panel,
      'field': l.field,
      'recessed': l.recessed,
      'recessedDeep': l.recessedDeep,
      'outgoing': l.outgoing,
      'outgoingRecessed': l.outgoingRecessed,
    };
    for (final entry in surfaces.entries) {
      test('main text on ${entry.key} meets 4.5:1', () {
        expect(contrast(l.text, entry.value), greaterThanOrEqualTo(4.5));
        expect(contrast(l.text70, entry.value), greaterThanOrEqualTo(4.5));
      });
      test('secondary text on ${entry.key} meets 3:1', () {
        for (final c in [l.text60, l.text54, l.grey]) {
          expect(contrast(over(c, entry.value), entry.value),
              greaterThanOrEqualTo(3.0));
        }
      });
    }
    test('hints on input surfaces meet 3:1', () {
      for (final bg in [l.panel, l.bar]) {
        expect(contrast(over(l.text38, bg), bg), greaterThanOrEqualTo(3.0));
      }
    });
    test('surfaces differ from the wallpaper and bubbles from each other', () {
      expect(l.panel, isNot(l.wallpaper));
      expect(l.outgoing, isNot(l.panel));
      expect(l.recessedDeep, isNot(l.panel));
      expect(l.outgoingRecessed, isNot(l.outgoing));
    });
  });
}
