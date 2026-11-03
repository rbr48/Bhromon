import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:bhromon/core/security/hive_encryption_service.dart';

import '../../helpers/perf_fixtures.dart';

/// The key older app versions used when secure storage failed.
final _legacyCipher =
    HiveAesCipher(List<int>.generate(32, (i) => (i * 7 + 13) % 256));

/// A key this device never has.
final _strangerCipher = HiveAesCipher(List<int>.generate(32, (i) => 255 - i));

bool _contains(List<int> haystack, List<int> needle) {
  for (var start = 0; start + needle.length <= haystack.length; start++) {
    var match = true;
    for (var i = 0; i < needle.length; i++) {
      if (haystack[start + i] != needle[i]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

/// The web path of [HiveEncryptionService], run on files. Each test writes a box the
/// way an older version or another key would, then opens it through the service.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bhromon_web_storage_');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File boxFile(String name) => File('${dir.path}/$name.hive');

  HiveEncryptionService webService() => HiveEncryptionService.withStorage(
        CountingSecureStorage(),
        webStorage: true,
      );

  Future<void> writeBox(
      String name, HiveCipher? cipher, Map<String, Object> values) async {
    final box = await Hive.openBox<dynamic>(name, encryptionCipher: cipher);
    await box.putAll(values);
    await box.close();
  }

  // Reading must never change the box: with the wrong key and crash recovery on,
  // Hive truncates it (see the regression guard in hive_encryption_test.dart).
  Future<Map<dynamic, dynamic>> readBox(String name, HiveCipher? cipher) async {
    final box = await Hive.openBox<dynamic>(
      name,
      encryptionCipher: cipher,
      crashRecovery: false,
    );
    final entries = box.toMap();
    await box.close();
    return entries;
  }

  /// Runs [body] with the stray errors a failed Hive open leaves behind contained.
  Future<T> guarded<T>(Future<T> Function() body) {
    final result = Completer<T>();
    runZonedGuarded(() async {
      try {
        result.complete(await body());
      } catch (error, stackTrace) {
        if (!result.isCompleted) result.completeError(error, stackTrace);
      }
    }, (_, __) {});
    return result.future;
  }

  test('a box written under the device key opens with its values', () async {
    final service = webService();
    final cipher = await service.getCipher();
    await writeBox('notes', cipher, {'k': 'v'});

    final box = await service.openEncryptedBox<dynamic>('notes');

    expect(box.get('k'), 'v');
  });

  test(
      'a box no key can read is recreated empty, and what is saved next is kept',
      () async {
    await writeBox(
        'drafts', _strangerCipher, {'d1': 'draft one', 'd2': 'draft two'});
    final service = webService();

    final box = await service.openEncryptedBox<dynamic>('drafts');
    expect(box.isEmpty, isTrue);
    await box.put('d3', 'draft three');
    await box.close();

    expect(await readBox('drafts', await service.getCipher()),
        {'d3': 'draft three'});
  });

  test('a box written with the older fixed key is migrated to the device key',
      () async {
    await writeBox('prefs', _legacyCipher, {'lang': 'bn', 'theme': 'dark'});
    final service = webService();

    final box = await service.openEncryptedBox<dynamic>('prefs');

    expect(box.toMap(), {'lang': 'bn', 'theme': 'dark'});
    expect(await readBox('prefs', await service.getCipher()),
        {'lang': 'bn', 'theme': 'dark'});
    await expectLater(
      guarded(() => readBox('prefs', _legacyCipher)),
      throwsA(anything),
    );
  });

  test('a plain-text box is encrypted when it is opened', () async {
    await writeBox('plain', null, {
      's': 'plain-secret-text',
      'm': <String, Object>{'a': 1}
    });
    final service = webService();

    final box = await service.openEncryptedBox<dynamic>('plain');

    expect(box.get('s'), 'plain-secret-text');
    expect(box.get('m'), {'a': 1});
    final bytes = boxFile('plain').readAsBytesSync();
    expect(_contains(bytes, utf8.encode('plain-secret-text')), isFalse);
  });

  test('a half-finished migration is completed on the next open', () async {
    // An older open was cut short after copying the entries under the device key.
    final service = webService();
    await writeBox(
        'settings__rekey', await service.getCipher(), {'lang': 'bn'});

    final box = await service.openEncryptedBox<dynamic>('settings');

    expect(box.get('lang'), 'bn');
    expect(boxFile('settings__rekey').existsSync(), isFalse);
  });

  test('a cache that no key can read is recreated, not kept', () async {
    await writeBox('chat_cache_msgs_x', _strangerCipher, {'m1': 'old'});
    final service = webService();

    final box = await service.openEncryptedBox<dynamic>('chat_cache_msgs_x');
    await box.put('m2', 'new');

    expect(await readBox('chat_cache_msgs_x', await service.getCipher()),
        {'m2': 'new'});
  });

  test('without a device key a box is kept in memory and writes nothing',
      () async {
    final service = HiveEncryptionService.withStorage(
      FailingSecureStorage(),
      webStorage: true,
    );

    final box = await service.openEncryptedBox<dynamic>('quiet');
    await box.put('k', 'v');

    expect(box.path, isNull);
    expect(boxFile('quiet').existsSync(), isFalse);
  });

  test('a folder in the way of a box fails the open and is left alone',
      () async {
    Directory('${dir.path}/drafts.hive').createSync();
    final service = webService();

    await expectLater(
      guarded(() => service.openEncryptedBox<dynamic>('drafts')),
      throwsA(anything),
    );

    expect(Directory('${dir.path}/drafts.hive').existsSync(), isTrue);
  });

  test(
      'an interrupted copy that neither key reads is dropped, and the original '
      'is moved to the device key', () async {
    await writeBox('settings', _legacyCipher, {'lang': 'bn'});
    await writeBox('settings__rekey', _strangerCipher, {'lang': 'en'});
    final service = webService();

    final box = await service.openEncryptedBox<dynamic>('settings');

    expect(box.get('lang'), 'bn');
    await box.close();
    expect(boxFile('settings__rekey').existsSync(), isFalse);
  });

  test('a later launch reopens a box the device key wrote, with its values',
      () async {
    final storage = CountingSecureStorage();
    final first = HiveEncryptionService.withStorage(storage, webStorage: true);
    final box = await first.openEncryptedBox<dynamic>('notes');
    await box.put('k', 'v');
    await box.close();

    // A new launch with the same keystore.
    await Hive.close();
    Hive.init(dir.path);
    final second = HiveEncryptionService.withStorage(storage, webStorage: true);
    final reopened = await second.openEncryptedBox<dynamic>('notes');

    expect(reopened.get('k'), 'v');
  });

  test('a box the device key wrote that is no longer readable is recreated',
      () async {
    final storage = CountingSecureStorage();
    final first = HiveEncryptionService.withStorage(storage, webStorage: true);
    final box = await first.openEncryptedBox<dynamic>('notes');
    await box.put('k', 'v');
    await box.close();
    // The box is replaced by one written under another key, while the marks still
    // say the device key opened it last.
    await writeBox('notes', _strangerCipher, {'k': 'other'});

    await Hive.close();
    Hive.init(dir.path);
    final second = HiveEncryptionService.withStorage(storage, webStorage: true);
    final recreated = await second.openEncryptedBox<dynamic>('notes');

    expect(recreated.isEmpty, isTrue);
  });
}
