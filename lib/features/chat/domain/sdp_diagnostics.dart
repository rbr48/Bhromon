/// The Opus format lines of an SDP, for checking the audio settings on a real
/// call. Opus is found by its rtpmap line, and its fmtp lines are returned.
/// For example `a=fmtp:111 minptime=10;useinbandfec=1` is one of them.
List<String> opusFmtpLines(String sdp) {
  final lines = sdp.split(RegExp(r'\r?\n'));
  final payloads = <String>{};
  final rtpmap = RegExp(r'^a=rtpmap:(\d+) opus/', caseSensitive: false);
  for (final line in lines) {
    final match = rtpmap.firstMatch(line);
    if (match != null) payloads.add(match.group(1)!);
  }
  final fmtp = RegExp(r'^a=fmtp:(\d+) ');
  final found = <String>[];
  for (final line in lines) {
    final match = fmtp.firstMatch(line);
    if (match != null && payloads.contains(match.group(1))) found.add(line);
  }
  return found.isEmpty ? const ['no Opus fmtp line'] : found;
}
