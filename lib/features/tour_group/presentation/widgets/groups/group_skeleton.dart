import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:flutter/material.dart';

/// Placeholder cards shown while a list loads. Never a bare spinner, and never a
/// "0 members" count while the members load (section 5.2).
class GroupSkeleton extends StatelessWidget {
  const GroupSkeleton({super.key, this.cards = 3});

  final int cards;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.translate('group_loading'),
      child: Column(
        children: [
          for (var i = 0; i < cards; i++)
            Container(
              height: 72,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: context.forest.divider10,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
        ],
      ),
    );
  }
}
