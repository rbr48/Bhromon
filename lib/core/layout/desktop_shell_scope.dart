import 'package:flutter/widgets.dart';

/// Marks the part of the tree that is drawn inside the desktop shell, between the sidebar and
/// the dock.
///
/// Inside it `MediaQuery.sizeOf` gives the page's own width, not the window's, so a screen
/// that picks a layout by width picks the one that fits its column. A widget that must know
/// it is on a desktop window all the same (the phone's tab bar, which must stay hidden) asks
/// [DesktopShellScope.isActive].
class DesktopShellScope extends InheritedWidget {
  const DesktopShellScope({super.key, required super.child});

  /// Whether [context] is inside the desktop shell.
  static bool isActive(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DesktopShellScope>() != null;

  @override
  bool updateShouldNotify(DesktopShellScope oldWidget) => false;
}
