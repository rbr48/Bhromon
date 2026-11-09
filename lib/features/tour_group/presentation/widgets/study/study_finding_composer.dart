import 'package:flutter/material.dart';
import 'study_modal.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../domain/models/study_finding_models.dart';

import 'study_text_field.dart';

/// What a member entered for a finding.
class StudyFindingDraft {
  const StudyFindingDraft({required this.text, required this.method});

  final String text;
  final String method;
}

/// Opens the editor for a finding. [existing] is null for a new finding. Returns what was saved,
/// or null when cancelled.
Future<StudyFindingDraft?> showStudyFindingEditor(
  BuildContext context, {
  StudyFinding? existing,
}) {
  return showStudyModal<StudyFindingDraft>(
    context: context,
    builder: (_) => StudyFindingEditor(existing: existing),
  );
}

/// Asks why a member challenges a finding. Returns the note, which is empty when there is none,
/// or null when the member cancels.
Future<String?> showStudyChallengeDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _StudyChallengeDialog(),
  );
}

/// The form for a finding: what was found, and how it was checked. Both are needed, so that
/// others can check it the same way.
class StudyFindingEditor extends StatefulWidget {
  const StudyFindingEditor({super.key, this.existing});

  final StudyFinding? existing;

  @override
  State<StudyFindingEditor> createState() => _StudyFindingEditorState();
}

class _StudyFindingEditorState extends State<StudyFindingEditor> {
  late final TextEditingController _text =
      TextEditingController(text: widget.existing?.text ?? '');
  late final TextEditingController _method =
      TextEditingController(text: widget.existing?.method ?? '');
  bool _tried = false;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _text.dispose();
    _method.dispose();
    super.dispose();
  }

  void _save() {
    setState(() => _tried = true);
    if (_text.text.trim().isEmpty || _method.text.trim().isEmpty) return;
    Navigator.of(context).pop(StudyFindingDraft(
      text: _text.text.trim(),
      method: _method.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final textError = _tried && _text.text.trim().isEmpty
        ? l10n.translate('study_finding_text_required')
        : null;
    final methodError = _tried && _method.text.trim().isEmpty
        ? l10n.translate('study_finding_method_required')
        : null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.translate(
                    _isNew ? 'study_finding_add' : 'study_post_edit_title'),
                style: TextStyle(
                    color: palette.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              StudyTextField(
                controller: _text,
                autofocus: _isNew,
                minLines: 2,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: l10n.translate('study_finding_text_label'),
                  errorText: textError,
                ),
              ),
              StudyTextField(
                controller: _method,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.translate('study_finding_method_label'),
                  errorText: methodError,
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _save,
                  child: Text(l10n.translate('study_save')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudyChallengeDialog extends StatefulWidget {
  const _StudyChallengeDialog();

  @override
  State<_StudyChallengeDialog> createState() => _StudyChallengeDialogState();
}

class _StudyChallengeDialogState extends State<_StudyChallengeDialog> {
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.translate('study_finding_challenge_title')),
      content: TextField(
        controller: _note,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
        decoration: InputDecoration(
          labelText: l10n.translate('study_finding_challenge_note_label'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.translate('study_cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_note.text.trim()),
          child: Text(l10n.translate('study_finding_challenge')),
        ),
      ],
    );
  }
}
