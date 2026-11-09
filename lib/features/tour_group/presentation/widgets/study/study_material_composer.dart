import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../domain/models/study_material_models.dart';
import '../../../domain/models/study_models.dart';
import '../../../domain/services/media_rules.dart';
import '../../../domain/services/study_material_rules.dart';

/// A material as the member filed it in the composer: its kind, title and chapter, with the file picked,
/// the link or the note's text. The screen uploads the file and saves the material.
class StudyMaterialDraft {
  const StudyMaterialDraft({
    required this.kind,
    required this.title,
    this.chapterId,
    this.url,
    this.body,
    this.file,
    this.fileName,
    this.sizeBytes,
    this.contentType,
  });

  final StudyMaterialKind kind;
  final String title;
  final String? chapterId;

  /// The address of a link. Null for the other kinds.
  final String? url;

  /// The text of a note. Null for the other kinds.
  final String? body;

  /// The picked file for a file kind, to upload. Null for a link or a note.
  final XFile? file;
  final String? fileName;
  final int? sizeBytes;
  final String? contentType;
}

/// Shows the composer for a material and returns what the member filed, or null when they cancelled.
Future<StudyMaterialDraft?> showStudyMaterialComposer(
  BuildContext context, {
  required List<StudyChapter> chapters,
}) {
  return showModalBottomSheet<StudyMaterialDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _StudyMaterialComposer(chapters: chapters),
  );
}

class _StudyMaterialComposer extends StatefulWidget {
  const _StudyMaterialComposer({required this.chapters});

  final List<StudyChapter> chapters;

  @override
  State<_StudyMaterialComposer> createState() => _StudyMaterialComposerState();
}

class _StudyMaterialComposerState extends State<_StudyMaterialComposer> {
  final _title = TextEditingController();
  final _link = TextEditingController();
  final _note = TextEditingController();

  StudyMaterialKind _kind = StudyMaterialKind.note;
  String? _chapterId;
  bool _rights = false;
  PlatformFile? _picked;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _link.dispose();
    _note.dispose();
    super.dispose();
  }

  void _chooseKind(StudyMaterialKind kind) {
    setState(() {
      _kind = kind;
      _error = null;
      if (!kind.isUpload) _picked = null;
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: studyMaterialExtensions(_kind),
      withData: kIsWeb,
    );
    final picked =
        result != null && result.files.isNotEmpty ? result.files.first : null;
    if (picked == null || !mounted) return;
    final problem = studyFileProblem(
      kind: _kind,
      fileName: picked.name,
      sizeBytes: picked.size,
    );
    setState(() {
      _picked = problem == null ? picked : null;
      _error = switch (problem) {
        null => null,
        StudyFileProblem.unsupported => 'study_material_file_unsupported',
        StudyFileProblem.empty => 'study_material_file_empty',
        StudyFileProblem.tooLarge => 'study_material_file_too_large',
      };
    });
  }

  XFile _toXFile(PlatformFile picked) {
    final mime = studyContentType(picked.name);
    final bytes = picked.bytes;
    if (bytes != null) {
      return XFile.fromData(bytes, name: picked.name, mimeType: mime);
    }
    return XFile(picked.path!, name: picked.name, mimeType: mime);
  }

  void _submit() {
    final title = _title.text.trim();
    final error = switch (_kind) {
      _ when title.isEmpty => 'study_material_title_required',
      _ when _kind.isUpload && _picked == null =>
        'study_material_file_required',
      StudyMaterialKind.link when !isStudyLinkValid(_link.text) =>
        'study_material_link_invalid',
      StudyMaterialKind.note when _note.text.trim().isEmpty =>
        'study_material_note_required',
      _ when !_rights => 'study_material_rights_required',
      _ => null,
    };
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final picked = _picked;
    Navigator.of(context).pop(StudyMaterialDraft(
      kind: _kind,
      title: title,
      chapterId: _chapterId,
      url: _kind == StudyMaterialKind.link ? _link.text.trim() : null,
      body: _kind == StudyMaterialKind.note ? _note.text.trim() : null,
      file: picked == null ? null : _toXFile(picked),
      fileName: picked?.name,
      sizeBytes: picked?.size,
      contentType: picked == null ? null : studyContentType(picked.name),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.translate('study_material_add'),
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final kind in StudyMaterialKind.values)
                ChoiceChip(
                  label:
                      Text(l10n.translate('study_material_kind_${kind.name}')),
                  selected: _kind == kind,
                  onSelected: (_) => _chooseKind(kind),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              maxLength: StudyMaterial.titleMax,
              decoration: InputDecoration(
                labelText: l10n.translate('study_material_title_label'),
              ),
            ),
            if (widget.chapters.isNotEmpty)
              DropdownButtonFormField<String?>(
                initialValue: _chapterId,
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
                          '${l10n.number(chapter.number)}. ${chapter.title}'),
                    ),
                ],
                onChanged: (value) => setState(() => _chapterId = value),
              ),
            const SizedBox(height: 8),
            ..._kindFields(context),
            CheckboxListTile(
              value: _rights,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.translate('study_material_rights')),
              onChanged: (value) => setState(() => _rights = value ?? false),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l10n.translate(_error!),
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            FilledButton(
              onPressed: _submit,
              child: Text(l10n.translate('study_material_submit')),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _kindFields(BuildContext context) {
    final l10n = context.l10n;
    if (_kind.isUpload) {
      final picked = _picked;
      return [
        OutlinedButton.icon(
          onPressed: _pickFile,
          icon: const Icon(Icons.attach_file_rounded),
          label: Text(picked == null
              ? l10n.translate('study_material_choose_file')
              : picked.name),
        ),
        if (picked != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              formatMegabytes(picked.size),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ];
    }
    if (_kind == StudyMaterialKind.link) {
      return [
        TextField(
          controller: _link,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: l10n.translate('study_material_link_label'),
            hintText: 'https://',
          ),
        ),
      ];
    }
    return [
      TextField(
        controller: _note,
        minLines: 4,
        maxLines: 10,
        maxLength: StudyMaterial.noteMax,
        decoration: InputDecoration(
          labelText: l10n.translate('study_material_note_label'),
          alignLabelWithHint: true,
        ),
      ),
    ];
  }
}
