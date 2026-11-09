import 'dart:async';
import 'dart:io';

import 'package:bhromon/app/di/injection.dart';
import 'package:bhromon/core/config/feature_flags.dart';
import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:bhromon/features/chat/data/e2ee/e2ee_chat_controller.dart';
import 'package:bhromon/features/chat/data/e2ee/e2ee_local_store.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../../../helpers/perf_fixtures.dart';
import 'fake_olm_engine.dart';
import 'memory_stores.dart';

// The default build must not touch encryption: the flag is off, so no chat gets a
// service, no chat is created encrypted, and nothing reads the native library.
// Erasing a closed account's state does not need a service, so it is tested here too.

import 'package:flutter/foundation.dart';

void main() {
  test('encryption is enabled by default on supported native builds', () {
    expect(kE2eeOneToOne, isTrue);
    expect(E2eeChatController.enabledInBuild, !kIsWeb);
  });

  test('service lookup behaves safely across native environments', () async {
    expect(E2eeChatController.instance.serviceFor(''), isNull);
    // On test host without libe2ee_olm.so/.dll, serviceFor falls back cleanly to null without crashing.
    final service = E2eeChatController.instance.serviceFor('uid-a');
    if (!E2eeChatController.enabledInBuild) {
      expect(service, isNull);
    }
    await E2eeChatController.instance.release();
  });

  group('deleting a closed account', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('bhromon_e2ee_controller_');
      Hive.init(dir.path);
      getIt.registerSingleton<HiveEncryptionService>(
        HiveEncryptionService.withStorage(CountingSecureStorage()),
      );
    });

    tearDown(() async {
      await getIt.reset();
      try {
        await Hive.close();
      } catch (_) {}
      if (dir.existsSync()) {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    HiveE2eeLocalStore storeFor(String uid) =>
        HiveE2eeLocalStore(getIt<HiveEncryptionService>(), userId: uid);

    test('erases the keys and text of that account only', () async {
      await storeFor('uid-a').writeDeviceId('device-a');
      await storeFor('uid-b').writeDeviceId('device-b');

      await E2eeChatController.instance.deleteAccountState('uid-a');

      expect(File('${dir.path}/e2ee_state_uid-a.hive').existsSync(), isFalse);
      expect(await storeFor('uid-a').readDeviceId(), isNull);
      expect(await storeFor('uid-b').readDeviceId(), 'device-b');
    });

    test('an empty id erases nothing', () async {
      await storeFor('uid-b').writeDeviceId('device-b');

      await E2eeChatController.instance.deleteAccountState('');

      expect(await storeFor('uid-b').readDeviceId(), 'device-b');
    });

    test('a failure is logged, and the account can still close', () async {
      getIt.unregister<HiveEncryptionService>();

      await expectLater(
        E2eeChatController.instance.deleteAccountState('uid-a'),
        completes,
      );
    });
  });

  group('signing out', () {
    test('does not wait for encryption work that never ends', () async {
      final service = E2eeService(
        userId: 'uid-a',
        engine: FakeOlmEngine(),
        keys: MemoryKeyStore(),
        local: _StuckLocalStore(),
        pickleKeys: FixedPickleKeyVault(),
        newDeviceId: () => 'device-1',
        now: DateTime.now,
      );
      E2eeChatController.instance.useServiceForTest(service, 'uid-a');
      // Its first read never returns, so the queue behind it never empties.
      unawaited(service.status());

      await expectLater(
        E2eeChatController.instance
            .release()
            .timeout(const Duration(seconds: 10)),
        completes,
      );
    });
  });
}

/// Local storage whose first read never returns, as a device call that hangs would not.
class _StuckLocalStore extends MemoryLocalStore {
  @override
  Future<String?> readDeviceId() => Completer<String?>().future;
}
