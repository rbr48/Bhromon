import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';

/// The persistent 5 navigation destinations used across the entire application:
/// 0: Tours (Hub)
/// 1: Moments (Instafeed)
/// 2: Channels (Tour group chat / channels)
/// 3: Games (Game Zone)
/// 4: Profile (Explorer profile)
class BhromonBottomNav extends StatelessWidget {
  final int selectedIndex;
  final String? tourId;

  const BhromonBottomNav({
    super.key,
    required this.selectedIndex,
    this.tourId,
  });

  static List<NavigationDestination> destinations(BuildContext context) {
    return [
      NavigationDestination(
        icon: const Icon(Icons.hub_outlined, color: AppColors.mintGreen),
        selectedIcon: const Icon(Icons.hub, color: AppColors.mintGreen),
        label: context.l10n.translate('hub_nav_tours'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.photo_library_outlined),
        selectedIcon: const Icon(Icons.photo_library),
        label: context.l10n.translate('hub_nav_moments'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.forum_outlined),
        selectedIcon: const Icon(Icons.forum),
        label: context.l10n.translate('hub_nav_channels'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.sports_esports_outlined),
        selectedIcon: const Icon(Icons.sports_esports),
        label: context.l10n.translate('hub_nav_games'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.person_outline),
        selectedIcon: const Icon(Icons.person),
        label: context.l10n.translate('hub_nav_profile'),
      ),
    ];
  }

  static void handleSelect(
    BuildContext context,
    int index, {
    String? tourId,
    int? currentIndex,
  }) {
    if (currentIndex != null && index == currentIndex) return;
    switch (index) {
      case 0:
        context.go('/group-hub');
        break;
      case 1:
        if (tourId != null && tourId.isNotEmpty) {
          context.pushReplacement('/group/$tourId/feed');
        } else {
          context.go('/group-hub');
        }
        break;
      case 2:
        if (tourId != null && tourId.isNotEmpty) {
          context.pushReplacement('/group/$tourId/channels');
        } else {
          context.push('/chats');
        }
        break;
      case 3:
        context.push('/game-zone');
        break;
      case 4:
        final uid = FirebaseAuth.instance.currentUser?.uid;
        final targetUid =
            (uid != null && uid.isNotEmpty) ? uid : 'explorer_user';
        context.push('/profile/$targetUid');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex.clamp(0, 4),
      maintainBottomViewPadding: true,
      onDestinationSelected: (index) => handleSelect(
        context,
        index,
        tourId: tourId,
        currentIndex: selectedIndex,
      ),
      destinations: destinations(context),
    );
  }
}
