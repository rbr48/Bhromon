import 'package:flutter/material.dart';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/features/tour_group/domain/models/study_streak_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_daily_streak_rules.dart';

/// Modal bottom sheet displaying the Branch Study Hall accountability leaderboard.
class BranchStudyHallSheet extends StatefulWidget {
  final List<BranchStudyStanding> standings;
  final String? selectedBank;

  const BranchStudyHallSheet({
    super.key,
    required this.standings,
    this.selectedBank,
  });

  /// Opens the Branch Study Hall modal sheet.
  static Future<void> show(
    BuildContext context, {
    required List<BranchStudyStanding> standings,
    String? selectedBank,
  }) {
    final palette = context.forest;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surfaceFor(const Color(0xFF141E18)),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => BranchStudyHallSheet(
        standings: standings,
        selectedBank: selectedBank,
      ),
    );
  }

  @override
  State<BranchStudyHallSheet> createState() => _BranchStudyHallSheetState();
}

class _BranchStudyHallSheetState extends State<BranchStudyHallSheet> {
  String? _filterBank;
  final Set<String> _cheeredEmails = <String>{};

  @override
  void initState() {
    super.initState();
    _filterBank = widget.selectedBank;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final allStandings = widget.standings;
    final summary = StudyDailyStreakRules.computeSummary(allStandings);

    // Extract unique bank names
    final bankNames = <String>{};
    for (final s in allStandings) {
      bankNames.add(s.bankName);
    }
    final sortedBanks = bankNames.toList()..sort();

    final filtered = _filterBank == null
        ? allStandings
        : allStandings.where((s) => s.bankName == _filterBank).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Drag Handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.divider12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header Title Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: palette.accentText.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.apartment_rounded,
                      color: palette.accentText,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.translate('study_branch_hall'),
                          style: TextStyle(
                            color: palette.isDark
                                ? Colors.white
                                : AppColors.darkText,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          l10n.translate('study_branch_hall_subtitle'),
                          style: TextStyle(
                            color: palette.isDark
                                ? Colors.white70
                                : AppColors.grayText,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: palette.text70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Summary Metrics Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: palette.isDark
                      ? const Color(0xFF1B2B22)
                      : const Color(0xFFEAF5EE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: palette.accentText.withValues(alpha: 0.25),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _metricItem(
                      label: l10n.translate('study_filter_all_banks'),
                      value: '${summary.activeBankersCount}',
                      icon: Icons.people_alt_outlined,
                      palette: palette,
                    ),
                    _verticalDivider(palette),
                    _metricItem(
                      label: l10n.translate('study_streak_title'),
                      value: '${summary.averageStreakDays} d',
                      icon: Icons.local_fire_department_rounded,
                      palette: palette,
                    ),
                    _verticalDivider(palette),
                    _metricItem(
                      label: l10n.translate('study_mock_exams_count',
                          args: {'count': ''}).trim(),
                      value: '${summary.totalStudyActions}',
                      icon: Icons.school_outlined,
                      palette: palette,
                    ),
                  ],
                ),
              ),
            ),

            // Bank Filter Chips (shown when members represent multiple banks/branches)
            if (sortedBanks.length > 1) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text(
                        l10n.translate('study_filter_all_banks'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _filterBank == null
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: _filterBank == null
                              ? palette.accentText
                              : palette.text70,
                        ),
                      ),
                      selected: _filterBank == null,
                      selectedColor: palette.accentText.withValues(alpha: 0.2),
                      backgroundColor: palette.divider10,
                      side: BorderSide(
                        color: _filterBank == null
                            ? palette.accentText.withValues(alpha: 0.6)
                            : palette.divider12,
                        width: 0.8,
                      ),
                      onSelected: (_) => setState(() => _filterBank = null),
                    ),
                    for (final bank in sortedBanks) ...[
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: Text(
                          bank,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _filterBank == bank
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: _filterBank == bank
                                ? palette.accentText
                                : palette.text70,
                          ),
                        ),
                        selected: _filterBank == bank,
                        selectedColor: palette.accentText.withValues(alpha: 0.2),
                        backgroundColor: palette.divider10,
                        side: BorderSide(
                          color: _filterBank == bank
                              ? palette.accentText.withValues(alpha: 0.6)
                              : palette.divider12,
                          width: 0.8,
                        ),
                        onSelected: (selected) {
                          setState(() => _filterBank = selected ? bank : null);
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 12),
            ],

            // Standings Leaderboard List
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        l10n.translate('study_chapters_empty_member'),
                        style: TextStyle(color: palette.text54),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final isCheered = _cheeredEmails.contains(item.email);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: item.isCurrentUser
                                ? (palette.isDark
                                    ? const Color(0xFF233B2E)
                                    : const Color(0xFFDEF2E5))
                                : (palette.isDark
                                    ? const Color(0xFF17241D)
                                    : Colors.white),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: item.isCurrentUser
                                  ? palette.accentText
                                  : palette.divider12,
                              width: item.isCurrentUser ? 1.5 : 0.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              // Rank Badge
                              _rankBadge(item.rank, palette),
                              const SizedBox(width: 12),

                              // Colleague Details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            item.displayName,
                                            style: TextStyle(
                                              color: palette.isDark
                                                  ? Colors.white
                                                  : AppColors.darkText,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (item.isCurrentUser) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: palette.accentText
                                                  .withValues(alpha: 0.2),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'YOU',
                                              style: TextStyle(
                                                color: palette.accentText,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${item.bankName} • ${item.branchName}',
                                      style: TextStyle(
                                        color: palette.isDark
                                            ? Colors.white70
                                            : AppColors.grayText,
                                        fontSize: 11.5,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        // Streak badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.orange
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Text('🔥',
                                                  style:
                                                      TextStyle(fontSize: 11)),
                                              const SizedBox(width: 3),
                                              Text(
                                                l10n.translate(
                                                    'study_streak_days_count',
                                                    args: {
                                                      'count':
                                                          '${item.streakDays}'
                                                    }),
                                                style: const TextStyle(
                                                  color: Colors.orange,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // Chapters read
                                        Text(
                                          '📖 ${l10n.translate('study_chapters_read_count', args: {
                                                'count': '${item.chaptersRead}'
                                              })}',
                                          style: TextStyle(
                                            color: palette.text70,
                                            fontSize: 11,
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // Mock exams
                                        Text(
                                          '📝 ${l10n.translate('study_mock_exams_count', args: {
                                                'count':
                                                    '${item.mockExamsAttempted}'
                                              })}',
                                          style: TextStyle(
                                            color: palette.text70,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // Interactive Nudge/Cheer Button
                              if (!item.isCurrentUser) ...[
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    minimumSize: Size.zero,
                                    side: BorderSide(
                                      color: isCheered
                                          ? palette.accentText
                                          : palette.divider12,
                                    ),
                                    backgroundColor: isCheered
                                        ? palette.accentText
                                            .withValues(alpha: 0.15)
                                        : Colors.transparent,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _cheeredEmails.add(item.email);
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          l10n.translate(
                                            'study_colleague_nudged',
                                            args: {'name': item.displayName},
                                          ),
                                        ),
                                        duration: const Duration(seconds: 2),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        isCheered ? '👏' : '📣',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isCheered
                                            ? l10n
                                                .translate('study_nudge_button')
                                            : l10n.translate(
                                                'study_nudge_button'),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isCheered
                                              ? palette.accentText
                                              : palette.text,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _rankBadge(int rank, ForestPalette palette) {
    Color bg;
    Color fg;
    String label = '$rank';

    if (rank == 1) {
      bg = const Color(0xFFFFD700);
      fg = const Color(0xFF5A4500);
      label = '🥇';
    } else if (rank == 2) {
      bg = const Color(0xFFC0C0C0);
      fg = const Color(0xFF333333);
      label = '🥈';
    } else if (rank == 3) {
      bg = const Color(0xFFCD7F32);
      fg = const Color(0xFF4A2A00);
      label = '🥉';
    } else {
      bg = palette.divider10;
      fg = palette.text70;
    }

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: bg.withValues(alpha: rank <= 3 ? 0.3 : 1.0),
        shape: BoxShape.circle,
        border: Border.all(
          color: rank <= 3 ? bg : palette.divider12,
          width: 1.2,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: rank <= 3 ? 16 : 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _metricItem({
    required String label,
    required String value,
    required IconData icon,
    required ForestPalette palette,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: palette.accentText),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                color: palette.isDark ? Colors.white : AppColors.darkText,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: palette.isDark ? Colors.white70 : AppColors.grayText,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _verticalDivider(ForestPalette palette) {
    return Container(
      height: 24,
      width: 1,
      color: palette.divider12,
    );
  }
}
