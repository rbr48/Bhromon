import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../tour_group/domain/services/chat_markdown.dart';

/// A bottom sheet modal for visually building and configuring a Markdown table.
///
/// Returns the generated Markdown table [String] when confirmed, or `null` if cancelled.
class TableBuilderSheet extends StatefulWidget {
  final ValueChanged<String>? onInsert;

  const TableBuilderSheet({super.key, this.onInsert});

  /// Displays the table builder modal bottom sheet.
  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const TableBuilderSheet(),
    );
  }

  @override
  State<TableBuilderSheet> createState() => _TableBuilderSheetState();
}

class _TableBuilderSheetState extends State<TableBuilderSheet> {
  int _columns = 3;
  int _rows = 2;

  late List<TextEditingController> _headerControllers;
  late List<ChatTableAlign> _alignments;
  late List<List<TextEditingController>> _cellControllers;

  @override
  void initState() {
    super.initState();
    _initGrid();
  }

  void _initGrid() {
    _headerControllers = List.generate(
      _columns,
      (i) => TextEditingController(text: 'Col ${i + 1}'),
    );
    _alignments = List.generate(_columns, (_) => ChatTableAlign.left);
    _cellControllers = List.generate(
      _rows,
      (_) => List.generate(_columns, (_) => TextEditingController()),
    );
  }

  void _updateColumns(int newCols) {
    if (newCols < 2 || newCols > 6) return;
    setState(() {
      if (newCols > _columns) {
        for (var c = _columns; c < newCols; c++) {
          _headerControllers.add(TextEditingController(text: 'Col ${c + 1}'));
          _alignments.add(ChatTableAlign.left);
          for (var r = 0; r < _rows; r++) {
            _cellControllers[r].add(TextEditingController());
          }
        }
      } else {
        for (var c = _columns - 1; c >= newCols; c--) {
          _headerControllers[c].dispose();
          _headerControllers.removeAt(c);
          _alignments.removeAt(c);
          for (var r = 0; r < _rows; r++) {
            _cellControllers[r][c].dispose();
            _cellControllers[r].removeAt(c);
          }
        }
      }
      _columns = newCols;
    });
  }

  void _updateRows(int newRows) {
    if (newRows < 1 || newRows > 10) return;
    setState(() {
      if (newRows > _rows) {
        for (var r = _rows; r < newRows; r++) {
          _cellControllers.add(
            List.generate(_columns, (_) => TextEditingController()),
          );
        }
      } else {
        for (var r = _rows - 1; r >= newRows; r--) {
          for (var c = 0; c < _columns; c++) {
            _cellControllers[r][c].dispose();
          }
          _cellControllers.removeAt(r);
        }
      }
      _rows = newRows;
    });
  }

  @override
  void dispose() {
    for (final c in _headerControllers) {
      c.dispose();
    }
    for (final row in _cellControllers) {
      for (final c in row) {
        c.dispose();
      }
    }
    super.dispose();
  }

  String _generateMarkdown() {
    final buffer = StringBuffer();

    // Headers
    buffer.write('|');
    for (var c = 0; c < _columns; c++) {
      final text = _headerControllers[c].text.trim().replaceAll('|', '/');
      buffer.write(' ${text.isEmpty ? "Col ${c + 1}" : text} |');
    }
    buffer.writeln();

    // Delimiters with alignment
    buffer.write('|');
    for (var c = 0; c < _columns; c++) {
      switch (_alignments[c]) {
        case ChatTableAlign.left:
          buffer.write(' :--- |');
          break;
        case ChatTableAlign.center:
          buffer.write(' :---: |');
          break;
        case ChatTableAlign.right:
          buffer.write(' ---: |');
          break;
      }
    }
    buffer.writeln();

    // Rows
    for (var r = 0; r < _rows; r++) {
      buffer.write('|');
      for (var c = 0; c < _columns; c++) {
        final text = _cellControllers[r][c].text.trim().replaceAll('|', '/');
        buffer.write(' ${text.isEmpty ? "-" : text} |');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF16231B) : Colors.white;
    final textStyle = TextStyle(color: context.forest.text);

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.forest.divider12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.table_chart_rounded,
                        color: AppColors.mintGreen, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      l10n.translate('table_builder_title'),
                      style: textStyle.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  color: context.forest.text70,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Stepper Controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: _stepper(
                    label: l10n.translate('table_builder_columns'),
                    value: _columns,
                    min: 2,
                    max: 6,
                    onChanged: _updateColumns,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _stepper(
                    label: l10n.translate('table_builder_rows'),
                    value: _rows,
                    min: 1,
                    max: 10,
                    onChanged: _updateRows,
                  ),
                ),
              ],
            ),
          ),

          // Grid Input Table
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Headers row
                    Row(
                      children: [
                        for (var c = 0; c < _columns; c++)
                          Container(
                            width: 130,
                            margin: const EdgeInsets.only(right: 8, bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  controller: _headerControllers[c],
                                  style: textStyle.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                  decoration: InputDecoration(
                                    labelText:
                                        '${l10n.translate('table_builder_header')} ${c + 1}',
                                    labelStyle: TextStyle(
                                      color: context.forest.text54,
                                      fontSize: 12,
                                    ),
                                    isDense: true,
                                    filled: true,
                                    fillColor: AppColors.midGreen
                                        .withValues(alpha: 0.15),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: AppColors.mintGreen
                                            .withValues(alpha: 0.3),
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                // Alignment selector
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _alignButton(c, ChatTableAlign.left,
                                        Icons.format_align_left_rounded),
                                    _alignButton(c, ChatTableAlign.center,
                                        Icons.format_align_center_rounded),
                                    _alignButton(c, ChatTableAlign.right,
                                        Icons.format_align_right_rounded),
                                  ],
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Cells rows
                    for (var r = 0; r < _rows; r++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            for (var c = 0; c < _columns; c++)
                              Container(
                                width: 130,
                                margin: const EdgeInsets.only(right: 8),
                                child: TextField(
                                  controller: _cellControllers[r][c],
                                  style: textStyle.copyWith(fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText:
                                        '${l10n.translate('table_builder_cell')} ${r + 1},${c + 1}',
                                    hintStyle: TextStyle(
                                      color: context.forest.text38,
                                      fontSize: 12,
                                    ),
                                    isDense: true,
                                    filled: true,
                                    fillColor: context.forest.inset26,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Insert Table CTA Button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.darkGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
              label: Text(
                l10n.translate('table_builder_insert'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: () {
                final md = _generateMarkdown();
                widget.onInsert?.call(md);
                Navigator.of(context).pop(md);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _alignButton(int col, ChatTableAlign align, IconData icon) {
    final selected = _alignments[col] == align;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () {
        setState(() => _alignments[col] = align);
      },
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.mintGreen.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          size: 15,
          color: selected ? AppColors.mintGreen : context.forest.text54,
        ),
      ),
    );
  }

  Widget _stepper({
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.forest.inset26,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: context.forest.text70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Icon(Icons.remove_circle_outline_rounded),
                color: value > min
                    ? context.forest.accentText
                    : context.forest.text38,
                onPressed: value > min ? () => onChanged(value - 1) : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '$value',
                  style: TextStyle(
                    color: context.forest.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Icon(Icons.add_circle_outline_rounded),
                color: value < max
                    ? context.forest.accentText
                    : context.forest.text38,
                onPressed: value < max ? () => onChanged(value + 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
