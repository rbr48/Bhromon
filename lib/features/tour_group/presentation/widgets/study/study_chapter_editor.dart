import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../domain/models/study_models.dart';
import '../../../domain/services/study_chapter_rules.dart';

/// What an admin entered for a chapter.
class StudyChapterDraft {
  const StudyChapterDraft({
    required this.number,
    required this.title,
    this.pageFrom,
    this.pageTo,
    this.dueOn,
    this.guide = const [],
  });

  final int number;
  final String title;
  final int? pageFrom;
  final int? pageTo;
  final DateTime? dueOn;
  final List<String> guide;
}

/// Opens the chapter editor. [existing] is null for a new chapter, which gets
/// [suggestedNumber]. Returns what was saved, or null when cancelled.
Future<StudyChapterDraft?> showStudyChapterEditor(
  BuildContext context, {
  StudyChapter? existing,
  int suggestedNumber = 1,
}) {
  return showModalBottomSheet<StudyChapterDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.forest.sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => StudyChapterEditor(
      existing: existing,
      suggestedNumber: suggestedNumber,
    ),
  );
}

class StudyChapterEditor extends StatefulWidget {
  const StudyChapterEditor({
    super.key,
    this.existing,
    this.suggestedNumber = 1,
  });

  final StudyChapter? existing;
  final int suggestedNumber;

  @override
  State<StudyChapterEditor> createState() => _StudyChapterEditorState();
}

class _StudyChapterEditorState extends State<StudyChapterEditor> {
  late final TextEditingController _number = TextEditingController(
      text: '${widget.existing?.number ?? widget.suggestedNumber}');
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _from =
      TextEditingController(text: widget.existing?.pageFrom?.toString() ?? '');
  late final TextEditingController _to =
      TextEditingController(text: widget.existing?.pageTo?.toString() ?? '');
  late DateTime? _dueOn = widget.existing?.dueOn;
  late final List<TextEditingController> _guide = [
    for (final question in widget.existing?.guide ?? const <String>[])
      TextEditingController(text: question),
  ];
  bool _tried = false;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _number.dispose();
    _title.dispose();
    _from.dispose();
    _to.dispose();
    for (final controller in _guide) {
      controller.dispose();
    }
    super.dispose();
  }

  /// The number typed, or null when it is not a whole number.
  int? get _numberValue => int.tryParse(_number.text.trim());

  bool get _numberOk {
    final n = _numberValue;
    return n != null && validChapterNumber(n);
  }

  bool get _titleOk {
    final title = _title.text.trim();
    return title.isNotEmpty;
  }

  /// A page is blank, or a whole number. The pair is checked with the rule for pages.
  bool get _pagesOk {
    final fromText = _from.text.trim();
    final toText = _to.text.trim();
    final from = fromText.isEmpty ? null : int.tryParse(fromText);
    final to = toText.isEmpty ? null : int.tryParse(toText);
    if (fromText.isNotEmpty && from == null) return false;
    if (toText.isNotEmpty && to == null) return false;
    return validPageRange(from, to);
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final initial = _dueOn ?? now;
    final earliest = DateTime(now.year - 2);
    final latest = DateTime(now.year + 5);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      // The picker asserts that its initial date is in range, so a saved date widens it.
      firstDate: initial.isBefore(earliest) ? initial : earliest,
      lastDate: initial.isAfter(latest) ? initial : latest,
    );
    if (picked == null || !mounted) return;
    setState(() => _dueOn = DateTime(picked.year, picked.month, picked.day));
  }

  void _save() {
    setState(() => _tried = true);
    if (!_numberOk || !_titleOk || !_pagesOk) return;
    final fromText = _from.text.trim();
    final toText = _to.text.trim();
    Navigator.of(context).pop(StudyChapterDraft(
      number: _numberValue!,
      title: _title.text.trim(),
      pageFrom: fromText.isEmpty ? null : int.tryParse(fromText),
      pageTo: toText.isEmpty ? null : int.tryParse(toText),
      dueOn: _dueOn,
      guide: cleanGuideQuestions(_guide.map((c) => c.text)),
    ));
  }

  void _addQuestion() {
    if (_guide.length >= StudyChapter.guideMax) return;
    setState(() => _guide.add(TextEditingController()));
  }

  void _removeQuestion(int index) {
    final controller = _guide.removeAt(index);
    setState(() {});
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final numberError = _tried && !_numberOk
        ? l10n.translate('study_chapter_number_invalid')
        : null;
    final titleError = _tried && !_titleOk
        ? l10n.translate('study_chapter_title_required')
        : null;
    final pagesError = _tried && !_pagesOk
        ? l10n.translate('study_chapter_pages_invalid')
        : null;
    final due = _dueOn;
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
                l10n.translate(_isNew
                    ? 'study_chapter_new_title'
                    : 'study_chapter_edit_title'),
                style: TextStyle(
                    color: palette.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _number,
                keyboardType: TextInputType.number,
                style: TextStyle(color: palette.text),
                decoration: InputDecoration(
                  labelText: l10n.translate('study_chapter_number_label'),
                  errorText: numberError,
                ),
              ),
              TextField(
                controller: _title,
                autofocus: _isNew,
                style: TextStyle(color: palette.text),
                decoration: InputDecoration(
                  labelText: l10n.translate('study_chapter_title_label'),
                  errorText: titleError,
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _from,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: palette.text),
                      decoration: InputDecoration(
                        labelText:
                            l10n.translate('study_chapter_pages_from_label'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _to,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: palette.text),
                      decoration: InputDecoration(
                        labelText:
                            l10n.translate('study_chapter_pages_to_label'),
                        errorText: pagesError,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickDue,
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(due == null
                        ? l10n.translate('study_chapter_due_label')
                        : localizedDateFormat('d MMM yyyy').format(due)),
                  ),
                  if (due != null)
                    TextButton(
                      onPressed: () => setState(() => _dueOn = null),
                      child: Text(l10n.translate('study_chapter_due_clear')),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                l10n.translate('study_chapter_guide_label'),
                style: TextStyle(color: palette.text70),
              ),
              const SizedBox(height: 6),
              for (var i = 0; i < _guide.length; i++)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _guide[i],
                        style: TextStyle(color: palette.text),
                        decoration: InputDecoration(
                          labelText: l10n.translate('study_chapter_guide_hint'),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.translate('study_chapter_guide_remove'),
                      icon: Icon(Icons.close_rounded, color: palette.text54),
                      onPressed: () => _removeQuestion(i),
                    ),
                  ],
                ),
              if (_guide.length < StudyChapter.guideMax)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addQuestion,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(l10n.translate('study_chapter_guide_add')),
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
