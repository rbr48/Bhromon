import 'package:flutter/material.dart';
import 'study_modal.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../domain/models/study_models.dart';
import '../../../domain/models/study_subject_models.dart';

import 'study_text_field.dart';

/// What a member entered for a subject.
class StudySubjectDraft {
  const StudySubjectDraft({
    required this.title,
    required this.code,
    required this.description,
    required this.examDate,
    this.bookId,
  });

  final String title;
  final String code;
  final String description;
  final DateTime? examDate;

  /// The listed book the subject studies, or null for none.
  final String? bookId;
}

/// Opens the editor for a subject. [existing] is null for a new subject, and [proposal] is true
/// when a member proposes one. [books] fills the book choice; only the listed ones are offered.
/// Returns what was saved, or null when cancelled.
Future<StudySubjectDraft?> showStudySubjectEditor(
  BuildContext context, {
  StudySubject? existing,
  bool proposal = false,
  List<StudyBook> books = const [],
}) {
  return showStudyModal<StudySubjectDraft>(
    context: context,
    builder: (_) => StudySubjectEditor(
      existing: existing,
      proposal: proposal,
      books: books,
    ),
  );
}

class StudySubjectEditor extends StatefulWidget {
  const StudySubjectEditor({
    super.key,
    this.existing,
    this.proposal = false,
    this.books = const [],
  });

  final StudySubject? existing;

  /// Whether the member is proposing a new subject.
  final bool proposal;

  /// The books of the group that the subject may name.
  final List<StudyBook> books;

  @override
  State<StudySubjectEditor> createState() => _StudySubjectEditorState();
}

class _StudySubjectEditorState extends State<StudySubjectEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _code =
      TextEditingController(text: widget.existing?.code ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late DateTime? _examDate = widget.existing?.examDate;
  late String? _bookId = _knownBook(widget.existing?.bookId);
  bool _tried = false;

  bool get _isNew => widget.existing == null;

  /// The books a subject may name: the listed ones only.
  List<StudyBook> get _listed => [
        for (final book in widget.books)
          if (book.isListed) book,
      ];

  /// The book of an existing subject, when it is still listed. A book removed since then is
  /// left out, so the choice does not point at nothing and saving clears it.
  String? _knownBook(String? id) =>
      id != null && _listed.any((book) => book.id == id) ? id : null;

  void _chooseBook(String? value) {
    setState(() {
      _bookId = value;
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _code.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickExam() async {
    final now = DateTime.now();
    // The picker asserts that its initial date lies inside its range, so a date saved long
    // ago or far ahead widens the range instead of breaking the picker.
    final initial = _examDate ?? now;
    final earliest = DateTime(now.year - 1);
    final latest = DateTime(now.year + 3);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: initial.isBefore(earliest) ? initial : earliest,
      lastDate: initial.isAfter(latest) ? initial : latest,
    );
    if (picked == null || !mounted) return;
    setState(() => _examDate = DateTime(picked.year, picked.month, picked.day));
  }

  void _save() {
    setState(() => _tried = true);
    final title = _title.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop(StudySubjectDraft(
      title: title,
      code: _code.text.trim(),
      description: _description.text.trim(),
      examDate: _examDate,
      bookId: _bookId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final titleError = _tried && _title.text.trim().isEmpty
        ? l10n.translate('study_subject_title_required')
        : null;
    final titleKey = _isNew
        ? (widget.proposal
            ? 'study_subject_proposal_title'
            : 'study_subject_new_title')
        : 'study_subject_edit_title';
    final saveKey = _isNew && widget.proposal
        ? 'study_subject_send_proposal'
        : 'study_save';
    final exam = _examDate;
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
                  labelText: l10n.translate('study_subject_title_label'),
                  errorText: titleError,
                ),
              ),
              TextField(
                controller: _code,
                style: TextStyle(color: palette.text),
                decoration: InputDecoration(
                  labelText: l10n.translate('study_subject_code_label'),
                ),
              ),
              StudyTextField(
                controller: _description,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.translate('study_subject_description_label'),
                ),
              ),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: l10n.translate('study_session_book_label'),
                  helperText: l10n.translate('study_subject_book_hint'),
                  helperMaxLines: 3,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _bookId,
                    isExpanded: true,
                    dropdownColor: palette.sheet,
                    style: TextStyle(color: palette.text),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(l10n.translate('study_session_book_none')),
                      ),
                      for (final book in _listed)
                        DropdownMenuItem<String?>(
                          value: book.id,
                          child:
                              Text(book.title, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _chooseBook,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickExam,
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(exam == null
                        ? l10n.translate('study_subject_exam_label')
                        : localizedDateFormat('d MMM yyyy').format(exam)),
                  ),
                  if (exam != null)
                    TextButton(
                      onPressed: () => setState(() => _examDate = null),
                      child: Text(l10n.translate('study_subject_exam_clear')),
                    ),
                ],
              ),
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
