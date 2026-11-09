import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../domain/models/study_models.dart';
import '../../../domain/services/study_glossary_rules.dart';

import 'study_text_field.dart';
// The short dialogs of the learning tools: a quiz's title and chapter, a glossary term, and the two sides of a
// flashcard. Each returns what the member typed once it passes its checks, or null when they cancel. The caller
// saves it.

/// A quiz to write: the chapter it covers and its title.
class StudyQuizDraft {
  const StudyQuizDraft({required this.chapterId, required this.title});

  final String chapterId;
  final String title;
}

/// A glossary term to propose or add: its word, its meaning, and the chapter it belongs to, or null for the
/// whole book.
class StudyTermDraft {
  const StudyTermDraft({
    required this.term,
    required this.definition,
    this.chapterId,
  });

  final String term;
  final String definition;
  final String? chapterId;
}

/// The two sides of a flashcard the member writes by hand.
class StudyCardDraft {
  const StudyCardDraft({required this.front, required this.back});

  final String front;
  final String back;
}

/// Asks for a quiz's title and the chapter it covers. [chapters] must not be empty.
Future<StudyQuizDraft?> showStudyQuizEditor(
  BuildContext context, {
  required List<StudyChapter> chapters,
}) {
  return showDialog<StudyQuizDraft>(
    context: context,
    builder: (_) => _QuizEditor(chapters: chapters),
  );
}

/// Asks for a glossary term, its meaning and, optionally, its chapter.
Future<StudyTermDraft?> showStudyGlossaryEditor(
  BuildContext context, {
  required List<StudyChapter> chapters,
}) {
  return showDialog<StudyTermDraft>(
    context: context,
    builder: (_) => _GlossaryEditor(chapters: chapters),
  );
}

/// Asks for the two sides of a flashcard.
Future<StudyCardDraft?> showStudyFlashcardEditor(BuildContext context) {
  return showDialog<StudyCardDraft>(
    context: context,
    builder: (_) => const _FlashcardEditor(),
  );
}

/// Asks whether to remove something. Returns true only when the member confirms.
Future<bool> confirmStudyRemoval(BuildContext context) async {
  final l10n = context.l10n;
  final sure = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.translate('study_remove_item_title')),
      content: Text(l10n.translate('study_remove_item_body')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.translate('study_cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.translate('study_remove')),
        ),
      ],
    ),
  );
  return sure ?? false;
}

class _QuizEditor extends StatefulWidget {
  const _QuizEditor({required this.chapters});

  final List<StudyChapter> chapters;

  @override
  State<_QuizEditor> createState() => _QuizEditorState();
}

class _QuizEditorState extends State<_QuizEditor> {
  final _title = TextEditingController();
  late String _chapterId = widget.chapters.first.id;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = context.l10n;
    final title = _title.text.trim();
    final key = switch (title) {
      '' => 'study_quiz_title_required',
      _ => null,
    };
    if (key != null) {
      setState(() => _error = l10n.translate(key));
      return;
    }
    Navigator.of(context)
        .pop(StudyQuizDraft(chapterId: _chapterId, title: title));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.translate('study_quiz_editor_title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _chapterId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.translate('study_quiz_chapter_label'),
              ),
              items: [
                for (final chapter in widget.chapters)
                  DropdownMenuItem<String>(
                    value: chapter.id,
                    child: Text(
                      l10n.translate('study_chapter_title_line', args: {
                        'number': l10n.number(chapter.number),
                        'title': chapter.title,
                      }),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _chapterId = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: InputDecoration(
                labelText: l10n.translate('study_quiz_title_label'),
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.translate('study_cancel')),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(l10n.translate('study_save')),
        ),
      ],
    );
  }
}

class _GlossaryEditor extends StatefulWidget {
  const _GlossaryEditor({required this.chapters});

  final List<StudyChapter> chapters;

  @override
  State<_GlossaryEditor> createState() => _GlossaryEditorState();
}

class _GlossaryEditorState extends State<_GlossaryEditor> {
  final _term = TextEditingController();
  final _definition = TextEditingController();

  /// Null means the whole book.
  String? _chapterId;
  String? _error;

  @override
  void dispose() {
    _term.dispose();
    _definition.dispose();
    super.dispose();
  }

  String _problemKey(StudyTermProblem problem) => switch (problem) {
        StudyTermProblem.emptyTerm => 'study_glossary_term_required',
        StudyTermProblem.termTooLong => 'study_glossary_term_long',
        StudyTermProblem.emptyDefinition =>
          'study_glossary_definition_required',
        StudyTermProblem.definitionTooLong => 'study_glossary_definition_long',
      };

  void _save() {
    final l10n = context.l10n;
    final problem = termProblem(term: _term.text, definition: _definition.text);
    if (problem != null) {
      setState(() => _error = l10n.translate(_problemKey(problem)));
      return;
    }
    Navigator.of(context).pop(StudyTermDraft(
      term: _term.text.trim(),
      definition: _definition.text.trim(),
      chapterId: _chapterId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.translate('study_glossary_add')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _term,
              decoration: InputDecoration(
                labelText: l10n.translate('study_glossary_term_label'),
              ),
            ),
            StudyTextField(
              controller: _definition,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.translate('study_glossary_definition_label'),
              ),
            ),
            if (widget.chapters.isNotEmpty)
              DropdownButtonFormField<String?>(
                initialValue: _chapterId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.translate('study_material_chapter'),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(l10n.translate('study_material_whole_book')),
                  ),
                  for (final chapter in widget.chapters)
                    DropdownMenuItem<String?>(
                      value: chapter.id,
                      child: Text(
                        l10n.translate('study_chapter_title_line', args: {
                          'number': l10n.number(chapter.number),
                          'title': chapter.title,
                        }),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _chapterId = value),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.translate('study_cancel')),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(l10n.translate('study_save')),
        ),
      ],
    );
  }
}

class _FlashcardEditor extends StatefulWidget {
  const _FlashcardEditor();

  @override
  State<_FlashcardEditor> createState() => _FlashcardEditorState();
}

class _FlashcardEditorState extends State<_FlashcardEditor> {
  final _front = TextEditingController();
  final _back = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = context.l10n;
    final front = _front.text.trim();
    final back = _back.text.trim();
    final key = switch ((front, back)) {
      ('', _) || (_, '') => 'study_flashcard_text_required',
      _ => null,
    };
    if (key != null) {
      setState(() => _error = l10n.translate(key));
      return;
    }
    Navigator.of(context).pop(StudyCardDraft(front: front, back: back));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.translate('study_flashcard_add')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _front,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: l10n.translate('study_flashcard_front'),
              ),
            ),
            TextField(
              controller: _back,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.translate('study_flashcard_back'),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.translate('study_cancel')),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(l10n.translate('study_save')),
        ),
      ],
    );
  }
}
