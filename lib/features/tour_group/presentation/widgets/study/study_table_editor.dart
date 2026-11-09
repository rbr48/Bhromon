import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../domain/services/study_table_markdown.dart';

/// Opens the table editor on [initial] (a new two-column table when null). Returns the grid to save, or null
/// when cancelled. The first row is the header.
Future<List<List<String>>?> showStudyTableEditor(
  BuildContext context, {
  List<List<String>>? initial,
}) {
  return showModalBottomSheet<List<List<String>>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.forest.sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => StudyTableEditor(initial: initial),
  );
}

/// Edits a table as a grid of cells. Rows and columns are added and removed at the end. There is no limit on
/// the length of a cell.
class StudyTableEditor extends StatefulWidget {
  const StudyTableEditor({super.key, this.initial});

  final List<List<String>>? initial;

  @override
  State<StudyTableEditor> createState() => _StudyTableEditorState();
}

class _StudyTableEditorState extends State<StudyTableEditor> {
  late final List<List<TextEditingController>> _cells = [
    for (final row in widget.initial ?? newStudyTable())
      [for (final cell in row) TextEditingController(text: cell)],
  ];
  bool _tried = false;

  int get _columns => _cells.first.length;

  @override
  void dispose() {
    for (final row in _cells) {
      for (final cell in row) {
        cell.dispose();
      }
    }
    super.dispose();
  }

  void _addRow() {
    setState(() => _cells.add([
          for (var i = 0; i < _columns; i++) TextEditingController(),
        ]));
  }

  void _addColumn() {
    setState(() {
      for (final row in _cells) {
        row.add(TextEditingController());
      }
    });
  }

  /// Removes the last body row. The header always stays.
  void _removeRow() {
    if (_cells.length <= 1) return;
    setState(() {
      for (final cell in _cells.removeLast()) {
        cell.dispose();
      }
    });
  }

  /// Removes the last column. A table keeps at least one.
  void _removeColumn() {
    if (_columns <= 1) return;
    setState(() {
      for (final row in _cells) {
        row.removeLast().dispose();
      }
    });
  }

  List<List<String>> get _grid => [
        for (final row in _cells) [for (final cell in row) cell.text.trim()],
      ];

  void _save() {
    setState(() => _tried = true);
    final anyText = _grid.any((row) => row.any((cell) => cell.isNotEmpty));
    if (!anyText) return;
    Navigator.of(context).pop(_grid);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final isNew = widget.initial == null;
    final emptyError =
        _tried && !_grid.any((row) => row.any((c) => c.isNotEmpty))
            ? l10n.translate('study_table_empty')
            : null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.translate(
                  isNew ? 'study_table_new_title' : 'study_table_edit_title'),
              style: TextStyle(
                  color: palette.text,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var r = 0; r < _cells.length; r++)
                        Row(
                          children: [
                            for (var c = 0; c < _columns; c++)
                              _cell(r, c, palette, l10n),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (emptyError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(emptyError,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(l10n.translate('study_table_add_row')),
                ),
                OutlinedButton.icon(
                  onPressed: _addColumn,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(l10n.translate('study_table_add_column')),
                ),
                OutlinedButton.icon(
                  onPressed: _cells.length > 1 ? _removeRow : null,
                  icon: const Icon(Icons.remove_rounded, size: 18),
                  label: Text(l10n.translate('study_table_remove_row')),
                ),
                OutlinedButton.icon(
                  onPressed: _columns > 1 ? _removeColumn : null,
                  icon: const Icon(Icons.remove_rounded, size: 18),
                  label: Text(l10n.translate('study_table_remove_column')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.translate('study_cancel')),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _save,
                  child: Text(l10n.translate('study_save')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(
      int row, int column, ForestPalette palette, AppLocalizations l10n) {
    final isHeader = row == 0;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(3),
      child: TextField(
        controller: _cells[row][column],
        maxLines: null,
        style: TextStyle(
          color: palette.text,
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText:
              isHeader ? l10n.translate('study_table_heading_hint') : null,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
