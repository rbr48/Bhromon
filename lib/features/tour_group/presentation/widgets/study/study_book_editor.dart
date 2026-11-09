import 'package:flutter/material.dart';
import 'study_modal.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../domain/models/study_models.dart';
import '../../../domain/services/study_rules.dart';
import 'study_labels.dart';

import 'study_text_field.dart';

/// What a member entered for a book.
class StudyBookDraft {
  const StudyBookDraft({
    required this.title,
    required this.author,
    required this.notes,
    required this.status,
  });

  final String title;
  final String author;
  final String notes;
  final StudyBookStatus status;
}

/// Opens the editor for a book. [existing] is null for a new book. [proposal] is true when
/// a member proposes a new book, which has no status until an admin lists it. Returns what
/// the member saved, or null when they cancel.
Future<StudyBookDraft?> showStudyBookEditor(
  BuildContext context, {
  StudyBook? existing,
  bool proposal = false,
}) {
  return showStudyModal<StudyBookDraft>(
    context: context,
    builder: (_) => StudyBookEditor(existing: existing, proposal: proposal),
  );
}

class StudyBookEditor extends StatefulWidget {
  const StudyBookEditor({super.key, this.existing, this.proposal = false});

  final StudyBook? existing;

  /// Whether the member is proposing a new book.
  final bool proposal;

  @override
  State<StudyBookEditor> createState() => _StudyBookEditorState();
}

class _StudyBookEditorState extends State<StudyBookEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _author =
      TextEditingController(text: widget.existing?.author ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');
  late StudyBookStatus _status =
      widget.existing?.status ?? StudyBookStatus.toRead;
  bool _tried = false;

  bool get _isNew => widget.existing == null;

  /// A status is set only for a book on the list. A proposal has none until it is listed.
  bool get _showStatus => _isNew ? !widget.proposal : widget.existing!.isListed;

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    setState(() => _tried = true);
    if (!isValidStudyTitle(_title.text)) return;
    Navigator.of(context).pop(StudyBookDraft(
      title: _title.text.trim(),
      author: _author.text.trim(),
      notes: _notes.text.trim(),
      status: _status,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final titleError = _tried && !isValidStudyTitle(_title.text)
        ? l10n.translate('study_book_title_required')
        : null;
    final titleKey = _isNew
        ? (widget.proposal
            ? 'study_book_proposal_title'
            : 'study_book_new_title')
        : 'study_book_edit_title';
    final saveKey =
        _isNew && widget.proposal ? 'study_book_send_proposal' : 'study_save';
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
                l10n.translate(titleKey),
                style: TextStyle(
                    color: palette.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                autofocus: _isNew,
                style: TextStyle(color: palette.text),
                decoration: InputDecoration(
                  labelText: l10n.translate('study_book_title_label'),
                  errorText: titleError,
                ),
              ),
              TextField(
                controller: _author,
                style: TextStyle(color: palette.text),
                decoration: InputDecoration(
                  labelText: l10n.translate('study_book_author_label'),
                ),
              ),
              StudyTextField(
                controller: _notes,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.translate('study_book_notes_label'),
                ),
              ),
              if (_showStatus) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.translate('study_book_status_label'),
                  style: TextStyle(color: palette.text70),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final status in StudyBookStatus.values)
                      ChoiceChip(
                        label: Text(l10n.translate(studyBookStatusKey(status))),
                        selected: _status == status,
                        onSelected: (_) => setState(() => _status = status),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _save,
                  child: Text(l10n.translate(saveKey)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
