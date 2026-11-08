import 'dart:convert';
import 'dart:typed_data';

import 'package:bhromon/features/chat/domain/e2ee/e2ee_exceptions.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_olm_engine.dart';
import 'memory_stores.dart';

// The service (E2EE_DESIGN.md, sections 6 and 9) over in-memory stores: the server's
// keys and the device's own state. The fakes keep the rules the real stores keep:
// one claim per one-time key, removals by the owner only, and no overwrite.

void main() {
  late FakeOlmEngine engine;
  late MemoryKeyStore keys;
  late DateTime clock;
  var deviceCounter = 0;

  setUp(() {
    engine = FakeOlmEngine();
    keys = MemoryKeyStore();
    clock = DateTime.utc(2026, 11, 8);
    deviceCounter = 0;
  });

  E2eeService serviceFor(
    String uid,
    MemoryLocalStore local, {
    int batch = 20,
    int lowWater = 10,
  }) {
    return E2eeService(
      userId: uid,
      engine: engine,
      keys: keys,
      local: local,
      pickleKeys: FixedPickleKeyVault(),
      newDeviceId: () => 'device-${++deviceCounter}',
      now: () => clock,
      oneTimeKeyBatch: batch,
      oneTimeKeyLowWater: lowWater,
    );
  }

  /// A signed-in user with this device set up.
  Future<(E2eeService, MemoryLocalStore)> setUpUser(String uid) async {
    final local = MemoryLocalStore();
    final service = serviceFor(uid, local);
    await service.setUpThisDevice();
    return (service, local);
  }

  group('setting up', () {
    test('a new user has no device until it is set up, then it is ready',
        () async {
      final local = MemoryLocalStore();
      final service = serviceFor('uid-a', local);
      expect(await service.status(), E2eeSetupStatus.notSetUp);
      await service.setUpThisDevice();
      expect(await service.status(), E2eeSetupStatus.ready);
      expect(await keys.publishedDeviceId('uid-a'), local.deviceId);
      expect(keys.fallbackKeyId('uid-a'), isNotNull);
      expect(keys.keyCount('uid-a'), 20);
      service.dispose();
    });

    test('closing waits for the operations already queued', () async {
      final (alice, _) = await setUpUser('uid-a');
      final (bob, _) = await setUpUser('uid-b');
      final sending = alice.encryptText(
        chatId: 'chat-1',
        messageId: 'msg-1',
        recipientUid: 'uid-b',
        text: 'sent while closing',
        sentAtMillis: 1,
      );

      await alice.close();

      final envelope = await sending;
      expect(
        await bob.decryptMessage(
          chatId: 'chat-1',
          messageId: 'msg-1',
          senderUid: 'uid-a',
          envelope: envelope,
        ),
        'sent while closing',
      );
      bob.dispose();
    });

    test(
        'closing keeps the keys on the device, so the same device is ready again',
        () async {
      final (alice, aliceLocal) = await setUpUser('uid-a');
      final deviceId = aliceLocal.deviceId;

      await alice.close();

      final again = serviceFor('uid-a', aliceLocal);
      expect(await again.status(), E2eeSetupStatus.ready);
      expect(aliceLocal.deviceId, deviceId);
      again.dispose();
    });

    test('a second device sees that the keys belong to another device',
        () async {
      final (alice, _) = await setUpUser('uid-a');
      final reinstalled = serviceFor('uid-a', MemoryLocalStore());
      expect(await reinstalled.status(), E2eeSetupStatus.otherDevice);
      expect(await alice.status(), E2eeSetupStatus.ready);
      alice.dispose();
      reinstalled.dispose();
    });

    test('taking the keys over removes the other device\'s one-time keys',
        () async {
      final (alice, _) = await setUpUser('uid-a');
      final takeover = serviceFor('uid-a', MemoryLocalStore());
      await takeover.setUpThisDevice();
      expect(await takeover.status(), E2eeSetupStatus.ready);
      expect(await alice.status(), E2eeSetupStatus.otherDevice);
      expect(keys.keyCount('uid-a'), 20);
      alice.dispose();
      takeover.dispose();
    });
  });

  group('sending and receiving', () {
    test('a message is read by the other person, and the used key is removed',
        () async {
      final (alice, _) = await setUpUser('uid-a');
      final (bob, _) = await setUpUser('uid-b');

      final envelope = await alice.encryptText(
        chatId: 'chat-1',
        messageId: 'msg-1',
        recipientUid: 'uid-b',
        text: 'hello',
        sentAtMillis: 1,
      );
      expect(
        await bob.decryptMessage(
          chatId: 'chat-1',
          messageId: 'msg-1',
          senderUid: 'uid-a',
          envelope: envelope,
        ),
        'hello',
      );
      expect(keys.keyCount('uid-b'), 19);
      expect(await alice.plaintextFor('chat-1', 'msg-1'), 'hello');
      alice.dispose();
      bob.dispose();
    });

    test('two senders never start from the same one-time key', () async {
      final (alice, _) = await setUpUser('uid-a');
      final (carol, _) = await setUpUser('uid-c');
      final (bob, _) = await setUpUser('uid-b');

      final fromAlice = await alice.encryptText(
        chatId: 'chat-1',
        messageId: 'msg-a',
        recipientUid: 'uid-b',
        text: 'from alice',
        sentAtMillis: 1,
      );
      final fromCarol = await carol.encryptText(
        chatId: 'chat-2',
        messageId: 'msg-c',
        recipientUid: 'uid-b',
        text: 'from carol',
        sentAtMillis: 2,
      );
      expect(
        engine.oneTimeKeyOfPreKey(ciphertextOf(fromAlice)),
        isNot(engine.oneTimeKeyOfPreKey(ciphertextOf(fromCarol))),
      );
      expect(
        await bob.decryptMessage(
          chatId: 'chat-1',
          messageId: 'msg-a',
          senderUid: 'uid-a',
          envelope: fromAlice,
        ),
        'from alice',
      );
      expect(
        await bob.decryptMessage(
          chatId: 'chat-2',
          messageId: 'msg-c',
          senderUid: 'uid-c',
          envelope: fromCarol,
        ),
        'from carol',
      );
      alice.dispose();
      carol.dispose();
      bob.dispose();
    });

    test('concurrent sends to one person claim one key and both read',
        () async {
      final (alice, _) = await setUpUser('uid-a');
      final (bob, _) = await setUpUser('uid-b');

      final sent = await Future.wait([
        alice.encryptText(
          chatId: 'chat-1',
          messageId: 'msg-1',
          recipientUid: 'uid-b',
          text: 'one',
          sentAtMillis: 1,
        ),
        alice.encryptText(
          chatId: 'chat-1',
          messageId: 'msg-2',
          recipientUid: 'uid-b',
          text: 'two',
          sentAtMillis: 2,
        ),
      ]);
      expect(keys.claimedCount('uid-b'), 1);
      expect(
        (await bob.decryptMessage(
          chatId: 'chat-1',
          messageId: 'msg-1',
          senderUid: 'uid-a',
          envelope: sent[0],
        )),
        'one',
      );
      expect(
        await bob.decryptMessage(
          chatId: 'chat-1',
          messageId: 'msg-2',
          senderUid: 'uid-a',
          envelope: sent[1],
        ),
        'two',
      );
      alice.dispose();
      bob.dispose();
    });

    test(
        'when every one-time key is claimed, the fallback key starts the session',
        () async {
      final (alice, _) = await setUpUser('uid-a');
      final (bob, _) = await setUpUser('uid-b');
      for (final keyId in keys.oneTime['uid-b']!.keys.toList()) {
        await keys.claimOneTimeKey(
          ownerUid: 'uid-b',
          keyId: keyId,
          claimerUid: 'uid-x',
        );
      }
      final envelope = await alice.encryptText(
        chatId: 'chat-1',
        messageId: 'msg-1',
        recipientUid: 'uid-b',
        text: 'fallback',
        sentAtMillis: 1,
      );
      expect(
        await bob.decryptMessage(
          chatId: 'chat-1',
          messageId: 'msg-1',
          senderUid: 'uid-a',
          envelope: envelope,
        ),
        'fallback',
      );
      alice.dispose();
      bob.dispose();
    });

    test('a message is read once and then kept on the device', () async {
      final (alice, _) = await setUpUser('uid-a');
      final (bob, _) = await setUpUser('uid-b');
      final envelope = await alice.encryptText(
        chatId: 'chat-1',
        messageId: 'msg-1',
        recipientUid: 'uid-b',
        text: 'kept',
        sentAtMillis: 1,
      );
      await bob.decryptMessage(
        chatId: 'chat-1',
        messageId: 'msg-1',
        senderUid: 'uid-a',
        envelope: envelope,
      );
      expect(
        await bob.decryptMessage(
          chatId: 'chat-1',
          messageId: 'msg-1',
          senderUid: 'uid-a',
          envelope: envelope,
        ),
        'kept',
      );
      alice.dispose();
      bob.dispose();
    });

    test('a damaged envelope is refused and keeps nothing', () async {
      final (alice, _) = await setUpUser('uid-a');
      final (bob, bobLocal) = await setUpUser('uid-b');
      final envelope = await alice.encryptText(
        chatId: 'chat-1',
        messageId: 'msg-1',
        recipientUid: 'uid-b',
        text: 'hello',
        sentAtMillis: 1,
      );
      final damaged = Map<String, dynamic>.from(envelope)..['ct'] = '!!';
      await expectLater(
        bob.decryptMessage(
          chatId: 'chat-1',
          messageId: 'msg-1',
          senderUid: 'uid-a',
          envelope: damaged,
        ),
        throwsA(isA<E2eeFormatException>()),
      );
      expect(bobLocal.plaintexts, isEmpty);
      alice.dispose();
      bob.dispose();
    });

    test('a person who has no session cannot read the message', () async {
      final (alice, _) = await setUpUser('uid-a');
      final (bob, _) = await setUpUser('uid-b');
      final (carol, _) = await setUpUser('uid-c');
      final envelope = await alice.encryptText(
        chatId: 'chat-1',
        messageId: 'msg-1',
        recipientUid: 'uid-b',
        text: 'for bob',
        sentAtMillis: 1,
      );
      await expectLater(
        carol.decryptMessage(
          chatId: 'chat-1',
          messageId: 'msg-1',
          senderUid: 'uid-a',
          envelope: envelope,
        ),
        throwsA(isA<E2eeSecurityException>()),
      );
      alice.dispose();
      bob.dispose();
      carol.dispose();
    });

    test('a person who has not set up encryption cannot be sent to', () async {
      final (alice, _) = await setUpUser('uid-a');
      await expectLater(
        alice.encryptText(
          chatId: 'chat-1',
          messageId: 'msg-1',
          recipientUid: 'uid-nobody',
          text: 'hello',
          sentAtMillis: 1,
        ),
        throwsA(isA<E2eeNotReadyException>()),
      );
      alice.dispose();
    });

    test('a device that is not set up cannot send', () async {
      final service = serviceFor('uid-a', MemoryLocalStore());
      await expectLater(
        service.encryptText(
          chatId: 'chat-1',
          messageId: 'msg-1',
          recipientUid: 'uid-b',
          text: 'hello',
          sentAtMillis: 1,
        ),
        throwsA(isA<E2eeNotReadyException>()),
      );
      service.dispose();
    });
  });

  group('key changes and verification', () {
    test(
        'a changed identity does not block the chat, and the warning stays until '
        'it is accepted', () async {
      final (alice, _) = await setUpUser('uid-a');
      final bobLocal = MemoryLocalStore();
      final bob = serviceFor('uid-b', bobLocal);
      await bob.setUpThisDevice();

      final first = await alice.encryptText(
        chatId: 'chat-1',
        messageId: 'msg-1',
        recipientUid: 'uid-b',
        text: 'before',
        sentAtMillis: 1,
      );
      expect((await alice.peerState('uid-b')).hasChange, isFalse);

      // Bob's keys are taken over on a new device.
      final bobNew = serviceFor('uid-b', MemoryLocalStore());
      await bobNew.setUpThisDevice();
      final second = await alice.encryptText(
        chatId: 'chat-1',
        messageId: 'msg-2',
        recipientUid: 'uid-b',
        text: 'after',
        sentAtMillis: 2,
      );
      expect((await alice.peerState('uid-b')).hasChange, isTrue);
      expect(
        await bobNew.decryptMessage(
          chatId: 'chat-1',
          messageId: 'msg-2',
          senderUid: 'uid-a',
          envelope: second,
        ),
        'after',
      );

      final accepted = await alice.acceptKeyChange('uid-b');
      expect(accepted.hasChange, isFalse);
      expect(accepted.isVerified, isFalse);
      expect(first, isNotEmpty);
      alice.dispose();
      bob.dispose();
      bobNew.dispose();
    });

    test('both sides compute the same safety number, and verifying records it',
        () async {
      final (alice, _) = await setUpUser('uid-a');
      final (bob, _) = await setUpUser('uid-b');
      final envelope = await alice.encryptText(
        chatId: 'chat-1',
        messageId: 'msg-1',
        recipientUid: 'uid-b',
        text: 'hello',
        sentAtMillis: 1,
      );
      await bob.decryptMessage(
        chatId: 'chat-1',
        messageId: 'msg-1',
        senderUid: 'uid-a',
        envelope: envelope,
      );

      final fromAlice = await alice.safetyNumber('uid-b');
      final fromBob = await bob.safetyNumber('uid-a');
      expect(fromAlice, hasLength(60));
      expect(fromAlice, fromBob);

      final bobState = await alice.peerState('uid-b');
      final verified = await alice.markVerified(
        'uid-b',
        bobState.pinned!.identityBlock,
      );
      expect(verified.isVerified, isTrue);
      alice.dispose();
      bob.dispose();
    });
  });

  group('upkeep', () {
    test('prepare tops up one-time keys when the unclaimed supply runs low',
        () async {
      final (alice, aliceLocal) = await setUpUser('uid-a');
      for (final keyId in keys.oneTime['uid-a']!.keys.take(15).toList()) {
        await keys.claimOneTimeKey(
          ownerUid: 'uid-a',
          keyId: keyId,
          claimerUid: 'uid-x',
        );
      }
      await alice.prepare();
      expect(
        await keys.unclaimedOneTimeKeyCount(
          uid: 'uid-a',
          deviceId: aliceLocal.deviceId!,
        ),
        25,
      );
      alice.dispose();
    });

    test('the fallback key is rotated once it is older than its lifetime',
        () async {
      final (alice, _) = await setUpUser('uid-a');
      final before = keys.fallbackKeyId('uid-a');
      clock = clock.add(const Duration(days: 8));
      await alice.prepare();
      expect(keys.fallbackKeyId('uid-a'), isNot(before));
      alice.dispose();
    });

    test(
        'a removal the server refused is kept, and retried on the next prepare',
        () async {
      final (alice, _) = await setUpUser('uid-a');
      final (bob, bobLocal) = await setUpUser('uid-b');
      final envelope = await alice.encryptText(
        chatId: 'chat-1',
        messageId: 'msg-1',
        recipientUid: 'uid-b',
        text: 'hello',
        sentAtMillis: 1,
      );
      keys.failDeletes = true;
      expect(
        await bob.decryptMessage(
          chatId: 'chat-1',
          messageId: 'msg-1',
          senderUid: 'uid-a',
          envelope: envelope,
        ),
        'hello',
      );
      expect(bobLocal.pending, hasLength(1));
      expect(keys.keyCount('uid-b'), 20);

      keys.failDeletes = false;
      await bob.prepare();
      expect(bobLocal.pending, isEmpty);
      expect(keys.keyCount('uid-b'), 19);
      alice.dispose();
      bob.dispose();
    });
  });
}

/// The Olm bytes inside an envelope, for checking which one-time key it used.
Uint8List ciphertextOf(Map<String, Object> envelope) {
  return base64Url.decode(envelope['ct']! as String);
}
