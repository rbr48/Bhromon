import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';

/// Asks an admin for the optional note to the person who proposed a book. The note is a
/// field of this dialog, so its controller is disposed with the dialog, after the dialog
/// has gone. Pops with the trimmed note, or with nothing when the admin cancels.
class StudyDeclineDialog extends StatefulWidget {
  const StudyDeclineDialog({super.key});

  @override
  State<StudyDeclineDialog> createState() => _StudyDeclineDialogState();
}

class _StudyDeclineDialogState extends State<StudyDeclineDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.translate('study_book_decline_title')),
      content: TextField(
        controller: _note,
        maxLength: 300,
        minLines: 1,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: l10n.translate('study_book_decline_note_label'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.translate('study_cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_note.text.trim()),
          child: Text(l10n.translate('study_book_decline')),
        ),
      ],
    );
  }
}
