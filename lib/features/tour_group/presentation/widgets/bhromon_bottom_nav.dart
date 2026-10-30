import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../tour_routes.dart';

/// The persistent 5 navigation destinations used across the entire application:
/// 0: Tours (Hub)
/// 1: Moments (Instafeed)
/// 2: Channels (Tour group chat / channels)
/// 3: Games (Game Zone)
/// 4: Profile (Explorer profile)
class BhromonBottomNav extends StatelessWidget {
  final int selectedIndex;

  /// The tour the current screen belongs to. The tour tabs open it. Null when
  /// the screen has no tour, and then the hub picks one.
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

    final openTourId = (tourId != null && tourId.isNotEmpty) ? tourId : null;

    switch (index) {
      case 0:
        context.go(tourHubPath(openTourId));
        break;
      case 1:
        _openTourTab(
          context,
          openTourId,
          'feed',
          missingTourMessage:
              'মোমেন্টস দেখতে অনুগ্রহ করে একটি ট্যুর গ্রুপ নির্বাচন বা তৈরি করুন।',
        );
        break;
      case 2:
        _openTourTab(
          context,
          openTourId,
          'channels',
          missingTourMessage:
              'চ্যানেল খুলতে অনুগ্রহ করে একটি ট্যুর গ্রুপ নির্বাচন বা তৈরি করুন।',
        );
        break;
      case 3:
        context.push(openTourId != null
            ? '/game-zone?tourId=${Uri.encodeQueryComponent(openTourId)}'
            : '/game-zone');
        break;
      case 4:
        final uid = FirebaseAuth.instance.currentUser?.uid;
        final targetUid =
            (uid != null && uid.isNotEmpty) ? uid : 'explorer_user';
        context.push(openTourId != null
            ? '/profile/$targetUid?tourId=${Uri.encodeQueryComponent(openTourId)}'
            : '/profile/$targetUid');
        break;
    }
  }

  /// Opens [tab] of [tourId]. With no tour there is nothing to open, so the
  /// hub takes over and says a tour has to be chosen first.
  static void _openTourTab(
    BuildContext context,
    String? tourId,
    String tab, {
    required String missingTourMessage,
  }) {
    if (tourId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(missingTourMessage),
          backgroundColor: AppColors.midGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go('/group-hub');
      return;
    }
    final path = '/group/$tourId/$tab';
    if (context.canPop()) {
      context.pushReplacement(path);
    } else {
      context.push(path);
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
