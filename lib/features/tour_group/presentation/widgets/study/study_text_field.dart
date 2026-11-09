import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../domain/services/study_table_markdown.dart';
import 'study_table_editor.dart';

/// A multi-line field for study text. It takes the same settings as a [TextField], and under it a Table
/// action: with the cursor in a table, the action edits that table; anywhere else it adds a new table at the
/// cursor. The text is markdown, so a table in it renders wherever study text is shown.
class StudyTextField extends StatelessWidget {
  const StudyTextField({
    super.key,
    required this.controller,
    this.decoration,
    this.autofocus = false,
    this.minLines = 2,
    this.maxLines = 6,
    this.keyboardType,
    this.onChanged,
  });

  final TextEditingController controller;
  final InputDecoration? decoration;
  final bool autofocus;
  final int minLines;
  final int maxLines;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          autofocus: autofocus,
          minLines: minLines,
          maxLines: maxLines,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: TextStyle(color: palette.text),
          decoration: decoration,
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => _openTable(context),
            icon: const Icon(Icons.table_chart_outlined, size: 18),
            label: Text(l10n.translate('study_table_insert')),
          ),
        ),
      ],
    );
  }

  /// Edits the table the cursor is in, or adds a new one at the cursor.
  Future<void> _openTable(BuildContext context) async {
    final text = controller.text;
    final selection = controller.selection;
    final offset = selection.isValid ? selection.start : text.length;
    final existing = studyTableAt(text, offset);
    final grid = await showStudyTableEditor(
      context,
      initial: existing?.rows,
    );
    if (grid == null) return;
    final markdown = studyTableMarkdown(grid);
    final edit = existing == null
        ? replaceStudyRange(text, offset, offset, markdown)
        : replaceStudyRange(text, existing.start, existing.end, markdown);
    controller.value = TextEditingValue(
      text: edit.text,
      selection: TextSelection.collapsed(offset: edit.cursor),
    );
    onChanged?.call(edit.text);
  }
}
