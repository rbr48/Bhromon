import 'package:flutter/material.dart';
import 'study_modal.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../domain/models/study_models.dart';

import 'study_text_field.dart';

/// What a member entered for a new thread.
class StudyThreadDraft {
  const StudyThreadDraft({
    required this.title,
    required this.body,
    required this.pageRef,
    required this.chapterId,
  });

  final String title;
  final String body;
  final String pageRef;

  /// The chapter the thread is about, or null when it is about the whole book.
  final String? chapterId;
}

/// Opens the composer for a new thread. [chapters] fills the chapter choice. [initialTitle],
/// [initialBody] and [initialChapterId] are set when the thread starts from a guide question or
/// from the text in the discussion's chat box. Returns what the member entered, or null when they
/// cancel.
Future<StudyThreadDraft?> showStudyThreadComposer(
  BuildContext context, {
  required List<StudyChapter> chapters,
  String initialTitle = '',
  String initialBody = '',
  String? initialChapterId,
}) {
  return showStudyModal<StudyThreadDraft>(
    context: context,
    builder: (_) => StudyThreadComposer(
      chapters: chapters,
      initialTitle: initialTitle,
      initialBody: initialBody,
      initialChapterId: initialChapterId,
    ),
  );
}

class StudyThreadComposer extends StatefulWidget {
  const StudyThreadComposer({
    super.key,
    required this.chapters,
    this.initialTitle = '',
    this.initialBody = '',
    this.initialChapterId,
  });

  final List<StudyChapter> chapters;
  final String initialTitle;
  final String initialBody;
  final String? initialChapterId;

  @override
  State<StudyThreadComposer> createState() => _StudyThreadComposerState();
}

class _StudyThreadComposerState extends State<StudyThreadComposer> {
  late final TextEditingController _title =
      TextEditingController(text: widget.initialTitle);
  late final TextEditingController _body =
      TextEditingController(text: widget.initialBody);
  final TextEditingController _page = TextEditingController();
  late String? _chapterId = _knownChapter(widget.initialChapterId);
  bool _tried = false;

  /// The chapter the thread starts on, when the chapter still exists.
  String? _knownChapter(String? id) =>
      id != null && widget.chapters.any((c) => c.id == id) ? id : null;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _page.dispose();
    super.dispose();
  }

  bool get _titleOk {
    final title = _title.text.trim();
    return title.isNotEmpty;
  }

  bool get _bodyOk {
    final body = _body.text.trim();
    return body.isNotEmpty;
  }

  void _save() {
    setState(() => _tried = true);
    if (!_titleOk || !_bodyOk) return;
    Navigator.of(context).pop(StudyThreadDraft(
      title: _title.text.trim(),
      body: _body.text.trim(),
      pageRef: _page.text.trim(),
      chapterId: _chapterId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final titleError = _tried && !_titleOk
        ? l10n.translate('study_thread_title_required')
        : null;
    final bodyError = _tried && !_bodyOk
        ? l10n.translate('study_thread_body_required')
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
                l10n.translate('study_thread_new_title'),
                style: TextStyle(
                    color: palette.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                autofocus: widget.initialTitle.isEmpty,
                style: TextStyle(color: palette.text),
                decoration: InputDecoration(
                  labelText: l10n.translate('study_thread_title_label'),
                  errorText: titleError,
                ),
              ),
              StudyTextField(
                controller: _body,
                autofocus: widget.initialTitle.isNotEmpty,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: l10n.translate('study_thread_body_label'),
                  errorText: bodyError,
                ),
              ),
              TextField(
                controller: _page,
                style: TextStyle(color: palette.text),
                decoration: InputDecoration(
                  labelText: l10n.translate('study_thread_page_label'),
                  hintText: l10n.translate('study_thread_page_hint'),
                ),
              ),
              if (widget.chapters.isNotEmpty) ...[
                const SizedBox(height: 8),
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: l10n.translate('study_thread_chapter_label'),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _chapterId,
                      isExpanded: true,
                      dropdownColor: palette.sheet,
                      style: TextStyle(color: palette.text),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child:
                              Text(l10n.translate('study_thread_chapter_none')),
                        ),
                        for (final chapter in widget.chapters)
                          DropdownMenuItem<String?>(
                            value: chapter.id,
                            child: Text(
                              l10n.translate('study_chapter_chip', args: {
                                'number': l10n.number(chapter.number),
                                'title': chapter.title,
                              }),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(() => _chapterId = value),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _save,
                  child: Text(l10n.translate('study_thread_post')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
