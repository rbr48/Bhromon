import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';

/// The bar a family uses during a trip. Every tour screen sits under one of its
/// five tabs. The bar is set on each route's own page rather than in a
/// ShellRoute, because a ShellRoute leaves the first screen it shows without a
/// back button. Tabs use pushReplacement, so the group hub stays underneath.
///
/// Below [railBreakpoint] the tabs sit in a bottom bar. From it they move to a
/// side rail, and the tour content is capped at [contentMaxWidth] so a wide
/// web or tablet window does not stretch a page across the screen.
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
    final tabs = _tabs(context.l10n);
    final index = tripTabFor(location);

    void select(int i) {
      if (i == index) return;
      context.pushReplacement(tripTabPaths(tourId)[i]);
    }

    if (MediaQuery.sizeOf(context).width < railBreakpoint) {
      return Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: select,
          destinations: [
            for (final tab in tabs)
              NavigationDestination(
                icon: Icon(tab.icon, color: tab.color),
                selectedIcon: Icon(tab.selectedIcon, color: tab.color),
                label: tab.label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: select,
            destinations: [
              for (final tab in tabs)
                NavigationRailDestination(
                  icon: Icon(tab.icon, color: tab.color),
                  selectedIcon: Icon(tab.selectedIcon, color: tab.color),
                  label: Text(tab.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: contentMaxWidth),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The five tabs in [tripTabFor] order. Both the bar and the rail read them.
  static List<_TripTab> _tabs(AppLocalizations l10n) => [
        _TripTab(
          l10n.translate('shell_feed'),
          Icons.photo_library_outlined,
          Icons.photo_library,
        ),
        _TripTab(
          l10n.translate('shell_chat'),
          Icons.forum_outlined,
          Icons.forum,
        ),
        _TripTab(
          l10n.translate('shell_plan'),
          Icons.event_note_outlined,
          Icons.event_note,
        ),
        _TripTab(
          l10n.translate('shell_money'),
          Icons.account_balance_wallet_outlined,
          Icons.account_balance_wallet,
        ),
        _TripTab(
          l10n.translate('shell_safety'),
          Icons.shield_outlined,
          Icons.shield,
          color: AppColors.amber,
        ),
      ];
}

/// One tab's label and icons.
class _TripTab {
  const _TripTab(
    this.label,
    this.icon,
    this.selectedIcon, {
    this.color,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Color? color;
}

/// The index of the tab a tour route belongs to:
/// 0 Feed (feed, scrapbook, quiz), 1 Chat (channels), 2 Plan (journey,
/// checklist, notices, logistics, tide), 3 Money (ledger), 4 Safety (safety).
int tripTabFor(String location) {
  final screen = location.split('/').last;
  return switch (screen) {
    'channels' => 1,
    'journey' || 'checklist' || 'notices' || 'logistics' || 'tide' => 2,
    'ledger' => 3,
    'safety' => 4,
    _ => 0,
  };
}

/// The route each tab opens, in the same order as [tripTabFor].
List<String> tripTabPaths(String tourId) => [
      '/group/$tourId/feed',
      '/group/$tourId/channels',
      '/group/$tourId/journey',
      '/group/$tourId/ledger',
      '/group/$tourId/safety',
    ];
