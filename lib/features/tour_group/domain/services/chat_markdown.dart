// Formatting for channel messages. Kept free of Flutter so it can be tested.
//
// Supported: **bold**, *italic* or _italic_, ~~strike~~, `code`, ||spoiler||,
// a line starting with "> " (quote), and http or https links. Anything else,
// including a marker with no partner, is shown exactly as typed.

/// A run of text that shares one set of styles.
class ChatSpan {
  final String text;
  final bool bold;
  final bool italic;
  final bool strike;
  final bool code;

  /// Set for text hidden behind a spoiler. Spans of the same spoiler share an id.
  final int? spoilerId;

  /// Set for a link. The text is the link itself.
  final String? link;

  const ChatSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.code = false,
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

class _Counter {
  int next = 0;
}

class _Style {
  final bool bold;
  final bool italic;
  final bool strike;
  final int? spoilerId;

  const _Style({
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.spoilerId,
  });

  _Style copyWith({bool? bold, bool? italic, bool? strike, int? spoilerId}) {
    return _Style(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      strike: strike ?? this.strike,
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
    if (s[i] == '`') {
      final end = s.indexOf('`', i + 1);
      if (end > i + 1) {
        flush();
        out.add(ChatSpan(
          s.substring(i + 1, end),
          bold: style.bold,
          italic: style.italic,
          strike: style.strike,
          code: true,
          spoilerId: style.spoilerId,
        ));
        i = end + 1;
        continue;
      }
    }

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
