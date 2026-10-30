import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../data/tour_group_repository.dart';
import '../tour_routes.dart';
import 'bhromon_bottom_nav.dart';
import 'command_palette_dialog.dart';
import 'desktop_tour_sidebar.dart';

/// The bar a family uses across all tour screens. Every tour screen sits under
/// the unified 5 app navigation destinations (Tours, Moments, Channels, Games, Profile).
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
  });

  /// The width from which the tabs move to a side rail.
  static const double railBreakpoint = 900;

  /// The widest a tour screen's content may grow.
  static const double contentMaxWidth = 960;

  final String tourId;

  /// The current path, used to pick the tab that matches the screen.
  final String location;

  final Widget child;

  /// Lets tests supply a repository that does not touch Firebase. The app
  /// leaves this null and gets a default [TourGroupRepository].
  final TourGroupRepository? repository;

  @override
  Widget build(BuildContext context) {
    final index = tripTabFor(location);

    void select(int i) {
      BhromonBottomNav.handleSelect(
        context,
        i,
        tourId: tourId,
        currentIndex: index,
      );
    }

    final wrappedChild = PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go(tourHubPath(tourId));
      },
      child: child,
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

    final Widget scaffold = MediaQuery.sizeOf(context).width < railBreakpoint
        ? Scaffold(
            body: wrappedChild,
            bottomNavigationBar: BhromonBottomNav(
              selectedIndex: index,
              tourId: tourId,
            ),
          )
        : Scaffold(
            body: Row(
              children: [
                DesktopTourSidebar(
                  tourId: tourId,
                  currentLocation: location,
                  repository: repository ?? TourGroupRepository(),
                ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: contentMaxWidth),
                      child: wrappedChild,
                    ),
                  ),
                ),
              ],
            ),
          );

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
/// 1 Moments (feed / instafeed)
/// 2 Channels (chat channels)
/// 3 Games (game zone)
/// 4 Profile (profile)
int tripTabFor(String location) {
  if (location.contains('/feed')) return 1;
  if (location.contains('/channels')) return 2;
  if (location.contains('/game-zone')) return 3;
  if (location.contains('/profile')) return 4;
  return 0;
}

/// The routes corresponding to the five tabs, in the same order as [tripTabFor].
List<String> tripTabPaths(String tourId) => [
      '/group-hub',
      '/group/$tourId/feed',
      '/group/$tourId/channels',
      '/game-zone',
      '/profile/me',
    ];
