import 'dart:convert';
import 'dart:typed_data';

import 'package:bhromon/features/chat/data/e2ee/olm_native.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_device.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_payload.dart';
import 'package:bhromon/features/chat/domain/e2ee/olm_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_library.dart';

// The native engine (native/e2ee_olm), through the Dart bindings. These tests need
// the built library: set E2EE_OLM_LIBRARY (see native_library.dart). Without it they
// are skipped. The device logic is also tested without the library, with a fake
// engine in device_test.dart.

Uint8List utf8Bytes(String text) => Uint8List.fromList(utf8.encode(text));

Uint8List bytesOf(int length, int seed) => Uint8List.fromList(
      List<int>.generate(length, (i) => (i * 7 + seed) & 0xff),
    );

OlmEngine? _engine;

/// The engine is opened on first use, so a skipped run never loads the library.
OlmEngine nativeEngine() =>
    _engine ??= openOlmEngine(libraryPath: nativeLibraryPath());

void main() {
  final skip = nativeLibraryPath() == null ? nativeLibrarySkipReason : null;

  group('native engine', skip: skip, () {
    test('accounts have 32-byte identity keys that differ between accounts',
        () {
      final a = nativeEngine().createAccount();
      final b = nativeEngine().createAccount();
      expect(a.curve25519Key, hasLength(32));
      expect(a.ed25519Key, hasLength(32));
      expect(a.curve25519Key, isNot(orderedEquals(b.curve25519Key)));
      expect(a.ed25519Key, isNot(orderedEquals(b.ed25519Key)));
      a.dispose();
      b.dispose();
    });

    test('signs and verifies, and refuses another message, key or signature',
        () {
      final engine = nativeEngine();
      final account = engine.createAccount();
      final other = engine.createAccount();
      final message = utf8Bytes('one-time key');
      final signature = account.sign(message);
      expect(signature, hasLength(64));

      bool verify(Uint8List key, Uint8List data, Uint8List sig) =>
          engine.verifySignature(
            ed25519Key: key,
            message: data,
            signature: sig,
          );

      expect(verify(account.ed25519Key, message, signature), isTrue);
      expect(
        verify(account.ed25519Key, utf8Bytes('another'), signature),
        isFalse,
      );
      expect(verify(other.ed25519Key, message, signature), isFalse);
      final tampered = Uint8List.fromList(signature)..[0] ^= 1;
      expect(verify(account.ed25519Key, message, tampered), isFalse);
      account.dispose();
      other.dispose();
    });

    test('restores an account under its pickle key and refuses another key',
        () {
      final engine = nativeEngine();
      final account = engine.createAccount();
      final key = bytesOf(32, 3);
      final pickle = account.pickle(key);
      final restored = engine.restoreAccount(pickle, key);
      expect(restored.curve25519Key, orderedEquals(account.curve25519Key));
      expect(restored.ed25519Key, orderedEquals(account.ed25519Key));
      expect(
        () => engine.restoreAccount(pickle, bytesOf(32, 4)),
        throwsA(
          isA<OlmEngineException>().having((e) => e.code, 'code', -6),
        ),
      );
      account.dispose();
      restored.dispose();
    });

    test('publishes one-time keys once, and the fallback key until published',
        () {
      final account = nativeEngine().createAccount();
      account.generateOneTimeKeys(5);
      account.generateFallbackKey();
      expect(account.unpublishedOneTimeKeys(), hasLength(5));
      expect(account.unpublishedFallbackKey(), hasLength(32));
      account.markKeysPublished();
      expect(account.unpublishedOneTimeKeys(), isEmpty);
      expect(account.unpublishedFallbackKey(), isNull);
      account.dispose();
    });

    test('lists at most 100 unpublished one-time keys, the buffer capacity',
        () {
      // The capacity counts keys. With 200 keys unpublished, the call must return
      // 100 and write no further than the 100-key buffer.
      final account = nativeEngine().createAccount();
      account.generateOneTimeKeys(100);
      account.generateOneTimeKeys(100);
      expect(account.unpublishedOneTimeKeys(), hasLength(100));
      account.dispose();
    });

    test('an outbound and an inbound session exchange messages both ways', () {
      final engine = nativeEngine();
      final alice = engine.createAccount();
      final bob = engine.createAccount();
      bob.generateOneTimeKeys(1);
      final oneTimeKey = bob.unpublishedOneTimeKeys().single;

      final outbound = engine.createOutboundSession(
        account: alice,
        theirCurve25519Key: bob.curve25519Key,
        theirOneTimeKey: oneTimeKey,
      );
      final first = outbound.encrypt(utf8Bytes('hello'));
      expect(first.messageType, 0, reason: 'the first message is a pre-key');

      final inbound = engine.createInboundSession(
        account: bob,
        theirCurve25519Key: alice.curve25519Key,
        prekeyMessage: first.bytes,
      );
      expect(inbound.plaintext, orderedEquals(utf8Bytes('hello')));
      expect(inbound.session.id, outbound.id, reason: 'both sides agree');

      final reply = inbound.session.encrypt(utf8Bytes('hi back'));
      expect(reply.messageType, 1);
      expect(
        outbound.decrypt(reply.messageType, reply.bytes),
        orderedEquals(utf8Bytes('hi back')),
      );

      final next = outbound.encrypt(utf8Bytes('third'));
      expect(next.messageType, 1, reason: 'after a reply, normal messages');
      expect(
        inbound.session.decrypt(next.messageType, next.bytes),
        orderedEquals(utf8Bytes('third')),
      );
    });

    test(
        'refuses a replayed pre-key and a tampered message; the session goes on',
        () {
      final engine = nativeEngine();
      final alice = engine.createAccount();
      final bob = engine.createAccount();
      bob.generateOneTimeKeys(1);
      final outbound = engine.createOutboundSession(
        account: alice,
        theirCurve25519Key: bob.curve25519Key,
        theirOneTimeKey: bob.unpublishedOneTimeKeys().single,
      );
      final first = outbound.encrypt(utf8Bytes('one'));
      final inbound = engine.createInboundSession(
        account: bob,
        theirCurve25519Key: alice.curve25519Key,
        prekeyMessage: first.bytes,
      );

      expect(
        () => inbound.session.decrypt(0, first.bytes),
        throwsA(isA<OlmEngineException>()),
        reason: 'a replayed pre-key',
      );

      final reply = inbound.session.encrypt(utf8Bytes('reply'));
      outbound.decrypt(reply.messageType, reply.bytes);

      final message = outbound.encrypt(utf8Bytes('two'));
      final tampered = Uint8List.fromList(message.bytes)
        ..[message.bytes.length - 1] ^= 1;
      expect(
        () => inbound.session.decrypt(message.messageType, tampered),
        throwsA(isA<OlmEngineException>()),
        reason: 'a message altered in transit',
      );
      expect(
        inbound.session.decrypt(message.messageType, message.bytes),
        orderedEquals(utf8Bytes('two')),
        reason: 'the untouched message still decrypts',
      );
    });

    test('refuses a pre-key message made for another identity key', () {
      final engine = nativeEngine();
      final alice = engine.createAccount();
      final bob = engine.createAccount();
      final mallory = engine.createAccount();
      bob.generateOneTimeKeys(1);
      final outbound = engine.createOutboundSession(
        account: alice,
        theirCurve25519Key: bob.curve25519Key,
        theirOneTimeKey: bob.unpublishedOneTimeKeys().single,
      );
      final first = outbound.encrypt(utf8Bytes('secret'));
      expect(
        () => engine.createInboundSession(
          account: bob,
          theirCurve25519Key: mallory.curve25519Key,
          prekeyMessage: first.bytes,
        ),
        throwsA(isA<OlmEngineException>()),
      );
    });

    test('a fallback key starts a session when there are no one-time keys', () {
      final engine = nativeEngine();
      final alice = engine.createAccount();
      final bob = engine.createAccount();
      bob.generateFallbackKey();
      final fallback = bob.unpublishedFallbackKey()!;

      final outbound = engine.createOutboundSession(
        account: alice,
        theirCurve25519Key: bob.curve25519Key,
        theirOneTimeKey: fallback,
      );
      final first = outbound.encrypt(utf8Bytes('via fallback'));
      final inbound = engine.createInboundSession(
        account: bob,
        theirCurve25519Key: alice.curve25519Key,
        prekeyMessage: first.bytes,
      );
      expect(inbound.plaintext, orderedEquals(utf8Bytes('via fallback')));
    });

    test('a session pickle restores under its key and refuses another', () {
      final engine = nativeEngine();
      final alice = engine.createAccount();
      final bob = engine.createAccount();
      bob.generateOneTimeKeys(1);
      final outbound = engine.createOutboundSession(
        account: alice,
        theirCurve25519Key: bob.curve25519Key,
        theirOneTimeKey: bob.unpublishedOneTimeKeys().single,
      );
      final key = bytesOf(32, 9);
      final restored = engine.restoreSession(outbound.pickle(key), key);
      expect(restored.id, outbound.id);
      expect(
        () => engine.restoreSession(outbound.pickle(key), bytesOf(32, 10)),
        throwsA(isA<OlmEngineException>()),
      );
    });

    test('two devices exchange encrypted payloads through the native engine',
        () {
      final engine = nativeEngine();
      final alice = E2eeDevice.create(
        engine: engine,
        userId: 'uid-a',
        deviceId: 'device-a',
        oneTimeKeyCount: 3,
      );
      final bob = E2eeDevice.create(
        engine: engine,
        userId: 'uid-b',
        deviceId: 'device-b',
        oneTimeKeyCount: 3,
      );
      final aliceBundle = alice.buildBundle();
      final bobBundle = bob.buildBundle();
      alice.markPublished();
      bob.markPublished();

      final envelope = alice.encrypt(
        recipient: bobBundle,
        payload: const E2eePayload(
          chatId: 'chat-1',
          senderUid: 'uid-a',
          recipientUid: 'uid-b',
          messageId: 'msg-1',
          sentAtMillis: 1700000000000,
          text: 'নমস্কার',
        ),
      );
      expect(envelope.messageType, 0);
      final received = bob.decrypt(
        sender: aliceBundle,
        envelope: envelope,
        chatId: 'chat-1',
        messageId: 'msg-1',
      );
      expect(received.text, 'নমস্কার');

      final reply = bob.encrypt(
        recipient: aliceBundle,
        payload: const E2eePayload(
          chatId: 'chat-1',
          senderUid: 'uid-b',
          recipientUid: 'uid-a',
          messageId: 'msg-2',
          sentAtMillis: 1700000000001,
          text: 'ok',
        ),
      );
      expect(reply.messageType, 1);
      final answered = alice.decrypt(
        sender: bobBundle,
        envelope: reply,
        chatId: 'chat-1',
        messageId: 'msg-2',
      );
      expect(answered.text, 'ok');
      alice.dispose();
      bob.dispose();
    });
  });
}
