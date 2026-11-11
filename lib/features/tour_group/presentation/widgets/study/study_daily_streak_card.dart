import 'package:flutter/material.dart';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/features/tour_group/domain/models/study_streak_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_daily_streak_rules.dart';
import 'branch_study_hall_sheet.dart';

/// Card displaying candidate's daily study streak, 7-day flame track, and branch accountability.
class StudyDailyStreakCard extends StatelessWidget {
  final StudyDailyStreak streak;
  final List<BranchStudyStanding>? standings;
  final VoidCallback? onOpenBranchHall;
  final EdgeInsetsGeometry margin;

  const StudyDailyStreakCard({
    super.key,
    required this.streak,
    this.standings,
    this.onOpenBranchHall,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final weekdayLabels = _getWeekdayLabels(context);
    final todayWeekdayIndex = (DateTime.now().weekday - 1) % 7;

    return Container(
      margin: margin,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.isDark ? const Color(0xFF14241B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: streak.isActiveToday
              ? palette.accentText.withValues(alpha: 0.6)
              : palette.divider12,
          width: streak.isActiveToday ? 1.4 : 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: palette.isDark ? 0.2 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Flame / Badge / Status
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Flame icon circle
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: streak.isActiveToday
                      ? Colors.orange.withValues(alpha: 0.18)
                      : palette.divider10,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: streak.isActiveToday
                        ? Colors.orange
                        : palette.divider12,
                    width: 1.2,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  streak.flameIcon,
                  style: const TextStyle(fontSize: 22),
                ),
              ),
              const SizedBox(width: 12),

              // Streak counts & tier
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          l10n.translate(
                            'study_streak_days',
                            args: {'count': '${streak.currentStreak}'},
                          ),
                          style: TextStyle(
                            color: palette.isDark
                                ? Colors.white
                                : AppColors.darkText,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (streak.currentStreak > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: palette.accentText.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              l10n.translate(streak.tierKey),
                              style: TextStyle(
                                color: palette.accentText,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.translate(
                        'study_streak_best_days',
                        args: {'count': '${streak.bestStreak}'},
                      ),
                      style: TextStyle(
                        color: palette.isDark
                            ? Colors.white70
                            : AppColors.grayText,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),

              // Active Today / Action Required badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: streak.isActiveToday
                      ? palette.accentText.withValues(alpha: 0.15)
                      : (streak.hasUsedFreeze
                          ? Colors.blue.withValues(alpha: 0.15)
                          : Colors.amber.withValues(alpha: 0.15)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: streak.isActiveToday
                        ? palette.accentText.withValues(alpha: 0.5)
                        : (streak.hasUsedFreeze
                            ? Colors.blue.withValues(alpha: 0.5)
                            : Colors.amber.withValues(alpha: 0.5)),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      streak.isActiveToday
                          ? Icons.check_circle_rounded
                          : (streak.hasUsedFreeze
                              ? Icons.shield_rounded
                              : Icons.hourglass_top_rounded),
                      size: 14,
                      color: streak.isActiveToday
                          ? palette.accentText
                          : (streak.hasUsedFreeze
                              ? Colors.blue
                              : Colors.amber.shade800),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      streak.isActiveToday
                          ? l10n.translate('study_streak_active_today')
                          : (streak.hasUsedFreeze
                              ? l10n.translate('study_streak_freeze_used')
                              : l10n.translate('study_streak_needs_action')),
                      style: TextStyle(
                        color: streak.isActiveToday
                            ? palette.accentText
                            : (streak.hasUsedFreeze
                                ? Colors.blue
                                : Colors.amber.shade900),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 7-Day Flame Track (Monday to Sunday)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final active =
                  streak.weekDaysActive.length > i && streak.weekDaysActive[i];
              final isToday = i == todayWeekdayIndex;

              return Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active
                          ? Colors.orange.withValues(alpha: 0.2)
                          : (isToday ? palette.divider12 : palette.divider10),
                      border: Border.all(
                        color: isToday
                            ? (active ? Colors.orange : palette.accentText)
                            : (active
                                ? Colors.orange.withValues(alpha: 0.6)
                                : Colors.transparent),
                        width: isToday ? 1.6 : 1.0,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: active
                        ? const Text('🔥', style: TextStyle(fontSize: 14))
                        : (isToday
                            ? Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: palette.text54,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : const SizedBox.shrink()),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    weekdayLabels[i],
                    style: TextStyle(
                      color: isToday
                          ? palette.accentText
                          : (palette.isDark
                              ? Colors.white60
                              : AppColors.grayText),
                      fontSize: 10.5,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              );
            }),
          ),

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),

          // Bottom Bar: Motivational copy & Branch Hall Button
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.translate('study_streak_motivation'),
                  style: TextStyle(
                    color: palette.isDark ? Colors.white60 : AppColors.grayText,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  backgroundColor: palette.accentText.withValues(alpha: 0.12),
                ),
                onPressed: () {
                  if (onOpenBranchHall != null) {
                    onOpenBranchHall!();
                  } else {
                    final list = standings ??
                        StudyDailyStreakRules.fromTourMembers(
                          members: const [],
                          myEmail: 'member@bhromon.fun',
                          myName: 'You',
                          myStreak: streak.currentStreak,
                        );
                    BranchStudyHallSheet.show(context, standings: list);
                  }
                },
                icon: Icon(Icons.apartment_rounded,
                    size: 16, color: palette.accentText),
                label: Text(
                  l10n.translate('study_branch_hall'),
                  style: TextStyle(
                    color: palette.accentText,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<String> _getWeekdayLabels(BuildContext context) {
    final isBangla = Localizations.localeOf(context).languageCode == 'bn';
    if (isBangla) {
      return const ['সোম', 'মঙ্গল', 'বুধ', 'বৃহ', 'শুক্র', 'শনি', 'রবি'];
    }
    return const ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  }
}
