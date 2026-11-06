import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../tour_group/domain/services/chat_markdown.dart';
import '../../../tour_group/domain/services/trip_ledger_engine.dart';
import 'chat_table_fullscreen_modal.dart';

/// A responsive, horizontally scrollable Markdown table widget for chat messages.
///
/// Features:
/// - Rounded container with crisp, subtle borders.
/// - Themed header row with column alignments (left, center, right).
/// - Alternating row background colors (zebra striping) for readability.
/// - Rich inline spans inside cells (bold, italic, code, underline, highlight, links).
/// - Micro-action toolbar in the top-right corner with 1-tap Copy/Export & Fullscreen.
/// - Scroll-fade edge indicator indicating horizontal swipeability.
/// - Auto-sum calculation for numeric/currency columns (Bengali & English digits).
/// - Contextual ecosystem bridges (Notice Board, Smart Ledger).
class ChatTableWidget extends StatefulWidget {
  final ChatTableBlock table;
  final TextStyle baseStyle;
  final Set<int> revealed;
  final ValueChanged<int> onSpoiler;
  final bool isMine;
  final String? title;
  final VoidCallback? onPinNotice;
  final VoidCallback? onImportLedger;

  const ChatTableWidget({
    super.key,
    required this.table,
    required this.baseStyle,
    required this.revealed,
    required this.onSpoiler,
    this.isMine = false,
    this.title,
    this.onPinNotice,
    this.onImportLedger,
  });

  @override
  State<ChatTableWidget> createState() => _ChatTableWidgetState();
}

class _ChatTableWidgetState extends State<ChatTableWidget> {
  final List<TapGestureRecognizer> _recognizers = [];
  final ScrollController _scrollController = ScrollController();
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollIndicator);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateScrollIndicator();
    });
  }

  @override
  void didUpdateWidget(covariant ChatTableWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateScrollIndicator();
    });
  }

  void _updateScrollIndicator() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final current = _scrollController.position.pixels;
    final canScroll = maxScroll > 8 && current < maxScroll - 6;
    if (canScroll != _canScrollRight && mounted) {
      setState(() => _canScrollRight = canScroll);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollIndicator);
    _scrollController.dispose();
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

  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontFamily: 'NotoSansBengali',
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.mintGreen,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _toTsv() {
    final buffer = StringBuffer();
    buffer.writeln(widget.table.headers
        .map((h) => h.plainText.replaceAll('\t', ' ').replaceAll('\n', ' '))
        .join('\t'));
    for (final row in widget.table.rows) {
      buffer.writeln(row.cells
          .map((c) => c.plainText.replaceAll('\t', ' ').replaceAll('\n', ' '))
          .join('\t'));
    }
    return buffer.toString().trimRight();
  }

  String _toCleanList() {
    final buffer = StringBuffer();
    final headerTitles =
        widget.table.headers.map((h) => h.plainText.trim()).toList();
    for (var r = 0; r < widget.table.rows.length; r++) {
      final row = widget.table.rows[r];
      if (row.cells.isEmpty) continue;
      final firstCell = row.cells.first.plainText.trim();
      buffer.writeln('📌 $firstCell');
      for (var c = 1; c < row.cells.length; c++) {
        final colName =
            c < headerTitles.length ? headerTitles[c] : 'Col ${c + 1}';
        final cellVal = row.cells[c].plainText.trim();
        if (cellVal.isNotEmpty) {
          buffer.writeln('  • $colName: $cellVal');
        }
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  String _toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln(
        '| ${widget.table.headers.map((h) => h.plainText.trim()).join(' | ')} |');
    buffer.writeln('| ${widget.table.alignments.map((a) {
      switch (a) {
        case ChatTableAlign.center:
          return ':---:';
        case ChatTableAlign.right:
          return '---:';
        case ChatTableAlign.left:
          return ':---';
      }
    }).join(' | ')} |');
    for (final row in widget.table.rows) {
      buffer.writeln(
          '| ${row.cells.map((c) => c.plainText.trim()).join(' | ')} |');
    }
    return buffer.toString().trim();
  }

  /// Inspects numeric columns and returns sum information if detected.
  List<({int colIndex, String header, int totalPaisa})> _detectNumericSums() {
    final results = <({int colIndex, String header, int totalPaisa})>[];
    final colCount = widget.table.headers.length;
    for (var c = 0; c < colCount; c++) {
      int count = 0;
      int totalPaisa = 0;
      for (final row in widget.table.rows) {
        if (c < row.cells.length) {
          final text = row.cells[c].plainText.trim();
          final paisa = TripLedgerEngine.parseTakaInput(text);
          if (paisa != null && paisa > 0) {
            count++;
            totalPaisa += paisa;
          }
        }
      }
      if (count >= 2 && count >= (widget.table.rows.length * 0.45)) {
        final header = c < widget.table.headers.length
            ? widget.table.headers[c].plainText.trim()
            : 'কলাম ${c + 1}';
        results.add((colIndex: c, header: header, totalPaisa: totalPaisa));
      }
    }
    return results;
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

  void _showExportMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.forest.surfaceFor(const Color(0xFF142428)),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color:
                        context.forest.isDark ? Colors.white24 : Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'টেবিল এক্সপোর্ট ও শেয়ার',
                  style: TextStyle(
                    fontFamily: 'HindSiliguri',
                    fontFamilyFallback: const [
                      'NotoSansBengali',
                      'Roboto',
                      'sans-serif'
                    ],
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: context.forest.text,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: Icon(Icons.table_chart_outlined,
                      color: context.forest.accentText),
                  title: Text(
                    'এক্সেল / গুগল শিটসের জন্য কপি (TSV)',
                    style: TextStyle(
                      fontFamily: 'HindSiliguri',
                      fontFamilyFallback: const [
                        'NotoSansBengali',
                        'Roboto',
                        'sans-serif'
                      ],
                      color: context.forest.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'পেস্ট করলে স্বয়ংক্রিয়ভাবে আলাদা কলাম ও সারিতে বসে যাবে',
                    style: TextStyle(
                      fontFamily: 'HindSiliguri',
                      fontFamilyFallback: const [
                        'NotoSansBengali',
                        'Roboto',
                        'sans-serif'
                      ],
                      color: context.forest.text70,
                      fontSize: 12,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    _copyToClipboard(
                        _toTsv(), 'শিটসের জন্য কপি করা হয়েছে (TSV)');
                  },
                ),
                ListTile(
                  leading: Icon(Icons.format_list_bulleted_rounded,
                      color: context.forest.readable(AppColors.gold)),
                  title: Text(
                    'লিস্ট আকারে কপি করুন (Clean List)',
                    style: TextStyle(
                      fontFamily: 'HindSiliguri',
                      fontFamilyFallback: const [
                        'NotoSansBengali',
                        'Roboto',
                        'sans-serif'
                      ],
                      color: context.forest.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'হোয়াটসঅ্যাপ বা মেসেঞ্জারে স্পষ্ট বুলেট পয়েন্টে শেয়ারের জন্য',
                    style: TextStyle(
                      fontFamily: 'HindSiliguri',
                      fontFamilyFallback: const [
                        'NotoSansBengali',
                        'Roboto',
                        'sans-serif'
                      ],
                      color: context.forest.text70,
                      fontSize: 12,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    _copyToClipboard(
                        _toCleanList(), 'ক্লিন লিস্ট কপি করা হয়েছে');
                  },
                ),
                ListTile(
                  leading: Icon(Icons.code_rounded,
                      color: context.forest.readable(const Color(0xFF0284C7))),
                  title: Text(
                    'মার্কডাউন ফরম্যাটে কপি করুন',
                    style: TextStyle(
                      fontFamily: 'HindSiliguri',
                      fontFamilyFallback: const [
                        'NotoSansBengali',
                        'Roboto',
                        'sans-serif'
                      ],
                      color: context.forest.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'আসল পাইপলাইন (| Col 1 | Col 2 |) কোড কপি হবে',
                    style: TextStyle(
                      fontFamily: 'HindSiliguri',
                      fontFamilyFallback: const [
                        'NotoSansBengali',
                        'Roboto',
                        'sans-serif'
                      ],
                      color: context.forest.text70,
                      fontSize: 12,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    _copyToClipboard(
                        _toMarkdown(), 'মার্কডাউন কোড কপি করা হয়েছে');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openFullscreen() {
    showChatTableFullscreenModal(
      context,
      table: widget.table,
      title: widget.title,
      isMine: widget.isMine,
      onPinNotice: widget.onPinNotice,
      onImportLedger: widget.onImportLedger,
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
      fontFamily: 'NotoSansBengali',
      fontWeight: FontWeight.bold,
      fontSize: 14.0,
      height: 1.35,
    );
    final cellStyle = widget.baseStyle.copyWith(
      fontFamily: 'NotoSansBengali',
      fontSize: 13.5,
      height: 1.35,
    );

    final colCount = widget.table.headers.length;
    if (colCount == 0) return const SizedBox.shrink();
    final numericSums = _detectNumericSums();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Table Container with Scroll and Edge Indicator
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: borderColor, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                children: [
                  SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    child: IntrinsicWidth(
                      child: Table(
                        defaultColumnWidth: const IntrinsicColumnWidth(),
                        border: TableBorder(
                          horizontalInside:
                              BorderSide(color: borderColor, width: 0.8),
                          verticalInside:
                              BorderSide(color: borderColor, width: 0.8),
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
                                color:
                                    (r % 2 == 1) ? zebraBg : Colors.transparent,
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

                  // Floating Micro-Toolbar (Top-Right)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white24, width: 0.8),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            label: 'টেবিল কপি বা এক্সপোর্ট করুন',
                            button: true,
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: IconButton(
                                tooltip: 'টেবিল এক্সপোর্ট করুন',
                                icon: const Icon(Icons.copy_rounded,
                                    size: 13, color: Colors.white),
                                padding: EdgeInsets.zero,
                                onPressed: _showExportMenu,
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Semantics(
                            label: 'বড় করে দেখুন ও জুম করুন',
                            button: true,
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: IconButton(
                                tooltip: 'বড় করে দেখুন (Fullscreen)',
                                icon: const Icon(Icons.fullscreen_rounded,
                                    size: 15, color: Colors.white),
                                padding: EdgeInsets.zero,
                                onPressed: _openFullscreen,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Soft Right Scroll-Fade Edge Indicator
                  if (_canScrollRight)
                    Positioned(
                      top: 0,
                      right: 0,
                      bottom: 0,
                      width: 26,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                (isDark
                                        ? const Color(0xFF0D1F17)
                                        : const Color(0xFFD9FDD3))
                                    .withValues(alpha: 0.88),
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                          ),
                          child: const Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: EdgeInsets.only(right: 2),
                              child: Icon(
                                Icons.chevron_right_rounded,
                                size: 16,
                                color: AppColors.mintGreen,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Auto-Sum Pill & Ecosystem Action Chips
          if (numericSums.isNotEmpty ||
              widget.onImportLedger != null ||
              widget.onPinNotice != null) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final sum in numericSums)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.mintGreen.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.mintGreen.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      '💰 মোট (${sum.header}): ${TripLedgerEngine.formatTaka(sum.totalPaisa)}',
                      style: TextStyle(
                        fontFamily: 'NotoSansBengali',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color:
                            isDark ? AppColors.mintGreen : AppColors.darkGreen,
                      ),
                    ),
                  ),
                if (widget.onImportLedger != null)
                  InkWell(
                    onTap: widget.onImportLedger,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.mintGreen.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: AppColors.mintGreen, width: 0.8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.account_balance_wallet_outlined,
                              size: 13, color: AppColors.mintGreen),
                          SizedBox(width: 4),
                          Text(
                            'লেজারে যুক্ত',
                            style: TextStyle(
                              fontFamily: 'NotoSansBengali',
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.mintGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (widget.onPinNotice != null)
                  InkWell(
                    onTap: widget.onPinNotice,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.darkGreen.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: AppColors.darkGreen, width: 0.8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.push_pin_outlined,
                              size: 13, color: AppColors.mintGreen),
                          SizedBox(width: 4),
                          Text(
                            'নোটিশে পিন',
                            style: TextStyle(
                              fontFamily: 'NotoSansBengali',
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.mintGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
