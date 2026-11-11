import 'package:bhromon/core/media/media_access.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/tour_group.dart';
import '../tour_routes.dart';
import 'command_palette_dialog.dart';

class DesktopTourSidebar extends StatelessWidget {
  final String tourId;
  final String currentLocation;
  final TourGroupRepository repository;

  const DesktopTourSidebar({
    super.key,
    required this.tourId,
    required this.currentLocation,
    required this.repository,
  });

  bool _isActive(String path) {
    if (path == '/group-hub') {
      return currentLocation == '/group-hub';
    }
    return currentLocation.startsWith(path);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: context.forest.surfaceFor(const Color(0xFF141414)),
        border: Border(right: BorderSide(color: context.forest.divider10)),
      ),
      child: StreamBuilder<TourGroup?>(
        stream: repository.watchGroup(tourId),
        builder: (context, snapshot) {
          final group = snapshot.data;
          final l10n = context.l10n;
          final tourTitle = group?.name ??
              (tourId.isEmpty
                  ? l10n.translate('desktop_sidebar_universal_engine')
                  : l10n.translate('desktop_sidebar_group'));
          final origin = group?.originCity ?? '';
          final destination = group?.destination ?? '';
          final routeSubtitle = (origin.isNotEmpty && destination.isNotEmpty)
              ? '$origin ➔ $destination'
              : (group != null
                  ? group.kind.name
                  : (tourId.isEmpty
                      ? l10n.translate('desktop_sidebar_select_group')
                      : l10n.translate('desktop_sidebar_loading')));

          return Column(
            children: [
              // Header with logo and tour identity
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: context.forest.divider10)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: Image.asset(
                            'assets/bhromon_emblem.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.explore_rounded,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bhromon',
                                style: TextStyle(
                                  color: context.forest.accentText,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                l10n.translate('login_tagline'),
                                style: TextStyle(
                                    color: context.forest.text54, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tourTitle,
                      style: TextStyle(
                        color: context.forest.text,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.route_rounded,
                            size: 13, color: context.forest.accentText),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            routeSubtitle,
                            style: TextStyle(
                              color: context.forest.text70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Command Palette Trigger Button
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: InkWell(
                  onTap: () => CommandPaletteDialog.show(context, tourId),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: context.forest.text.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.forest.divider12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded,
                            size: 16, color: context.forest.accentText),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.translate('desktop_sidebar_search'),
                            style: TextStyle(
                                color: context.forest.text70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: const Text(
                            'Ctrl+K',
                            style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Scrollable Navigation List
              Expanded(
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  children: [
                    _buildSectionHeader(context,
                        l10n.translate('desktop_sidebar_core_modules')),
                    _buildNavItem(
                      context,
                      title: l10n.translate('desktop_sidebar_group_hub'),
                      icon: Icons.dashboard_outlined,
                      activeIcon: Icons.dashboard_rounded,
                      route: tourHubPath(tourId),
                      isActive: _isActive('/group-hub'),
                    ),
                    _buildNavItem(
                      context,
                      title: l10n.translate('desktop_sidebar_journey'),
                      icon: Icons.calendar_month_outlined,
                      activeIcon: Icons.calendar_month_rounded,
                      route: '/group/$tourId/journey',
                      isActive: _isActive('/group/$tourId/journey'),
                    ),
                    _buildNavItem(
                      context,
                      title: l10n.translate('desktop_sidebar_feed'),
                      icon: Icons.photo_library_outlined,
                      activeIcon: Icons.photo_library_rounded,
                      route: '/group/$tourId/feed',
                      isActive: _isActive('/group/$tourId/feed'),
                    ),
                    _buildNavItem(
                      context,
                      title: l10n.translate('desktop_sidebar_channels'),
                      icon: Icons.forum_outlined,
                      activeIcon: Icons.forum_rounded,
                      route: '/group/$tourId/channels',
                      isActive: _isActive('/group/$tourId/channels'),
                    ),
                    _buildNavItem(
                      context,
                      title: l10n.translate('desktop_sidebar_game_zone'),
                      icon: Icons.sports_esports_outlined,
                      activeIcon: Icons.sports_esports_rounded,
                      route: '/game-zone',
                      isActive: _isActive('/game-zone'),
                    ),
                    _buildNavItem(
                      context,
                      title: l10n.translate('desktop_sidebar_ledger'),
                      icon: Icons.account_balance_wallet_outlined,
                      activeIcon: Icons.account_balance_wallet_rounded,
                      route: '/group/$tourId/ledger',
                      isActive: _isActive('/group/$tourId/ledger'),
                    ),
                    _buildNavItem(
                      context,
                      title: l10n.translate('desktop_sidebar_logistics'),
                      icon: Icons.airline_seat_recline_extra_outlined,
                      activeIcon: Icons.airline_seat_recline_extra_rounded,
                      route: '/group/$tourId/logistics',
                      isActive: _isActive('/group/$tourId/logistics'),
                    ),
                    _buildNavItem(
                      context,
                      title: l10n.translate('desktop_sidebar_notices'),
                      icon: Icons.campaign_outlined,
                      activeIcon: Icons.campaign_rounded,
                      route: '/group/$tourId/notices',
                      isActive: _isActive('/group/$tourId/notices'),
                    ),
                    _buildNavItem(
                      context,
                      title: l10n.translate('desktop_sidebar_checklist'),
                      icon: Icons.checklist_outlined,
                      activeIcon: Icons.checklist_rounded,
                      route: '/group/$tourId/checklist',
                      isActive: _isActive('/group/$tourId/checklist'),
                    ),
                    const SizedBox(height: 12),
                    _buildSectionHeader(
                        context, l10n.translate('desktop_sidebar_superpowers')),
                    // The Safety hub is the SOS feature: only the groups that have SOS show it.
                    if (group != null && group.supportsSafetyAlerts)
                      _buildToolItem(
                        context,
                        title: l10n.translate('desktop_sidebar_safety'),
                        badge: 'GPS',
                        icon: Icons.fmd_good_rounded,
                        route: '/group/$tourId/safety',
                        badgeColor: Colors.redAccent,
                        isActive: _isActive('/group/$tourId/safety'),
                      ),
                    _buildToolItem(
                      context,
                      title: l10n.translate('desktop_sidebar_tide'),
                      badge: l10n.translate('desktop_sidebar_badge_beach'),
                      icon: Icons.tsunami_rounded,
                      route: '/group/$tourId/tide',
                      badgeColor: Colors.cyanAccent,
                      isActive: _isActive('/group/$tourId/tide'),
                    ),
                    _buildToolItem(
                      context,
                      title: l10n.translate('desktop_sidebar_scrapbook'),
                      badge: 'PDF',
                      icon: Icons.menu_book_rounded,
                      route: '/group/$tourId/scrapbook',
                      badgeColor: Colors.amberAccent,
                      isActive: _isActive('/group/$tourId/scrapbook'),
                    ),
                    _buildToolItem(
                      context,
                      title: l10n.translate('desktop_sidebar_quiz'),
                      badge: l10n.translate('desktop_sidebar_badge_quiz'),
                      icon: Icons.quiz_rounded,
                      route: '/group/$tourId/quiz',
                      badgeColor: Colors.greenAccent,
                      isActive: _isActive('/group/$tourId/quiz'),
                    ),
                  ],
                ),
              ),

              // Footer: User profile and Firebase live sync status
              _buildFooter(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: context.forest.text38,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required String title,
    required IconData icon,
    required IconData activeIcon,
    required String route,
    required bool isActive,
  }) {
    return InkWell(
      onTap: () {
        if (route.contains('/group//')) {
          context.go('/group-hub');
          return;
        }
        context.go(route);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7.5),
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.4),
                  width: 0.8)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              isActive ? activeIcon : icon,
              size: 18,
              color:
                  isActive ? context.forest.accentText : context.forest.text70,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isActive
                      ? context.forest.accentText
                      : context.forest.text,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolItem(
    BuildContext context, {
    required String title,
    required String badge,
    required IconData icon,
    required String route,
    required Color badgeColor,
    required bool isActive,
  }) {
    return InkWell(
      onTap: () {
        if (route.contains('/group//')) {
          context.go('/group-hub');
          return;
        }
        context.go(route);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.4),
                  width: 0.8)
              : null,
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: isActive
                    ? context.forest.accentText
                    : context.forest.text70),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isActive
                      ? context.forest.accentText
                      : context.forest.text70,
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: badgeColor.withValues(alpha: 0.4), width: 0.6),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    String displayName = context.l10n.translate('desktop_sidebar_explorer');
    String email = '';
    String? photoUrl;
    try {
      final name = repository.currentDisplayName;
      if (name.isNotEmpty && name != 'Explorer') {
        displayName = name;
      }
      email = repository.currentEmail;
      photoUrl = repository.currentPhotoUrl;
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.forest.surfaceFor(const Color(0xFF101010)),
        border: Border(top: BorderSide(color: context.forest.divider10)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.midGreen,
                backgroundImage: photoUrl != null
                    ? NetworkImage(signedMediaUrl(photoUrl))
                    : null,
                child: photoUrl == null
                    ? Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                        color: context.forest.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      email,
                      style:
                          TextStyle(color: context.forest.text38, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.settings_outlined,
                    size: 16, color: context.forest.text54),
                tooltip:
                    context.l10n.translate('desktop_sidebar_profile_settings'),
                onPressed: () {
                  final uid = repository.currentUid.isNotEmpty
                      ? repository.currentUid
                      : 'me';
                  context.push('/profile/$uid');
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Google Play Download Link
          InkWell(
            onTap: () async {
              final uri = Uri.parse(
                  'https://play.google.com/store/apps/details?id=com.bhromon.app&pli=1');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.mintGreen.withValues(alpha: 0.35),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.play_arrow_rounded,
                    color: AppColors.mintGreen,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.locale.languageCode == 'bn'
                              ? 'গেট ইট অন'
                              : 'GET IT ON',
                          style: TextStyle(
                            color: context.forest.text38,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'Google Play',
                          style: TextStyle(
                            color: context.forest.text,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.open_in_new_rounded,
                    color: context.forest.text54,
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
