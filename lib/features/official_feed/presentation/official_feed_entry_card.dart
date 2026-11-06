import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/forest_palette.dart';

/// A card on the groups hub that opens the official feed. It keeps the hub useful for a new
/// person who has no group yet.
class OfficialFeedEntryCard extends StatelessWidget {
  const OfficialFeedEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final forest = context.forest;
    return Material(
      color: forest.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/official-feed'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // The official account's picture, cropped to a circle at the size the icon had.
              SizedBox.square(
                dimension: 52,
                child: ClipOval(
                  child: Image.asset(
                    'assets/official_feed_avatar.jpg',
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  l10n.translate('official_feed_title'),
                  style: TextStyle(
                    color: forest.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: forest.text54),
            ],
          ),
        ),
      ),
    );
  }
}
