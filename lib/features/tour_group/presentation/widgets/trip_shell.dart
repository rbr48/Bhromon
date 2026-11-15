import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/breakpoints.dart';
import '../../../../core/layout/desktop_shell_scope.dart';
import '../../data/tour_group_repository.dart';
import '../tour_routes.dart';
import 'bhromon_bottom_nav.dart';
import 'command_palette_dialog.dart';
import 'desktop_right_dock.dart';
import 'desktop_tour_sidebar.dart';
import 'tour_membership_guard.dart';

/// The bar a family uses across all tour screens. Every tour screen sits under
/// the unified 5 app navigation destinations (Tours, Channels, Moments, Chat, Profile).
///
/// Below [railBreakpoint] the tabs sit in a persistent bottom bar. From it they move to a
/// side rail on wide screens, and the tour content is capped at [contentMaxWidth].
class TripShell extends StatelessWidget {
  const TripShell({
    super.key,
    required this.tourId,
    required this.location,
    required this.child,
    this.repository,
    this.guardMembership = true,
    this.ownMobileScaffold = false,
    this.hideNavWhileTyping = false,
  });

  /// The width from which the tabs move to a side rail.
  static const double railBreakpoint = kDesktopShellBreakpoint;

  /// The widest a tour screen's content may grow.
  static const double contentMaxWidth = kDesktopContentMaxWidth;

  /// Whether the right dock's groups list is shown beside [location]. The groups page is
  /// that list already.
  static bool dockShowsGroups(String location) => location != '/group-hub';

  /// Whether the right dock's direct messages are shown beside [location]. The chats list
  /// and an open chat are those messages already.
  static bool dockShowsChats(String location) =>
      location != '/chats' && !location.startsWith('/chat/');

  final String tourId;

  /// The current path, used to pick the tab that matches the screen.
  final String location;

  final Widget child;

  /// Lets tests supply a repository that does not touch Firebase. The app
  /// leaves this null and gets a default [TourGroupRepository].
  final TourGroupRepository? repository;

  /// Whether to verify tour membership. False for public or top-level screens.
  final bool guardMembership;

  /// Whether the child screen already provides its own mobile Scaffold and navigation bar.
  /// When true, below [railBreakpoint] the child is rendered as-is without an outer Scaffold.
  final bool ownMobileScaffold;

  /// Whether the tab bar leaves a phone while the keyboard is open. A group chat sets it, so its
  /// text box sits on the keyboard rather than under a bar that the keyboard pushes up. The bar
  /// is back once the keyboard closes. The side rail on wide screens is unchanged.
  final bool hideNavWhileTyping;

  @override
  Widget build(BuildContext context) {
    final index = tripTabFor(location);

    void select(int i) {
      BhromonBottomNav.handleSelect(
        context,
        i,
        tourId: tourId.isNotEmpty ? tourId : null,
        currentIndex: index,
      );
    }

    final Widget guardedChild = (guardMembership && tourId.isNotEmpty)
        ? TourMembershipGuard(
            tourId: tourId,
            repository: repository,
            child: child,
          )
        : child;

    final wrappedChild = PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (tourId.isNotEmpty) {
          context.go(tourHubPath(tourId));
        } else {
          context.go('/group-hub');
        }
      },
      child: guardedChild,
    );

    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.digit1, alt: true): () =>
          select(0),
      const SingleActivator(LogicalKeyboardKey.digit2, alt: true): () =>
          select(1),
      const SingleActivator(LogicalKeyboardKey.digit3, alt: true): () =>
          select(2),
      const SingleActivator(LogicalKeyboardKey.digit4, alt: true): () =>
          select(3),
      const SingleActivator(LogicalKeyboardKey.digit5, alt: true): () =>
          select(4),
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
          CommandPaletteDialog.show(context, tourId),
      const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
          CommandPaletteDialog.show(context, tourId),
    };

    final double screenWidth = MediaQuery.sizeOf(context).width;
    // The dock is shown only where it leaves the page room (kDesktopDockBreakpoint), and
    // never repeats the list the page itself is showing.
    final showGroups = dockShowsGroups(location);
    final showChats = dockShowsChats(location);
    final showDock =
        isDesktopDockWidth(screenWidth) && (showGroups || showChats);
    // With the keyboard open, a screen that asks for it has no bar under it.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final showTabBar = !(hideNavWhileTyping && keyboardOpen);

    // A shell inside a shell (a page pushed over a tool, see ShellPageRoute) draws its
    // page only: the outer shell already carries the sidebar and the dock.
    final nested = DesktopShellScope.isActive(context);
    final Widget scaffold;
    if (nested) {
      scaffold = wrappedChild;
    } else if (screenWidth < railBreakpoint) {
      scaffold = ownMobileScaffold
          ? wrappedChild
          : Scaffold(
              body: wrappedChild,
              bottomNavigationBar: showTabBar
                  ? BhromonBottomNav(
                      selectedIndex: index,
                      tourId: tourId.isNotEmpty ? tourId : null,
                    )
                  : null,
            );
    } else {
      final dockWidth = showDock ? desktopDockWidthFor(screenWidth) : 0.0;
      final contentWidth = desktopContentWidth(
        screenWidth,
        sidebarWidth: DesktopTourSidebar.width,
        dockWidth: dockWidth,
      );
      final media = MediaQuery.of(context);
      scaffold = Scaffold(
        body: Row(
          children: [
            DesktopTourSidebar(
              tourId: tourId,
              currentLocation: location,
              repository: repository ?? TourGroupRepository(),
            ),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: contentWidth,
                  // The page is told its own width, so a screen that chooses a layout by
                  // width chooses the one that fits this column, not the whole window.
                  child: MediaQuery(
                    data: media.copyWith(
                      size: Size(contentWidth, media.size.height),
                    ),
                    child: DesktopShellScope(child: wrappedChild),
                  ),
                ),
              ),
            ),
            if (showDock)
              DesktopRightDock(
                activeTourId: tourId.isNotEmpty ? tourId : null,
                repository: repository ?? TourGroupRepository(),
                width: dockWidth,
                currentLocation: location,
                showGroups: showGroups,
                showChats: showChats,
              ),
          ],
        ),
      );
    }

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        child: scaffold,
      ),
    );
  }
}

/// The index of the tab a tour route belongs to:
/// 0 Tours (hub, journey, checklist, notices, logistics, tide, ledger, safety, etc.)
/// 1 Channels (chat channels)
/// 2 Moments (feed / instafeed)
/// 3 Chat (one-to-one chats)
/// 4 Profile (profile)
int tripTabFor(String location) {
  if (location.contains('/channels')) return 1;
  if (location.contains('/feed')) return 2;
  if (location.contains('/chats') || location.startsWith('/chat/')) return 3;
  if (location.contains('/profile')) return 4;
  return 0;
}

/// The routes corresponding to the five tabs, in the same order as [tripTabFor].
List<String> tripTabPaths(String tourId) => [
      '/group-hub',
      '/group/$tourId/channels',
      '/group/$tourId/feed',
      '/chats',
      '/profile/me',
    ];
