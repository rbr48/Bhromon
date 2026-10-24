import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:bhromon/core/security/hive_encryption_service.dart';

import '../helpers/perf_fixtures.dart';

/// The fixed key older app versions used when secure storage failed.
final _legacyCipher =
    HiveAesCipher(List<int>.generate(32, (i) => (i * 7 + 13) % 256));

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bhromon_hive_enc_');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> writeBox(String name, HiveAesCipher? cipher, int n) async {
    final box = await Hive.openBox<dynamic>(name, encryptionCipher: cipher);
    for (var i = 0; i < n; i++) {
      await box.put('k$i', 'v$i');
    }
    await box.close();
  }

  File boxFile(String name) => File('${dir.path}/$name.hive');

  var probes = 0;

  /// Whether [name] opens with [cipher], checked on a copy in a guarded zone
  /// (a failed Hive open leaves stray async errors behind).
  Future<bool> opensWith(String name, HiveAesCipher? cipher) async {
    final probe = 'probe${probes++}';
    boxFile(name).copySync('${dir.path}/$probe.hive');
    final result = Completer<bool>();
    runZonedGuarded(() async {
      try {
        final box = await Hive.openBox<dynamic>(probe,
            encryptionCipher: cipher, crashRecovery: false);
        await box.close();
        if (!result.isCompleted) result.complete(true);
      } on HiveError {
        if (!result.isCompleted) result.complete(false);
      }
    }, (_, __) {
      if (!result.isCompleted) result.complete(false);
    });
    return result.future;
  }

  test('regression guard: Hive empties a box opened with the wrong key',
      () async {
    // This is why boxes must never be opened with recovery on and a key
    // that may be wrong (old code's fixed fallback key vs the real one).
    await writeBox('b', _legacyCipher, 20);
    final wrong = HiveAesCipher(List<int>.generate(32, (i) => i));
    final box = await Hive.openBox<dynamic>('b', encryptionCipher: wrong);
    expect(box.length, 0);
    await box.close();
    expect(boxFile('b').lengthSync(), 0);
  });

  test('first run creates a key, stores it, and reads it once', () async {
    final storage = CountingSecureStorage();
    final service = HiveEncryptionService.withStorage(storage);

    final box = await service.openEncryptedBox<dynamic>('drafts');
    await box.put('a', 1);
    await service.openEncryptedBox<dynamic>('drafts');
    await service.openEncryptedBox<dynamic>('other');

    expect(storage.writes, 1);
    expect(storage.reads, 1);
    expect(storage.values, contains('hive_encryption_key'));
    expect(service.usedInMemoryFallback, isFalse);
  });

  test('data written with the old fixed key is re-encrypted, not lost',
      () async {
    await writeBox('saved_logs', _legacyCipher, 50);
    final storage = CountingSecureStorage();
    final service = HiveEncryptionService.withStorage(storage);

    final box = await service.openEncryptedBox<dynamic>('saved_logs');

    expect(box.length, 50);
    expect(box.get('k49'), 'v49');
    await box.close();
    // Now readable with the device key only.
    final realKey = await service.getCipher();
    final reopened = await Hive.openBox<dynamic>('saved_logs',
        encryptionCipher: realKey, crashRecovery: false);
    expect(reopened.length, 50);
    await reopened.close();
    expect(await opensWith('saved_logs', _legacyCipher), isFalse);
    expect(File('${dir.path}/saved_logs__rekey.hive').existsSync(), isFalse);
  });

  test('an unencrypted box is encrypted on first open', () async {
    await writeBox('plain', null, 5);
    final service = HiveEncryptionService.withStorage(CountingSecureStorage());

    final box = await service.openEncryptedBox<dynamic>('plain');

    expect(box.toMap(), {for (var i = 0; i < 5; i++) 'k$i': 'v$i'});
    await box.close();
    expect(await opensWith('plain', null), isFalse);
  });

  test('a migration cut short after the copy is completed next time', () async {
    final storage = CountingSecureStorage();
    final first = HiveEncryptionService.withStorage(storage);
    final realKey = await first.getCipher();
    // Simulate a crash right after step 1: the durable copy exists and the
    // original has already been deleted.
    await writeBox('drafts__rekey', realKey, 7);

    final service = HiveEncryptionService.withStorage(storage);
    final box = await service.openEncryptedBox<dynamic>('drafts');

    expect(box.length, 7);
    expect(File('${dir.path}/drafts__rekey.hive').existsSync(), isFalse);
  });

  test('without secure storage nothing is written with a public key', () async {
    final storage = FailingSecureStorage();
    final service = HiveEncryptionService.withStorage(storage);

    final box = await service.openEncryptedBox<dynamic>('session');
    await box.put('secret', 'value');

    expect(service.usedInMemoryFallback, isTrue);
    expect(box.get('secret'), 'value');
    expect(boxFile('session').existsSync(), isFalse,
        reason: 'old code wrote this to disk under a key shipped in the app');
    // No retry storm: one read per process.
    await service.openEncryptedBox<dynamic>('another');
    expect(storage.reads, 1);
  });

  test(
      'without secure storage, existing legacy data is still readable and '
      'its file left untouched', () async {
    await writeBox('saved_logs', _legacyCipher, 3);
    final before = boxFile('saved_logs').readAsBytesSync();
    final service = HiveEncryptionService.withStorage(FailingSecureStorage());

    final box = await service.openEncryptedBox<dynamic>('saved_logs');
    await box.put('new', 'session-only');

    expect(box.get('k2'), 'v2');
    await box.close();
    expect(boxFile('saved_logs').readAsBytesSync(), before);
  });

  test(
      'a box encrypted with an unknown key is not wiped while the key is '
      'unavailable', () async {
    final unknown = HiveAesCipher(List<int>.generate(32, (i) => 255 - i));
    await writeBox('drafts', unknown, 10);
    final size = boxFile('drafts').lengthSync();
    final service = HiveEncryptionService.withStorage(FailingSecureStorage());

    final box = await service.openEncryptedBox<dynamic>('drafts');

    expect(box.length, 0);
    expect(boxFile('drafts').lengthSync(), size,
        reason: 'the file must survive until the real key is back');
  });

  test('a later launch opens directly (no probe copies) and keeps the data',
      () async {
    await writeBox('saved_logs', _legacyCipher, 4);
    final storage = CountingSecureStorage();
    final first = HiveEncryptionService.withStorage(storage);
    final box = await first.openEncryptedBox<dynamic>('saved_logs');
    await box.put('added', 'later');
    await Hive.close();

    // New process, same keystore.
    Hive.init(dir.path);
    final second = HiveEncryptionService.withStorage(storage);
    final watcher = dir.watch();
    final created = <String>[];
    final sub = watcher.listen((e) => created.add(e.path));
    final reopened = await second.openEncryptedBox<dynamic>('saved_logs');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    expect(reopened.length, 5);
    expect(reopened.get('added'), 'later');
    expect(created.where((p) => p.contains('__probe')), isEmpty);
  });

  test('a lost keystore key recovers the box instead of crashing', () async {
    final storage = CountingSecureStorage();
    final first = HiveEncryptionService.withStorage(storage);
    final box = await first.openEncryptedBox<dynamic>('drafts');
    await box.put('a', 1);
    await Hive.close();

    // The keystore entry is gone (e.g. restored from a backup): a new key is
    // generated and the old data can't be decrypted by anyone.
    storage.values.clear();
    Hive.init(dir.path);
    final errors = <Object>[];
    await runZonedGuarded(() async {
      final service = HiveEncryptionService.withStorage(storage);
      final recovered = await service.openEncryptedBox<dynamic>('drafts');
      expect(recovered.length, 0);
      await recovered.put('b', 2);
      expect(recovered.get('b'), 2);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }, (e, _) => errors.add(e));
    expect(errors, isEmpty, reason: 'no stray Hive errors may escape');
  });

  test('concurrent first opens during a migration agree', () async {
    await writeBox('feed', _legacyCipher, 12);
    final service = HiveEncryptionService.withStorage(CountingSecureStorage());
    final boxes = await Future.wait([
      for (var i = 0; i < 5; i++) service.openEncryptedBox<dynamic>('feed')
    ]);
    expect(boxes.toSet(), hasLength(1));
    expect(boxes.first.length, 12);
  });
}
