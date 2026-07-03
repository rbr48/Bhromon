import 'package:flutter/material.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/services/diary_badges_service.dart';

class BadgeShelf extends StatelessWidget {
  final List<String> badges;
  final bool isBangla;

  const BadgeShelf({super.key, required this.badges, this.isBangla = false});

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) {
      return Text(
        isBangla ? 'এখনও কোনো ব্যাজ অর্জিত হয়নি।' : 'No badges earned yet.',
        style: const TextStyle(color: Colors.white54, fontSize: 13, fontStyle: FontStyle.italic),
      );
    }
    
    final Map<String, Map<String, String>> badgeDetails = {
      'pioneer': {
        'title': 'PIONEER EXPLORER',
        'desc': 'Earned by logging the first verified trip to a new district.',
        'next': 'Log 3 new district draft logs to reach Level 2.',
      },
      'verified': {
        'title': 'VERIFIED CONTRIBUTOR',
        'desc': 'Assigned to users with over 80% accuracy score in verification tasks.',
        'next': 'Perform 5 more freshness audits to level up.',
      },
      'trailblazer': {
        'title': 'TRAILBLAZER',
        'desc': 'Granted for charting remote coordinates and unsafe notes.',
        'next': 'Add 2 safety warning notes to unlock Level 3.',
      },
      'sajek': {
        'title': 'SAJEK SCOUT',
        'desc': 'Logged trip details of Sajek Valley with helpful logs.',
        'next': 'Complete 3 local ProTip reviews.',
      },
    };

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: badges.map((badge) {
        final key = badge.toLowerCase().trim();
        final badgeDef = DiaryBadgesService.getBadge(key);

        final String emoji = badgeDef?.emoji ?? '🏅';
        final String title = badgeDef != null
            ? (isBangla ? badgeDef.titleBn : badgeDef.titleEn)
            : (badgeDetails[key]?['title'] ?? badge.toUpperCase());
        final String desc = badgeDef != null
            ? (isBangla ? badgeDef.descBn : badgeDef.titleEn) // Use titleEn as English desc if descEn not present
            : (badgeDetails[key]?['desc'] ?? 'A unique exploration achievement milestone for Bhromon.');
        final String next = badgeDetails[key]?['next'] ??
            (isBangla ? 'ভ্রমণ অব্যাহত রাখুন এবং এক্সপি অর্জন করুন!' : 'Keep exploring and sharing logs to level up!');

        return GestureDetector(
          onTap: () {
            showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF111111),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.mintGreen, width: 0.8),
                ),
                title: Row(
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      desc,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isBangla ? 'পরবর্তী মাইলস্টোন' : 'NEXT MILESTONE',
                      style: const TextStyle(color: AppColors.mintGreen, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      next,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    child: Text(isBangla ? 'অসাধারণ' : 'Awesome', style: const TextStyle(color: AppColors.mintGreen)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            );
          },
          child: Chip(
            backgroundColor: AppColors.darkGreen.withOpacity(0.4),
            side: const BorderSide(color: AppColors.mintGreen, width: 0.8),
            avatar: Text(emoji, style: const TextStyle(fontSize: 12)),
            label: Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
