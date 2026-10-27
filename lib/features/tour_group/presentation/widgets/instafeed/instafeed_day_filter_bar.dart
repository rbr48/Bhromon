import 'package:flutter/material.dart';
import '../../../../../core/theme/colors.dart';
import '../../../domain/models/tour_group.dart';
import '../../../domain/models/tour_post_models.dart';

class InstafeedDayFilterBar extends StatelessWidget {
  final List<TourDayInfo> days;
  final String selectedDay;
  final ValueChanged<String> onDaySelected;
  final List<TourPostItem> allPosts;
  final int filteredCount;
  final bool isGridView;
  final ValueChanged<bool> onViewModeChanged;
  final VoidCallback onOpenFilterSheet;
  final String activeFilterSummary;

  const InstafeedDayFilterBar({
    super.key,
    required this.days,
    required this.selectedDay,
    required this.onDaySelected,
    required this.allPosts,
    required this.filteredCount,
    required this.isGridView,
    required this.onViewModeChanged,
    required this.onOpenFilterSheet,
    required this.activeFilterSummary,
  });

  int _countFor(String dayId) {
    if (dayId == 'all') return allPosts.length;
    return allPosts.where((p) => p.tourDay == dayId).length;
  }

  String _dayEmoji(int dayNumber) {
    switch (dayNumber) {
      case 1:
        return '🚌';
      case 2:
        return '🏖️';
      case 3:
        return '🔥';
      case 4:
        return '⛵';
      case 5:
        return '🏠';
      default:
        return '🌄';
    }
  }

  String _dayLabelBn(int dayNumber) {
    const bnNums = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
    final s = dayNumber.toString();
    final bnStr = s.split('').map((c) {
      final i = int.tryParse(c);
      return i != null ? bnNums[i] : c;
    }).join();

    switch (dayNumber) {
      case 1:
        return '১ম দিন';
      case 2:
        return '২য় দিন';
      case 3:
        return '৩য় দিন';
      case 4:
        return '৪র্থ দিন';
      case 5:
        return '৫ম দিন';
      case 6:
        return '৬ষ্ঠ দিন';
      default:
        return '$bnStrতম দিন';
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveDays = days.isNotEmpty
        ? days
        : List.generate(
            5,
            (i) => TourDayInfo(
              id: 'day${i + 1}',
              dayNumber: i + 1,
              date: DateTime.now().add(Duration(days: i)),
              label: '${i + 1}ম দিন',
            ),
          );

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Horizontal circular day selector
          SizedBox(
            height: 84,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: effectiveDays.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  final isSelected = selectedDay == 'all';
                  final count = _countFor('all');
                  return _buildCircleItem(
                    label: 'সব দিন',
                    topWidget: const Text(
                      'সব',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    count: count,
                    isSelected: isSelected,
                    onTap: () => onDaySelected('all'),
                  );
                }

                final d = effectiveDays[index - 1];
                final isSelected = selectedDay == d.id;
                final count = _countFor(d.id);
                final emoji = _dayEmoji(d.dayNumber);
                final label = _dayLabelBn(d.dayNumber);

                return _buildCircleItem(
                  label: label,
                  topWidget: Text(
                    emoji,
                    style: const TextStyle(fontSize: 20),
                  ),
                  count: count,
                  isSelected: isSelected,
                  onTap: () => onDaySelected(d.id),
                );
              },
            ),
          ),

          const SizedBox(height: 4),

          // 2. Sub-header bar: Post count + View mode toggle + Filter button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                // Post counter
                Row(
                  children: [
                    Text(
                      'পোস্ট ($filteredCountটি)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (selectedDay != 'all') ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppColors.mintGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color:
                                  AppColors.mintGreen.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          selectedDay == 'all'
                              ? 'সব দিন'
                              : _dayLabelBn(int.tryParse(
                                      selectedDay.replaceAll('day', '')) ??
                                  1),
                          style: const TextStyle(
                            color: AppColors.mintGreen,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                const Spacer(),

                // List / Grid toggle
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () => onViewModeChanged(false),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: !isGridView
                                ? AppColors.mintGreen.withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.view_agenda_rounded,
                                size: 14,
                                color: !isGridView
                                    ? AppColors.mintGreen
                                    : Colors.white54,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'List',
                                style: TextStyle(
                                  color: !isGridView
                                      ? AppColors.mintGreen
                                      : Colors.white54,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => onViewModeChanged(true),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isGridView
                                ? AppColors.mintGreen.withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.grid_view_rounded,
                                size: 14,
                                color: isGridView
                                    ? AppColors.mintGreen
                                    : Colors.white54,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Grid',
                                style: TextStyle(
                                  color: isGridView
                                      ? AppColors.mintGreen
                                      : Colors.white54,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Filter Pill Button
                InkWell(
                  onTap: onOpenFilterSheet,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: activeFilterSummary != 'all'
                            ? AppColors.mintGreen.withValues(alpha: 0.5)
                            : Colors.white12,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          size: 14,
                          color: activeFilterSummary != 'all'
                              ? AppColors.mintGreen
                              : Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'ফিল্টার',
                          style: TextStyle(
                            color: activeFilterSummary != 'all'
                                ? AppColors.mintGreen
                                : Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleItem({
    required String label,
    required Widget topWidget,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? AppColors.mintGreen.withValues(alpha: 0.15)
                        : const Color(0xFF1E1E1E),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.mintGreen
                          : Colors.white.withValues(alpha: 0.15),
                      width: isSelected ? 2.2 : 1.2,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color:
                                  AppColors.mintGreen.withValues(alpha: 0.25),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(child: topWidget),
                ),
                // Count badge at top-right
                if (count > 0)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4.5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.mintGreen
                            : const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? Colors.black : Colors.white24,
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: isSelected ? Colors.black : Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.mintGreen : Colors.white70,
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
