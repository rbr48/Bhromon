import 'invite_code.dart';

/// The host a group's QR code links to. Only links on this host are read as invitations.
const String inviteJoinHost = 'app.bhromon.fun';

/// The join link a group's QR code encodes: the web address that opens the join page for [code].
String inviteJoinLink(String code) =>
    'https://$inviteJoinHost/#/join?code=${code.trim().toUpperCase()}';

/// The invite code that a scanned or pasted text carries, or null when it carries none.
///
/// Accepts a bare code (in any case, with surrounding spaces ignored) or an https join link on
/// [inviteJoinHost], in the forms the app uses: `#/join?code=…`, `#/join/…` and `/join?code=…`.
/// Anything else is refused, so a QR code from somewhere else cannot start a join.
String? inviteCodeFromScan(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final bare = text.toUpperCase();
  if (isValidInviteCode(bare)) return bare;

  final link = Uri.tryParse(text);
  if (link == null ||
      link.scheme != 'https' ||
      link.host.toLowerCase() != inviteJoinHost) {
    return null;
  }
  return _codeInRoute(link.fragment) ??
      _codeInRoute('${link.path}?${link.query}');
}

/// The code in a route such as `/join?code=ABCD2345` or `/join/ABCD2345?name=Trip`, or null.
String? _codeInRoute(String route) {
  if (route.isEmpty) return null;
  final parsed = Uri.tryParse(route.startsWith('/') ? route : '/$route');
  if (parsed == null) return null;
  final segments = parsed.pathSegments;
  final String? code;
  if (segments.length == 1 && segments.first == 'join') {
    code = parsed.queryParameters['code'];
  } else if (segments.length == 2 && segments.first == 'join') {
    code = segments[1];
  } else {
    code = null;
  }
  final normalised = code?.trim().toUpperCase() ?? '';
  return isValidInviteCode(normalised) ? normalised : null;
}
