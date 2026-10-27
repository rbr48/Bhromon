import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/tour_group.dart';
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
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        border: Border(right: BorderSide(color: Colors.white10)),
      ),
      child: StreamBuilder<TourGroup?>(
        stream: repository.watchGroup(tourId),
        builder: (context, snapshot) {
          final group = snapshot.data;
          final tourTitle = group?.name ?? 'ট্যুর গ্রুপ';
          final origin = group?.originCity ?? 'ঢাকা';
          final destination = group?.destination ?? 'কক্সবাজার';
          final routeSubtitle = '$origin ➔ $destination';

          return Column(
            children: [
              // Header with logo and tour identity
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white10)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00BFA5), Color(0xFF1B4332)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color:
                                    AppColors.mintGreen.withValues(alpha: 0.5)),
                          ),
                          child: const Center(
                            child: Icon(Icons.explore_rounded,
                                color: Colors.white, size: 20),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bhromon OS',
                                style: TextStyle(
                                  color: AppColors.mintGreen,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                'Universal Tour Engine',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tourTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.route_rounded,
                            size: 13, color: AppColors.mintGreen),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            routeSubtitle,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11.5,
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
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.terminal_rounded,
                            size: 15, color: AppColors.mintGreen),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '>_ কমান্ড প্যালেট',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11.5,
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
                                fontSize: 9.5,
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
                    _buildSectionHeader('প্রধান মডিউলসমূহ'),
                    _buildNavItem(
                      context,
                      title: 'ড্যাশবোর্ড',
                      icon: Icons.dashboard_outlined,
                      activeIcon: Icons.dashboard_rounded,
                      route: '/group-hub',
                      isActive: _isActive('/group-hub'),
                    ),
                    _buildNavItem(
                      context,
                      title: 'ভ্রমণ সূচি ও ট্র্যাকার',
                      icon: Icons.calendar_month_outlined,
                      activeIcon: Icons.calendar_month_rounded,
                      route: '/group/$tourId/journey',
                      isActive: _isActive('/group/$tourId/journey'),
                    ),
                    _buildNavItem(
                      context,
                      title: 'ইন্সটাফিড ও রিলস',
                      icon: Icons.photo_library_outlined,
                      activeIcon: Icons.photo_library_rounded,
                      route: '/group/$tourId/feed',
                      isActive: _isActive('/group/$tourId/feed'),
                    ),
                    _buildNavItem(
                      context,
                      title: 'ডিসকর্ড চ্যাট ও ভয়েস',
                      icon: Icons.forum_outlined,
                      activeIcon: Icons.forum_rounded,
                      route: '/group/$tourId/channels',
                      isActive: _isActive('/group/$tourId/channels'),
                    ),
                    _buildNavItem(
                      context,
                      title: 'গেমিং জোন',
                      icon: Icons.sports_esports_outlined,
                      activeIcon: Icons.sports_esports_rounded,
                      route: '/game-zone',
                      isActive: _isActive('/game-zone'),
                    ),
                    _buildNavItem(
                      context,
                      title: 'হিসাব ও স্প্লিট',
                      icon: Icons.account_balance_wallet_outlined,
                      activeIcon: Icons.account_balance_wallet_rounded,
                      route: '/group/$tourId/ledger',
                      isActive: _isActive('/group/$tourId/ledger'),
                    ),
                    _buildNavItem(
                      context,
                      title: 'সিট ও রুম প্ল্যান',
                      icon: Icons.airline_seat_recline_extra_outlined,
                      activeIcon: Icons.airline_seat_recline_extra_rounded,
                      route: '/group/$tourId/logistics',
                      isActive: _isActive('/group/$tourId/logistics'),
                    ),
                    _buildNavItem(
                      context,
                      title: 'নোটিশ ও মিটিং',
                      icon: Icons.campaign_outlined,
                      activeIcon: Icons.campaign_rounded,
                      route: '/group/$tourId/notices',
                      isActive: _isActive('/group/$tourId/notices'),
                    ),
                    _buildNavItem(
                      context,
                      title: 'চেকলিস্ট',
                      icon: Icons.checklist_outlined,
                      activeIcon: Icons.checklist_rounded,
                      route: '/group/$tourId/checklist',
                      isActive: _isActive('/group/$tourId/checklist'),
                    ),
                    const SizedBox(height: 12),
                    _buildSectionHeader('ট্যুর সুপারপাওয়ার ও বিশেষ টুলস'),
                    _buildToolItem(
                      context,
                      title: 'সুরক্ষা ও বিচ কম্পাস',
                      badge: 'GPS',
                      icon: Icons.fmd_good_rounded,
                      route: '/group/$tourId/safety',
                      badgeColor: Colors.redAccent,
                      isActive: _isActive('/group/$tourId/safety'),
                    ),
                    _buildToolItem(
                      context,
                      title: 'সৈকত ও খাবার গাইড',
                      badge: 'সৈকত',
                      icon: Icons.tsunami_rounded,
                      route: '/group/$tourId/tide',
                      badgeColor: Colors.cyanAccent,
                      isActive: _isActive('/group/$tourId/tide'),
                    ),
                    _buildToolItem(
                      context,
                      title: 'ডিজিটাল স্ক্র্যাপবুক',
                      badge: 'PDF',
                      icon: Icons.menu_book_rounded,
                      route: '/group/$tourId/scrapbook',
                      badgeColor: Colors.amberAccent,
                      isActive: _isActive('/group/$tourId/scrapbook'),
                    ),
                    _buildToolItem(
                      context,
                      title: 'ফ্যামিলি কুইজ',
                      badge: 'কুইজ',
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 9.5,
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
        TourGroupRepository.lastActiveTourId = tourId;
        context.go(route);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7.5),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.mintGreen.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? Border.all(
                  color: AppColors.mintGreen.withValues(alpha: 0.4), width: 0.8)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              isActive ? activeIcon : icon,
              size: 18,
              color: isActive ? AppColors.mintGreen : Colors.white70,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isActive ? AppColors.mintGreen : Colors.white,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12.5,
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
        TourGroupRepository.lastActiveTourId = tourId;
        context.go(route);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.mintGreen.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? Border.all(
                  color: AppColors.mintGreen.withValues(alpha: 0.4), width: 0.8)
              : null,
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: isActive ? AppColors.mintGreen : Colors.white70),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isActive ? AppColors.mintGreen : Colors.white70,
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
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Reads the signed-in user, or null when Firebase is not initialised (as in
  /// widget tests), so the footer shows its placeholder instead of throwing.
  User? _currentUser() {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }

  Widget _buildFooter(BuildContext context) {
    final user = _currentUser();
    final displayName = user?.displayName ?? 'এক্সপ্লোরার';
    final email = user?.email ?? '';
    final photoUrl = user?.photoURL;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF101010),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.midGreen,
                backgroundImage:
                    photoUrl != null ? NetworkImage(photoUrl) : null,
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      email,
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined,
                    size: 16, color: Colors.white54),
                tooltip: 'প্রোফাইল সেটিংস',
                onPressed: () {
                  final uid = user?.uid ?? 'me';
                  context.push('/profile/$uid');
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Connection status
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.mintGreen,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'ফায়ারবেস লাইভ সিঙ্ক সক্রিয়',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white54, fontSize: 9.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
