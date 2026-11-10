import 'package:flutter/material.dart';
import 'study_modal.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../domain/models/study_assignment_models.dart';

import 'study_text_field.dart';

/// What a member entered for an assignment.
class StudyAssignmentDraft {
  const StudyAssignmentDraft({
    required this.title,
    required this.details,
    required this.url,
    required this.dueAt,
  });

  final String title;
  final String details;

  /// The link, which is empty or an https address.
  final String url;

  /// The day it is due, on the date only, or null for none.
  final DateTime? dueAt;
}

/// Opens the editor for an assignment. [existing] is null for a new one. Returns what was saved,
/// or null when cancelled.
Future<StudyAssignmentDraft?> showStudyAssignmentEditor(
  BuildContext context, {
  StudyAssignment? existing,
}) {
  return showStudyModal<StudyAssignmentDraft>(
    context: context,
    builder: (_) => StudyAssignmentEditor(existing: existing),
  );
}

class StudyAssignmentEditor extends StatefulWidget {
  const StudyAssignmentEditor({super.key, this.existing});

  final StudyAssignment? existing;

  @override
  State<StudyAssignmentEditor> createState() => _StudyAssignmentEditorState();
}

class _StudyAssignmentEditorState extends State<StudyAssignmentEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _details =
      TextEditingController(text: widget.existing?.details ?? '');
  late final TextEditingController _url =
      TextEditingController(text: widget.existing?.url ?? '');
  late DateTime? _dueAt = widget.existing?.dueAt;
  bool _tried = false;

  bool get _isNew => widget.existing == null;

  /// A link is empty, or an https address.
  bool get _urlOk {
    final text = _url.text.trim();
    if (text.isEmpty) return true;
    final uri = Uri.tryParse(text);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    // The picker asserts that its initial date lies inside its range, so a day saved long ago or
    // far ahead widens the range instead of breaking the picker.
    final initial = _dueAt ?? now;
    final earliest = DateTime(now.year - 1);
    final latest = DateTime(now.year + 3);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: initial.isBefore(earliest) ? initial : earliest,
      lastDate: initial.isAfter(latest) ? initial : latest,
    );
    if (picked == null || !mounted) return;
    setState(() => _dueAt = DateTime(picked.year, picked.month, picked.day));
  }

  void _save() {
    setState(() => _tried = true);
    if (_title.text.trim().isEmpty || !_urlOk) return;
    Navigator.of(context).pop(StudyAssignmentDraft(
      title: _title.text.trim(),
      details: _details.text.trim(),
      url: _url.text.trim(),
      dueAt: _dueAt,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final titleError = _tried && _title.text.trim().isEmpty
        ? l10n.translate('study_assignment_title_required')
        : null;
    final urlError =
        _tried && !_urlOk ? l10n.translate('study_post_url_invalid') : null;
    final titleKey =
        _isNew ? 'study_assignment_new_title' : 'study_assignment_edit_title';
    final due = _dueAt;
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
                  labelText: l10n.translate('study_assignment_title_label'),
                  errorText: titleError,
                ),
              ),
              StudyTextField(
                controller: _details,
                minLines: 2,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: l10n.translate('study_assignment_details_label'),
                ),
              ),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                style: TextStyle(color: palette.text),
                decoration: InputDecoration(
                  labelText: l10n.translate('study_post_url_label'),
                  errorText: urlError,
                ),
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
                        ? l10n.translate('study_assignment_due_label')
                        : localizedDateFormat('d MMM yyyy').format(due)),
                  ),
                  if (due != null)
                    TextButton(
                      onPressed: () => setState(() => _dueAt = null),
                      child: Text(l10n.translate('study_subject_exam_clear')),
                    ),
                ],
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
