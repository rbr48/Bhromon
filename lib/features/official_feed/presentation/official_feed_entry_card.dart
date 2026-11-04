import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/colors.dart';
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.midGreen.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.play_circle_outline_rounded,
                  size: 28,
                  color: forest.accentText,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('official_feed_title'),
                      style: TextStyle(
                        color: forest.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.translate('official_feed_card_body'),
                      style: TextStyle(color: forest.text70, fontSize: 13),
                    ),
                  ],
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
