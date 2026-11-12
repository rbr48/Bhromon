// Plain text for study cards. A past-year solution is markdown, and a flashcard is shown as plain text,
// so the markup is taken out where a card is made and where it is shown. A card made before that already
// holds the markup, so the same conversion runs on it when it is shown or exported.

/// The marks a solution may escape with a backslash. While the markup is removed, each escaped mark is held
/// as a private-use character, so it is never read as markup, and it is put back at the end.
const String _escapable = r'\`*_{}[]()#+-.!>|~';

/// Plain text from markdown: the words stay, and the markup goes.
///
/// Emphasis, strikethrough, headings, quote marks, code marks, links, images, escapes, rules and HTML comments
/// are removed. A list item gets a bullet, a table row reads as its cells joined with a dot, and a `chart:ppc`
/// or `svg` figure is dropped, since a card has no room for one. Line breaks stay. Plain text comes back as it
/// went in, so a card saved before this conversion reads the same as one made after it.
String plainTextFromMarkdown(String source) {
  var text = source.replaceAll('\r\n', '\n');

  // Comments, figures and line breaks.
  text = text
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
      .replaceAll(
        RegExp(
          r'^```[ \t]*(?:chart:ppc|svg)\b[^\n]*\n[\s\S]*?^```[ \t]*$',
          multiLine: true,
        ),
        '',
      )
      .replaceAll(RegExp(r'<svg\b[\s\S]*?</svg>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');

  // Escaped marks become private-use characters until the markup is gone.
  text = text.replaceAllMapped(RegExp(r'\\([\\`*_{}\[\]()#+\-.!>|~])'), (m) {
    final index = _escapable.indexOf(m.group(1)!);
    return index < 0 ? m.group(0)! : String.fromCharCode(0xE000 + index);
  });

  // An image keeps its alt text and a link keeps its words. The address goes.
  text = text
      .replaceAllMapped(
        RegExp(r'!\[([^\]\n]*)\]\([^)\n]*\)'),
        (m) => m.group(1)!,
      )
      .replaceAllMapped(
        RegExp(r'\[([^\]\n]+)\]\([^)\n]*\)'),
        (m) => m.group(1)!,
      );

  // Code: the fence lines go, the code stays, and inline code loses its marks.
  text = text
      .replaceAll(RegExp(r'^[ \t]*```[^\n]*$', multiLine: true), '')
      .replaceAllMapped(RegExp(r'`([^`\n]+)`'), (m) => m.group(1)!);

  // Headings and quote marks, then rules, then tables and list bullets. A table's separator row goes before
  // its rows are read, or it would show as cells of dashes.
  text = text
      .replaceAll(RegExp(r'^[ \t]{0,3}#{1,6}[ \t]+', multiLine: true), '')
      .replaceAll(RegExp(r'^[ \t]*(?:>[ \t]?)+', multiLine: true), '')
      .replaceAll(
        RegExp(r'^[ \t]*([-*_])(?:[ \t]*\1){2,}[ \t]*$', multiLine: true),
        '',
      )
      .replaceAll(
        RegExp(
          r'^(?=[^\n]*\|)[ \t]*\|?[ \t]*:?-{2,}:?[ \t]*(?:\|[ \t]*:?-{2,}:?[ \t]*)*\|?[ \t]*$\n?',
          multiLine: true,
        ),
        '',
      )
      .replaceAllMapped(
        RegExp(r'^[ \t]*\|(.+)\|[ \t]*$', multiLine: true),
        (m) => m
            .group(1)!
            .split('|')
            .map((cell) => cell.trim())
            .where((cell) => cell.isNotEmpty)
            .join(' · '),
      )
      .replaceAllMapped(
        RegExp(r'^([ \t]*)[-*+][ \t]+', multiLine: true),
        (m) => '${m.group(1)}• ',
      );

  // Emphasis. A marker must touch a word on each side, so 2 * 3 * 4 and snake_case stay as they are.
  text = text
      .replaceAllMapped(
        RegExp(r'(\*\*|__)(?=\S)([^\n]*?\S)\1'),
        (m) => m.group(2)!,
      )
      .replaceAllMapped(
        RegExp(r'(?<![\w*])\*(?=\S)([^*\n]*?\S)\*(?![\w*])'),
        (m) => m.group(1)!,
      )
      .replaceAllMapped(
        RegExp(r'(?<![\w_])_(?=\S)([^_\n]*?\S)_(?![\w_])'),
        (m) => m.group(1)!,
      )
      .replaceAllMapped(RegExp(r'~~(?=\S)([^\n]*?\S)~~'), (m) => m.group(1)!);

  // The escaped marks come back as themselves.
  for (var i = 0; i < _escapable.length; i++) {
    text = text.replaceAll(String.fromCharCode(0xE000 + i), _escapable[i]);
  }

  // Tidy: no trailing spaces, and no run of more than one blank line.
  text = text
      .replaceAll(RegExp(r'[ \t]+$', multiLine: true), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}
