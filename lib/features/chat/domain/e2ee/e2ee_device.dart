import 'dart:convert';
import 'dart:typed_data';

import 'package:bhromon/features/chat/domain/e2ee/e2ee_envelope.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_exceptions.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_payload.dart';
import 'package:bhromon/features/chat/domain/e2ee/olm_engine.dart';
import 'package:bhromon/features/chat/domain/e2ee/prekey_bundle.dart';

/// The end-to-end encryption state of one device: its Olm account and its
/// sessions with peer devices (E2EE_DESIGN.md, sections 4 and 6). It works over
/// [OlmEngine], so it does not depend on the native library.
///
/// Nothing is decrypted or used after a failed check. A peer key is used only
/// after its signature verifies, and a changed identity key stops the session.
class E2eeDevice {
  E2eeDevice._(this._engine, this.userId, this.deviceId, this._account);

  /// Creates a device with fresh keys: [oneTimeKeyCount] one-time keys and a
  /// fallback key.
  factory E2eeDevice.create({
    required OlmEngine engine,
    required String userId,
    required String deviceId,
    int oneTimeKeyCount = 20,
  }) {
    if (oneTimeKeyCount < 1 || oneTimeKeyCount > 100) {
      throw ArgumentError.value(
        oneTimeKeyCount,
        'oneTimeKeyCount',
        'must be from 1 to 100',
      );
    }
    final account = engine.createAccount();
    account.generateOneTimeKeys(oneTimeKeyCount);
    account.generateFallbackKey();
    return E2eeDevice._(engine, userId, deviceId, account);
  }

  final OlmEngine _engine;
  final String userId;
  final String deviceId;
  final OlmAccount _account;
  final Map<String, _Peer> _peers = {};

  /// The bundle to publish. It carries the identity key, signed by this device's
  /// Ed25519 key, and the keys not yet published, each signed the same way. The
  /// server keeps a published fallback key and adds new keys to the bundle (M3).
  /// Uploading it and calling [markPublished] are the app's job.
  E2eePrekeyBundle buildBundle() {
    final fallback = _account.unpublishedFallbackKey();
    final identity = _account.curve25519Key;
    return E2eePrekeyBundle(
      userId: userId,
      deviceId: deviceId,
      curve25519Key: identity,
      ed25519Key: _account.ed25519Key,
      identitySignature: _account.sign(
        E2eePrekeyBundle.identityMessageFor(identity),
      ),
      oneTimeKeys: [
        for (final key in _account.unpublishedOneTimeKeys()) _sign(key),
      ],
      fallbackKey: fallback == null ? null : _sign(fallback),
    );
  }

  /// Marks the current keys as published, after the bundle is uploaded.
  void markPublished() => _account.markKeysPublished();

  /// Frees the native account and every session. The device must not be used
  /// afterwards.
  void dispose() {
    for (final peer in _peers.values) {
      peer.session.dispose();
    }
    _peers.clear();
    _account.dispose();
  }

  /// Encrypts [payload] for [recipient]. A session is started from one of the
  /// recipient's verified one-time keys, or its verified fallback key, if there is
  /// no session yet.
  E2eeEnvelope encrypt({
    required E2eePrekeyBundle recipient,
    required E2eePayload payload,
  }) {
    _checkBundle(recipient);
    final peer = _outboundPeer(recipient);
    final plaintext = Uint8List.fromList(utf8.encode(payload.encode()));
    final message = peer.session.encrypt(plaintext);
    return E2eeEnvelope(
      senderDeviceId: deviceId,
      recipientDeviceId: recipient.deviceId,
      messageType: message.messageType,
      ciphertext: message.bytes,
    );
  }

  /// Decrypts [envelope] from [sender] and checks the payload against the chat,
  /// the sender, this user and the message id. Throws if any check fails. The text
  /// is returned only after all of them pass.
  E2eePayload decrypt({
    required E2eePrekeyBundle sender,
    required E2eeEnvelope envelope,
    required String chatId,
    required String messageId,
  }) {
    if (envelope.senderDeviceId != sender.deviceId) {
      throw const E2eeSecurityException('the envelope is from another device');
    }
    if (envelope.recipientDeviceId != deviceId) {
      throw const E2eeSecurityException('the envelope is for another device');
    }
    _checkBundle(sender);
    final plaintext = _decryptRaw(sender, envelope);
    final String text;
    try {
      text = utf8.decode(plaintext);
    } on FormatException {
      throw const E2eeFormatException('the payload is not UTF-8');
    }
    final payload = E2eePayload.decode(text);
    payload.checkBinding(
      expectedChatId: chatId,
      expectedSenderUid: sender.userId,
      expectedRecipientUid: userId,
      expectedMessageId: messageId,
    );
    return payload;
  }

  E2eeSignedKey _sign(Uint8List key) {
    return E2eeSignedKey(
      keyId: E2eeSignedKey.idFor(key),
      key: key,
      signature: _account.sign(E2eePrekeyBundle.signedMessageFor(key)),
    );
  }

  _Peer _outboundPeer(E2eePrekeyBundle recipient) {
    final existing = _peers[recipient.deviceId];
    if (existing != null) {
      _checkIdentity(existing, recipient);
      return existing;
    }
    final oneTimeKey = _verifiedKey(recipient);
    final session = _engine.createOutboundSession(
      account: _account,
      theirCurve25519Key: recipient.curve25519Key,
      theirOneTimeKey: oneTimeKey,
    );
    final peer = _Peer(recipient.curve25519Key, session);
    _peers[recipient.deviceId] = peer;
    return peer;
  }

  Uint8List _decryptRaw(E2eePrekeyBundle sender, E2eeEnvelope envelope) {
    final existing = _peers[sender.deviceId];
    if (existing != null) {
      _checkIdentity(existing, sender);
      try {
        return existing.session.decrypt(
          envelope.messageType,
          envelope.ciphertext,
        );
      } on OlmEngineException {
        throw const E2eeSecurityException('the message could not be decrypted');
      }
    }
    if (envelope.messageType != 0) {
      throw const E2eeSecurityException('there is no session with the sender');
    }
    final inbound = _startInbound(sender, envelope);
    _peers[sender.deviceId] = _Peer(sender.curve25519Key, inbound.session);
    return inbound.plaintext;
  }

  OlmInbound _startInbound(E2eePrekeyBundle sender, E2eeEnvelope envelope) {
    try {
      return _engine.createInboundSession(
        account: _account,
        theirCurve25519Key: sender.curve25519Key,
        prekeyMessage: envelope.ciphertext,
      );
    } on OlmEngineException {
      throw const E2eeSecurityException(
        'the first message does not start a session',
      );
    }
  }

  /// A one-time key whose signature verifies, or the fallback key if none does.
  /// Throws if the peer has neither.
  Uint8List _verifiedKey(E2eePrekeyBundle peer) {
    for (final signed in peer.oneTimeKeys) {
      if (_verifies(peer, signed)) {
        return signed.key;
      }
    }
    final fallback = peer.fallbackKey;
    if (fallback != null && _verifies(peer, fallback)) {
      return fallback.key;
    }
    throw const E2eeSecurityException(
      'the peer has no key with a valid signature',
    );
  }

  bool _verifies(E2eePrekeyBundle peer, E2eeSignedKey signed) {
    return _verified(
      peer,
      message: E2eePrekeyBundle.signedMessageFor(signed.key),
      signature: signed.signature,
    );
  }

  /// Refuses a bundle whose identity key its device key did not sign. Nothing is
  /// taken from such a bundle.
  void _checkBundle(E2eePrekeyBundle peer) {
    final signed = _verified(
      peer,
      message: E2eePrekeyBundle.identityMessageFor(peer.curve25519Key),
      signature: peer.identitySignature,
    );
    if (!signed) {
      throw const E2eeSecurityException(
        "the peer's identity key is not signed by its device key",
      );
    }
  }

  bool _verified(
    E2eePrekeyBundle peer, {
    required Uint8List message,
    required Uint8List signature,
  }) {
    try {
      return _engine.verifySignature(
        ed25519Key: peer.ed25519Key,
        message: message,
        signature: signature,
      );
    } on OlmEngineException {
      return false;
    }
  }

  void _checkIdentity(_Peer peer, E2eePrekeyBundle other) {
    if (!_sameBytes(peer.identityKey, other.curve25519Key)) {
      throw const E2eeSecurityException("the peer's identity key has changed");
    }
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// A session with one peer device, and the identity key it was started with.
class _Peer {
  const _Peer(this.identityKey, this.session);

  final Uint8List identityKey;
  final OlmSession session;
}
