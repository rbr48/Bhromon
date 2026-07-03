import 'package:flutter/material.dart';

/// Semantic color tokens resolved from the active theme.
///
/// Screens must not hardcode surface hex values — use these getters so both
/// themes (and future rebrands) work from a single source. In dark mode the
/// values match the original hand-picked panel colors exactly.
extension AppThemeContextX on BuildContext {
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  /// Near-black panel used for cards, tiles and sheets placed on the scaffold.
  Color get surfacePanel =>
      isDarkMode ? const Color(0xFF111111) : Colors.white;

  /// Slightly elevated surface (dialogs, popovers, chips on panels).
  Color get surfaceElevated =>
      isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF1F4F2);

  /// The scaffold background.
  Color get surfaceBg => Theme.of(this).scaffoldBackgroundColor;

  /// Hairline border used on panels.
  Color get borderFaint =>
      (isDarkMode ? Colors.white : Colors.black).withValues(alpha: 0.08);

  /// Primary text on surfaces.
  Color get textPrimary => cs.onSurface;

  /// Secondary/muted text on surfaces.
  Color get textMuted => cs.onSurfaceVariant;
}
