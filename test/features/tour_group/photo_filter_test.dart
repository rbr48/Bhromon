import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/tour_group/domain/services/photo_filter.dart';

void main() {
  test('an untouched photo needs no filter', () {
    expect(photoColorMatrix(), isNull);
    expect(photoColorMatrix(filterId: 'normal'), isNull);
  });

  test('every preset changes the photo', () {
    for (final id in [
      'clarendon',
      'juno',
      'valencia',
      'lark',
      'sunset',
      'moon',
      'vintage',
    ]) {
      expect(photoColorMatrix(filterId: id), isNotNull, reason: id);
    }
  });

  test('an unknown preset id leaves the photo alone', () {
    expect(photoColorMatrix(filterId: 'nope'), isNull);
  });

  test('moon makes the photo grey', () {
    final m = photoColorMatrix(filterId: 'moon')!;
    // A grey pixel stays grey: each output channel reads the same mix of input.
    for (var r = 0; r < 3; r++) {
      final sum = m[r * 5] + m[r * 5 + 1] + m[r * 5 + 2];
      expect(sum, closeTo(m[0] + m[1] + m[2], 1e-9));
    }
    expect(m[0], closeTo(m[5], 1e-9));
  });

  test('brightness slider shifts the offsets by the slider times 255', () {
    final m = photoColorMatrix(brightness: 0.2)!;
    expect(m[4], closeTo(51, 1e-9));
    expect(m[9], closeTo(51, 1e-9));
    expect(m[14], closeTo(51, 1e-9));
    expect(m[0], closeTo(1, 1e-9));
  });

  test('contrast slider scales and centres on mid grey', () {
    final m = photoColorMatrix(contrast: 1.5)!;
    expect(m[0], closeTo(1.5, 1e-9));
    // Mid grey (127.5) maps to itself: 1.5 * 127.5 + offset == 127.5.
    expect(1.5 * 127.5 + m[4], closeTo(127.5, 1e-6));
  });

  test('warmth warms the red channel and cools the blue one', () {
    final m = photoColorMatrix(warmth: 0.4)!;
    expect(m[0], greaterThan(1));
    expect(m[12], lessThan(1));
  });

  test('sliders stack on top of the preset', () {
    final preset = photoColorMatrix(filterId: 'juno')!;
    final both = photoColorMatrix(filterId: 'juno', brightness: 0.1)!;
    expect(both[0], closeTo(preset[0], 1e-9));
    expect(both[4], isNot(closeTo(preset[4], 1e-6)));
  });
}
