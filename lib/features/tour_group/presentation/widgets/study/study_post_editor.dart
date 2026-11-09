import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../domain/models/study_subject_models.dart';

/// What a member entered for a post.
class StudyPostDraft {
  const StudyPostDraft({
    required this.text,
    required this.title,
    required this.url,
  });

  final String text;
  final String title;
  final String url;
}

/// Opens the editor for a post. [withLink] is true for a suggestion, which can carry a title
/// and a link. [existing] is null for a new post. Returns what was saved, or null when
/// cancelled.
Future<StudyPostDraft?> showStudyPostEditor(
  BuildContext context, {
  required bool withLink,
  StudyPost? existing,
}) {
  return showModalBottomSheet<StudyPostDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.forest.sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => StudyPostEditor(withLink: withLink, existing: existing),
  );
}

class StudyPostEditor extends StatefulWidget {
  const StudyPostEditor({super.key, required this.withLink, this.existing});

  final bool withLink;
  final StudyPost? existing;

  @override
  State<StudyPostEditor> createState() => _StudyPostEditorState();
}

class _StudyPostEditorState extends State<StudyPostEditor> {
  late final TextEditingController _text =
      TextEditingController(text: widget.existing?.text ?? '');
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _url =
      TextEditingController(text: widget.existing?.url ?? '');
  bool _tried = false;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _text.dispose();
    _title.dispose();
    _url.dispose();
    super.dispose();
  }

  /// A link is optional, and when it is given it must be https.
  bool get _urlOk {
    final url = _url.text.trim();
    return url.isEmpty || url.startsWith('https://');
  }

  void _save() {
    setState(() => _tried = true);
    if (_text.text.trim().isEmpty || !_urlOk) return;
    Navigator.of(context).pop(StudyPostDraft(
      text: _text.text.trim(),
      title: _title.text.trim(),
      url: _url.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final textError = _tried && _text.text.trim().isEmpty
        ? l10n.translate('study_post_text_required')
        : null;
    final urlError =
        _tried && !_urlOk ? l10n.translate('study_post_url_invalid') : null;
    final titleKey = widget.withLink
        ? (_isNew ? 'study_post_add_suggestion' : 'study_post_edit_title')
        : (_isNew ? 'study_post_add_tip' : 'study_post_edit_title');
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
              if (widget.withLink)
                TextField(
                  controller: _title,
                  maxLength: 120,
                  style: TextStyle(color: palette.text),
                  decoration: InputDecoration(
                    labelText: l10n.translate('study_post_title_label'),
                  ),
                ),
              TextField(
                controller: _text,
                autofocus: _isNew,
                maxLength: 1000,
                minLines: 2,
                maxLines: 6,
                style: TextStyle(color: palette.text),
                decoration: InputDecoration(
                  labelText: l10n.translate(widget.withLink
                      ? 'study_post_text_label_suggestion'
                      : 'study_post_text_label_tip'),
                  errorText: textError,
                ),
              ),
              if (widget.withLink)
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  style: TextStyle(color: palette.text),
                  decoration: InputDecoration(
                    labelText: l10n.translate('study_post_url_label'),
                    errorText: urlError,
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
