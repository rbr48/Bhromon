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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: forest.divider10),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/official-feed'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Frame the avatar in a dark circular backing so the pin emblem never clips against light cards.
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.forestScaffold,
                  border: Border.all(color: forest.divider12),
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/official_feed_avatar.jpg',
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.translate('official_feed_title'),
                      style: TextStyle(
                        color: forest.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: forest.accentText.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        l10n.translate('official_feed_badge'),
                        style: TextStyle(
                          color: forest.accentText,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
