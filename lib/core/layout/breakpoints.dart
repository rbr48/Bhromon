// The window widths at which the desktop layout changes. One place, so the shell, the tab
// bar and the screens agree on what "desktop" means.

/// From this width the app shows the left sidebar instead of the phone's tab bar.
const double kDesktopShellBreakpoint = 900;

/// From this width the right dock (groups and direct messages) is shown too. Below it the
/// dock would leave the page about half the window, so the page takes the space.
const double kDesktopDockBreakpoint = 1280;

/// The widest a page's content grows inside the desktop shell.
const double kDesktopContentMaxWidth = 960;

/// Whether a window this wide uses the desktop shell.
bool isDesktopShellWidth(double width) => width >= kDesktopShellBreakpoint;

/// Whether a window this wide has room for the right dock.
bool isDesktopDockWidth(double width) => width >= kDesktopDockBreakpoint;

/// The right dock's width in a window this wide.
double desktopDockWidthFor(double width) => width >= 1440 ? 320 : 280;

/// The width left for the page inside the desktop shell: the window less the sidebar and,
/// where it is shown, the dock, and no more than [kDesktopContentMaxWidth].
double desktopContentWidth(
  double windowWidth, {
  required double sidebarWidth,
  required double dockWidth,
}) {
  final free = windowWidth - sidebarWidth - dockWidth;
  if (free <= 0) return 0;
  return free > kDesktopContentMaxWidth ? kDesktopContentMaxWidth : free;
}
