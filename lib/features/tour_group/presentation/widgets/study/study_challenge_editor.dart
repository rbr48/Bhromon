import 'package:flutter/material.dart';
import 'study_modal.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../domain/models/study_challenge_models.dart';
import 'study_labels.dart';

/// Opens the sheet where an admin sets a week's challenge: what members do, and how many. Returns the challenge to
/// save, or null when the sheet is closed without saving. [current] fills the sheet when a challenge is already set.
Future<StudyChallenge?> showStudyChallengeEditor(
  BuildContext context, {
  required String weekKey,
  StudyChallenge? current,
}) {
  return showStudyModal<StudyChallenge>(
    context: context,
    builder: (_) => _StudyChallengeSheet(weekKey: weekKey, current: current),
  );
}

class _StudyChallengeSheet extends StatefulWidget {
  const _StudyChallengeSheet({required this.weekKey, this.current});

  final String weekKey;
  final StudyChallenge? current;

  @override
  State<_StudyChallengeSheet> createState() => _StudyChallengeSheetState();
}

class _StudyChallengeSheetState extends State<_StudyChallengeSheet> {
  late ChallengeKind _kind = widget.current?.kind ?? ChallengeKind.problems;
  late int _target = widget.current?.target ?? 5;

  void _save() {
    Navigator.of(context).pop(StudyChallenge(
      weekKey: widget.weekKey,
      kind: _kind,
      target: _target,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.translate('study_challenge_editor_title'),
              style: TextStyle(
                color: palette.text,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.translate('study_challenge_kind_label'),
              style: TextStyle(color: palette.text70),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in ChallengeKind.values)
                  ChoiceChip(
                    label: Text(l10n.translate(challengeKindKey(kind))),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              l10n.translate('study_challenge_target_label'),
              style: TextStyle(color: palette.text70),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: l10n.translate('study_challenge_fewer'),
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  onPressed: _target > StudyChallengeLimits.targetMin
                      ? () => setState(() => _target--)
                      : null,
                ),
                Text(
                  l10n.number(_target),
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                IconButton(
                  tooltip: l10n.translate('study_challenge_more'),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: _target < StudyChallengeLimits.targetMax
                      ? () => setState(() => _target++)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _save,
                child: Text(l10n.translate('study_challenge_save_btn')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
