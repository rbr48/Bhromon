import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The forest-green popup colour is for dark mode only. A dropdown that uses it
/// unchanged puts dark item text on dark green in light mode, so every such
/// popup must go through `context.forest.surfaceFor(...)`, which keeps dark
/// mode as it was and gives light mode a pale tint.
void main() {
  test('forest-green dropdown menus follow the active theme', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('dropdownColor:')) continue;
        // The value can wrap onto the next line, so read both.
        final statement =
            i + 1 < lines.length ? '${lines[i]} ${lines[i + 1]}' : lines[i];
        final fixedGreen = statement.contains('0xFF1B4332') ||
            statement.contains('_menuColor');
        if (fixedGreen && !statement.contains('surfaceFor(')) {
          offenders.add('${file.path}:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Wrap the forest green in context.forest.surfaceFor(...) '
          'so light mode stays readable.',
    );
  });
}
