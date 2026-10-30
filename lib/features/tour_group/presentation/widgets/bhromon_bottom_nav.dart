import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';

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

    // The tour in the route wins. The shared last-active id can be set by a
    // screen that is still underneath, such as the hub, so it is only the
    // fallback for screens that have no tour of their own.
    final effectiveTourId = (tourId != null && tourId.isNotEmpty)
        ? tourId
        : TourGroupRepository.lastActiveTourId;

    switch (index) {
      case 0:
        context.go('/group-hub');
        break;
      case 1:
        if (effectiveTourId != null && effectiveTourId.isNotEmpty) {
          if (context.canPop()) {
            context.pushReplacement('/group/$effectiveTourId/feed');
          } else {
            context.push('/group/$effectiveTourId/feed');
          }
        } else {
          TourGroupRepository().getActiveTourId().then((id) {
            if (!context.mounted) return;
            if (id != null && id.isNotEmpty) {
              if (context.canPop()) {
                context.pushReplacement('/group/$id/feed');
              } else {
                context.push('/group/$id/feed');
              }
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'মোমেন্টস দেখতে অনুগ্রহ করে একটি ট্যুর গ্রুপ নির্বাচন বা তৈরি করুন।'),
                  backgroundColor: AppColors.midGreen,
                  behavior: SnackBarBehavior.floating,
                ),
              );
              context.go('/group-hub');
            }
          });
        }
        break;
      case 2:
        if (effectiveTourId != null && effectiveTourId.isNotEmpty) {
          if (context.canPop()) {
            context.pushReplacement('/group/$effectiveTourId/channels');
          } else {
            context.push('/group/$effectiveTourId/channels');
          }
        } else {
          TourGroupRepository().getActiveTourId().then((id) {
            if (!context.mounted) return;
            if (id != null && id.isNotEmpty) {
              if (context.canPop()) {
                context.pushReplacement('/group/$id/channels');
              } else {
                context.push('/group/$id/channels');
              }
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'চ্যানেল খুলতে অনুগ্রহ করে একটি ট্যুর গ্রুপ নির্বাচন বা তৈরি করুন।'),
                  backgroundColor: AppColors.midGreen,
                  behavior: SnackBarBehavior.floating,
                ),
              );
              context.go('/group-hub');
            }
          });
        }
        break;
      case 3:
        final gameTourId = (tourId != null && tourId.isNotEmpty)
            ? tourId
            : TourGroupRepository.lastActiveTourId;
        context.push(gameTourId != null && gameTourId.isNotEmpty
            ? '/game-zone?tourId=$gameTourId'
            : '/game-zone');
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
    final navBar = NavigationBar(
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

    final width = MediaQuery.sizeOf(context).width;
    if (width <= 800) {
      return navBar;
    }

    return SizedBox(
      height: 80,
      child: ColoredBox(
        color: Theme.of(context).navigationBarTheme.backgroundColor ??
            const Color(0xFF0D1A12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: navBar,
          ),
        ),
      ),
    );
  }
}
