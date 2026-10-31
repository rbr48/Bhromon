// What a notice says when it is read aloud: its title, its text, then when it is
// and where. Pure text, so the wording is tested without a voice engine.

/// Builds the spoken text. Empty parts are skipped. A part that does not end in a
/// full stop, a question mark or an exclamation mark gets one, in the language's
/// own style (a Bengali sentence ends with "।").
///
/// [timeSentence] and [placeSentence] are already worded for the language, such
/// as "At 6:00 AM" or "Place: Lobby".
String noticeSpeechText({
  required String title,
  required String content,
  String? timeSentence,
  String? placeSentence,
  required bool bengali,
}) {
  final end = bengali ? '।' : '.';
  final endsSentence = RegExp(r'[.!?।]$');
  final sentences = <String>[];

  void add(String? part) {
    final text = part?.trim() ?? '';
    if (text.isEmpty) return;
    sentences.add(endsSentence.hasMatch(text) ? text : '$text$end');
  }

  add(title);
  add(content);
  add(timeSentence);
  add(placeSentence);
  return sentences.join(' ');
}
