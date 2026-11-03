import 'package:bhromon/features/tour_group/domain/services/member_profile_sync.dart';
import 'package:flutter_test/flutter_test.dart';

class _Row {
  _Row(this.id, this.data);

  final String id;
  final Map<String, dynamic> data;
}

void main() {
  const uid = 'uid-1';
  const name = 'Rahim';
  const photo =
      'https://bhromon.fun/media/t1/avatars/0123456789abcdef0123456789abcdef.jpg';

  Map<String, Object> updatesFor(_Row row) => memberRowUpdates(
        row: row.data,
        uid: uid,
        displayName: name,
        photoUrl: photo,
      );

  test('a row that already matches the profile is not written', () async {
    final rows = [
      _Row('a', {'uid': uid, 'displayName': name, 'photoUrl': photo}),
    ];
    final writes = <String>[];

    final written = await applyMemberRowSync<_Row>(
      rows,
      updatesFor: updatesFor,
      write: (row, updates) async => writes.add(row.id),
      onFailure: (error, stackTrace) => fail('no write should fail: $error'),
    );

    expect(written, 0);
    expect(writes, isEmpty);
  });

  test('a row that differs is written once, with only the fields that changed',
      () async {
    final rows = [
      _Row('a', {'displayName': 'Old name'}),
    ];
    final sent = <Map<String, Object>>[];

    final written = await applyMemberRowSync<_Row>(
      rows,
      updatesFor: updatesFor,
      write: (row, updates) async => sent.add(updates),
      onFailure: (error, stackTrace) => fail('no write should fail: $error'),
    );

    expect(written, 1);
    expect(sent, hasLength(1));
    expect(sent.single, {'uid': uid, 'displayName': name, 'photoUrl': photo});
  });

  test('a failed write is reported, and the other rows are still written',
      () async {
    final rows = [_Row('a', {}), _Row('b', {}), _Row('c', {})];
    final writtenIds = <String>[];
    final failures = <Object>[];

    final written = await applyMemberRowSync<_Row>(
      rows,
      updatesFor: updatesFor,
      write: (row, updates) async {
        if (row.id == 'b') throw StateError('permission denied');
        writtenIds.add(row.id);
      },
      onFailure: (error, stackTrace) => failures.add(error),
    );

    expect(written, 2);
    expect(writtenIds, ['a', 'c']);
    expect(failures, hasLength(1));
    expect(failures.single, isA<StateError>());
  });

  test('a second run over the same rows writes nothing', () async {
    final store = <String, Map<String, dynamic>>{
      'a': {'displayName': 'Old name'},
      'b': {},
    };
    Future<int> run() => applyMemberRowSync<_Row>(
          store.entries.map((e) => _Row(e.key, e.value)).toList(),
          updatesFor: updatesFor,
          write: (row, updates) async => store[row.id]!.addAll(updates),
          onFailure: (error, stackTrace) => fail('no write should fail'),
        );

    expect(await run(), 2);
    expect(await run(), 0);
    expect(store['a']!['uid'], uid);
    expect(store['b']!['photoUrl'], photo);
  });
}
