// Formatting for chat and channel messages. Kept free of Flutter so it can be tested.
//
// Supported inline: **bold**, *italic* or _italic_, __underline__, ~~strike~~,
// ==highlight==, `code`, ||spoiler||, [label](url), and bare http/https links.
//
// Supported blocks:
// - Tables: Markdown pipe tables (| Col 1 | Col 2 | with separator | --- | :---: | ---: |)
// - Fenced code blocks: ```dart ... ```
// - Headings: # H1, ## H2, ### H3
// - Lists: unordered (- or *), ordered (1., 2.), and checklists (- [ ] / - [x])
// - Quotes: lines starting with >
// - Horizontal rules / dividers: ---, ***, ___

import 'ppc_curve.dart';

/// A run of text that shares one set of styles.
class ChatSpan {
  final String text;
  final bool bold;
  final bool italic;
  final bool strike;
  final bool underline;
  final bool highlight;
  final bool code;
  final bool math;

  /// Set for text hidden behind a spoiler. Spans of the same spoiler share an id.
  final int? spoilerId;

  /// Set for a link. The text is either the link itself or the markdown label.
  final String? link;

  const ChatSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.underline = false,
    this.highlight = false,
    this.code = false,
    this.math = false,
    this.spoilerId,
    this.link,
  });
}

/// One line of a message. A quote is drawn with a bar beside it.
class ChatLine {
  final bool quote;
  final List<ChatSpan> spans;

  const ChatLine({required this.quote, required this.spans});
}

/// Column alignment for Markdown tables.
enum ChatTableAlign { left, center, right }

/// A single cell in a Markdown table with rich inline spans.
class ChatTableCell {
  final List<ChatSpan> spans;

  const ChatTableCell(this.spans);

  String get plainText => spans.map((s) => s.text).join();
}

/// A row of cells in a Markdown table.
class ChatTableRow {
  final List<ChatTableCell> cells;

  const ChatTableRow(this.cells);
}

/// An item in a list or checklist.
class ChatListItem {
  /// Null for standard bullets / numbers. False for unchecked `[ ]`, true for checked `[x]`.
  final bool? isChecked;

  /// Number prefix for ordered lists (1, 2, 3...), or null for unordered.
  final int? number;

  final List<ChatSpan> spans;

  const ChatListItem({
    this.isChecked,
    this.number,
    required this.spans,
  });
}

/// Base class for block-level chat message nodes.
abstract class ChatBlock {
  const ChatBlock();
}

/// A paragraph of one or more lines of styled text.
class ChatParagraphBlock extends ChatBlock {
  final List<ChatLine> lines;

  const ChatParagraphBlock(this.lines);
}

/// A section heading (# Level 1, ## Level 2, ### Level 3).
class ChatHeadingBlock extends ChatBlock {
  final int level;
  final List<ChatSpan> spans;

  const ChatHeadingBlock({required this.level, required this.spans});
}

/// A blockquote with one or more lines prefixed by "> ".
class ChatQuoteBlock extends ChatBlock {
  final List<ChatBlock> blocks;
  final List<ChatLine> lines;

  const ChatQuoteBlock({this.blocks = const [], this.lines = const []});
}

/// A fenced code block with optional syntax language.
class ChatCodeBlock extends ChatBlock {
  final String code;
  final String? language;

  const ChatCodeBlock({required this.code, this.language});
}

/// A responsive Markdown table with headers, alignments, and rows.
class ChatTableBlock extends ChatBlock {
  final List<ChatTableCell> headers;
  final List<ChatTableAlign> alignments;
  final List<ChatTableRow> rows;

  const ChatTableBlock({
    required this.headers,
    required this.alignments,
    required this.rows,
  });
}

/// An ordered, unordered, or checklist item group.
class ChatListBlock extends ChatBlock {
  final bool ordered;
  final List<ChatListItem> items;

  const ChatListBlock({required this.ordered, required this.items});
}

/// A horizontal divider line (---, ***, ___).
class ChatDividerBlock extends ChatBlock {
  const ChatDividerBlock();
}

/// A block-level LaTeX display equation ($$...$$).
class ChatMathBlock extends ChatBlock {
  final String latex;

  const ChatMathBlock(this.latex);
}

/// An interactive chart, from a ```chart:ppc fence (see [PpcSpec]).
class ChatChartBlock extends ChatBlock {
  final PpcSpec spec;

  const ChatChartBlock(this.spec);
}

/// A scalable vector graphic from an ```svg code fence or an embedded <svg> element.
class ChatSvgBlock extends ChatBlock {
  final String svg;

  const ChatSvgBlock(this.svg);
}

/// Cleans raw LaTeX math commands for Bengali script text, avoiding broken font
/// shaping in flutter_math_fork and converting fractions and symbols into legible Unicode text.
String cleanBengaliMath(String input) {
  var s = input.trim();
  // Handle fractions: \frac{A}{B} -> (A ÷ B)
  s = s.replaceAllMapped(
    RegExp(r'\\frac\s*\{([^{}]+)\}\s*\{([^{}]+)\}'),
    (m) => '(${m.group(1)} ÷ ${m.group(2)})',
  );
  s = s.replaceAll(r'\times', '×');
  s = s.replaceAll(r'\div', '÷');
  s = s.replaceAll(r'\cdot', '·');
  s = s.replaceAll(r'\pm', '±');
  s = s.replaceAll(r'\approx', '≈');
  s = s.replaceAll(r'\neq', '≠');
  s = s.replaceAll(r'\le', '≤');
  s = s.replaceAll(r'\ge', '≥');
  s = s.replaceAll(r'\rightarrow', '→');
  s = s.replaceAll(r'\implies', '⇒');
  s = s.replaceAll(RegExp(r'\\text\s*\{([^{}]+)\}'), r'$1');
  s = s.replaceAll(RegExp(r'\\mathbf\s*\{([^{}]+)\}'), r'$1');
  s = s.replaceAll(RegExp(r'\\math[a-zA-Z]+\s*\{([^{}]+)\}'), r'$1');
  s = s.replaceAll('{', '').replaceAll('}', '');
  return s;
}

/// Splits [text] into lines, each with its styled runs.
List<ChatLine> parseChatMarkdown(String text) {
  final counter = _Counter();
  final lines = <ChatLine>[];
  for (final raw in text.split('\n')) {
    final quote = raw.startsWith('> ');
    final body = quote ? raw.substring(2) : raw;
    lines.add(ChatLine(
      quote: quote,
      spans: _inline(body, const _Style(), counter),
    ));
  }
  return lines;
}

final RegExp _dividerPattern = RegExp(r'^\s*([-*_])(?:\s*\1){2,}\s*$');
final RegExp _taskPattern = RegExp(r'^(?:[-*+]|\d+\.)\s+\[([ xX])\]\s+(.*)$');
final RegExp _unorderedPattern = RegExp(r'^[-*+]\s+(.*)$');
final RegExp _orderedPattern = RegExp(r'^(\d+)\.\s+(.*)$');

/// Heuristically restores paragraph and list item line breaks when long text
/// was pasted without newlines.
String _restoreCollapsedStructure(String s) {
  if (s.length >= 250) {
    final nlCount = s.split('\n').length - 1;
    final density = s.length / (nlCount + 1);
    if (density > 180) {
      // 1. Break before Step X:
      s = s.replaceAllMapped(
        RegExp(r'([.!?\):])\s*(Step\s+\d+:)'),
        (m) => '${m.group(1)}\n\n${m.group(2)}',
      );
      // 2. Break before Phase X
      s = s.replaceAllMapped(
        RegExp(r'([.!?\):])\s*(Phase\s+[IVXLCDM\d]+(?:\s*[—-]\s*|\s*:))'),
        (m) => '${m.group(1)}\n\n${m.group(2)}',
      );
      // 3. Break before numbered question sub-items
      s = s.replaceAllMapped(
        RegExp(r'([.!?\):\]])\s*(\d+\([a-z\d]+\))'),
        (m) => '${m.group(1)}\n\n${m.group(2)}',
      );
      // 4. Break after [X Marks] or [Marks: ...]
      s = s.replaceAllMapped(
        RegExp(
            r'(\[\s*(?:\d+(?:\s*[+xX*]\s*\d+)*\s*Marks|Marks:[^\]]+)\s*\])\s*([A-Z\d])'),
        (m) => '${m.group(1)}\n\n${m.group(2)}',
      );
      // 5. Break before numbered list items
      s = s.replaceAllMapped(
        RegExp(r'([.!?\):]|(?<=[a-z]))\s*(\d+\.\s+[A-Z])'),
        (m) => '${m.group(1)}\n\n${m.group(2)}',
      );
      // 6. Break before Roman numeral headings
      s = s.replaceAllMapped(
        RegExp(r'([.!?\):])\s*([IVXLCDM]+\.\s+[A-Z])'),
        (m) => '${m.group(1)}\n\n${m.group(2)}',
      );
      // 7. Break before Question X
      s = s.replaceAllMapped(
        RegExp(r'([.!?\):\]])\s*(Question\s+\d+)'),
        (m) => '${m.group(1)}\n\n${m.group(2)}',
      );
      // 8. Break before Markdown headings (# H1 to ###### H6)
      s = s.replaceAllMapped(
        RegExp(r'([.!?\):\]])\s*(#{1,6}\s+)'),
        (m) => '${m.group(1)}\n\n${m.group(2)}',
      );
    }
  }
  return s;
}

/// Parses [text] into block-level elements (tables, code blocks, lists, headings, dividers, paragraphs).
String _autoWrapRawLatex(String s) {
  if (s.contains(r'$')) return s;
  final trimmed = s.trim();
  if (trimmed.isEmpty) return s;

  // Complex Indic / Bengali script must not be auto-wrapped into LaTeX math!
  // flutter_math_fork lacks HarfBuzz font shaping, which renders broken ligatures
  // and Unicode dotted circles (U+25CC).
  if (RegExp(r'[\u0980-\u09FF]').hasMatch(trimmed)) {
    return s;
  }

  const indicators = [
    r'\frac',
    r'\text{',
    r'\times',
    r'\sqrt',
    r'\sum',
    r'\mathbf{',
    r'\implies',
    r'\pm',
    r'\div',
    r'\cdot',
    r'\le',
    r'\ge',
    r'\neq',
    r'\approx',
  ];
  final hasIndicator = indicators.any((ind) => trimmed.contains(ind));
  if (!hasIndicator) return s;

  if (trimmed.startsWith(r'\text{') ||
      trimmed.startsWith(r'\frac') ||
      trimmed.startsWith(r'\sqrt') ||
      trimmed.startsWith(r'\mathbf{') ||
      trimmed.startsWith(r'\left') ||
      trimmed.contains(r'\frac') ||
      trimmed.contains(r'\times')) {
    return '\$$trimmed\$';
  }
  return s;
}

List<ChatBlock> parseChatBlocks(String text) {
  final counter = _Counter();

  // Fix corrupted LaTeX right-arrow carriage return artifact: \$ \n ightarrow\$ or \$\r?ightarrow\$
  var normalized = text.replaceAll(
    RegExp(r'\\?\$[\s\r\n]*\\?r?ightarrow\\?\$?', caseSensitive: false),
    '→',
  );
  normalized = normalized.replaceAll(r'\rightarrow', '→');
  normalized = normalized.replaceAll(r'\implies', '⇒');

  // Normalize line endings and unescape markdown brackets
  normalized = normalized.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  normalized = normalized.replaceAll(r'\[', '[').replaceAll(r'\]', ']');

  // Wrap display math $$...$$ with line breaks so it forms its own block
  normalized = normalized.replaceAllMapped(
    RegExp(r'(?<!\$)\$\$(.+?)\$\$(?!\$)', dotAll: true),
    (m) => '\n\n\$\$${m.group(1)}\$\$\n\n',
  );

  // Restore line breaks for collapsed/run-on pasted texts
  normalized = _restoreCollapsedStructure(normalized);

  // If newlines were collapsed into a single line, expand collapsed table rows
  if (!normalized.contains('\n') && normalized.contains('|')) {
    normalized = normalized.replaceAllMapped(
      RegExp(r'\|\s{1,}\|'),
      (_) => '|\n|',
    );
    normalized = normalized.replaceAllMapped(
      RegExp(r'(\|[^\n]+?)\s{2,}(\|?[^\n]+?\|)'),
      (m) => '${m.group(1)}\n${m.group(2)}',
    );
  }

  final rawLines = normalized.split('\n');
  final blocks = <ChatBlock>[];
  var i = 0;

  List<String> splitTableRow(String line) {
    var trimmed = line.trim();
    if (trimmed.startsWith('|')) {
      trimmed = trimmed.substring(1);
    }
    if (trimmed.endsWith('|')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed.split('|').map((c) => c.trim()).toList();
  }

  bool isTableDelimiter(String line) {
    final trimmed = line.trim();
    if (!trimmed.contains('-')) return false;
    final cells = splitTableRow(trimmed);
    if (cells.isEmpty) return false;
    final delimPattern = RegExp(r'^:?\s*-[\s-]*:?$');
    for (final cell in cells) {
      if (!delimPattern.hasMatch(cell)) return false;
    }
    return true;
  }

  ChatTableAlign parseAlign(String cell) {
    final starts = cell.startsWith(':');
    final ends = cell.endsWith(':');
    if (starts && ends) return ChatTableAlign.center;
    if (ends) return ChatTableAlign.right;
    return ChatTableAlign.left;
  }

  while (i < rawLines.length) {
    final line = rawLines[i];
    final trimmed = line.trim();

    // 0. Display Math Block ($$...$$)
    if (trimmed.startsWith(r'$$')) {
      if (trimmed.length > 2 && trimmed.endsWith(r'$$')) {
        final mathContent = trimmed.substring(2, trimmed.length - 2).trim();
        blocks.add(ChatMathBlock(mathContent));
        i++;
        continue;
      }
      final mathLines = <String>[];
      final firstLineBody = trimmed.substring(2).trim();
      if (firstLineBody.isNotEmpty) mathLines.add(firstLineBody);
      i++;
      while (i < rawLines.length && !rawLines[i].trim().endsWith(r'$$')) {
        mathLines.add(rawLines[i]);
        i++;
      }
      if (i < rawLines.length) {
        final lastTrimmed = rawLines[i].trim();
        final lastBody =
            lastTrimmed.substring(0, lastTrimmed.length - 2).trim();
        if (lastBody.isNotEmpty) mathLines.add(lastBody);
        i++;
      }
      blocks.add(ChatMathBlock(mathLines.join('\n')));
      continue;
    }

    // 1. Fenced Code Block
    if (trimmed.startsWith('```')) {
      final lang = trimmed.substring(3).trim();
      final codeLines = <String>[];
      i++;
      while (i < rawLines.length && !rawLines[i].trim().startsWith('```')) {
        codeLines.add(rawLines[i]);
        i++;
      }
      final code = codeLines.join('\n');
      final normalizedLang = lang.toLowerCase();
      final trimmedCode = code.trim();
      final isSvgFence = normalizedLang == 'svg' ||
          ((normalizedLang.isEmpty || normalizedLang == 'xml') &&
              trimmedCode.startsWith('<svg') &&
              trimmedCode.endsWith('</svg>'));

      if (isSvgFence) {
        blocks.add(ChatSvgBlock(trimmedCode));
      } else {
        // A chart fence that does not parse stays a plain code block, so the
        // mistake is seen in the text rather than dropped.
        final chart = lang == 'chart:ppc' ? PpcSpec.parse(code) : null;
        blocks.add(chart != null
            ? ChatChartBlock(chart)
            : ChatCodeBlock(code: code, language: lang.isEmpty ? null : lang));
      }
      if (i < rawLines.length) i++; // skip closing ```
      continue;
    }

    // 1b. Raw SVG Block
    if (trimmed.startsWith('<svg')) {
      final svgLines = <String>[rawLines[i]];
      var foundEnd = trimmed.contains('</svg>');
      i++;
      while (!foundEnd && i < rawLines.length) {
        svgLines.add(rawLines[i]);
        if (rawLines[i].contains('</svg>')) {
          foundEnd = true;
        }
        i++;
      }
      blocks.add(ChatSvgBlock(svgLines.join('\n').trim()));
      continue;
    }

    // 2. Markdown Table Detection
    // Must have a header row and a delimiter row immediately following.
    if (trimmed.contains('|') &&
        i + 1 < rawLines.length &&
        isTableDelimiter(rawLines[i + 1])) {
      final headerRawCells = splitTableRow(rawLines[i]);
      final delimCells = splitTableRow(rawLines[i + 1]);
      final colCount = headerRawCells.length;

      final alignments = <ChatTableAlign>[];
      for (var col = 0; col < colCount; col++) {
        if (col < delimCells.length) {
          alignments.add(parseAlign(delimCells[col]));
        } else {
          alignments.add(ChatTableAlign.left);
        }
      }

      final headers = headerRawCells
          .map((c) => ChatTableCell(
              _inline(_autoWrapRawLatex(c), const _Style(), counter)))
          .toList();

      i += 2; // skip header and delimiter

      final rows = <ChatTableRow>[];
      while (i < rawLines.length) {
        final rowLine = rawLines[i].trim();
        if (rowLine.isEmpty || !rowLine.contains('|')) break;
        final rawCells = splitTableRow(rowLine);
        if (rowLine == '|' || rawCells.every((c) => c.isEmpty)) {
          i++;
          continue;
        }
        final cells = <ChatTableCell>[];
        for (var col = 0; col < colCount; col++) {
          final cellText = col < rawCells.length ? rawCells[col] : '';
          cells.add(ChatTableCell(
              _inline(_autoWrapRawLatex(cellText), const _Style(), counter)));
        }
        rows.add(ChatTableRow(cells));
        i++;
      }

      blocks.add(ChatTableBlock(
        headers: headers,
        alignments: alignments,
        rows: rows,
      ));
      continue;
    }

    // 3. Section Headings (# H1, ## H2, ### H3)
    if (trimmed.startsWith('#')) {
      final match = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (match != null) {
        final level = match.group(1)!.length;
        final body = match.group(2)!;
        blocks.add(ChatHeadingBlock(
          level: level,
          spans: _inline(body, const _Style(), counter),
        ));
        i++;
        continue;
      }
    }

    // 4. Horizontal Rule / Divider
    if (_dividerPattern.hasMatch(trimmed) && trimmed.length >= 3) {
      blocks.add(const ChatDividerBlock());
      i++;
      continue;
    }

    // 5. Blockquotes (consecutive > lines)
    if (trimmed.startsWith('> ') || trimmed == '>') {
      final quoteRawLines = <String>[];
      final quoteLines = <ChatLine>[];
      while (i < rawLines.length) {
        final qLine = rawLines[i].trim();
        if (qLine.startsWith('> ') || qLine == '>') {
          final body = qLine.startsWith('> ') ? qLine.substring(2) : '';
          quoteRawLines.add(body);
          quoteLines.add(ChatLine(
            quote: true,
            spans: _inline(body, const _Style(), counter),
          ));
          i++;
        } else {
          break;
        }
      }
      final innerContent = quoteRawLines.join('\n');
      final innerBlocks = parseChatBlocks(innerContent);
      blocks.add(ChatQuoteBlock(blocks: innerBlocks, lines: quoteLines));
      continue;
    }

    // 6. Lists and Checklists
    final taskMatch = _taskPattern.firstMatch(trimmed);
    final unorderedMatch =
        taskMatch == null ? _unorderedPattern.firstMatch(trimmed) : null;
    final orderedMatch = (taskMatch == null && unorderedMatch == null)
        ? _orderedPattern.firstMatch(trimmed)
        : null;

    if (taskMatch != null || unorderedMatch != null || orderedMatch != null) {
      final isOrdered = orderedMatch != null;
      final items = <ChatListItem>[];

      while (i < rawLines.length) {
        final l = rawLines[i].trim();
        final tMatch = _taskPattern.firstMatch(l);
        if (tMatch != null) {
          final checked = tMatch.group(1)!.toLowerCase() == 'x';
          final body = tMatch.group(2)!;
          items.add(ChatListItem(
            isChecked: checked,
            spans: _inline(body, const _Style(), counter),
          ));
          i++;
          continue;
        }

        final uMatch = _unorderedPattern.firstMatch(l);
        if (uMatch != null && !isOrdered) {
          final body = uMatch.group(1)!;
          items.add(ChatListItem(
            spans: _inline(body, const _Style(), counter),
          ));
          i++;
          continue;
        }

        final oMatch = _orderedPattern.firstMatch(l);
        if (oMatch != null && isOrdered) {
          final num = int.tryParse(oMatch.group(1)!);
          final body = oMatch.group(2)!;
          items.add(ChatListItem(
            number: num,
            spans: _inline(body, const _Style(), counter),
          ));
          i++;
          continue;
        }

        break;
      }

      blocks.add(ChatListBlock(ordered: isOrdered, items: items));
      continue;
    }

    // 7. Standard Paragraphs
    final paraLines = <ChatLine>[];
    while (i < rawLines.length) {
      final next = rawLines[i];
      final nextTrimmed = next.trim();
      if (nextTrimmed.isEmpty) {
        // preserve blank line or break paragraph
        if (paraLines.isNotEmpty) {
          blocks.add(ChatParagraphBlock(List.from(paraLines)));
          paraLines.clear();
        }
        i++;
        continue;
      }

      // Check if next starts another block
      final isBlockStart = nextTrimmed.startsWith('```') ||
          nextTrimmed.startsWith(r'$$') ||
          nextTrimmed.startsWith('<svg') ||
          (nextTrimmed.contains('|') &&
              i + 1 < rawLines.length &&
              isTableDelimiter(rawLines[i + 1])) ||
          RegExp(r'^(#{1,6})\s+').hasMatch(nextTrimmed) ||
          (_dividerPattern.hasMatch(nextTrimmed) && nextTrimmed.length >= 3) ||
          nextTrimmed.startsWith('> ') ||
          _taskPattern.hasMatch(nextTrimmed) ||
          _unorderedPattern.hasMatch(nextTrimmed) ||
          _orderedPattern.hasMatch(nextTrimmed);

      if (isBlockStart) break;

      paraLines.add(ChatLine(
        quote: false,
        spans: _inline(next, const _Style(), counter),
      ));
      i++;
    }

    if (paraLines.isNotEmpty) {
      blocks.add(ChatParagraphBlock(paraLines));
    }
  }

  return blocks;
}

class _Counter {
  int next = 0;
}

class _Style {
  final bool bold;
  final bool italic;
  final bool strike;
  final bool underline;
  final bool highlight;
  final int? spoilerId;

  const _Style({
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.underline = false,
    this.highlight = false,
    this.spoilerId,
  });

  _Style copyWith({
    bool? bold,
    bool? italic,
    bool? strike,
    bool? underline,
    bool? highlight,
    int? spoilerId,
  }) {
    return _Style(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      strike: strike ?? this.strike,
      underline: underline ?? this.underline,
      highlight: highlight ?? this.highlight,
      spoilerId: spoilerId ?? this.spoilerId,
    );
  }
}

final RegExp _linkPattern = RegExp(r'https?://[^\s<>]+');
const int _schemeLength = 8; // "https://"
final RegExp _wordChar = RegExp(r'[\p{L}\p{N}_]', unicode: true);

List<ChatSpan> _inline(String s, _Style style, _Counter counter) {
  final out = <ChatSpan>[];
  final plain = StringBuffer();

  void flush() {
    if (plain.isEmpty) return;
    out.add(_span(plain.toString(), style));
    plain.clear();
  }

  var i = 0;
  while (i < s.length) {
    // 0. Inline Math: $...$
    if (s[i] == r'$' && !s.startsWith(r'$$', i)) {
      final end = s.indexOf(r'$', i + 1);
      if (end > i + 1 && !s.startsWith(r'$$', end)) {
        final mathContent = s.substring(i + 1, end);
        final startsWithDigitOrSpace =
            mathContent.startsWith(' ') || RegExp(r'^\d').hasMatch(mathContent);
        final endsWithSpace = mathContent.endsWith(' ');
        if (!startsWithDigitOrSpace &&
            !endsWithSpace &&
            !mathContent.contains('\n') &&
            mathContent.isNotEmpty) {
          flush();
          out.add(ChatSpan(
            mathContent.trim(),
            math: true,
            spoilerId: style.spoilerId,
          ));
          i = end + 1;
          continue;
        }
      }
    }

    // 1. Inline Code `code`
    if (s[i] == '`') {
      final end = s.indexOf('`', i + 1);
      if (end > i + 1) {
        flush();
        out.add(ChatSpan(
          s.substring(i + 1, end),
          bold: style.bold,
          italic: style.italic,
          strike: style.strike,
          underline: style.underline,
          highlight: style.highlight,
          code: true,
          spoilerId: style.spoilerId,
        ));
        i = end + 1;
        continue;
      }
    }

    // 2. Spoiler ||text||
    if (s.startsWith('||', i)) {
      final end = s.indexOf('||', i + 2);
      if (end > i + 2) {
        flush();
        final id = style.spoilerId ?? counter.next++;
        out.addAll(_inline(
            s.substring(i + 2, end), style.copyWith(spoilerId: id), counter));
        i = end + 2;
        continue;
      }
    }

    // 3. Bold **text**
    if (s.startsWith('**', i)) {
      final end = s.indexOf('**', i + 2);
      if (end > i + 2) {
        flush();
        out.addAll(_inline(
            s.substring(i + 2, end), style.copyWith(bold: true), counter));
        i = end + 2;
        continue;
      }
    }

    // 4. Underline __text__
    if (s.startsWith('__', i)) {
      final end = s.indexOf('__', i + 2);
      if (end > i + 2) {
        flush();
        out.addAll(_inline(
            s.substring(i + 2, end), style.copyWith(underline: true), counter));
        i = end + 2;
        continue;
      }
    }

    // 5. Strikethrough ~~text~~
    if (s.startsWith('~~', i)) {
      final end = s.indexOf('~~', i + 2);
      if (end > i + 2) {
        flush();
        out.addAll(_inline(
            s.substring(i + 2, end), style.copyWith(strike: true), counter));
        i = end + 2;
        continue;
      }
    }

    // 6. Highlight ==text==
    if (s.startsWith('==', i)) {
      final end = s.indexOf('==', i + 2);
      if (end > i + 2) {
        flush();
        out.addAll(_inline(
            s.substring(i + 2, end), style.copyWith(highlight: true), counter));
        i = end + 2;
        continue;
      }
    }

    // 7. Named Markdown Link [label](url)
    if (s[i] == '[') {
      final endBracket = s.indexOf(']', i + 1);
      if (endBracket > i + 1 &&
          endBracket + 1 < s.length &&
          s[endBracket + 1] == '(') {
        final endParen = s.indexOf(')', endBracket + 2);
        if (endParen > endBracket + 2) {
          final label = s.substring(i + 1, endBracket);
          final url = s.substring(endBracket + 2, endParen).trim();
          final isValidScheme = url.startsWith('http://') ||
              url.startsWith('https://') ||
              url.startsWith('mailto:') ||
              url.startsWith('tel:');
          if (isValidScheme) {
            flush();
            out.add(ChatSpan(
              label,
              bold: style.bold,
              italic: style.italic,
              strike: style.strike,
              underline: true,
              highlight: style.highlight,
              spoilerId: style.spoilerId,
              link: url,
            ));
            i = endParen + 1;
            continue;
          }
        }
      }
    }

    // 8. Italic *text* or _text_
    if (s[i] == '*' || s[i] == '_') {
      final marker = s[i];
      final opens = i + 1 < s.length && s[i + 1] != ' ' && s[i + 1] != marker;
      final wordStart =
          marker == '*' || i == 0 || !_wordChar.hasMatch(s[i - 1]);
      if (opens && wordStart) {
        final end = s.indexOf(marker, i + 1);
        final closesWell = end > i + 1 &&
            s[end - 1] != ' ' &&
            (marker == '*' ||
                end + 1 >= s.length ||
                !_wordChar.hasMatch(s[end + 1]));
        if (closesWell) {
          flush();
          out.addAll(_inline(
              s.substring(i + 1, end), style.copyWith(italic: true), counter));
          i = end + 1;
          continue;
        }
      }
    }

    // 9. Bare HTTP / HTTPS link
    final link = _linkPattern.matchAsPrefix(s, i);
    if (link != null) {
      final url = _trimTrailingPunctuation(link.group(0)!);
      if (url.length > _schemeLength) {
        flush();
        out.add(ChatSpan(
          url,
          bold: style.bold,
          italic: style.italic,
          strike: style.strike,
          underline: true,
          highlight: style.highlight,
          spoilerId: style.spoilerId,
          link: url,
        ));
        i += url.length;
        continue;
      }
    }

    plain.write(s[i]);
    i++;
  }
  flush();
  return out;
}

ChatSpan _span(String text, _Style style) {
  return ChatSpan(
    text,
    bold: style.bold,
    italic: style.italic,
    strike: style.strike,
    underline: style.underline,
    highlight: style.highlight,
    spoilerId: style.spoilerId,
  );
}

/// A link at the end of a sentence usually ends with punctuation that is not
/// part of the address.
String _trimTrailingPunctuation(String url) {
  var end = url.length;
  while (end > 0 && '.,;:!?)'.contains(url[end - 1])) {
    end--;
  }
  return url.substring(0, end);
}
