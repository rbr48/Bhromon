// The labels of an SVG figure, made safe for a printed booklet. The booklet's built-in font draws
// ASCII and Latin-1 letters only, and a label with any other character stops the whole booklet at
// save time, after the figure has been placed. So the common symbols become plain words, Latin-1
// letters stay, and the rest is dropped. The app draws the figure with its own font, so only the
// printed booklet changes. This file is plain Dart, so it can be tested without the PDF package.

/// The plain form of the symbols a figure label commonly carries.
const Map<String, String> _plainForms = {
  '→': '->', // right arrow
  '➔': '->', // heavy wide-headed right arrow
  '➜': '->', // heavy round-tipped right arrow
  '➝': '->', // triangle-headed right arrow
  '⟶': '->', // long right arrow
  '⇒': '=>', // double right arrow
  '←': '<-', // left arrow
  '⇐': '<=', // double left arrow
  '↑': 'up', // up arrow
  '↓': 'down', // down arrow
  '≥': '>=', // greater than or equal to
  '≤': '<=', // less than or equal to
  '≠': '!=', // not equal to
  '≈': '~', // almost equal to
  '∞': 'inf', // infinity
  '√': 'sqrt', // square root
  'Δ': 'Delta', // Greek capital delta
  'Σ': 'Sum', // Greek capital sigma
  'σ': 'sigma', // Greek small sigma
  'α': 'alpha', // Greek small alpha
  'β': 'beta', // Greek small beta
  'ε': 'epsilon', // Greek small epsilon
  'λ': 'lambda', // Greek small lambda
  'μ': 'mu', // Greek small mu
  'π': 'pi', // Greek small pi
  '—': '-', // em dash
  '–': '-', // en dash
  '−': '-', // minus sign
  '•': '-', // bullet
  '…': '...', // ellipsis
  '“': '"', // left double quotation mark
  '”': '"', // right double quotation mark
  '‘': "'", // left single quotation mark
  '’': "'", // right single quotation mark
  '⁰': '0', // superscript zero
  '⁴': '4', // superscript four
  '⁵': '5', // superscript five
  '⁶': '6', // superscript six
  '⁷': '7', // superscript seven
  '⁸': '8', // superscript eight
  '⁹': '9', // superscript nine
  '₀': '0', // subscript zero
  '₁': '1', // subscript one
  '₂': '2', // subscript two
  '₃': '3', // subscript three
  '₄': '4', // subscript four
  '₅': '5', // subscript five
  '₆': '6', // subscript six
  '₇': '7', // subscript seven
  '₈': '8', // subscript eight
  '₉': '9', // subscript nine
};

/// A `<text>` element, from its start tag to its end tag.
final RegExp _textElement =
    RegExp(r'<text\b[^>]*>[\s\S]*?</text>', caseSensitive: false);

/// One tag inside a `<text>` element, such as a `<tspan>` or the element's own tags.
final RegExp _tag = RegExp(r'<[^>]*>');

/// A character reference: `&amp;`, `&lt;`, `&#8594;`, `&#x2192;` and the like.
final RegExp _reference =
    RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);');

/// The SVG with the characters of its `<text>` labels made safe for the booklet's font. Tags,
/// shapes and attributes are left as they are, and so is the markup inside a label.
String studyBookletPdfSafeSvg(String svg) {
  return svg.replaceAllMapped(
    _textElement,
    (match) => _safeTextElement(match.group(0)!),
  );
}

/// One `<text>` element with its text runs cleaned and its tags kept.
String _safeTextElement(String element) {
  final out = StringBuffer();
  var last = 0;
  for (final tag in _tag.allMatches(element)) {
    out.write(_safeRun(element.substring(last, tag.start)));
    out.write(tag.group(0));
    last = tag.end;
  }
  out.write(_safeRun(element.substring(last)));
  return out.toString();
}

/// The characters of one run of label text, with no tags in it: decoded, mapped, and escaped again.
String _safeRun(String run) {
  final decoded = run.replaceAllMapped(
      _reference, (match) => _referenceText(match.group(1)!));
  final out = StringBuffer();
  for (final rune in decoded.runes) {
    if (rune == 0x09 || rune == 0x0A || rune == 0x0D) {
      out.write(' ');
    } else if ((rune >= 0x20 && rune <= 0x7E) ||
        (rune >= 0xA0 && rune <= 0xFF)) {
      out.writeCharCode(rune);
    } else {
      out.write(_plainForms[String.fromCharCode(rune)] ?? '');
    }
  }
  return out
      .toString()
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

/// What a character reference stands for. An unknown or out-of-range reference stands for nothing.
String _referenceText(String name) {
  switch (name) {
    case 'amp':
      return '&';
    case 'lt':
      return '<';
    case 'gt':
      return '>';
    case 'quot':
      return '"';
    case 'apos':
      return "'";
  }
  final code = name.startsWith('#x')
      ? int.tryParse(name.substring(2), radix: 16)
      : int.tryParse(name.substring(1));
  if (code == null || code > 0x10FFFF) return '';
  return String.fromCharCode(code);
}
