import 'package:flutter/material.dart';
import '../value_objects/diary_visibility.dart';
import '../theme/colors.dart';

/// 🔒 Three-state privacy toggle: Private | Friends | Community
/// Warm, animated segmented control — core to the Travel Diary experience.
class PrivacyToggleWidget extends StatelessWidget {
  final DiaryVisibility current;
  final ValueChanged<DiaryVisibility> onChanged;

  const PrivacyToggleWidget({
    super.key,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: DiaryVisibility.values
            .map((v) => _Segment(
                  visibility: v,
                  isSelected: v == current,
                  onTap: () => onChanged(v),
                ))
            .toList(),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final DiaryVisibility visibility;
  final bool isSelected;
  final VoidCallback onTap;

  const _Segment({
    required this.visibility,
    required this.isSelected,
    required this.onTap,
  });

  Color get _selectedColor => switch (visibility) {
        DiaryVisibility.private => Colors.white54,
        DiaryVisibility.friends => AppColors.gold,
        DiaryVisibility.community => AppColors.mintGreen,
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? _selectedColor.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: _selectedColor.withValues(alpha: 0.5))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              visibility.icon,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(width: 5),
            Text(
              visibility.label,
              style: TextStyle(
                color: isSelected ? _selectedColor : Colors.white38,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
