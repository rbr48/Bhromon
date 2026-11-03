import 'package:bhromon/features/tour_group/domain/services/member_profile_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const url =
      'https://bhromon.fun/media/profiles/avatars/0123456789abcdef0123456789abcdef.jpg';

  test('a row that already matches gets no write', () {
    expect(
      memberRowUpdates(
        row: {'uid': 'u1', 'displayName': 'Rahim', 'photoUrl': url},
        uid: 'u1',
        displayName: 'Rahim',
        photoUrl: url,
      ),
      isEmpty,
    );
  });

  test('a row without a uid gets the uid, and an empty uid counts as missing',
      () {
    expect(
      memberRowUpdates(
          row: {'displayName': 'Rahim'},
          uid: 'u1',
          displayName: 'Rahim',
          photoUrl: null),
      {'uid': 'u1'},
    );
    expect(
      memberRowUpdates(
          row: {'uid': ''}, uid: 'u1', displayName: 'Rahim', photoUrl: null),
      {'uid': 'u1', 'displayName': 'Rahim'},
    );
  });

  test('the placeholder name is never written', () {
    expect(
      memberRowUpdates(
          row: {'uid': 'u1', 'displayName': 'Old'},
          uid: 'u1',
          displayName: 'Explorer',
          photoUrl: null),
      isEmpty,
    );
  });

  test('a changed name is written', () {
    expect(
      memberRowUpdates(
          row: {'uid': 'u1', 'displayName': 'Old'},
          uid: 'u1',
          displayName: 'New',
          photoUrl: null),
      {'displayName': 'New'},
    );
  });

  test('a profile without a photo leaves the row photo alone', () {
    expect(
      memberRowUpdates(
          row: {'uid': 'u1', 'displayName': 'Rahim', 'photoUrl': url},
          uid: 'u1',
          displayName: 'Rahim',
          photoUrl: null),
      isEmpty,
    );
  });

  test('the photo is written when it differs', () {
    expect(
      memberRowUpdates(
          row: {'uid': 'u1', 'displayName': 'Rahim'},
          uid: 'u1',
          displayName: 'Rahim',
          photoUrl: url),
      {'photoUrl': url},
    );
  });

  test('applying the updates once is enough: a second pass writes nothing', () {
    final row = <String, dynamic>{'displayName': 'Old'};
    final first = memberRowUpdates(
        row: row, uid: 'u1', displayName: 'New', photoUrl: url);
    final merged = {...row, ...first};
    expect(
        memberRowUpdates(
            row: merged, uid: 'u1', displayName: 'New', photoUrl: url),
        isEmpty);
  });
}
