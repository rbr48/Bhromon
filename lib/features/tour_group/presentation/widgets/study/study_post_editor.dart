import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'study_modal.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../../../core/utils/app_logger.dart';
import '../../../data/tour_media_uploader.dart';
import '../../../domain/models/study_material_models.dart';
import '../../../domain/models/study_subject_models.dart';
import '../../../domain/services/media_rules.dart';
import '../../../domain/services/study_material_rules.dart';

import 'study_text_field.dart';

/// What a member entered for a post.
class StudyPostDraft {
  const StudyPostDraft({
    required this.text,
    required this.title,
    required this.url,
    this.upload,
  });

  final String text;
  final String title;
  final String url;

  /// The file a past paper was attached as, already uploaded. The screen commits it once the paper is saved, and
  /// discards it when saving fails. Null when no file was attached.
  final TourMediaUpload? upload;
}

/// Opens the editor for a post. [withLink] is true for a suggestion or a past paper, which can
/// carry a title and a link. [paper] names the post a past paper, so its words are the paper's.
/// [chart] names a post that draws a chart: it has a title, and its text is the chart and what
/// it shows. [existing] is null for a new post. Returns what was saved, or null when cancelled.
Future<StudyPostDraft?> showStudyPostEditor(
  BuildContext context, {
  required bool withLink,
  StudyPost? existing,
  bool paper = false,
  bool chart = false,
  String? tourId,
}) {
  return showStudyModal<StudyPostDraft>(
    context: context,
    builder: (_) => StudyPostEditor(
      withLink: withLink,
      existing: existing,
      paper: paper,
      chart: chart,
      tourId: tourId,
    ),
  );
}

class StudyPostEditor extends StatefulWidget {
  const StudyPostEditor({
    super.key,
    required this.withLink,
    this.existing,
    this.paper = false,
    this.chart = false,
    this.tourId,
  });

  final bool withLink;
  final StudyPost? existing;

  /// Whether the post is a past paper.
  final bool paper;

  /// Whether the post draws a chart: it has a title, and its text is the chart.
  final bool chart;

  /// The group the paper belongs to. A paper can be attached as a file only when it is known, since the file is
  /// stored in the group's study folder.
  final String? tourId;

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
  TourMediaUpload? _upload;
  String? _fileName;
  bool _attaching = false;
  String? _attachError;

  bool get _isNew => widget.existing == null;

  /// A past paper can take a file, when the group is known.
  bool get _canAttach => widget.paper && widget.tourId != null;

  @override
  void dispose() {
    _text.dispose();
    _title.dispose();
    _url.dispose();
    super.dispose();
  }

  /// Picks a document for the paper and uploads it to the group's study folder. Its address becomes the paper's link,
  /// and the upload is kept until the paper is saved.
  Future<void> _attach() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: studyMaterialExtensions(StudyMaterialKind.file),
      withData: kIsWeb,
    );
    final picked =
        result != null && result.files.isNotEmpty ? result.files.first : null;
    if (picked == null || !mounted) return;
    final problem = studyFileProblem(
      kind: StudyMaterialKind.file,
      fileName: picked.name,
      sizeBytes: picked.size,
    );
    if (problem != null) {
      setState(() => _attachError = switch (problem) {
            StudyFileProblem.unsupported => 'study_material_file_unsupported',
            StudyFileProblem.empty => 'study_material_file_empty',
            StudyFileProblem.tooLarge => 'study_material_file_too_large',
          });
      return;
    }
    setState(() {
      _attaching = true;
      _attachError = null;
    });
    final mime = studyContentType(picked.name);
    final bytes = picked.bytes;
    final file = bytes != null
        ? XFile.fromData(bytes, name: picked.name, mimeType: mime)
        : XFile(picked.path!, name: picked.name, mimeType: mime);
    try {
      final upload = await TourMediaUploader.start(
        tourId: widget.tourId!,
        folder: 'study',
        file: file,
        contentType: mime ?? 'application/octet-stream',
        extension: storedExtension(picked.name, 'bin'),
        maxBytes: kMaxDocBytes,
      );
      final url = await upload.finish();
      if (!mounted) {
        await upload.discard();
        return;
      }
      final previous = _upload;
      setState(() {
        _upload = upload;
        _fileName = picked.name;
        _url.text = url;
        _attaching = false;
      });
      await previous?.discard();
    } catch (error, stackTrace) {
      logWarning('A study paper file could not be attached', error, stackTrace);
      if (mounted) {
        setState(() {
          _attaching = false;
          _attachError = 'study_material_error';
        });
      }
    }
  }

  /// Takes the attached file off the paper. Its upload is discarded, so it is not kept on the server.
  Future<void> _removeFile() async {
    final upload = _upload;
    setState(() {
      _upload = null;
      _fileName = null;
      _url.clear();
    });
    await upload?.discard();
  }

  /// A link is optional, and when it is given it must be https.
  bool get _urlOk {
    final url = _url.text.trim();
    return url.isEmpty || url.startsWith('https://');
  }

  void _save() {
    setState(() => _tried = true);
    if (_text.text.trim().isEmpty || !_urlOk || _attaching) return;
    Navigator.of(context).pop(StudyPostDraft(
      text: _text.text.trim(),
      title: _title.text.trim(),
      url: _url.text.trim(),
      upload: _upload,
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
    final titleKey = widget.paper
        ? (_isNew ? 'study_paper_add' : 'study_paper_edit_title')
        : widget.chart
            ? (_isNew ? 'study_chart_add' : 'study_post_edit_title')
            : widget.withLink
                ? (_isNew
                    ? 'study_post_add_suggestion'
                    : 'study_post_edit_title')
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
              if (widget.withLink || widget.chart)
                TextField(
                  controller: _title,
                  style: TextStyle(color: palette.text),
                  decoration: InputDecoration(
                    labelText: l10n.translate(widget.paper
                        ? 'study_paper_title_label'
                        : 'study_post_title_label'),
                  ),
                ),
              StudyTextField(
                controller: _text,
                autofocus: _isNew,
                minLines: 2,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: l10n.translate(widget.paper
                      ? 'study_paper_text_label'
                      : widget.chart
                          ? 'study_chart_text_label'
                          : widget.withLink
                              ? 'study_post_text_label_suggestion'
                              : 'study_post_text_label_tip'),
                  errorText: textError,
                ),
              ),
              if (widget.chart)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    l10n.translate('study_chart_hint'),
                    style: TextStyle(color: palette.text54, fontSize: 12),
                  ),
                ),
              if (widget.withLink)
                TextField(
                  controller: _url,
                  readOnly: _upload != null,
                  keyboardType: TextInputType.url,
                  style: TextStyle(color: palette.text),
                  decoration: InputDecoration(
                    labelText: l10n.translate('study_post_url_label'),
                    errorText: urlError,
                  ),
                ),
              if (_canAttach) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _attaching
                            ? null
                            : (_upload == null ? _attach : null),
                        icon: _attaching
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.attach_file_rounded),
                        label: Text(_fileName ??
                            l10n.translate(_attaching
                                ? 'study_paper_uploading'
                                : 'study_paper_attach')),
                      ),
                    ),
                    if (_upload != null)
                      IconButton(
                        tooltip: l10n.translate('study_paper_remove_file'),
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _removeFile,
                      ),
                  ],
                ),
                if (_attachError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      l10n.translate(_attachError!),
                      style: const TextStyle(color: Colors.redAccent),
                    ),
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
