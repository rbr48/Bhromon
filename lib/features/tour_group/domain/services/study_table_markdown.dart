// Markdown pipe tables in study text: the grid an editor works on, and the text it is saved as. The chat
// renders the same syntax (chat_markdown.dart), so a table written here shows the same way everywhere. Pure
// Dart, so the editor, the composer and the tests read a table the same way.

/// A table found in a piece of text: where it starts and ends, and its cells. Row 0 is the header.
class StudyTableBlock {
  const StudyTableBlock({
    required this.start,
    required this.end,
    required this.rows,
  });

  /// The offset of the table's first character.
  final int start;

  /// The offset just after the table's last character, before any line break that follows it.
  final int end;

  /// The cells, row by row. Every row has the same number of cells as the header.
  final List<List<String>> rows;
}

/// The grid of a new table: a header row and one body row, two columns.
List<List<String>> newStudyTable() => [
      ['', ''],
      ['', ''],
    ];

/// The table as markdown: a header, a separator, then one line per row. A pipe in a cell is escaped, and a
/// line break in a cell becomes a space, so every row stays on one line. Empty cells are kept.
String studyTableMarkdown(List<List<String>> rows) {
  final columns = rows.isEmpty ? 1 : rows.first.length;
  String line(List<String> cells) {
    final padded = [
      for (var i = 0; i < columns; i++)
        i < cells.length ? _escapeCell(cells[i]) : '',
    ];
    return '| ${padded.join(' | ')} |';
  }

  final header = rows.isEmpty ? <String>[] : rows.first;
  final separator = '| ${List.filled(columns, '---').join(' | ')} |';
  final body = rows.skip(1).map(line);
  return [line(header), separator, ...body].join('\n');
}

/// The grid a markdown table's lines describe, or null when they are not a table: a header line, a separator
/// line of dashes, then rows, each starting and ending with a pipe. A row with fewer cells than the header is
/// padded with empty cells, and one with more is cut to the header's width, so every row has the same width.
List<List<String>>? parseStudyTableLines(List<String> lines) {
  if (lines.length < 2) return null;
  final header = _cells(lines[0]);
  if (header == null || header.isEmpty) return null;
  final separator = _cells(lines[1]);
  if (separator == null ||
      separator.length != header.length ||
      !separator.every(_separatorCell.hasMatch)) {
    return null;
  }
  List<String> fit(List<String> cells) => [
        for (var i = 0; i < header.length; i++)
          i < cells.length ? cells[i] : '',
      ];

  final rows = <List<String>>[header];
  for (final line in lines.skip(2)) {
    final cells = _cells(line);
    if (cells == null) return null;
    rows.add(fit(cells));
  }
  return rows;
}

/// The table the offset falls in, or null. A table is a run of lines that start with a pipe, whose first two
/// lines are a header and a separator. An offset on the line right after a table still counts as outside it.
StudyTableBlock? studyTableAt(String text, int offset) {
  if (offset < 0 || offset > text.length) return null;
  final lines = <_Line>[];
  var start = 0;
  for (final raw in text.split('\n')) {
    lines.add(_Line(start, start + raw.length, raw));
    start += raw.length + 1;
  }
  for (var first = 0; first < lines.length; first++) {
    if (!_startsTable(lines[first].text)) continue;
    var last = first;
    while (last + 1 < lines.length && _startsTable(lines[last + 1].text)) {
      last++;
    }
    final block = lines.sublist(first, last + 1);
    final rows = parseStudyTableLines([for (final l in block) l.text]);
    if (rows == null) {
      first = last;
      continue;
    }
    final blockStart = block.first.start;
    final blockEnd = block.last.end;
    if (offset >= blockStart && offset <= blockEnd) {
      return StudyTableBlock(start: blockStart, end: blockEnd, rows: rows);
    }
    first = last;
  }
  return null;
}

/// The result of an insert or a replace: the new text, and where the cursor belongs in it.
class StudyTextEdit {
  const StudyTextEdit(this.text, this.cursor);
  final String text;
  final int cursor;
}

/// [text] with [replacement] put in place of the range [start, end), on lines of its own: a line break is
/// added before and after where the text next to it is not already one.
StudyTextEdit replaceStudyRange(
  String text,
  int start,
  int end,
  String replacement,
) {
  final before = text.substring(0, start);
  final after = text.substring(end);
  final lead = before.isEmpty || before.endsWith('\n') ? '' : '\n';
  final tail = after.isEmpty || after.startsWith('\n') ? '' : '\n';
  final inserted = '$lead$replacement$tail';
  return StudyTextEdit(
    before + inserted + after,
    before.length + inserted.length - tail.length,
  );
}

/// A cell that is a separator: dashes, with optional colons for alignment.
final RegExp _separatorCell = RegExp(r'^:?-{3,}:?$');

/// A pipe in a cell is written as `\|`, so it does not end the cell.
final RegExp _unescapedPipe = RegExp(r'(?<!\\)\|');

class _Line {
  const _Line(this.start, this.end, this.text);
  final int start;
  final int end;
  final String text;
}

bool _startsTable(String line) => line.trimLeft().startsWith('|');

/// The cells of one table line, or null when the line is not a row: it must start and end with a pipe.
List<String>? _cells(String line) {
  final trimmed = line.trim();
  if (trimmed.length < 2 ||
      !trimmed.startsWith('|') ||
      !trimmed.endsWith('|')) {
    return null;
  }
  final inner = trimmed.substring(1, trimmed.length - 1);
  return [
    for (final part in inner.split(_unescapedPipe))
      part.trim().replaceAll(r'\|', '|'),
  ];
}

String _escapeCell(String cell) =>
    cell.replaceAll(RegExp(r'[\r\n]+'), ' ').replaceAll('|', r'\|').trim();
