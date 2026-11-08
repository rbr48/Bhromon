import 'dart:typed_data';

import 'package:bhromon/features/chat/domain/e2ee/e2ee_device.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_envelope.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_exceptions.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_payload.dart';
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
      final first = alice.encrypt(
        recipient: bobBundle,
        payload: payloadFor(text: 'first'),
      );
      expect(first.messageType, 0, reason: 'the first message is a pre-key');
      final heard = bob.decrypt(
        sender: aliceBundle,
        envelope: first,
        chatId: 'chat-1',
        messageId: 'msg-1',
      );
      expect(heard.text, 'first');

      final reply = bob.encrypt(
        recipient: aliceBundle,
        payload: payloadFor(
          from: 'uid-b',
          to: 'uid-a',
          messageId: 'msg-2',
          text: 'reply',
        ),
      );
      expect(reply.messageType, 1);
      final answered = alice.decrypt(
        sender: bobBundle,
        envelope: reply,
        chatId: 'chat-1',
        messageId: 'msg-2',
      );
      expect(answered.text, 'reply');

      final next = alice.encrypt(
        recipient: bobBundle,
        payload: payloadFor(messageId: 'msg-3', text: 'next'),
      );
      expect(next.messageType, 1);
      final heardNext = bob.decrypt(
        sender: aliceBundle,
        envelope: next,
        chatId: 'chat-1',
        messageId: 'msg-3',
      );
      expect(heardNext.text, 'next');
    });

    test('a bundle with no one-time keys starts a session from the fallback',
        () {
      final fallbackOnly = rebuilt(bobBundle, oneTimeKeys: const []);
      final envelope = alice.encrypt(
        recipient: fallbackOnly,
        payload: payloadFor(text: 'via fallback'),
      );
      final heard = bob.decrypt(
        sender: aliceBundle,
        envelope: envelope,
        chatId: 'chat-1',
        messageId: 'msg-1',
      );
      expect(heard.text, 'via fallback');
    });

    test('refuses a payload for another chat or message id', () {
      final envelope = alice.encrypt(
        recipient: bobBundle,
        payload: payloadFor(),
      );
      expect(
        () => bob.decrypt(
          sender: aliceBundle,
          envelope: envelope,
          chatId: 'chat-2',
          messageId: 'msg-1',
        ),
        throwsA(isA<E2eeSecurityException>()),
      );
      expect(
        () => bob.decrypt(
          sender: aliceBundle,
          envelope: envelope,
          chatId: 'chat-1',
          messageId: 'msg-9',
        ),
        throwsA(isA<E2eeSecurityException>()),
      );
    });

    test('refuses an envelope from another device or addressed to another', () {
      final envelope = alice.encrypt(
        recipient: bobBundle,
        payload: payloadFor(),
      );
      final fromElsewhere = E2eeEnvelope(
        senderDeviceId: 'device-x',
        recipientDeviceId: 'device-b',
        messageType: envelope.messageType,
        ciphertext: envelope.ciphertext,
      );
      final toElsewhere = E2eeEnvelope(
        senderDeviceId: 'device-a',
        recipientDeviceId: 'device-x',
        messageType: envelope.messageType,
        ciphertext: envelope.ciphertext,
      );
      for (final envelope in [fromElsewhere, toElsewhere]) {
        expect(
          () => bob.decrypt(
            sender: aliceBundle,
            envelope: envelope,
            chatId: 'chat-1',
            messageId: 'msg-1',
          ),
          throwsA(isA<E2eeSecurityException>()),
        );
      }
    });

    test('refuses an altered message, and the session still reads the next one',
        () {
      final first = alice.encrypt(
        recipient: bobBundle,
        payload: payloadFor(),
      );
      bob.decrypt(
        sender: aliceBundle,
        envelope: first,
        chatId: 'chat-1',
        messageId: 'msg-1',
      );
      final reply = bob.encrypt(
        recipient: aliceBundle,
        payload: payloadFor(from: 'uid-b', to: 'uid-a', messageId: 'msg-2'),
      );
      alice.decrypt(
        sender: bobBundle,
        envelope: reply,
        chatId: 'chat-1',
        messageId: 'msg-2',
      );

      final genuine = alice.encrypt(
        recipient: bobBundle,
        payload: payloadFor(messageId: 'msg-3', text: 'genuine'),
      );
      final altered = Uint8List.fromList(genuine.ciphertext)
        ..[genuine.ciphertext.length ~/ 2] ^= 0x01;
      expect(
        () => bob.decrypt(
          sender: aliceBundle,
          envelope: E2eeEnvelope(
            senderDeviceId: 'device-a',
            recipientDeviceId: 'device-b',
            messageType: genuine.messageType,
            ciphertext: altered,
          ),
          chatId: 'chat-1',
          messageId: 'msg-3',
        ),
        throwsA(isA<E2eeSecurityException>()),
      );

      final heard = bob.decrypt(
        sender: aliceBundle,
        envelope: genuine,
        chatId: 'chat-1',
        messageId: 'msg-3',
      );
      expect(heard.text, 'genuine');
    });

    test('refuses a normal message from a device it has no session with', () {
      final unsolicited = E2eeEnvelope(
        senderDeviceId: 'device-a',
        recipientDeviceId: 'device-b',
        messageType: 1,
        ciphertext: Uint8List.fromList([1, 2, 3]),
      );
      expect(
        () => bob.decrypt(
          sender: aliceBundle,
          envelope: unsolicited,
          chatId: 'chat-1',
          messageId: 'msg-1',
        ),
        throwsA(isA<E2eeSecurityException>()),
      );
    });
  });

  group('identity keys', () {
    test('refuses a bundle whose identity key its device key did not sign', () {
      final swapped = rebuilt(
        bobBundle,
        curve25519Key: aliceBundle.curve25519Key,
      );
      expect(
        () => alice.encrypt(recipient: swapped, payload: payloadFor()),
        throwsA(isA<E2eeSecurityException>()),
      );
    });

    test('refuses an identity signature copied from a one-time key', () {
      final presented = rebuilt(
        bobBundle,
        identitySignature: bobBundle.oneTimeKeys.first.signature,
      );
      expect(
        () => alice.encrypt(recipient: presented, payload: payloadFor()),
        throwsA(isA<E2eeSecurityException>()),
      );
    });

    test('refuses a device whose identity key changed after a session began',
        () {
      alice.encrypt(recipient: bobBundle, payload: payloadFor());
      final reinstalled = newDevice('uid-b', 'device-b').buildBundle();
      expect(
        () => alice.encrypt(
          recipient: reinstalled,
          payload: payloadFor(messageId: 'msg-2'),
        ),
        throwsA(isA<E2eeSecurityException>()),
      );
    });

    test('refuses a message from a sender whose identity key changed', () {
      final first = alice.encrypt(recipient: bobBundle, payload: payloadFor());
      bob.decrypt(
        sender: aliceBundle,
        envelope: first,
        chatId: 'chat-1',
        messageId: 'msg-1',
      );
      final reinstalledAlice = newDevice('uid-a', 'device-a');
      final fromReinstall = reinstalledAlice.encrypt(
        recipient: bobBundle,
        payload: payloadFor(messageId: 'msg-2'),
      );
      expect(
        () => bob.decrypt(
          sender: reinstalledAlice.buildBundle(),
          envelope: fromReinstall,
          chatId: 'chat-1',
          messageId: 'msg-2',
        ),
        throwsA(isA<E2eeSecurityException>()),
      );
    });
  });

  group('bundles', () {
    test('a one-time key without a valid signature is skipped', () {
      final forged = E2eeSignedKey(
        keyId: 'forged',
        key: aliceBundle.curve25519Key,
        signature: bobBundle.oneTimeKeys.first.signature,
      );
      final mixed = rebuilt(
        bobBundle,
        oneTimeKeys: [forged, ...bobBundle.oneTimeKeys],
      );
      final envelope = alice.encrypt(
        recipient: mixed,
        payload: payloadFor(text: 'mixed'),
      );
      final heard = bob.decrypt(
        sender: aliceBundle,
        envelope: envelope,
        chatId: 'chat-1',
        messageId: 'msg-1',
      );
      expect(heard.text, 'mixed');
    });

    test('refuses a bundle with no key that verifies', () {
      final forged = E2eeSignedKey(
        keyId: 'forged',
        key: aliceBundle.curve25519Key,
        signature: bobBundle.oneTimeKeys.first.signature,
      );
      final unusable = rebuilt(
        bobBundle,
        oneTimeKeys: [forged],
        dropFallback: true,
      );
      expect(
        () => alice.encrypt(recipient: unusable, payload: payloadFor()),
        throwsA(isA<E2eeSecurityException>()),
      );
    });

    test('refuses a bundle with neither one-time nor fallback keys', () {
      final empty = rebuilt(
        bobBundle,
        oneTimeKeys: const [],
        dropFallback: true,
      );
      expect(
        () => alice.encrypt(recipient: empty, payload: payloadFor()),
        throwsA(isA<E2eeSecurityException>()),
      );
    });

    test('every key in a bundle verifies under its Ed25519 key', () {
      final bundle = bob.buildBundle();
      expect(
        engine.verifySignature(
          ed25519Key: bundle.ed25519Key,
          message: E2eePrekeyBundle.identityMessageFor(bundle.curve25519Key),
          signature: bundle.identitySignature,
        ),
        isTrue,
      );
      for (final signed in [...bundle.oneTimeKeys, bundle.fallbackKey!]) {
        expect(signed.keyId, E2eeSignedKey.idFor(signed.key));
        expect(
          engine.verifySignature(
            ed25519Key: bundle.ed25519Key,
            message: E2eePrekeyBundle.signedMessageFor(signed.key),
            signature: signed.signature,
          ),
          isTrue,
        );
      }
    });

    test('publishes each key once: the next bundle has nothing left to publish',
        () {
      final first = bob.buildBundle();
      expect(first.oneTimeKeys, hasLength(4));
      expect(first.fallbackKey, isNotNull);

      bob.markPublished();
      final second = bob.buildBundle();
      expect(second.oneTimeKeys, isEmpty);
      expect(second.fallbackKey, isNull);
      expect(second.curve25519Key, orderedEquals(first.curve25519Key));
      expect(second.identitySignature, orderedEquals(first.identitySignature));
    });

    test('refuses a one-time key count outside 1 to 100', () {
      for (final count in [0, 101]) {
        expect(
          () => E2eeDevice.create(
            engine: engine,
            userId: 'uid-x',
            deviceId: 'device-x',
            oneTimeKeyCount: count,
          ),
          throwsArgumentError,
          reason: 'count $count',
        );
      }
    });
  });
}
