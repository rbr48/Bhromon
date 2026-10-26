import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';

/// The bottom bar a family uses during a trip. Every tour screen sits under one
/// of its five tabs. The bar is set on each route's own page rather than in a
/// ShellRoute, because a ShellRoute leaves the first screen it shows without a
/// back button. Tabs use pushReplacement, so the group hub stays underneath.
class TripShell extends StatelessWidget {
  const TripShell({
    super.key,
    required this.tourId,
    required this.location,
    required this.child,
  });

  final String tourId;

  /// The current path, used to pick the tab that matches the screen.
  final String location;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tripTabFor(location),
        onDestinationSelected: (index) {
          if (index == tripTabFor(location)) return;
          context.pushReplacement(tripTabPaths(tourId)[index]);
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.photo_library_outlined),
            selectedIcon: const Icon(Icons.photo_library),
            label: l10n.translate('shell_feed'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.forum_outlined),
            selectedIcon: const Icon(Icons.forum),
            label: l10n.translate('shell_chat'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.event_note_outlined),
            selectedIcon: const Icon(Icons.event_note),
            label: l10n.translate('shell_plan'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: const Icon(Icons.account_balance_wallet),
            label: l10n.translate('shell_money'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.shield_outlined, color: AppColors.amber),
            selectedIcon: const Icon(Icons.shield, color: AppColors.amber),
            label: l10n.translate('shell_safety'),
          ),
        ],
      ),
    );
  }
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
