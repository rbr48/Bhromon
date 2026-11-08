import 'dart:convert';
import 'dart:typed_data';

import 'package:bhromon/features/chat/domain/e2ee/e2ee_envelope.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_exceptions.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_payload.dart';
import 'package:bhromon/features/chat/domain/e2ee/olm_engine.dart';
import 'package:bhromon/features/chat/domain/e2ee/prekey_bundle.dart';

/// One session with a peer identity, pickled for storage.
class SessionSnapshot {
  const SessionSnapshot({
    required this.userId,
    required this.identityKey,
    required this.pickle,
    required this.confirmed,
  });

  final String userId;

  /// The peer's Curve25519 identity key the session was made with.
  final Uint8List identityKey;

  /// The session, encrypted under the pickle key.
  final Uint8List pickle;

  /// Whether a message from the peer has been decrypted on this session.
  final bool confirmed;
}

/// The result of [E2eeDevice.decrypt].
class DecryptedEnvelope {
  const DecryptedEnvelope({
    required this.payload,
    required this.startedSession,
  });

  final E2eePayload payload;

  /// Whether this was a pre-key message that started a session, so its one-time
  /// key has now been used up and must be removed from the server.
  final bool startedSession;
}

/// The end-to-end encryption state of one device: its Olm account and its
/// sessions with peer devices (E2EE_DESIGN.md, sections 4 and 6). It works over
/// [OlmEngine], so it does not depend on the native library.
///
/// Sessions are kept per peer identity, several at a time (decision in M4 of
/// E2EE_DESIGN.md). Two first messages sent at the same moment each start a session,
/// and both stay usable. Nothing is decrypted or used after a failed check. A peer
/// key is used only after its signature verifies. A changed identity does not stop
/// the chat. The app warns about it and keeps the old session for old messages.
class E2eeDevice {
  E2eeDevice._(this._engine, this.userId, this.deviceId, this._account);

  /// The most sessions kept with one peer identity. The oldest unconfirmed session
  /// is dropped first.
  static const int maxSessionsPerIdentity = 4;

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

  /// Restores a device from its pickles, as written by [pickleAccount] and
  /// [snapshotSessions]. [pickleKey] is the 32-byte key they were written under.
  factory E2eeDevice.restore({
    required OlmEngine engine,
    required String userId,
    required String deviceId,
    required Uint8List accountPickle,
    required Uint8List pickleKey,
    required List<SessionSnapshot> sessions,
  }) {
    final account = engine.restoreAccount(accountPickle, pickleKey);
    final device = E2eeDevice._(engine, userId, deviceId, account);
    for (final snapshot in sessions) {
      final session = engine.restoreSession(snapshot.pickle, pickleKey);
      device._add(
        snapshot.userId,
        snapshot.identityKey,
        session,
        confirmed: snapshot.confirmed,
      );
    }
    return device;
  }

  final OlmEngine _engine;
  final String userId;
  final String deviceId;
  final OlmAccount _account;

  /// The sessions by peer identity, keyed by the identity's fingerprint.
  final Map<String, _Bucket> _buckets = {};

  /// The bundle to publish. It carries the identity key, signed by this device's
  /// Ed25519 key, and the keys not yet published, each signed the same way. The
  /// app merges it into the published bundle, which keeps the published fallback
  /// key (see the chat service).
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

  /// The one-time keys not yet uploaded, signed. Call [markPublished] once they
  /// are on the server.
  List<E2eeSignedKey> unpublishedOneTimeKeys() {
    return [
      for (final key in _account.unpublishedOneTimeKeys()) _sign(key),
    ];
  }

  /// Makes [count] one-time keys and returns every unpublished one, signed, ready
  /// to upload. Call [markPublished] once the upload has succeeded.
  List<E2eeSignedKey> newOneTimeKeys(int count) {
    _account.generateOneTimeKeys(count);
    return unpublishedOneTimeKeys();
  }

  /// Starts a new fallback key and returns it signed, ready to publish. The
  /// previous fallback key stays valid for messages already on their way. Call
  /// [markPublished] once the upload has succeeded.
  E2eeSignedKey rotateFallbackKey() {
    _account.generateFallbackKey();
    final fallback = _account.unpublishedFallbackKey();
    if (fallback == null) {
      throw StateError('the new fallback key is not unpublished');
    }
    return _sign(fallback);
  }

  /// Marks the unpublished keys as published, after the upload succeeded.
  void markPublished() => _account.markKeysPublished();

  /// The Curve25519 and Ed25519 identity keys together, for safety numbers.
  Uint8List get identityBlock => Uint8List.fromList(
        [..._account.curve25519Key, ..._account.ed25519Key],
      );

  /// The account, encrypted under [key] (32 bytes), for storage.
  Uint8List pickleAccount(Uint8List key) => _account.pickle(key);

  /// Every session, encrypted under [key], oldest first within each identity.
  List<SessionSnapshot> snapshotSessions(Uint8List key) {
    return [
      for (final bucket in _buckets.values)
        for (final entry in bucket.sessions)
          SessionSnapshot(
            userId: bucket.userId,
            identityKey: bucket.identityKey,
            pickle: entry.session.pickle(key),
            confirmed: entry.confirmed,
          ),
    ];
  }

  /// Whether a session exists with the identity [peer] presents. If not, the next
  /// [encrypt] needs a one-time key.
  bool hasSessionWith(E2eePrekeyBundle peer) {
    final bucket = _buckets[_fingerprint(peer.curve25519Key)];
    return bucket != null && bucket.sessions.isNotEmpty;
  }

  /// The one-time keys of [peer] whose signatures verify. Throws if the identity
  /// key is not signed by the peer's device key.
  List<E2eeSignedKey> verifiedOneTimeKeys(E2eePrekeyBundle peer) {
    _checkBundle(peer);
    return [
      for (final key in peer.oneTimeKeys)
        if (_verifies(peer, key)) key,
    ];
  }

  /// Frees the native account and every session. The device must not be used
  /// afterwards.
  void dispose() {
    for (final bucket in _buckets.values) {
      for (final entry in bucket.sessions) {
        entry.session.dispose();
      }
    }
    _buckets.clear();
    _account.dispose();
  }

  /// Encrypts [payload] for [recipient]. If no session exists with the recipient's
  /// identity, one is started from [oneTimeKey] (which the caller has claimed on the
  /// server), or from the recipient's verified fallback key when there is none.
  E2eeEnvelope encrypt({
    required E2eePrekeyBundle recipient,
    required E2eePayload payload,
    E2eeSignedKey? oneTimeKey,
  }) {
    if (payload.senderUid != userId ||
        payload.recipientUid != recipient.userId) {
      throw ArgumentError('the payload names other users than the devices');
    }
    if (utf8.encode(payload.text).length > E2eePayload.maxTextBytes) {
      throw ArgumentError('the text is longer than the payload allows');
    }
    _checkBundle(recipient);
    final session = _outboundSession(recipient, oneTimeKey);
    final plaintext = Uint8List.fromList(utf8.encode(payload.encode()));
    final message = session.encrypt(plaintext);
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
  DecryptedEnvelope decrypt({
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
    final decrypted = _decryptRaw(sender, envelope);
    final String text;
    try {
      text = utf8.decode(decrypted.plaintext);
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
    return DecryptedEnvelope(
      payload: payload,
      startedSession: decrypted.startedSession,
    );
  }

  E2eeSignedKey _sign(Uint8List key) {
    return E2eeSignedKey(
      keyId: E2eeSignedKey.idFor(key),
      key: key,
      signature: _account.sign(E2eePrekeyBundle.signedMessageFor(key)),
    );
  }

  /// The session to send on: the newest one the peer has answered, else the
  /// newest one. A new session starts from [oneTimeKey] or the fallback key.
  OlmSession _outboundSession(
    E2eePrekeyBundle recipient,
    E2eeSignedKey? oneTimeKey,
  ) {
    final bucket = _buckets[_fingerprint(recipient.curve25519Key)];
    if (bucket != null && bucket.sessions.isNotEmpty) {
      return _preferred(bucket).session;
    }
    final Uint8List theirKey;
    if (oneTimeKey != null) {
      if (!_verifies(recipient, oneTimeKey)) {
        throw const E2eeSecurityException(
          'the one-time key is not signed by the peer device',
        );
      }
      theirKey = oneTimeKey.key;
    } else {
      final fallback = recipient.fallbackKey;
      if (fallback == null || !_verifies(recipient, fallback)) {
        throw const E2eeSecurityException(
          'the peer has no key with a valid signature',
        );
      }
      theirKey = fallback.key;
    }
    final session = _engine.createOutboundSession(
      account: _account,
      theirCurve25519Key: recipient.curve25519Key,
      theirOneTimeKey: theirKey,
    );
    _add(recipient.userId, recipient.curve25519Key, session, confirmed: false);
    return session;
  }

  ({Uint8List plaintext, bool startedSession}) _decryptRaw(
    E2eePrekeyBundle sender,
    E2eeEnvelope envelope,
  ) {
    for (final bucket in _buckets.values) {
      if (bucket.userId != sender.userId) {
        continue;
      }
      for (final entry in bucket.sessions.reversed) {
        try {
          final plaintext = entry.session.decrypt(
            envelope.messageType,
            envelope.ciphertext,
          );
          entry.confirmed = true;
          return (plaintext: plaintext, startedSession: false);
        } on OlmEngineException {
          // Not this session. Another one may hold the message.
        }
      }
    }
    if (envelope.messageType != 0) {
      throw const E2eeSecurityException('the message could not be decrypted');
    }
    final OlmInbound inbound;
    try {
      inbound = _engine.createInboundSession(
        account: _account,
        theirCurve25519Key: sender.curve25519Key,
        prekeyMessage: envelope.ciphertext,
      );
    } on OlmEngineException {
      throw const E2eeSecurityException(
        'the first message does not start a session',
      );
    }
    _add(sender.userId, sender.curve25519Key, inbound.session, confirmed: true);
    return (plaintext: inbound.plaintext, startedSession: true);
  }

  _Session _preferred(_Bucket bucket) {
    for (final entry in bucket.sessions.reversed) {
      if (entry.confirmed) {
        return entry;
      }
    }
    return bucket.sessions.last;
  }

  /// Keeps [session] with the identity, dropping the oldest unconfirmed session
  /// when there are too many. The new session is never the one dropped.
  void _add(
    String userId,
    Uint8List identityKey,
    OlmSession session, {
    required bool confirmed,
  }) {
    final bucket = _buckets.putIfAbsent(
      _fingerprint(identityKey),
      () => _Bucket(userId, identityKey),
    );
    bucket.sessions.add(_Session(session, confirmed: confirmed));
    while (bucket.sessions.length > maxSessionsPerIdentity) {
      final last = bucket.sessions.length - 1;
      var victim = 0;
      for (var i = 0; i < last; i++) {
        if (!bucket.sessions[i].confirmed) {
          victim = i;
          break;
        }
      }
      bucket.sessions.removeAt(victim).session.dispose();
    }
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

  static String _fingerprint(Uint8List identityKey) =>
      base64Url.encode(identityKey);
}

/// The sessions with one peer identity, oldest first.
class _Bucket {
  _Bucket(this.userId, this.identityKey);

  final String userId;
  final Uint8List identityKey;
  final List<_Session> sessions = [];
}

class _Session {
  _Session(this.session, {required this.confirmed});

  final OlmSession session;

  /// Set once a message from the peer has been decrypted on this session.
  bool confirmed;
}
