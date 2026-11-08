import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../tour_group/domain/services/chat_markdown.dart';
import '../../../tour_group/domain/services/trip_ledger_engine.dart';

/// Shows an edge-to-edge, zoomable and pannable Fullscreen Modal for a Markdown Table.
Future<void> showChatTableFullscreenModal(
  BuildContext context, {
  required ChatTableBlock table,
  String? title,
  bool isMine = false,
  VoidCallback? onPinNotice,
  VoidCallback? onImportLedger,
}) {
  return showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (dialogCtx) => ChatTableFullscreenModal(
      table: table,
      title: title,
      isMine: isMine,
      onPinNotice: onPinNotice,
      onImportLedger: onImportLedger,
    ),
  );
}

/// An interactive, full-screen viewer for chat tables with 2D pan/zoom, cell inspection,
/// and quick export tools.
class ChatTableFullscreenModal extends StatefulWidget {
  final ChatTableBlock table;
  final String? title;
  final bool isMine;
  final VoidCallback? onPinNotice;
  final VoidCallback? onImportLedger;

  const ChatTableFullscreenModal({
    super.key,
    required this.table,
    this.title,
    this.isMine = false,
    this.onPinNotice,
    this.onImportLedger,
  });

  @override
  State<ChatTableFullscreenModal> createState() =>
      _ChatTableFullscreenModalState();
}

class _ChatTableFullscreenModalState extends State<ChatTableFullscreenModal> {
  final TransformationController _transformController =
      TransformationController();
  bool _isRotatedLandscape = false;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  void _copyToClipboard(String text, String successMessage) {
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          successMessage,
          style: const TextStyle(
            fontFamily: 'NotoSansBengali',
            fontFamilyFallback: ['HindSiliguri', 'Roboto', 'sans-serif'],
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.mintGreen,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Converts table to Tab-Separated Values (TSV) for Google Sheets / Excel.
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

  /// Converts table into a clean, human-readable bullet list for WhatsApp / SMS.
  String _toCleanList() {
    final buffer = StringBuffer();
    final headerTitles =
        widget.table.headers.map((h) => h.plainText.trim()).toList();
    if (widget.title != null && widget.title!.isNotEmpty) {
      buffer.writeln('📋 ${widget.title}');
      buffer.writeln();
    }
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

  /// Converts table back to raw Markdown.
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
    if (span.math) {
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Math.tex(
              span.text,
              textStyle: style,
              onErrorFallback: (_) => Text(
                '\$${span.text}\$',
                style: style.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ),
        ),
      );
    }

    final textStyle = style.copyWith(
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
      color: span.link != null ? AppColors.mintGreen : null,
    );

    return TextSpan(text: span.text, style: textStyle);
  }

  Widget _buildCellContent(
    List<ChatSpan> spans,
    ChatTableAlign align,
    TextStyle style,
  ) {
    final textAlign = switch (align) {
      ChatTableAlign.center => TextAlign.center,
      ChatTableAlign.right => TextAlign.right,
      ChatTableAlign.left => TextAlign.left,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      alignment: _toAlignment(align),
      child: Text.rich(
        TextSpan(
          children: [for (final span in spans) _span(span, style)],
        ),
        textAlign: textAlign,
      ),
    );
  }

  void _showCellDetail(String header, ChatTableCell cell) {
    final content = cell.plainText;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.forest.surfaceFor(const Color(0xFF142428)),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final cellDetailStyle = TextStyle(
          fontFamily: 'NotoSansBengali',
          fontFamilyFallback: const ['NotoSansBengali', 'Roboto', 'sans-serif'],
          fontSize: 16,
          height: 1.45,
          color: context.forest.text,
        );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.forest.isDark
                          ? Colors.white24
                          : Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  header,
                  style: TextStyle(
                    fontFamily: 'NotoSansBengali',
                    fontFamilyFallback: const [
                      'NotoSansBengali',
                      'Roboto',
                      'sans-serif'
                    ],
                    fontSize: 13,
                    color: context.forest.accentText,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        for (final span in cell.spans)
                          _span(span, cellDetailStyle),
                      ],
                    ),
                  ),
                ),
                if (cell.spans.any((s) => s.math)) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: SelectableText(
                      content,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: context.forest.text70,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: context.forest.accentText,
                      ),
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text(
                        'সেল কপি করুন',
                        style: TextStyle(
                          fontFamily: 'NotoSansBengali',
                          fontFamilyFallback: [
                            'NotoSansBengali',
                            'Roboto',
                            'sans-serif'
                          ],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(sheetCtx).pop();
                        _copyToClipboard(content, 'সেল কপি করা হয়েছে');
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showExportSheet() {
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
                    fontFamily: 'NotoSansBengali',
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
                      fontFamily: 'NotoSansBengali',
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
                      fontFamily: 'NotoSansBengali',
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
                      fontFamily: 'NotoSansBengali',
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
                      fontFamily: 'NotoSansBengali',
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
                      fontFamily: 'NotoSansBengali',
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
                      fontFamily: 'NotoSansBengali',
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

  @override
  Widget build(BuildContext context) {
    final colCount = widget.table.headers.length;
    final rowCount = widget.table.rows.length;
    final numericSums = _detectNumericSums();

    final contentWidget = Scaffold(
      backgroundColor: const Color(0xFF0B1410),
      appBar: AppBar(
        backgroundColor: const Color(0xFF142428),
        elevation: 0,
        title: Text(
          widget.title ?? 'টেবিল ভিউ ($rowCount সারি, $colCount কলাম)',
          style: const TextStyle(
            fontFamily: 'NotoSansBengali',
            fontFamilyFallback: ['HindSiliguri', 'Roboto', 'sans-serif'],
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            tooltip: _isRotatedLandscape ? 'সোজা করুন' : 'ল্যান্ডস্কেপ ভিউ',
            icon: Icon(
              _isRotatedLandscape
                  ? Icons.screen_lock_portrait_rounded
                  : Icons.screen_lock_landscape_rounded,
              color: AppColors.mintGreen,
            ),
            onPressed: () {
              setState(() {
                _isRotatedLandscape = !_isRotatedLandscape;
                _resetZoom();
              });
            },
          ),
          IconButton(
            tooltip: 'জুম রিসেট করুন',
            icon: const Icon(Icons.zoom_out_map_rounded, color: Colors.white70),
            onPressed: _resetZoom,
          ),
          IconButton(
            tooltip: 'কপি ও এক্সপোর্ট',
            icon:
                const Icon(Icons.copy_all_rounded, color: AppColors.mintGreen),
            onPressed: _showExportSheet,
          ),
          IconButton(
            tooltip: 'বন্ধ করুন',
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Informative hint banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              color: AppColors.midGreen.withValues(alpha: 0.12),
              child: const Row(
                children: [
                  Icon(Icons.pinch_outlined,
                      size: 16, color: AppColors.mintGreen),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'দুই আঙুলে জুম করুন, টেনে স্ক্রল করুন অথবা সেলে ট্যাপ করে কপি করুন',
                      style: TextStyle(
                        fontFamily: 'NotoSansBengali',
                        fontFamilyFallback: [
                          'NotoSansBengali',
                          'Roboto',
                          'sans-serif'
                        ],
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Zoomable Interactive Grid
            Expanded(
              child: InteractiveViewer(
                transformationController: _transformController,
                panAxis: PanAxis.free,
                minScale: 0.4,
                maxScale: 4.5,
                boundaryMargin: const EdgeInsets.all(80),
                child: Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: _buildGridTable(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Bottom Summary & Ecosystem Action Bar
            if (numericSums.isNotEmpty ||
                widget.onPinNotice != null ||
                widget.onImportLedger != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  color: Color(0xFF142428),
                  border: Border(
                      top: BorderSide(color: Colors.white12, width: 0.8)),
                ),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final sum in numericSums)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.mintGreen.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color:
                                  AppColors.mintGreen.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          '💰 মোট (${sum.header}): ${TripLedgerEngine.formatTaka(sum.totalPaisa)}',
                          style: const TextStyle(
                            fontFamily: 'NotoSansBengali',
                            fontFamilyFallback: [
                              'NotoSansBengali',
                              'Roboto',
                              'sans-serif'
                            ],
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.mintGreen,
                          ),
                        ),
                      ),
                    if (widget.onImportLedger != null)
                      ActionChip(
                        avatar: const Icon(Icons.account_balance_wallet_rounded,
                            size: 16, color: Colors.black),
                        label: const Text(
                          'লেজারে যুক্ত করুন',
                          style: TextStyle(
                            fontFamily: 'NotoSansBengali',
                            fontFamilyFallback: [
                              'NotoSansBengali',
                              'Roboto',
                              'sans-serif'
                            ],
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                            fontSize: 12.5,
                          ),
                        ),
                        backgroundColor: AppColors.mintGreen,
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onImportLedger!();
                        },
                      ),
                    if (widget.onPinNotice != null)
                      ActionChip(
                        avatar: const Icon(Icons.push_pin_rounded,
                            size: 16, color: Colors.white),
                        label: const Text(
                          'নোটিশে পিন করুন',
                          style: TextStyle(
                            fontFamily: 'NotoSansBengali',
                            fontFamilyFallback: [
                              'NotoSansBengali',
                              'Roboto',
                              'sans-serif'
                            ],
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 12.5,
                          ),
                        ),
                        backgroundColor: AppColors.darkGreen,
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onPinNotice!();
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    if (_isRotatedLandscape) {
      return RotatedBox(quarterTurns: 1, child: contentWidget);
    }
    return contentWidget;
  }

  Widget _buildGridTable(BuildContext context) {
    const borderColor = Color(0xFF264639);
    const headerBg = Color(0xFF1B4332);
    const zebraBg = Color(0xFF13221C);

    final colCount = widget.table.headers.length;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1A15),
        border: Border.all(color: borderColor, width: 1.2),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: const TableBorder(
            horizontalInside: BorderSide(color: borderColor, width: 0.8),
            verticalInside: BorderSide(color: borderColor, width: 0.8),
          ),
          children: [
            // Header
            TableRow(
              decoration: const BoxDecoration(color: headerBg),
              children: [
                for (var c = 0; c < colCount; c++)
                  InkWell(
                    onTap: () => _showCellDetail(
                      'কলাম হেডার',
                      widget.table.headers[c],
                    ),
                    child: _buildCellContent(
                      widget.table.headers[c].spans,
                      widget.table.alignments[c],
                      const TextStyle(
                        fontFamily: 'NotoSansBengali',
                        fontFamilyFallback: [
                          'NotoSansBengali',
                          'Roboto',
                          'sans-serif'
                        ],
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.05,
                      ),
                    ),
                  ),
              ],
            ),

            // Rows
            for (var r = 0; r < widget.table.rows.length; r++)
              TableRow(
                decoration: BoxDecoration(
                  color: (r % 2 == 1) ? zebraBg : Colors.transparent,
                ),
                children: [
                  for (var c = 0; c < colCount; c++)
                    InkWell(
                      onTap: () {
                        final cell = c < widget.table.rows[r].cells.length
                            ? widget.table.rows[r].cells[c]
                            : const ChatTableCell([]);
                        final header = c < widget.table.headers.length
                            ? widget.table.headers[c].plainText
                            : 'কলাম ${c + 1}';
                        _showCellDetail(header, cell);
                      },
                      child: _buildCellContent(
                        c < widget.table.rows[r].cells.length
                            ? widget.table.rows[r].cells[c].spans
                            : const [],
                        widget.table.alignments[c],
                        const TextStyle(
                          fontFamily: 'NotoSansBengali',
                          fontFamilyFallback: [
                            'NotoSansBengali',
                            'Roboto',
                            'sans-serif'
                          ],
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.4,
                          letterSpacing: 0.05,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
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
}
