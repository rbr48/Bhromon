import 'package:bhromon/core/media/media_access.dart';
import 'package:bhromon/core/media/media_signing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const url =
      'https://bhromon.fun/media/t1/avatars/0123456789abcdef0123456789abcdef.jpg';

  test('a link is signed for the key in use, and the same link comes back', () {
    MediaAccess.instance.debugSetCredentials('uid1', 'key1');
    final first = MediaAccess.instance.sign(url);
    expect(first, signMediaUrl(url, uid: 'uid1', key: 'key1'));
    expect(MediaAccess.instance.sign(url), first);
  });

  test('a new key signs the same URL again, so no stale link is kept', () {
    MediaAccess.instance.debugSetCredentials('uid1', 'key1');
    final before = MediaAccess.instance.sign(url);
    MediaAccess.instance.debugSetCredentials('uid1', 'key2');
    final after = MediaAccess.instance.sign(url);
    expect(after, isNot(before));
    expect(after, signMediaUrl(url, uid: 'uid1', key: 'key2'));
  });

  test('without a key the URL is returned unsigned', () {
    MediaAccess.instance.debugSetCredentials(null, null);
    expect(MediaAccess.instance.sign(url), url);
  });
}
