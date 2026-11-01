import 'package:bhromon/core/media/media_signing.dart';
import 'package:flutter_test/flutter_test.dart';

// The media server (media-server/tests/test_media_access.py) checks the same fixture
// signature, so the app and the server agree on the signature of one path.
const String _fixture = 'reference-fixture';
const String _fixtureSignature = '2PftvSx_pqisla3aVd1117iZJWrvKfvdi7vhkOwDAdI';
const String _path = '/media/t1/posts/0123456789abcdef0123456789abcdef.jpg';
const String _url = 'https://bhromon.fun$_path';

void main() {
  test('the signature matches the media server', () {
    expect(mediaSignature(_fixture, _path), _fixtureSignature);
  });

  test('a media URL is signed for its person', () {
    expect(
      signMediaUrl(_url, uid: 'uid-alice', key: _fixture),
      '$_url?u=uid-alice&s=$_fixtureSignature',
    );
  });

  test('a signed URL is not signed again', () {
    final signed = signMediaUrl(_url, uid: 'uid-alice', key: _fixture);
    expect(signMediaUrl(signed, uid: 'uid-alice', key: _fixture), signed);
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
      expect(signMediaUrl(url, uid: 'uid-alice', key: _fixture), url);
    }
  });

  test('a uid with unexpected characters is not signed', () {
    expect(signMediaUrl(_url, uid: 'uid alice', key: _fixture), _url);
  });
}
