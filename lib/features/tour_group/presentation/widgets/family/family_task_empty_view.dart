import 'package:flutter/material.dart';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/features/tour_group/domain/models/family_task_models.dart';

import 'family_task_shared.dart';

const _shoppingSuggestionKeys = [
  'ft_suggest_shopping_1',
  'ft_suggest_shopping_2',
  'ft_suggest_shopping_3',
  'ft_suggest_shopping_4',
  'ft_suggest_shopping_5',
];

const _todoSuggestionKeys = [
  'ft_suggest_todo_1',
  'ft_suggest_todo_2',
  'ft_suggest_todo_3',
  'ft_suggest_todo_4',
  'ft_suggest_todo_5',
];

/// What a kind's page shows when it has no items: a short explanation and quick suggestions.
/// A suggestion adds that item at once.
class FamilyTaskEmptyView extends StatelessWidget {
  const FamilyTaskEmptyView({
    super.key,
    required this.kind,
    required this.onSuggest,
  });

  final FamilyTaskKind kind;
  final ValueChanged<String> onSuggest;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final isShopping = kind == FamilyTaskKind.shopping;
    final keys = isShopping ? _shoppingSuggestionKeys : _todoSuggestionKeys;
    final suggestions = [for (final key in keys) l10n.translate(key)];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.mintGreen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isShopping
                    ? Icons.shopping_basket_outlined
                    : Icons.playlist_add_check_rounded,
                color: palette.accentText,
                size: 40,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              isShopping
                  ? l10n.translate('ft_empty_shopping_title')
                  : l10n.translate('ft_empty_todo_title'),
              style: TextStyle(
                color: palette.text,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isShopping
                  ? l10n.translate('ft_empty_shopping_body')
                  : l10n.translate('ft_empty_todo_body'),
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.text54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final suggestion in suggestions)
                  ActionChip(
                    backgroundColor: palette.surfaceFor(familyTaskCard),
                    label: Text(
                      suggestion,
                      style: TextStyle(color: palette.accentText, fontSize: 12),
                    ),
                    onPressed: () => onSuggest(suggestion),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
