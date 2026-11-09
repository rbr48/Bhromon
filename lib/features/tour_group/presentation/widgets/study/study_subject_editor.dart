import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../domain/models/study_subject_models.dart';

/// The longest name a subject can have.
const int kStudySubjectTitleMax = 80;

/// What a member entered for a subject.
class StudySubjectDraft {
  const StudySubjectDraft({
    required this.title,
    required this.code,
    required this.description,
    required this.examDate,
  });

  final String title;
  final String code;
  final String description;
  final DateTime? examDate;
}

/// Opens the editor for a subject. [existing] is null for a new subject, and [proposal] is true
/// when a member proposes one. Returns what was saved, or null when cancelled.
Future<StudySubjectDraft?> showStudySubjectEditor(
  BuildContext context, {
  StudySubject? existing,
  bool proposal = false,
}) {
  return showModalBottomSheet<StudySubjectDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.forest.sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => StudySubjectEditor(existing: existing, proposal: proposal),
  );
}

class StudySubjectEditor extends StatefulWidget {
  const StudySubjectEditor({super.key, this.existing, this.proposal = false});

  final StudySubject? existing;

  /// Whether the member is proposing a new subject.
  final bool proposal;

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
  bool _tried = false;

  bool get _isNew => widget.existing == null;

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
    if (title.isEmpty || title.length > kStudySubjectTitleMax) return;
    Navigator.of(context).pop(StudySubjectDraft(
      title: title,
      code: _code.text.trim(),
      description: _description.text.trim(),
      examDate: _examDate,
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
                maxLength: kStudySubjectTitleMax,
                style: TextStyle(color: palette.text),
                decoration: InputDecoration(
                  labelText: l10n.translate('study_subject_title_label'),
                  errorText: titleError,
                ),
              ),
              TextField(
                controller: _code,
                maxLength: 20,
                style: TextStyle(color: palette.text),
                decoration: InputDecoration(
                  labelText: l10n.translate('study_subject_code_label'),
                ),
              ),
              TextField(
                controller: _description,
                maxLength: 300,
                minLines: 1,
                maxLines: 3,
                style: TextStyle(color: palette.text),
                decoration: InputDecoration(
                  labelText: l10n.translate('study_subject_description_label'),
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
