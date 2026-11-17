import 'package:flutter/material.dart';

import '../localization/locale_controller.dart';
import '../theme/colors.dart';

/// Understandable language switcher combining the universal translate icon
/// (`A/文`) with explicit `EN` / `বাংলা` labels.
class LanguageSwitchButton extends StatelessWidget {
  const LanguageSwitchButton({super.key}) : compact = false;

  /// Compact badge-style switcher tailored for crowded AppBar action rows.
  const LanguageSwitchButton.compact({super.key}) : compact = true;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleController.instance,
      builder: (context, _) {
        final isBn = LocaleController.instance.locale.languageCode == 'bn';
        if (compact) {
          return _buildCompactChip(isBn);
        }
        return _buildSegmentedPill(isBn);
      },
    );
  }

  Widget _buildCompactChip(bool isBn) {
    final tooltip = isBn ? 'Switch to English' : 'বাংলায় দেখুন';
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Material(
            color: AppColors.midGreen.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              key: const Key('compact_language_switch_button'),
              borderRadius: BorderRadius.circular(18),
              onTap: () =>
                  LocaleController.instance.setLanguage(isBn ? 'en' : 'bn'),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.midGreen.withValues(alpha: 0.38),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.translate_rounded,
                      size: 16,
                      color: AppColors.midGreen,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isBn ? 'বাং' : 'EN',
                      style: const TextStyle(
                        color: AppColors.midGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentedPill(bool isBn) {
    return Tooltip(
      message: 'Language / ভাষা',
      child: Container(
        key: const Key('login_language_switch_pill'),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1D14),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF1E3A26), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 6, right: 6),
              child: Icon(
                Icons.translate_rounded,
                size: 16,
                color: AppColors.freshGreen,
              ),
            ),
            _LanguageSegment(
              segmentKey: const Key('language_option_en'),
              label: 'EN',
              selected: !isBn,
              onTap: () => LocaleController.instance.setLanguage('en'),
            ),
            const SizedBox(width: 2),
            _LanguageSegment(
              segmentKey: const Key('language_option_bn'),
              label: 'বাংলা',
              selected: isBn,
              onTap: () => LocaleController.instance.setLanguage('bn'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageSegment extends StatelessWidget {
  const _LanguageSegment({
    required this.segmentKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Key segmentKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.freshGreen : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: segmentKey,
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              color:
                  selected ? const Color(0xFF050C08) : const Color(0xB3ECF0F1),
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
