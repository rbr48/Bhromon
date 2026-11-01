import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Signed links for private media. The media server (media-server/media_access.py) gives
/// each person a key, and serves a file only to a link that carries a valid signature for
/// that person. The app signs its links here, with the key it was given.

const String _mediaPrefix = 'https://bhromon.fun/media/';
const String _signingPrefix = 'v1|';

/// The paths the media server serves: /media/{space}/{folder}/{file}, with the file names it
/// issues. Any other URL is not signed, and is used as it is.
final RegExp _signablePath = RegExp(
  r'^/media/[A-Za-z0-9_-]{1,128}/[a-z_]{1,32}/[0-9a-f]{32}\.'
  r'(jpg|jpeg|png|webp|gif|heic|heif|mp4|mov|m4v|webm|3gp|mkv|m4a|mp3|aac|wav|ogg|opus|pdf|doc|docx|xls|xlsx|ppt|pptx|txt|csv|zip)$',
);
final RegExp _safeUid = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// The signature of [path] under [key], as the media server computes it: HMAC-SHA256 of
/// `v1|` followed by the path, keyed with the key's text, in base64url without padding.
String mediaSignature(String key, String path) {
  final digest = Hmac(sha256, utf8.encode(key))
      .convert(utf8.encode('$_signingPrefix$path'));
  return base64Url.encode(digest.bytes).replaceAll('=', '');
}

/// [url] with `u` and `s` added, so the media server serves it to [uid]. A URL that is not one
/// of ours, or that already has a query, comes back unchanged.
String signMediaUrl(String url, {required String uid, required String key}) {
  if (!url.startsWith(_mediaPrefix) || !_safeUid.hasMatch(uid)) return url;
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty) {
    return url;
  }
  if (!_signablePath.hasMatch(uri.path)) return url;
  return '$url?u=$uid&s=${mediaSignature(key, uri.path)}';
}
