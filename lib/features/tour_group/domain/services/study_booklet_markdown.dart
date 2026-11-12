// The Markdown of a study booklet page. A solution is parsed with the chat's parser, so the
// headings, quotes, lists, tables, rules and emphasis the app shows are the same blocks here, and
// each one is drawn as PDF widgets. Every widget is cut to fit a page, so no single block can
// stall the layout. Only the PDF package is used, so this file stays free of Flutter.

import 'dart:math' as math;

import 'package:bangla_pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

import 'chat_markdown.dart';
import 'ppc_pdf_figure.dart';

/// Most visual lines one block of solution text may take. A block has to fit on a page below the
/// header and the footer. A block that does not is retried on each new page, and the layout gives
/// up after 20 pages with a `PdfTooBigPageException`, so a long solution used to stall the booklet
/// and then fail. Twenty-four lines of the booklet's 9.5 pt text is well under a page.
const int studyBookletBlockLines = 24;

/// Characters that take one visual line of the booklet's text. It is kept low, so a block that is
/// estimated as short is never taller than a page.
const int studyBookletCharsPerLine = 80;

/// The most characters one line may hold before it is cut into pieces.
const int _maxBlockChars = studyBookletBlockLines * studyBookletCharsPerLine;

/// Width of the text area of a booklet page, in points: A4 less the page margins and padding.
const double _textWidth = 523;

/// Average width of one body character in a table cell, in points.
const double _tableCharWidth = 5.5;

/// Width of a figure drawn on the booklet, in points.
const double _figureWidth = 440;

const PdfColor _linkColor = PdfColor(0.08, 0.25, 0.18);

/// Cuts solution prose into blocks of plain text that each fit on one page.
///
/// Lines keep their order and their words, and a block joins its lines with newlines. Only a line
/// longer than a block is cut, at a space, and then its two halves start on separate lines.
List<String> studyBookletProseBlocks(String text) {
  final blocks = <String>[];
  final current = <String>[];
  var used = 0;

  void close() {
    if (current.isEmpty) return;
    blocks.add(current.join('\n'));
    current.clear();
    used = 0;
  }

  for (final line in text.split('\n')) {
    for (final piece in _linePieces(line)) {
      final cost = _linesFor(piece.length, studyBookletCharsPerLine);
      if (used + cost > studyBookletBlockLines) close();
      current.add(piece);
      used += cost;
    }
  }
  close();
  return blocks;
}

/// Cuts one line that is longer than a block into pieces, at spaces where it can be.
List<String> _linePieces(String line) {
  if (line.length <= _maxBlockChars) return [line];
  final pieces = <String>[];
  var rest = line;
  while (rest.length > _maxBlockChars) {
    var cut = rest.lastIndexOf(' ', _maxBlockChars);
    if (cut <= 0) cut = _maxBlockChars;
    pieces.add(rest.substring(0, cut).trimRight());
    rest = rest.substring(cut).trimLeft();
  }
  pieces.add(rest);
  return pieces;
}

/// Makes a solution's raw text ready for parsing: HTML comments go and runs of blank lines are cut
/// to one. The Markdown itself stays, so [studyBookletMarkdownWidgets] can draw it.
String studyBookletCleanSolution(String raw) => raw
    .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

/// Replaces the characters the booklet's bundled fonts cannot draw, so none of them prints as a
/// blank box. The fonts have no arrows and no ballot boxes. An arrow becomes an em dash, as it
/// does in the group record, and a no-break space becomes a plain space. Zero-width characters
/// that do nothing on the page are dropped; the joiners that Bengali conjuncts need are kept.
String studyBookletCleanText(String text) => text
    .replaceAll(' ', ' ')
    .replaceAll('\t', ' ')
    .replaceAll(RegExp('[​⁠﻿]'), '')
    .replaceAll('→', '—')
    .replaceAll('⇒', '—')
    .replaceAll('☐', '[ ]')
    .replaceAll('☑', '[x]');

/// The widgets of one solution's Markdown, in order. Each widget takes at most one block of lines,
/// so the booklet can break a page between any two of them.
List<pw.Widget> studyBookletMarkdownWidgets(String markdown) {
  const body = _Look();
  final widgets = <pw.Widget>[];
  final blocks = parseChatBlocks(markdown);
  for (var i = 0; i < blocks.length; i++) {
    if (i > 0) widgets.add(pw.SizedBox(height: 4));
    widgets.addAll(_blockWidgets(blocks[i], body));
  }
  return widgets;
}

/// A vector graphic from an `svg` fence or an `<svg>` element, drawn where it sat. A graphic that
/// cannot be drawn leaves a labelled box, so the reader sees that a figure was there.
pw.Widget studyBookletSvgFigure(
  String svg, {
  double width = 440,
  double height = 230,
}) {
  try {
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 8),
      alignment: pw.Alignment.center,
      child: pw.SvgImage(
        svg: svg,
        width: width,
        height: height,
        fit: pw.BoxFit.contain,
      ),
    );
  } catch (_) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Text(
        '[Vector Diagram / চিত্র]',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      ),
    );
  }
}

/// How a run of text is drawn.
class _Look {
  const _Look({
    this.size = 9.5,
    this.bold = false,
    this.color = PdfColors.grey900,
    this.lineSpacing = 2,
  });

  final double size;
  final bool bold;
  final PdfColor color;
  final double lineSpacing;

  _Look copy({double? size, bool? bold, PdfColor? color}) => _Look(
        size: size ?? this.size,
        bold: bold ?? this.bold,
        color: color ?? this.color,
        lineSpacing: lineSpacing,
      );
}

/// One row of a table as it is drawn: its cells, and the lines its tallest cell takes.
class _Fragment {
  const _Fragment(this.cells, this.lines);

  final List<List<ChatSpan>> cells;
  final int lines;
}

List<pw.Widget> _blockWidgets(ChatBlock block, _Look look) => switch (block) {
      ChatParagraphBlock(:final lines) =>
        _paragraph([for (final line in lines) line.spans], look),
      ChatHeadingBlock(:final level, :final spans) =>
        _heading(level, spans, look),
      ChatQuoteBlock(:final blocks) => _quote(blocks, look),
      ChatListBlock(:final ordered, :final items) =>
        _list(ordered, items, look),
      ChatTableBlock t => _tableWidgets(t, look),
      ChatDividerBlock() => [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            child: pw.Divider(color: PdfColors.grey400, thickness: 0.6),
          ),
        ],
      ChatMathBlock(:final latex) => _math(latex),
      ChatCodeBlock(:final code) => _code(code),
      ChatChartBlock(:final spec) => [
          pw.Center(child: ppcPdfFigure(spec, width: _figureWidth)),
        ],
      ChatSvgBlock(:final svg) => [
          pw.Center(child: studyBookletSvgFigure(svg, width: _figureWidth)),
        ],
      _ => const <pw.Widget>[],
    };

/// Lines of ordinary text, packed so that each widget takes at most one block of lines.
List<pw.Widget> _paragraph(List<List<ChatSpan>> lines, _Look look) {
  final pieces = [for (final line in lines) ..._pieces(line, _maxBlockChars)];
  final widgets = <pw.Widget>[];
  var group = <pw.Widget>[];
  var used = 0;

  void close() {
    if (group.isEmpty) return;
    widgets.add(
      pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start, children: group),
    );
    group = <pw.Widget>[];
    used = 0;
  }

  for (final piece in pieces) {
    final cost = _linesFor(_plainLength(piece), studyBookletCharsPerLine);
    if (used + cost > studyBookletBlockLines) close();
    group.add(_rich(piece, look));
    used += cost;
  }
  close();
  return widgets;
}

/// A heading, in bold and larger the higher its level.
List<pw.Widget> _heading(int level, List<ChatSpan> spans, _Look look) {
  final size = switch (level) {
    1 => 13.0,
    2 => 12.0,
    3 => 11.5,
    _ => 10.5,
  };
  final headLook = look.copy(size: size, bold: true, color: PdfColors.black);
  return [
    for (final piece in _pieces(spans, _maxBlockChars))
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 3, bottom: 1),
        child: _rich(piece, headLook),
      ),
  ];
}

/// A quote: its content, each part with a bar at its left. The bar is drawn on every part, so it
/// runs unbroken down the quote, and a page can still break between two parts.
List<pw.Widget> _quote(List<ChatBlock> blocks, _Look look) {
  final inner = look.copy(color: PdfColors.grey800);
  final parts = <pw.Widget>[];
  for (var i = 0; i < blocks.length; i++) {
    if (i > 0) parts.add(pw.SizedBox(height: 3));
    parts.addAll(_blockWidgets(blocks[i], inner));
  }
  return [
    for (final part in parts)
      pw.Container(
        padding: const pw.EdgeInsets.only(left: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            left: pw.BorderSide(color: PdfColors.grey500, width: 2),
          ),
        ),
        child: part,
      ),
  ];
}

/// A list: one row per item, marked by a bullet, a number, or a checkbox.
List<pw.Widget> _list(bool ordered, List<ChatListItem> items, _Look look) {
  final widgets = <pw.Widget>[];
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final marker = _marker(item, ordered, i);
    final pieces = _pieces(item.spans, _maxBlockChars);
    for (var p = 0; p < pieces.length; p++) {
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 1.5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 18,
                child: pw.Text(p == 0 ? marker : '', style: _style(look)),
              ),
              pw.Expanded(child: _rich(pieces[p], look)),
            ],
          ),
        ),
      );
    }
  }
  return widgets;
}

String _marker(ChatListItem item, bool ordered, int index) {
  final checked = item.isChecked;
  if (checked != null) return checked ? '[x]' : '[ ]';
  if (ordered) return '${item.number ?? index + 1}.';
  return '•';
}

/// A display equation, read as plain text, centred.
List<pw.Widget> _math(String latex) {
  final text = studyBookletCleanText(cleanBengaliMath(latex));
  return [
    for (final block in studyBookletProseBlocks(text))
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Center(
          child: pw.Text(
            block,
            textAlign: pw.TextAlign.center,
            style: _style(const _Look(size: 10.5)),
          ),
        ),
      ),
  ];
}

/// A code block, on a light panel. The booklet has no monospace face, so the code reads as text.
List<pw.Widget> _code(String code) => [
      for (final block in studyBookletProseBlocks(studyBookletCleanText(code)))
        pw.Container(
          width: double.infinity,
          margin: const pw.EdgeInsets.symmetric(vertical: 2),
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            block,
            style: const pw.TextStyle(
              fontSize: 8.5,
              lineSpacing: 1.5,
              color: PdfColors.grey800,
            ),
          ),
        ),
    ];

/// A table, drawn as one or more tables that each repeat the header. A row too tall for a block is
/// cut into fragments, one per block; a header too tall to repeat turns the table into records.
List<pw.Widget> _tableWidgets(ChatTableBlock table, _Look look) {
  final columns = table.headers.length;
  if (columns == 0) return const <pw.Widget>[];
  final charsPerLine = _cellCharsPerLine(columns);
  final headerLines =
      _cellLines(table.headers.map((cell) => cell.spans), charsPerLine);
  if (headerLines * 2 > studyBookletBlockLines) {
    return _recordWidgets(table, look);
  }

  // A table takes one line for its header row and one for each row's padding. A fragment has to
  // fit what is left of a block after the header, so no table can outgrow a block.
  final bodyBudget = studyBookletBlockLines - (headerLines + 1);
  final maxCellChars = (bodyBudget - 1) * charsPerLine;
  final fragments = <_Fragment>[];
  for (final row in table.rows) {
    final cellPieces = [
      for (var c = 0; c < columns; c++)
        _pieces(
          c < row.cells.length ? row.cells[c].spans : const <ChatSpan>[],
          maxCellChars,
        ),
    ];
    final count = cellPieces.fold<int>(
      1,
      (most, pieces) => math.max(most, pieces.length),
    );
    for (var k = 0; k < count; k++) {
      final cells = [
        for (final pieces in cellPieces)
          k < pieces.length ? pieces[k] : const <ChatSpan>[],
      ];
      fragments.add(_Fragment(cells, _cellLines(cells, charsPerLine)));
    }
  }

  final groups = <List<_Fragment>>[];
  var group = <_Fragment>[];
  var used = 0;
  for (final fragment in fragments) {
    final cost = fragment.lines + 1;
    if (group.isNotEmpty && used + cost > bodyBudget) {
      groups.add(group);
      group = <_Fragment>[];
      used = 0;
    }
    group.add(fragment);
    used += cost;
  }
  if (group.isNotEmpty || groups.isEmpty) groups.add(group);
  return [for (final rows in groups) _tableWidget(table, rows, look)];
}

/// One table: its header row, then the given body fragments.
pw.Widget _tableWidget(ChatTableBlock table, List<_Fragment> rows, _Look look) {
  final columns = table.headers.length;
  final headLook = look.copy(bold: true, color: PdfColors.black);

  pw.Widget cell(List<ChatSpan> spans, _Look cellLook, int column) =>
      pw.Padding(
        padding: const pw.EdgeInsets.all(3),
        child: _rich(spans, cellLook, align: _align(table, column)),
      );

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
    defaultColumnWidth: const pw.FlexColumnWidth(),
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          for (var c = 0; c < columns; c++)
            cell(table.headers[c].spans, headLook, c),
        ],
      ),
      for (final row in rows)
        pw.TableRow(
          children: [
            for (var c = 0; c < columns; c++) cell(row.cells[c], look, c),
          ],
        ),
    ],
  );
}

/// A table too tall to repeat its header: each row is drawn cell by cell, each labelled by its
/// header, so every line stays within a block whatever the size of the table.
List<pw.Widget> _recordWidgets(ChatTableBlock table, _Look look) {
  final widgets = <pw.Widget>[];
  for (final row in table.rows) {
    for (var c = 0; c < table.headers.length; c++) {
      final value =
          c < row.cells.length ? row.cells[c].spans : const <ChatSpan>[];
      final line = [
        for (final span in table.headers[c].spans) _copyOf(span, bold: true),
        const ChatSpan(': ', bold: true),
        ...value,
      ];
      for (final piece in _pieces(line, _maxBlockChars)) {
        widgets.add(_rich(piece, look));
      }
    }
    widgets.add(pw.SizedBox(height: 4));
  }
  return widgets;
}

pw.TextAlign _align(ChatTableBlock table, int column) {
  final align = column < table.alignments.length
      ? table.alignments[column]
      : ChatTableAlign.left;
  return switch (align) {
    ChatTableAlign.left => pw.TextAlign.left,
    ChatTableAlign.center => pw.TextAlign.center,
    ChatTableAlign.right => pw.TextAlign.right,
  };
}

pw.TextStyle _style(_Look look) => pw.TextStyle(
      fontSize: look.size,
      fontWeight: look.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: look.color,
      lineSpacing: look.lineSpacing,
    );

/// One line of spans, drawn with the look. An empty line keeps its height. A line with no bold,
/// strike-through, underline or link is one shaped text, so its Bengali and English share one
/// baseline; only a line with such emphasis is drawn run by run, where the runs may sit a little
/// apart in height.
pw.Widget _rich(List<ChatSpan> spans, _Look look, {pw.TextAlign? align}) {
  if (spans.isEmpty) {
    return pw.SizedBox(height: look.size + look.lineSpacing);
  }
  final emphasised = spans.any(
    (span) => span.bold || span.strike || span.underline || span.link != null,
  );
  if (!emphasised) {
    final plain = spans
        .map((span) => span.math ? cleanBengaliMath(span.text) : span.text)
        .join();
    return pw.Text(
      studyBookletCleanText(plain),
      textAlign: align,
      style: _style(look),
    );
  }
  return pw.RichText(
    textAlign: align,
    text: pw.TextSpan(
      style: _style(look),
      children: [for (final span in spans) _span(span, look)],
    ),
  );
}

/// One styled run of text, as the booklet draws it. Italic is drawn upright: the bundled fonts have
/// no Bengali italic, and a Latin italic face does not share the Bengali baseline on a mixed line,
/// so the marks after an English gloss would sit higher than the gloss. Bold, strike-through,
/// underline and links are drawn.
pw.TextSpan _span(ChatSpan span, _Look look) {
  final text = studyBookletCleanText(
    span.math ? cleanBengaliMath(span.text) : span.text,
  );
  final bold = look.bold || span.bold;
  final linked = span.link != null;
  final pw.TextDecoration? decoration = span.strike
      ? pw.TextDecoration.lineThrough
      : (span.underline || linked)
          ? pw.TextDecoration.underline
          : null;
  return pw.TextSpan(
    text: text,
    style: pw.TextStyle(
      fontSize: look.size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: linked ? _linkColor : look.color,
      lineSpacing: look.lineSpacing,
      decoration: decoration,
    ),
  );
}

/// The pieces of a line of spans, each at most [maxChars] long. A cut falls at a space where there
/// is one within reach; otherwise the line is cut where the limit falls.
List<List<ChatSpan>> _pieces(List<ChatSpan> spans, int maxChars) {
  if (_plainLength(spans) <= maxChars) return [spans];
  final plain = spans.map((span) => span.text).join();
  final pieces = <List<ChatSpan>>[];
  var start = 0;
  while (plain.length - start > maxChars) {
    var cut = plain.lastIndexOf(' ', start + maxChars);
    if (cut <= start) cut = start + maxChars;
    pieces.add(_slice(spans, start, cut));
    start = cut;
    while (start < plain.length && plain[start] == ' ') {
      start++;
    }
  }
  pieces.add(_slice(spans, start, plain.length));
  return pieces;
}

/// The spans between [start] and [end] of their joined text, each keeping its style.
List<ChatSpan> _slice(List<ChatSpan> spans, int start, int end) {
  final out = <ChatSpan>[];
  var offset = 0;
  for (final span in spans) {
    final from = math.max(start, offset);
    final to = math.min(end, offset + span.text.length);
    if (from < to) {
      out.add(
        _copyOf(span, text: span.text.substring(from - offset, to - offset)),
      );
    }
    offset += span.text.length;
  }
  return out;
}

/// A copy of [span] with new text or weight. Every other style is kept.
ChatSpan _copyOf(ChatSpan span, {String? text, bool? bold}) => ChatSpan(
      text ?? span.text,
      bold: bold ?? span.bold,
      italic: span.italic,
      strike: span.strike,
      underline: span.underline,
      highlight: span.highlight,
      code: span.code,
      math: span.math,
      spoilerId: span.spoilerId,
      link: span.link,
    );

int _plainLength(List<ChatSpan> spans) =>
    spans.fold<int>(0, (total, span) => total + span.text.length);

/// The visual lines [length] characters take at [charsPerLine]. Every line takes at least one.
int _linesFor(int length, int charsPerLine) =>
    length == 0 ? 1 : (length / charsPerLine).ceil();

/// Characters per line in one cell of a table with [columns] columns.
int _cellCharsPerLine(int columns) =>
    math.max(4, ((_textWidth / columns - 8) / _tableCharWidth).floor());

/// The lines the tallest of [cells] takes.
int _cellLines(Iterable<List<ChatSpan>> cells, int charsPerLine) =>
    cells.fold<int>(
      1,
      (most, cell) =>
          math.max(most, _linesFor(_plainLength(cell), charsPerLine)),
    );
