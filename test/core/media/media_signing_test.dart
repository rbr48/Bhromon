import 'package:bhromon/core/media/media_signing.dart';
import 'package:flutter_test/flutter_test.dart';

// These reference values are the ones media-server/tests/test_media_access.py checks, so the
// app and the media server agree on every signature.
const String _keyAlice = 'oJ1WRboA_XoAcNYlTsgzTVWOOKQNhYMybHxcuXMHph0';
const String _signatureAlicePath =
    '6piNFezcCVn8Hdbk6KXFKcjVXuAqI_DHsixeQRqoDAY';
const String _path = '/media/t1/posts/0123456789abcdef0123456789abcdef.jpg';
const String _url = 'https://bhromon.fun$_path';

void main() {
  test('the signature matches the media server', () {
    expect(mediaSignature(_keyAlice, _path), _signatureAlicePath);
  });

  test('a media URL is signed for its person', () {
    expect(
      signMediaUrl(_url, uid: 'uid-alice', key: _keyAlice),
      '$_url?u=uid-alice&s=$_signatureAlicePath',
    );
  });

  test('a signed URL is not signed again', () {
    final signed = signMediaUrl(_url, uid: 'uid-alice', key: _keyAlice);
    expect(signMediaUrl(signed, uid: 'uid-alice', key: _keyAlice), signed);
  });

  test('URLs that are not private media are left as they are', () {
    const urls = [
      'https://bhromon.fun/media/apk/bhromon-release.apk',
      'https://lh3.googleusercontent.com/a/photo.jpg',
      '/data/user/0/app/cache/picked.jpg',
      'https://bhromon.fun/media/t1/posts/../../secret.jpg',
      'https://bhromon.fun/media/t1/posts/photo.jpg',
    ];
    for (final url in urls) {
      expect(signMediaUrl(url, uid: 'uid-alice', key: _keyAlice), url);
    }
  });

  test('a uid with unexpected characters is not signed', () {
    expect(signMediaUrl(_url, uid: 'uid alice', key: _keyAlice), _url);
  });
}
