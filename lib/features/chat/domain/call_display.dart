/// Small display rules for the call screens that need no Flutter.
library;

/// The first character of [name] for an avatar placeholder, upper-cased. A
/// whole code point is taken, so an emoji or other character outside the basic
/// plane is never cut in half. An empty name gives '?'.
String callInitial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}

/// [value] kept between [low] and [high]. When the space is smaller than the
/// range allows (a very small window), [low] wins instead of throwing.
double clampWithin(double value, double low, double high) {
  if (high < low) return low;
  return value.clamp(low, high).toDouble();
}
