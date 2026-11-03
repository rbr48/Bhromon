@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:bhromon/core/security/hive_encryption_service.dart';

/// The key older app versions used when secure storage failed.
final _legacyCipher =
    HiveAesCipher(List<int>.generate(32, (i) => (i * 7 + 13) % 256));

/// A key this device never has.
final _strangerCipher = HiveAesCipher(List<int>.generate(32, (i) => 255 - i));

/// Secure storage kept in memory, for the browser run (the shared fixtures use
/// dart:io, which a browser does not have).
class _MemorySecureStorage implements FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final key = invocation.namedArguments[#key] as String?;
    if (invocation.memberName == #read) {
      return Future<String?>.value(values[key]);
    }
    if (invocation.memberName == #write) {
      final value = invocation.namedArguments[#value] as String?;
      if (key != null && value != null) values[key] = value;
      return Future<void>.value();
    }
    return Future<void>.value();
  }
}

/// The web path of [HiveEncryptionService] against IndexedDB, in Chrome:
///   flutter test --platform chrome test/core/security/hive_web_storage_browser_test.dart
void main() {
  setUpAll(() {
    Hive.init(null);
  });

  tearDown(() async {
    await Hive.close();
  });

  HiveEncryptionService service() => HiveEncryptionService.withStorage(
        _MemorySecureStorage(),
        webStorage: true,
      );

  Future<void> writeBox(
      String name, HiveCipher? cipher, Map<String, Object> values) async {
    final box = await Hive.openBox<dynamic>(name, encryptionCipher: cipher);
    await box.putAll(values);
    await box.close();
  }

  Future<Map<dynamic, dynamic>> readBox(String name, HiveCipher? cipher) async {
    final box = await Hive.openBox<dynamic>(name, encryptionCipher: cipher);
    final entries = box.toMap();
    await box.close();
    return entries;
  }

  /// Runs [body] with the stray errors a failed IndexedDB open leaves behind
  /// contained, as the service does.
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
    final s = service();
    await writeBox('web_notes', await s.getCipher(), {'k': 'v'});

    final box = await s.openEncryptedBox<dynamic>('web_notes');

    expect(box.get('k'), 'v');
  });

  test('a box written under another key is refused and left as it was',
      () async {
    await writeBox('web_drafts', _strangerCipher, {'d1': 'draft one'});

    await expectLater(
      guarded(() => service().openEncryptedBox<dynamic>('web_drafts')),
      throwsA(anything),
    );

    expect(await readBox('web_drafts', _strangerCipher), {'d1': 'draft one'});
  });

  test('a box written with the older fixed key is migrated to the device key',
      () async {
    await writeBox('web_prefs', _legacyCipher, {'lang': 'bn'});
    final s = service();

    final box = await s.openEncryptedBox<dynamic>('web_prefs');

    expect(box.get('lang'), 'bn');
    expect(await readBox('web_prefs', await s.getCipher()), {'lang': 'bn'});
  });

  test('a plain-text box is encrypted when it is opened', () async {
    await writeBox('web_plain', null, {'s': 'plain-secret-text'});

    final box = await service().openEncryptedBox<dynamic>('web_plain');
    expect(box.get('s'), 'plain-secret-text');
    await box.close();

    // Opened without the key, the values no longer read as plain text.
    await expectLater(
      guarded(() => readBox('web_plain', null)),
      throwsA(anything),
    );
  });

  test('a half-finished migration is completed on the next open', () async {
    final s = service();
    await writeBox('web_settings__rekey', await s.getCipher(), {'lang': 'bn'});

    final box = await s.openEncryptedBox<dynamic>('web_settings');

    expect(box.get('lang'), 'bn');
  });

  test('a cache that no key can read is recreated, not kept', () async {
    await writeBox('web_cache', _strangerCipher, {'m1': 'old'});
    final s = service();

    final box = await s.openEncryptedBox<dynamic>(
      'web_cache',
      rebuildable: true,
    );
    await box.put('m2', 'new');

    expect(await readBox('web_cache', await s.getCipher()), {'m2': 'new'});
  });
}
