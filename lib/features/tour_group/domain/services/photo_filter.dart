/// Colour look for a Moments photo: a preset plus the manual sliders.
///
/// Pure Dart so it can be unit-tested. The result is a 4x5 colour matrix in the
/// row-major order that `ColorFilter.matrix` expects, with the offsets in the
/// 0..255 range.
library;

const List<double> _identity = [
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0, //
];

/// Per-preset look: a saturation factor, a contrast factor, a small brightness
/// lift and per-channel tints (red, green, blue).
class _PresetLook {
  const _PresetLook({
    this.saturation = 1,
    this.contrast = 1,
    this.brightness = 0,
    this.tint = const (1, 1, 1),
  });

  final double saturation;
  final double contrast;
  final double brightness;
  final (double, double, double) tint;
}

const Map<String, _PresetLook> _presets = {
  'clarendon':
      _PresetLook(contrast: 1.2, saturation: 1.15, tint: (0.95, 1.0, 1.08)),
  'juno': _PresetLook(saturation: 1.3, tint: (1.08, 1.02, 0.92)),
  'valencia':
      _PresetLook(saturation: 1.08, brightness: 0.03, tint: (1.08, 1.0, 0.92)),
  'lark':
      _PresetLook(contrast: 0.95, saturation: 1.15, tint: (0.98, 1.02, 1.06)),
  'sunset': _PresetLook(saturation: 1.2, tint: (1.12, 0.98, 0.85)),
  'moon': _PresetLook(saturation: 0, contrast: 1.1),
  'vintage':
      _PresetLook(saturation: 0.6, contrast: 0.95, tint: (1.06, 1.0, 0.86)),
};

/// Multiplies two 4x5 matrices: the result applies [b] first, then [a].
List<double> _compose(List<double> a, List<double> b) {
  final out = List<double>.filled(20, 0);
  for (var r = 0; r < 4; r++) {
    for (var c = 0; c < 4; c++) {
      var sum = 0.0;
      for (var k = 0; k < 4; k++) {
        sum += a[r * 5 + k] * b[k * 5 + c];
      }
      out[r * 5 + c] = sum;
    }
    var offset = a[r * 5 + 4];
    for (var k = 0; k < 4; k++) {
      offset += a[r * 5 + k] * b[k * 5 + 4];
    }
    out[r * 5 + 4] = offset;
  }
  return out;
}

List<double> _saturationMatrix(double s) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  return [
    lr + (1 - lr) * s, lg - lg * s, lb - lb * s, 0, 0, //
    lr - lr * s, lg + (1 - lg) * s, lb - lb * s, 0, 0, //
    lr - lr * s, lg - lg * s, lb + (1 - lb) * s, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

List<double> _contrastMatrix(double c) {
  final t = 255 * 0.5 * (1 - c);
  return [
    c, 0, 0, 0, t, //
    0, c, 0, 0, t, //
    0, 0, c, 0, t, //
    0, 0, 0, 1, 0, //
  ];
}

List<double> _brightnessMatrix(double b) => [
      1, 0, 0, 0, 255 * b, //
      0, 1, 0, 0, 255 * b, //
      0, 0, 1, 0, 255 * b, //
      0, 0, 0, 1, 0, //
    ];

List<double> _tintMatrix(double r, double g, double b) => [
      r, 0, 0, 0, 0, //
      0, g, 0, 0, 0, //
      0, 0, b, 0, 0, //
      0, 0, 0, 1, 0, //
    ];

/// The colour matrix for [filterId] with the manual sliders applied on top, or
/// `null` when the photo is unchanged (so callers can skip the filter).
///
/// Slider ranges: [brightness] -0.4..0.4, [contrast] 0.5..1.5,
/// [saturation] 0..2, [warmth] -0.4..0.4.
List<double>? photoColorMatrix({
  String filterId = 'normal',
  double brightness = 0,
  double contrast = 1,
  double saturation = 1,
  double warmth = 0,
}) {
  var m = List<double>.of(_identity);
  final preset = _presets[filterId];
  if (preset != null) {
    m = _compose(
        _tintMatrix(preset.tint.$1, preset.tint.$2, preset.tint.$3), m);
    m = _compose(_saturationMatrix(preset.saturation), m);
    m = _compose(_contrastMatrix(preset.contrast), m);
    m = _compose(_brightnessMatrix(preset.brightness), m);
  }
  if (saturation != 1) m = _compose(_saturationMatrix(saturation), m);
  if (contrast != 1) m = _compose(_contrastMatrix(contrast), m);
  if (brightness != 0) m = _compose(_brightnessMatrix(brightness), m);
  if (warmth != 0) {
    m = _compose(_tintMatrix(1 + warmth * 0.35, 1, 1 - warmth * 0.35), m);
  }
  var changed = false;
  for (var i = 0; i < 20; i++) {
    if ((m[i] - _identity[i]).abs() > 1e-9) {
      changed = true;
      break;
    }
  }
  return changed ? m : null;
}
