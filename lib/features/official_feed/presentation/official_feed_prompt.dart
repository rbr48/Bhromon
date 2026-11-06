import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';
import '../domain/official_feed_choice.dart';

/// Asks a person once whether to follow the official feed. The answer is kept, so the
/// question is not asked again. [onFollowChanged] applies the answer to the push
/// subscription. [loadChoice] and [saveChoice] default to the stored answer; a test may
/// pass its own.
Future<void> showOfficialFeedPromptIfNeeded(
  BuildContext context, {
  required Future<void> Function(bool follow) onFollowChanged,
  Future<OfficialFeedChoice> Function() loadChoice =
      OfficialFeedPreference.load,
  Future<void> Function(OfficialFeedChoice choice) saveChoice =
      OfficialFeedPreference.save,
}) async {
  final choice = await loadChoice();
  if (choice != OfficialFeedChoice.unanswered || !context.mounted) return;
  final follow = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.l10n.translate('official_feed_prompt_title')),
      content: Text(dialogContext.l10n.translate('official_feed_prompt_body')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(dialogContext.l10n.translate('official_feed_not_now')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(dialogContext.l10n.translate('official_feed_follow')),
        ),
      ],
    ),
  );
  final answer =
      follow == true ? OfficialFeedChoice.follow : OfficialFeedChoice.notNow;
  await saveChoice(answer);
  await onFollowChanged(answer == OfficialFeedChoice.follow);
}
