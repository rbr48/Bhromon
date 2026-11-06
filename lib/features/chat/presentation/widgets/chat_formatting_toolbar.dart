import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import 'table_builder_sheet.dart';

/// A rich text formatting toolbar for chat message composers.
///
/// Provides one-tap actions for:
/// - Inline styling: Bold (**), Italic (*), Underline (__), Strikethrough (~~), Highlight (==), Spoiler (||), Code (`)
/// - Block elements: Heading (#), Blockquote (>), Bullet list (-), Numbered list (1.), Checklist (- [ ])
/// - Structural: Divider (---), Interactive Table Builder (opens [TableBuilderSheet])
class ChatFormattingToolbar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback? onClose;

  const ChatFormattingToolbar({
    super.key,
    required this.controller,
    this.focusNode,
    this.onClose,
  });

  /// Applies inline wrapping to current selection or inserts empty paired markers.
  void _wrapSelection(String prefix, [String? suffix]) {
    final s = suffix ?? prefix;
    final text = controller.text;
    final sel = controller.selection;

    if (!sel.isValid || sel.isCollapsed) {
      final insertPos =
          (sel.isValid ? sel.start : text.length).clamp(0, text.length);
      final newText = text.replaceRange(insertPos, insertPos, '$prefix$s');
      final newOffset = (insertPos + prefix.length).clamp(0, newText.length);
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newOffset),
      );
    } else {
      final start = sel.start.clamp(0, text.length);
      final end = sel.end.clamp(0, text.length);
      final safeStart = start <= end ? start : end;
      final safeEnd = start <= end ? end : start;
      final selected = text.substring(safeStart, safeEnd);
      final newText =
          text.replaceRange(safeStart, safeEnd, '$prefix$selected$s');
      final newStart = (safeStart + prefix.length).clamp(0, newText.length);
      final newEnd = (newStart + selected.length).clamp(0, newText.length);
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: newStart,
          extentOffset: newEnd,
        ),
      );
    }
    focusNode?.requestFocus();
  }

  /// Prepends a line prefix (e.g. `# `, `> `, `- `, `- [ ] `) to the current line.
  void _prefixLine(String prefix) {
    final text = controller.text;
    final sel = controller.selection;
    final pos = (sel.isValid ? sel.start : text.length).clamp(0, text.length);

    // Find start of current line
    final lineStart = pos <= 0 ? -1 : text.lastIndexOf('\n', pos - 1);
    final insertPos =
        (lineStart == -1 ? 0 : lineStart + 1).clamp(0, text.length);

    final newText = text.replaceRange(insertPos, insertPos, prefix);
    final currentOffset =
        (sel.isValid ? sel.extentOffset : text.length).clamp(0, text.length);
    final newOffset = (currentOffset + prefix.length).clamp(0, newText.length);

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
    focusNode?.requestFocus();
  }

  /// Appends or inserts a structural block (e.g., Table or Divider).
  void _insertBlock(String block) {
    final text = controller.text;
    final sel = controller.selection;
    final pos = (sel.isValid ? sel.start : text.length).clamp(0, text.length);

    final prefixNewline =
        (pos > 0 && !text.substring(0, pos).endsWith('\n')) ? '\n' : '';
    final suffixNewline =
        (pos < text.length && !text.substring(pos).startsWith('\n'))
            ? '\n'
            : '';

    final toInsert = '$prefixNewline$block$suffixNewline';
    final newText = text.replaceRange(pos, pos, toInsert);
    final newOffset = (pos + toInsert.length).clamp(0, newText.length);

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
    focusNode?.requestFocus();
  }

  Future<void> _openTableBuilder(BuildContext context) async {
    final mdTable = await TableBuilderSheet.show(context);
    if (mdTable != null && mdTable.trim().isNotEmpty) {
      _insertBlock(mdTable.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF131F17) : const Color(0xFFF1F5F2);
    final itemColor = context.forest.text70;

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          top: BorderSide(
            color: context.forest.divider10,
            width: 1,
          ),
          bottom: BorderSide(
            color: context.forest.divider10,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  // Bold
                  _btn(
                    tooltip: l10n.translate('format_toolbar_bold'),
                    child: const Text('B',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    onTap: () => _wrapSelection('**'),
                    color: itemColor,
                  ),
                  // Italic
                  _btn(
                    tooltip: l10n.translate('format_toolbar_italic'),
                    child: const Text('I',
                        style: TextStyle(
                            fontStyle: FontStyle.italic, fontSize: 15)),
                    onTap: () => _wrapSelection('*'),
                    color: itemColor,
                  ),
                  // Underline
                  _btn(
                    tooltip: l10n.translate('format_toolbar_underline'),
                    child: const Text('U',
                        style: TextStyle(
                            decoration: TextDecoration.underline,
                            fontSize: 14)),
                    onTap: () => _wrapSelection('__'),
                    color: itemColor,
                  ),
                  // Strikethrough
                  _btn(
                    tooltip: l10n.translate('format_toolbar_strike'),
                    child: const Text('S',
                        style: TextStyle(
                            decoration: TextDecoration.lineThrough,
                            fontSize: 14)),
                    onTap: () => _wrapSelection('~~'),
                    color: itemColor,
                  ),
                  // Heading
                  _btn(
                    tooltip: l10n.translate('format_toolbar_heading'),
                    child: const Text('H',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: AppColors.mintGreen)),
                    onTap: () => _prefixLine('# '),
                    color: AppColors.mintGreen,
                  ),
                  // Highlight
                  _btn(
                    tooltip: l10n.translate('format_toolbar_highlight'),
                    icon: Icons.border_color,
                    onTap: () => _wrapSelection('=='),
                    color: AppColors.gold,
                  ),
                  // Spoiler
                  _btn(
                    tooltip: l10n.translate('format_toolbar_spoiler'),
                    child: const Text('||',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    onTap: () => _wrapSelection('||'),
                    color: itemColor,
                  ),
                  // Inline Code
                  _btn(
                    tooltip: l10n.translate('format_toolbar_code'),
                    icon: Icons.code,
                    onTap: () => _wrapSelection('`'),
                    color: itemColor,
                  ),
                  // Code Block
                  _btn(
                    tooltip: l10n.translate('format_toolbar_code_block'),
                    child: const Text('{ }',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    onTap: () => _wrapSelection('```\n', '\n```'),
                    color: itemColor,
                  ),
                  // Blockquote
                  _btn(
                    tooltip: l10n.translate('format_toolbar_quote'),
                    icon: Icons.format_quote,
                    onTap: () => _prefixLine('> '),
                    color: itemColor,
                  ),
                  // Bullet List
                  _btn(
                    tooltip: l10n.translate('format_toolbar_list'),
                    icon: Icons.format_list_bulleted,
                    onTap: () => _prefixLine('- '),
                    color: itemColor,
                  ),
                  // Numbered List
                  _btn(
                    tooltip: l10n.translate('format_toolbar_num_list'),
                    icon: Icons.format_list_numbered,
                    onTap: () => _prefixLine('1. '),
                    color: itemColor,
                  ),
                  // Checklist
                  _btn(
                    tooltip: l10n.translate('format_toolbar_task'),
                    icon: Icons.check_box,
                    onTap: () => _prefixLine('- [ ] '),
                    color: AppColors.mintGreen,
                  ),
                  // Divider
                  _btn(
                    tooltip: l10n.translate('format_toolbar_divider'),
                    icon: Icons.horizontal_rule,
                    onTap: () => _insertBlock('---'),
                    color: itemColor,
                  ),
                  // Table Builder Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.darkGreen,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.table_chart, size: 14),
                      label: Text(
                        l10n.translate('format_toolbar_table'),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => _openTableBuilder(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onClose != null) ...[
            VerticalDivider(
              width: 1,
              indent: 8,
              endIndent: 8,
              color: context.forest.divider12,
            ),
            IconButton(
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              icon: const Icon(Icons.close),
              color: context.forest.text54,
              onPressed: onClose,
            ),
          ],
        ],
      ),
    );
  }

  Widget _btn({
    required String tooltip,
    IconData? icon,
    Widget? child,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          child: icon != null
              ? Icon(icon, size: 18, color: color)
              : (child != null
                  ? DefaultTextStyle(
                      style: TextStyle(color: color),
                      child: child,
                    )
                  : const SizedBox.shrink()),
        ),
      ),
    );
  }
}
