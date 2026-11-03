import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:bhromon/core/security/hive_encryption_service.dart';

import '../../helpers/perf_fixtures.dart';

/// What happens to a box whose file cannot be opened. A directory where the box
/// file belongs makes every open fail for a reason that is not a key, so the box
/// must fail to open and stay where it is. Cache boxes get no memory fallback
/// either: a cache that cannot be opened is reported, and its caller carries on.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bhromon_cache_box_');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  void breakBox(String name) =>
      Directory('${dir.path}/$name.hive').createSync();

  File boxFile(String name) => File('${dir.path}/$name.hive');

  /// Runs [body] in a guarded zone. A failed Hive open leaves stray async errors
  /// behind (see the encryption tests); they are not what these tests check, and
  /// the result of [body] is.
  Future<T> guarded<T>(Future<T> Function() body) {
    final result = Completer<T>();
    runZonedGuarded(() async {
      try {
        result.complete(await body());
      } catch (error, stackTrace) {
        if (!result.isCompleted) result.completeError(error, stackTrace);
      }
    }, (error, stackTrace) {});
    return result.future;
  }

  test('a cache with no device key stays in memory and writes no file',
      () async {
    final service = HiveEncryptionService.withStorage(FailingSecureStorage());

    final box = await service.openEncryptedBox<dynamic>('chat_cache_msgs_a');
    await box.put('message', 'hello');

    expect(box.path, isNull);
    expect(boxFile('chat_cache_msgs_a').existsSync(), isFalse);
    expect(service.usedInMemoryFallback, isTrue);
  });

  test('a cache that cannot be opened is reported, never kept in memory',
      () async {
    final service = HiveEncryptionService.withStorage(CountingSecureStorage());
    breakBox('chat_cache_msgs_b');

    await expectLater(
      guarded(() => service.openEncryptedBox<dynamic>('chat_cache_msgs_b')),
      throwsA(anything),
    );

    // The entry that could not be opened is still there, untouched: nothing
    // replaced it with a plain box file, and nothing was kept in memory.
    expect(
        Directory('${dir.path}/chat_cache_msgs_b.hive').existsSync(), isTrue);
    expect(service.usedInMemoryFallback, isFalse);
  });

  test('a user box that cannot be opened is reported and left on disk',
      () async {
    final service = HiveEncryptionService.withStorage(CountingSecureStorage());
    breakBox('drafts');

    await expectLater(
      guarded(() => service.openEncryptedBox<dynamic>('drafts')),
      throwsA(anything),
    );
    expect(Directory('${dir.path}/drafts.hive').existsSync(), isTrue);
    expect(service.usedInMemoryFallback, isFalse);
  });
}
