import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../tour_group/domain/services/chat_markdown.dart';

/// A responsive, horizontally scrollable Markdown table widget for chat messages.
///
/// Features:
/// - Rounded container with crisp, subtle borders.
/// - Themed header row with column alignments (left, center, right).
/// - Alternating row background colors (zebra striping) for readability.
/// - Rich inline spans inside cells (bold, italic, code, underline, highlight, links).
/// - Smooth horizontal scrolling for tables that exceed bubble width on mobile devices.
class ChatTableWidget extends StatefulWidget {
  final ChatTableBlock table;
  final TextStyle baseStyle;
  final Set<int> revealed;
  final ValueChanged<int> onSpoiler;
  final bool isMine;

  const ChatTableWidget({
    super.key,
    required this.table,
    required this.baseStyle,
    required this.revealed,
    required this.onSpoiler,
    this.isMine = false,
  });

  @override
  State<ChatTableWidget> createState() => _ChatTableWidgetState();
}

class _ChatTableWidgetState extends State<ChatTableWidget> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TextAlign _toTextAlign(ChatTableAlign align) {
    switch (align) {
      case ChatTableAlign.center:
        return TextAlign.center;
      case ChatTableAlign.right:
        return TextAlign.right;
      case ChatTableAlign.left:
        return TextAlign.left;
    }
  }

  Alignment _toAlignment(ChatTableAlign align) {
    switch (align) {
      case ChatTableAlign.center:
        return Alignment.center;
      case ChatTableAlign.right:
        return Alignment.centerRight;
      case ChatTableAlign.left:
        return Alignment.centerLeft;
    }
  }

  void _openLink(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
    }
  }

  InlineSpan _span(ChatSpan span, TextStyle style) {
    var textStyle = style.copyWith(
      fontWeight: span.bold ? FontWeight.bold : null,
      fontStyle: span.italic ? FontStyle.italic : null,
      decoration: TextDecoration.combine([
        if (span.strike) TextDecoration.lineThrough,
        if (span.underline || span.link != null) TextDecoration.underline,
      ]),
      fontFamily: span.code ? 'monospace' : null,
      backgroundColor: span.code
          ? Colors.black38
          : (span.highlight ? AppColors.gold.withValues(alpha: 0.35) : null),
      color: span.link != null
          ? (widget.isMine ? const Color(0xFF0D47A1) : AppColors.mintGreen)
          : null,
    );

    final spoilerId = span.spoilerId;
    if (spoilerId != null && !widget.revealed.contains(spoilerId)) {
      textStyle = textStyle.copyWith(
        color: Colors.transparent,
        backgroundColor: context.forest.surfaceFor(const Color(0xFF0B1410)),
      );
    }

    TapGestureRecognizer? recognizer;
    if (span.link != null) {
      recognizer = TapGestureRecognizer()..onTap = () => _openLink(span.link!);
    } else if (spoilerId != null) {
      recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onSpoiler(spoilerId);
    }
    if (recognizer != null) _recognizers.add(recognizer);

    return TextSpan(text: span.text, style: textStyle, recognizer: recognizer);
  }

  Widget _buildCellContent(
    List<ChatSpan> spans,
    ChatTableAlign align,
    TextStyle style,
  ) {
    final textAlign = _toTextAlign(align);
    final alignment = _toAlignment(align);

    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Text.rich(
        TextSpan(
          children: [for (final span in spans) _span(span, style)],
        ),
        textAlign: textAlign,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark
        ? AppColors.mintGreen.withValues(alpha: 0.25)
        : Colors.black.withValues(alpha: 0.15);
    final headerBg = isDark
        ? AppColors.darkGreen.withValues(alpha: 0.75)
        : AppColors.midGreen.withValues(alpha: 0.18);
    final zebraBg = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.black.withValues(alpha: 0.03);

    final headerStyle = widget.baseStyle.copyWith(
      fontWeight: FontWeight.bold,
      fontSize: 12.5,
    );
    final cellStyle = widget.baseStyle.copyWith(
      fontSize: 12,
    );

    final colCount = widget.table.headers.length;
    if (colCount == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: IntrinsicWidth(
              child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                border: TableBorder(
                  horizontalInside: BorderSide(color: borderColor, width: 0.8),
                  verticalInside: BorderSide(color: borderColor, width: 0.8),
                ),
                children: [
                  // Header Row
                  TableRow(
                    decoration: BoxDecoration(color: headerBg),
                    children: [
                      for (var col = 0; col < colCount; col++)
                        _buildCellContent(
                          widget.table.headers[col].spans,
                          widget.table.alignments[col],
                          headerStyle,
                        ),
                    ],
                  ),
                  // Data Rows
                  for (var r = 0; r < widget.table.rows.length; r++)
                    TableRow(
                      decoration: BoxDecoration(
                        color: (r % 2 == 1) ? zebraBg : Colors.transparent,
                      ),
                      children: [
                        for (var col = 0; col < colCount; col++)
                          _buildCellContent(
                            col < widget.table.rows[r].cells.length
                                ? widget.table.rows[r].cells[col].spans
                                : const [],
                            widget.table.alignments[col],
                            cellStyle,
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
