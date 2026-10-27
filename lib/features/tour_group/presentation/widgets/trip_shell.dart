import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';
import 'bhromon_bottom_nav.dart';

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
  });

  /// The width from which the tabs move to a side rail.
  static const double railBreakpoint = 900;

  /// The widest a tour screen's content may grow.
  static const double contentMaxWidth = 960;

  final String tourId;

  /// The current path, used to pick the tab that matches the screen.
  final String location;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    TourGroupRepository.lastActiveTourId = tourId;
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
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !context.canPop()) {
          context.go('/group-hub');
        }
      },
      child: child,
    );

    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.digit1, alt: true): () => select(0),
      const SingleActivator(LogicalKeyboardKey.digit2, alt: true): () => select(1),
      const SingleActivator(LogicalKeyboardKey.digit3, alt: true): () => select(2),
      const SingleActivator(LogicalKeyboardKey.digit4, alt: true): () => select(3),
      const SingleActivator(LogicalKeyboardKey.digit5, alt: true): () => select(4),
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
                NavigationRail(
                  selectedIndex: index,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: select,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: context.l10n.translate('hub_title'),
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/group-hub');
                        }
                      },
                    ),
                  ),
                  destinations: [
                    NavigationRailDestination(
                      icon: const Icon(Icons.hub_outlined, color: AppColors.mintGreen),
                      selectedIcon: const Icon(Icons.hub, color: AppColors.mintGreen),
                      label: Text(context.l10n.translate('hub_nav_tours')),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.photo_library_outlined),
                      selectedIcon: const Icon(Icons.photo_library),
                      label: Text(context.l10n.translate('hub_nav_moments')),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.forum_outlined),
                      selectedIcon: const Icon(Icons.forum),
                      label: Text(context.l10n.translate('hub_nav_channels')),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.sports_esports_outlined),
                      selectedIcon: const Icon(Icons.sports_esports),
                      label: Text(context.l10n.translate('hub_nav_games')),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.person_outline),
                      selectedIcon: const Icon(Icons.person),
                      label: Text(context.l10n.translate('hub_nav_profile')),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
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
