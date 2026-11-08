import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../domain/models/study_models.dart';
import '../../../domain/services/study_rules.dart';

/// What a member entered for a reading session.
class ReadingSessionDraft {
  const ReadingSessionDraft({
    required this.title,
    required this.startsAt,
    required this.bookId,
    required this.place,
    required this.notes,
  });

  final String title;
  final DateTime startsAt;
  final String? bookId;
  final String place;
  final String notes;
}

/// Opens the editor for a session. [books] fills the book choice. [existing] is null for a
/// new session. Returns what the member saved, or null when they cancel.
Future<ReadingSessionDraft?> showReadingSessionEditor(
  BuildContext context, {
  required List<StudyBook> books,
  ReadingSession? existing,
}) {
  return showModalBottomSheet<ReadingSessionDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.forest.sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ReadingSessionEditor(books: books, existing: existing),
  );
}

class ReadingSessionEditor extends StatefulWidget {
  const ReadingSessionEditor({super.key, required this.books, this.existing});

  final List<StudyBook> books;
  final ReadingSession? existing;

  @override
  State<ReadingSessionEditor> createState() => _ReadingSessionEditorState();
}

class _ReadingSessionEditorState extends State<ReadingSessionEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _place =
      TextEditingController(text: widget.existing?.place ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');
  late String? _bookId = _knownBook(widget.existing?.bookId);
  late DateTime _startsAt = widget.existing?.startsAt ?? _defaultStart();
  bool _tried = false;

  /// The book of an existing session, when the list still has it. A book removed since
  /// then is left out, so the choice does not point at nothing.
  String? _knownBook(String? id) =>
      id != null && widget.books.any((b) => b.id == id) ? id : null;

  static DateTime _defaultStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 7, 18);
  }

  @override
  void dispose() {
    _title.dispose();
    _place.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    setState(() => _startsAt = DateTime(picked.year, picked.month, picked.day,
        _startsAt.hour, _startsAt.minute));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt),
    );
    if (picked == null) return;
    setState(() => _startsAt = DateTime(_startsAt.year, _startsAt.month,
        _startsAt.day, picked.hour, picked.minute));
  }

  void _save() {
    setState(() => _tried = true);
    if (!isValidStudyTitle(_title.text)) return;
    Navigator.of(context).pop(ReadingSessionDraft(
      title: _title.text.trim(),
      startsAt: _startsAt,
      bookId: _bookId,
      place: _place.text.trim(),
      notes: _notes.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final titleError = _tried && !isValidStudyTitle(_title.text)
        ? l10n.translate('study_session_title_required')
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
                l10n.translate(widget.existing == null
                    ? 'study_session_new_title'
                    : 'study_session_edit_title'),
                style: TextStyle(
                    color: palette.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                autofocus: widget.existing == null,
                maxLength: kStudyTitleMax,
                style: TextStyle(color: palette.text),
                decoration: InputDecoration(
                  labelText: l10n.translate('study_session_title_label'),
                  errorText: titleError,
                ),
              ),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: l10n.translate('study_session_book_label'),
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
                      for (final book in widget.books)
                        DropdownMenuItem<String?>(
                          value: book.id,
                          child:
                              Text(book.title, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (value) => setState(() => _bookId = value),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.translate('study_session_when_label'),
                style: TextStyle(color: palette.text70),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: Text(
                        localizedDateFormat('d MMM yyyy').format(_startsAt)),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule_rounded, size: 18),
                    label:
                        Text(localizedDateFormat('h:mm a').format(_startsAt)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _place,
                maxLength: 120,
                style: TextStyle(color: palette.text),
                decoration: InputDecoration(
                  labelText: l10n.translate('study_session_place_label'),
                ),
              ),
              TextField(
                controller: _notes,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                style: TextStyle(color: palette.text),
                decoration: InputDecoration(
                  labelText: l10n.translate('study_session_notes_label'),
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
