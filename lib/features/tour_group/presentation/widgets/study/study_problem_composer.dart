import 'package:flutter/material.dart';
import 'study_modal.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../domain/models/study_problem_models.dart';
import 'study_text_field.dart';

/// What an admin or a member entered for a problem: its words, an optional title, and, for an admin,
/// the day the reference solution opens.
class StudyProblemDraft {
  const StudyProblemDraft({
    required this.text,
    required this.title,
    required this.releaseAt,
  });

  final String text;
  final String title;
  final DateTime? releaseAt;
}

/// Opens the editor for a problem. [existing] is null for a new problem. [withRelease] adds the
/// release-day picker, which only an admin uses. Returns what was saved, or null when cancelled.
Future<StudyProblemDraft?> showStudyProblemEditor(
  BuildContext context, {
  StudyProblem? existing,
  bool withRelease = false,
}) {
  return showStudyModal<StudyProblemDraft>(
    context: context,
    builder: (_) => StudyProblemEditor(
      existing: existing,
      withRelease: withRelease,
    ),
  );
}

/// Opens a sheet with one text field, and returns the text when it is saved, or null when cancelled.
/// Used for a member's working and for an admin's reference solution.
Future<String?> showStudyTextEditor(
  BuildContext context, {
  required String titleKey,
  required String labelKey,
  String initial = '',
}) {
  return showStudyModal<String>(
    context: context,
    builder: (_) => _StudyTextSheet(
      titleKey: titleKey,
      labelKey: labelKey,
      initial: initial,
    ),
  );
}

/// Asks why a member found a gap in a working. Returns the note, which is empty when there is none,
/// or null when the member cancels.
Future<String?> showStudyGapDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _StudyGapDialog(),
  );
}

class StudyProblemEditor extends StatefulWidget {
  const StudyProblemEditor({
    super.key,
    this.existing,
    this.withRelease = false,
  });

  final StudyProblem? existing;
  final bool withRelease;

  @override
  State<StudyProblemEditor> createState() => _StudyProblemEditorState();
}

class _StudyProblemEditorState extends State<StudyProblemEditor> {
  late final TextEditingController _text =
      TextEditingController(text: widget.existing?.text ?? '');
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  DateTime? _releaseAt;
  bool _tried = false;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _text.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickRelease() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _releaseAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(
        () => _releaseAt = DateTime(picked.year, picked.month, picked.day));
  }

  void _save() {
    setState(() => _tried = true);
    if (_text.text.trim().isEmpty) return;
    Navigator.of(context).pop(StudyProblemDraft(
      text: _text.text.trim(),
      title: _title.text.trim(),
      releaseAt: widget.withRelease ? _releaseAt : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final textError = _tried && _text.text.trim().isEmpty
        ? l10n.translate('study_problem_text_required')
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
                    _isNew ? 'study_problem_add' : 'study_post_edit_title'),
                style: TextStyle(
                    color: palette.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                style: TextStyle(color: palette.text),
                decoration: InputDecoration(
                  labelText: l10n.translate('study_problem_title_label'),
                ),
              ),
              StudyTextField(
                controller: _text,
                autofocus: _isNew,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: l10n.translate('study_problem_text_label'),
                  errorText: textError,
                ),
              ),
              if (widget.withRelease) ...[
                const SizedBox(height: 8),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: _pickRelease,
                      icon: Icon(Icons.event_rounded,
                          size: 18, color: palette.accentText),
                      label: Text(_releaseAt == null
                          ? l10n.translate('study_problem_release_pick')
                          : l10n.translate('study_problem_release_on', args: {
                              'date': localizedDateFormat('d MMM yyyy')
                                  .format(_releaseAt!),
                            })),
                    ),
                    if (_releaseAt != null)
                      TextButton(
                        onPressed: () => setState(() => _releaseAt = null),
                        child:
                            Text(l10n.translate('study_problem_release_clear')),
                      ),
                  ],
                ),
              ],
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

class _StudyTextSheet extends StatefulWidget {
  const _StudyTextSheet({
    required this.titleKey,
    required this.labelKey,
    required this.initial,
  });

  final String titleKey;
  final String labelKey;
  final String initial;

  @override
  State<_StudyTextSheet> createState() => _StudyTextSheetState();
}

class _StudyTextSheetState extends State<_StudyTextSheet> {
  late final TextEditingController _text =
      TextEditingController(text: widget.initial);
  bool _tried = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    setState(() => _tried = true);
    if (_text.text.trim().isEmpty) return;
    Navigator.of(context).pop(_text.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final textError = _tried && _text.text.trim().isEmpty
        ? l10n.translate('study_problem_text_required')
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
                l10n.translate(widget.titleKey),
                style: TextStyle(
                    color: palette.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              StudyTextField(
                controller: _text,
                autofocus: true,
                minLines: 4,
                maxLines: 12,
                decoration: InputDecoration(
                  labelText: l10n.translate(widget.labelKey),
                  errorText: textError,
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

class _StudyGapDialog extends StatefulWidget {
  const _StudyGapDialog();

  @override
  State<_StudyGapDialog> createState() => _StudyGapDialogState();
}

class _StudyGapDialogState extends State<_StudyGapDialog> {
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
      title: Text(l10n.translate('study_work_gap_title')),
      content: TextField(
        controller: _note,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
        decoration: InputDecoration(
          labelText: l10n.translate('study_work_gap_note_label'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.translate('study_cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_note.text.trim()),
          child: Text(l10n.translate('study_work_gap_send')),
        ),
      ],
    );
  }
}
