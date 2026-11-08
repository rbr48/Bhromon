import 'dart:typed_data';

import 'package:bhromon/features/chat/domain/e2ee/e2ee_device.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_envelope.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_exceptions.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_payload.dart';
import 'package:bhromon/features/chat/domain/e2ee/olm_engine.dart';
import 'package:bhromon/features/chat/domain/e2ee/prekey_bundle.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_olm_engine.dart';

// The device logic (E2EE_DESIGN.md, sections 4 and 6), run with the fake engine so
// that it needs no native library. olm_native_test.dart runs the same kinds of flow
// against the native engine.

E2eePayload payloadFor({
  String from = 'uid-a',
  String to = 'uid-b',
  String messageId = 'msg-1',
  String text = 'hello',
}) {
  return E2eePayload(
    chatId: 'chat-1',
    senderUid: from,
    recipientUid: to,
    messageId: messageId,
    sentAtMillis: 1700000000000,
    text: text,
  );
}

/// [from] with some parts replaced. The rest, the keys and the signatures, stay as
/// they were, which is how a server could alter a bundle it stores.
E2eePrekeyBundle rebuilt(
  E2eePrekeyBundle from, {
  Uint8List? curve25519Key,
  Uint8List? identitySignature,
  List<E2eeSignedKey>? oneTimeKeys,
  E2eeSignedKey? fallbackKey,
  bool dropFallback = false,
}) {
  return E2eePrekeyBundle(
    userId: from.userId,
    deviceId: from.deviceId,
    curve25519Key: curve25519Key ?? from.curve25519Key,
    ed25519Key: from.ed25519Key,
    identitySignature: identitySignature ?? from.identitySignature,
    oneTimeKeys: oneTimeKeys ?? from.oneTimeKeys,
    fallbackKey: dropFallback ? null : (fallbackKey ?? from.fallbackKey),
  );
}

Uint8List keyOf(int seed) => Uint8List.fromList(List.filled(32, seed));

void main() {
  late FakeOlmEngine engine;
  late E2eeDevice alice;
  late E2eeDevice bob;
  late E2eePrekeyBundle aliceBundle;
  late E2eePrekeyBundle bobBundle;

  E2eeDevice newDevice(String userId, String deviceId) => E2eeDevice.create(
        engine: engine,
        userId: userId,
        deviceId: deviceId,
        oneTimeKeyCount: 4,
      );

  /// The one-time keys of [peer] that alice may start a session from.
  E2eeSignedKey oneTimeKeyOf(
      E2eeDevice device, E2eePrekeyBundle peer, int index) {
    return device.verifiedOneTimeKeys(peer)[index];
  }

  setUp(() {
    engine = FakeOlmEngine();
    alice = newDevice('uid-a', 'device-a');
    bob = newDevice('uid-b', 'device-b');
    aliceBundle = alice.buildBundle();
    bobBundle = bob.buildBundle();
  });

  tearDown(() {
    alice.dispose();
    bob.dispose();
  });

  group('sending and receiving', () {
    test('a message round trips, and a reply is a normal message', () {
      final sent = alice.encrypt(
        recipient: bobBundle,
        payload: payloadFor(),
        oneTimeKey: oneTimeKeyOf(alice, bobBundle, 0),
      );
      expect(sent.messageType, 0);

      final received = bob.decrypt(
        sender: aliceBundle,
        envelope: sent,
        chatId: 'chat-1',
        messageId: 'msg-1',
      );
      expect(received.payload.text, 'hello');
      expect(received.startedSession, isTrue);

      final reply = bob.encrypt(
        recipient: aliceBundle,
        payload: payloadFor(
          from: 'uid-b',
          to: 'uid-a',
          messageId: 'msg-2',
          text: 'hi',
        ),
      );
      expect(reply.messageType, 1);

      final back = alice.decrypt(
        sender: bobBundle,
        envelope: reply,
        chatId: 'chat-1',
        messageId: 'msg-2',
      );
      expect(back.payload.text, 'hi');
      expect(back.startedSession, isFalse);
    });

    test('the pre-key message carries the one-time key it was given', () {
      final key = oneTimeKeyOf(alice, bobBundle, 1);
      final sent = alice.encrypt(
        recipient: bobBundle,
        payload: payloadFor(),
        oneTimeKey: key,
      );
      expect(engine.oneTimeKeyOfPreKey(sent.ciphertext), key.key);
    });

    test('with no one-time key, a session starts from the fallback key', () {
      final sent = alice.encrypt(recipient: bobBundle, payload: payloadFor());
      expect(
        engine.oneTimeKeyOfPreKey(sent.ciphertext),
        bobBundle.fallbackKey!.key,
      );
      final received = bob.decrypt(
        sender: aliceBundle,
        envelope: sent,
        chatId: 'chat-1',
        messageId: 'msg-1',
      );
      expect(received.payload.text, 'hello');
    });

    test('refuses a payload for another chat or message id', () {
      final sent = alice.encrypt(
        recipient: bobBundle,
        payload: payloadFor(),
        oneTimeKey: oneTimeKeyOf(alice, bobBundle, 0),
      );
      expect(
        () => bob.decrypt(
          sender: aliceBundle,
          envelope: sent,
          chatId: 'chat-2',
          messageId: 'msg-1',
        ),
        throwsA(isA<E2eeSecurityException>()),
      );
    });

    test('refuses an envelope from another device or addressed to another', () {
      final sent = alice.encrypt(
        recipient: bobBundle,
        payload: payloadFor(),
        oneTimeKey: oneTimeKeyOf(alice, bobBundle, 0),
      );
      final misaddressed = E2eeEnvelope(
        senderDeviceId: sent.senderDeviceId,
        recipientDeviceId: 'device-c',
        messageType: sent.messageType,
        ciphertext: sent.ciphertext,
      );
      expect(
        () => bob.decrypt(
          sender: aliceBundle,
          envelope: misaddressed,
          chatId: 'chat-1',
          messageId: 'msg-1',
        ),
        throwsA(isA<E2eeSecurityException>()),
      );
      final fromElsewhere = E2eeEnvelope(
        senderDeviceId: 'device-x',
        recipientDeviceId: sent.recipientDeviceId,
        messageType: sent.messageType,
        ciphertext: sent.ciphertext,
      );
      expect(
        () => bob.decrypt(
          sender: aliceBundle,
          envelope: fromElsewhere,
          chatId: 'chat-1',
          messageId: 'msg-1',
        ),
        throwsA(isA<E2eeSecurityException>()),
      );
    });

    test('refuses an altered message, and the session still reads the next one',
        () {
      final first = alice.encrypt(
        recipient: bobBundle,
        payload: payloadFor(),
        oneTimeKey: oneTimeKeyOf(alice, bobBundle, 0),
      );
      final altered = Uint8List.fromList(first.ciphertext);
      altered[altered.length - 2] ^= 1;
      expect(
        () => bob.decrypt(
          sender: aliceBundle,
          envelope: E2eeEnvelope(
            senderDeviceId: first.senderDeviceId,
            recipientDeviceId: first.recipientDeviceId,
            messageType: first.messageType,
            ciphertext: altered,
          ),
          chatId: 'chat-1',
          messageId: 'msg-1',
        ),
        throwsA(isA<E2eeSecurityException>()),
      );

      final second = alice.encrypt(
        recipient: bobBundle,
        payload: payloadFor(messageId: 'msg-2', text: 'again'),
      );
      expect(
        bob
            .decrypt(
              sender: aliceBundle,
              envelope: second,
              chatId: 'chat-1',
              messageId: 'msg-2',
            )
            .payload
            .text,
        'again',
      );
    });

    test('refuses a normal message when there is no session to read it', () {
      final stray = E2eeEnvelope(
        senderDeviceId: 'device-a',
        recipientDeviceId: 'device-b',
        messageType: 1,
        ciphertext: Uint8List.fromList([1, 2, 3]),
      );
      expect(
        () => bob.decrypt(
          sender: aliceBundle,
          envelope: stray,
          chatId: 'chat-1',
          messageId: 'msg-1',
        ),
        throwsA(isA<E2eeSecurityException>()),
      );
    });

    test('refuses text longer than the payload allows', () {
      expect(
        () => alice.encrypt(
          recipient: bobBundle,
          payload: payloadFor(
            text: 'x' * (E2eePayload.maxTextBytes + 1),
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('sessions per identity', () {
    test(
        'two first messages sent at the same moment both read, and both '
        'sides keep talking', () {
      final aliceToBob = alice.encrypt(
        recipient: bobBundle,
        payload: payloadFor(),
        oneTimeKey: oneTimeKeyOf(alice, bobBundle, 0),
      );
      final bobToAlice = bob.encrypt(
        recipient: aliceBundle,
        payload: payloadFor(
          from: 'uid-b',
          to: 'uid-a',
          messageId: 'msg-2',
          text: 'at the same time',
        ),
        oneTimeKey: oneTimeKeyOf(bob, aliceBundle, 0),
      );

      // Each side reads the other's first message. Each starts a second session,
      // and neither one replaces the session it sent on.
      expect(
        bob
            .decrypt(
              sender: aliceBundle,
              envelope: aliceToBob,
              chatId: 'chat-1',
              messageId: 'msg-1',
            )
            .payload
            .text,
        'hello',
      );
      expect(
        alice
            .decrypt(
              sender: bobBundle,
              envelope: bobToAlice,
              chatId: 'chat-1',
              messageId: 'msg-2',
            )
            .payload
            .text,
        'at the same time',
      );

      final aliceNext = alice.encrypt(
        recipient: bobBundle,
        payload: payloadFor(messageId: 'msg-3', text: 'three'),
      );
      expect(
        bob
            .decrypt(
              sender: aliceBundle,
              envelope: aliceNext,
              chatId: 'chat-1',
              messageId: 'msg-3',
            )
            .payload
            .text,
        'three',
      );

      final bobNext = bob.encrypt(
        recipient: aliceBundle,
        payload: payloadFor(
          from: 'uid-b',
          to: 'uid-a',
          messageId: 'msg-4',
          text: 'four',
        ),
      );
      expect(
        alice
            .decrypt(
              sender: bobBundle,
              envelope: bobNext,
              chatId: 'chat-1',
              messageId: 'msg-4',
            )
            .payload
            .text,
        'four',
      );
    });

    test(
        'keeps at most four sessions per identity, dropping the oldest '
        'unconfirmed one first', () {
      final carol = E2eeDevice.create(
        engine: engine,
        userId: 'uid-c',
        deviceId: 'device-c',
        oneTimeKeyCount: 5,
      );
      final carolBundle = carol.buildBundle();
      carol.dispose();
      final account = engine.createAccount();
      final key = keyOf(7);
      final snapshots = [
        for (var i = 0; i < 5; i++)
          SessionSnapshot(
            userId: 'uid-c',
            identityKey: carolBundle.curve25519Key,
            pickle: engine
                .createOutboundSession(
                  account: account,
                  theirCurve25519Key: carolBundle.curve25519Key,
                  theirOneTimeKey: carolBundle.oneTimeKeys[i].key,
                )
                .pickle(key),
            confirmed: i == 0,
          ),
      ];
      final restored = E2eeDevice.restore(
        engine: engine,
        userId: 'uid-a',
        deviceId: 'device-a',
        accountPickle: account.pickle(key),
        pickleKey: key,
        sessions: snapshots,
      );
      final kept = restored.snapshotSessions(key);
      expect(kept, hasLength(E2eeDevice.maxSessionsPerIdentity));
      expect(
        [for (final session in kept) session.pickle],
        [
          snapshots[0].pickle,
          snapshots[2].pickle,
          snapshots[3].pickle,
          snapshots[4].pickle,
        ],
      );
      expect(kept.first.confirmed, isTrue);
      restored.dispose();
    });
  });

  group('identity keys', () {
    test('refuses a bundle whose identity key its device key did not sign', () {
      final forged =
          rebuilt(bobBundle, curve25519Key: aliceBundle.curve25519Key);
      expect(
        () => alice.encrypt(recipient: forged, payload: payloadFor()),
        throwsA(isA<E2eeSecurityException>()),
      );
    });

    test('refuses an identity signature copied from a one-time key', () {
      final copied = rebuilt(
        bobBundle,
        identitySignature: bobBundle.oneTimeKeys.first.signature,
      );
      expect(
        () => alice.encrypt(recipient: copied, payload: payloadFor()),
        throwsA(isA<E2eeSecurityException>()),
      );
    });

    test(
        'a changed identity starts a session with the new device, and the old '
        'session still reads its own messages', () {
      final oldMessage = alice.encrypt(
        recipient: bobBundle,
        payload: payloadFor(),
        oneTimeKey: oneTimeKeyOf(alice, bobBundle, 0),
      );

      // Bob's device is reinstalled: same user and device id, a new identity.
      final bob2 = newDevice('uid-b', 'device-b');
      final bob2Bundle = bob2.buildBundle();
      expect(alice.hasSessionWith(bob2Bundle), isFalse);

      final newMessage = alice.encrypt(
        recipient: bob2Bundle,
        payload: payloadFor(messageId: 'msg-2', text: 'to the new device'),
        oneTimeKey: oneTimeKeyOf(alice, bob2Bundle, 0),
      );
      expect(
        bob2
            .decrypt(
              sender: aliceBundle,
              envelope: newMessage,
              chatId: 'chat-1',
              messageId: 'msg-2',
            )
            .payload
            .text,
        'to the new device',
      );
      expect(
        bob
            .decrypt(
              sender: aliceBundle,
              envelope: oldMessage,
              chatId: 'chat-1',
              messageId: 'msg-1',
            )
            .payload
            .text,
        'hello',
      );
      bob2.dispose();
    });
  });

  group('bundles', () {
    test('a one-time key without a valid signature is skipped', () {
      final keys = bobBundle.oneTimeKeys;
      final tampered = rebuilt(
        bobBundle,
        oneTimeKeys: [
          E2eeSignedKey(
            keyId: keys.first.keyId,
            key: keys.first.key,
            signature: keys[1].signature,
          ),
          ...keys.skip(1),
        ],
      );
      final usable = alice.verifiedOneTimeKeys(tampered);
      expect(usable.map((key) => key.keyId), keys.skip(1).map((k) => k.keyId));
    });

    test('refuses a bundle with no key that verifies', () {
      final noKeys =
          rebuilt(bobBundle, oneTimeKeys: const [], dropFallback: true);
      expect(
        () => alice.encrypt(recipient: noKeys, payload: payloadFor()),
        throwsA(isA<E2eeSecurityException>()),
      );
    });

    test('every key in a bundle verifies under its Ed25519 key', () {
      expect(alice.verifiedOneTimeKeys(bobBundle), hasLength(4));
      expect(
        alice.verifiedOneTimeKeys(bobBundle).map((key) => key.keyId).toSet(),
        bobBundle.oneTimeKeys.map((key) => key.keyId).toSet(),
      );
    });

    test('publishes each key once: the next bundle has nothing left to publish',
        () {
      bob.markPublished();
      final next = bob.buildBundle();
      expect(next.oneTimeKeys, isEmpty);
      expect(next.fallbackKey, isNull);
    });

    test(
        'newOneTimeKeys makes keys and returns only the ones not yet published',
        () {
      bob.markPublished();
      final fresh = bob.newOneTimeKeys(3);
      expect(fresh, hasLength(3));
      expect(
        bob.unpublishedOneTimeKeys().map((key) => key.keyId).toSet(),
        fresh.map((key) => key.keyId).toSet(),
      );
    });

    test(
        'rotating the fallback key keeps the previous one for messages already '
        'on their way', () {
      final oldFallback = bobBundle.fallbackKey!;
      bob.markPublished();
      final newFallback = bob.rotateFallbackKey();
      expect(newFallback.key, isNot(oldFallback.key));
      expect(bob.buildBundle().fallbackKey!.key, newFallback.key);

      final sent = alice.encrypt(
        recipient:
            rebuilt(bobBundle, oneTimeKeys: const [], fallbackKey: oldFallback),
        payload: payloadFor(),
      );
      expect(
        bob
            .decrypt(
              sender: aliceBundle,
              envelope: sent,
              chatId: 'chat-1',
              messageId: 'msg-1',
            )
            .payload
            .text,
        'hello',
      );
    });

    test('refuses a one-time key count outside 1 to 100', () {
      expect(
        () => E2eeDevice.create(
          engine: engine,
          userId: 'uid-c',
          deviceId: 'device-c',
          oneTimeKeyCount: 101,
        ),
        throwsArgumentError,
      );
    });
  });

  group('pickles', () {
    test('a restored device reads and sends on the sessions it had', () {
      final key = keyOf(3);
      final first = alice.encrypt(
        recipient: bobBundle,
        payload: payloadFor(),
        oneTimeKey: oneTimeKeyOf(alice, bobBundle, 0),
      );
      bob.decrypt(
        sender: aliceBundle,
        envelope: first,
        chatId: 'chat-1',
        messageId: 'msg-1',
      );

      final restored = E2eeDevice.restore(
        engine: engine,
        userId: 'uid-a',
        deviceId: 'device-a',
        accountPickle: alice.pickleAccount(key),
        pickleKey: key,
        sessions: alice.snapshotSessions(key),
      );
      final after = restored.encrypt(
        recipient: bobBundle,
        payload: payloadFor(messageId: 'msg-2', text: 'after a restart'),
      );
      expect(
        bob
            .decrypt(
              sender: aliceBundle,
              envelope: after,
              chatId: 'chat-1',
              messageId: 'msg-2',
            )
            .payload
            .text,
        'after a restart',
      );
      restored.dispose();
    });

    test('pickles under another key are refused', () {
      final key = keyOf(3);
      expect(
        () => E2eeDevice.restore(
          engine: engine,
          userId: 'uid-a',
          deviceId: 'device-a',
          accountPickle: alice.pickleAccount(key),
          pickleKey: keyOf(4),
          sessions: const [],
        ),
        throwsA(isA<OlmEngineException>()),
      );
    });
  });
}
