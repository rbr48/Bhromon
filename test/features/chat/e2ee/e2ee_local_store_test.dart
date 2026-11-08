import 'dart:io';
import 'dart:typed_data';

import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:bhromon/features/chat/data/e2ee/e2ee_local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../../../helpers/perf_fixtures.dart';

// The device's own state for one account (E2EE_DESIGN.md, sections 6 and 9), kept in a
// real encrypted Hive box. Erasing an account removes its box and no other account's.

void main() {
  late Directory dir;
  late HiveEncryptionService encryption;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bhromon_e2ee_store_');
    Hive.init(dir.path);
    encryption = HiveEncryptionService.withStorage(CountingSecureStorage());
  });

  tearDown(() async {
    try {
      await Hive.close();
    } catch (_) {}
    if (dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  File boxFile(String userId) => File('${dir.path}/e2ee_state_$userId.hive');

  Future<void> keepStateFor(HiveE2eeLocalStore store, String tag) async {
    await store.writeDeviceId('device-$tag');
    await store.writeAccountPickle(Uint8List.fromList([1, 2, 3]));
    await store.writePlaintext('chat-1', 'msg-$tag', 'text-$tag');
  }

  test('erasing an account removes its keys and its kept text from the device',
      () async {
    final store = HiveE2eeLocalStore(encryption, userId: 'uid-a');
    await keepStateFor(store, 'a');
    expect(boxFile('uid-a').existsSync(), isTrue);

    await store.erase();

    expect(boxFile('uid-a').existsSync(), isFalse);
    final after = HiveE2eeLocalStore(encryption, userId: 'uid-a');
    expect(await after.readDeviceId(), isNull);
    expect(await after.readAccountPickle(), isNull);
    expect(await after.readPlaintext('chat-1', 'msg-a'), isNull);
  });

  test('erasing one account leaves every other account on the device as it was',
      () async {
    final alice = HiveE2eeLocalStore(encryption, userId: 'uid-a');
    final bob = HiveE2eeLocalStore(encryption, userId: 'uid-b');
    await keepStateFor(alice, 'a');
    await keepStateFor(bob, 'b');

    await alice.erase();

    expect(boxFile('uid-b').existsSync(), isTrue);
    expect(await bob.readDeviceId(), 'device-b');
    expect(await bob.readPlaintext('chat-1', 'msg-b'), 'text-b');
  });

  test('an account erased here starts empty when it is used again', () async {
    final store = HiveE2eeLocalStore(encryption, userId: 'uid-a');
    await keepStateFor(store, 'a');
    await store.erase();

    final again = HiveE2eeLocalStore(encryption, userId: 'uid-a');
    await again.writeDeviceId('device-new');

    expect(await again.readDeviceId(), 'device-new');
    expect(await again.readPlaintext('chat-1', 'msg-a'), isNull);
  });

  test('erasing an account that never kept anything is harmless', () async {
    final store = HiveE2eeLocalStore(encryption, userId: 'uid-x');

    await store.erase();

    expect(await store.readDeviceId(), isNull);
  });

  test(
      'without a device key the state is session-only, and erasing it leaves nothing',
      () async {
    final noKey = HiveEncryptionService.withStorage(FailingSecureStorage());
    final store = HiveE2eeLocalStore(noKey, userId: 'uid-a');
    await keepStateFor(store, 'a');
    expect(boxFile('uid-a').existsSync(), isFalse);

    await store.erase();

    final after = HiveE2eeLocalStore(noKey, userId: 'uid-a');
    expect(await after.readDeviceId(), isNull);
    expect(await after.readPlaintext('chat-1', 'msg-a'), isNull);
  });
}
