import 'dart:typed_data';

import 'package:bhromon/features/chat/domain/e2ee/e2ee_device.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_envelope.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_payload.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_stores.dart';
import 'package:bhromon/features/chat/domain/e2ee/olm_engine.dart';
import 'package:bhromon/features/chat/domain/e2ee/peer_key_state.dart';
import 'package:bhromon/features/chat/domain/e2ee/prekey_bundle.dart';
import 'package:bhromon/features/chat/domain/e2ee/safety_number.dart';

/// Whether this device can use encryption for the signed-in user.
enum E2eeSetupStatus {
  /// This device holds the account and its keys are the ones on the server.
  ready,

  /// Nothing is published for the user, and this device has no account yet.
  notSetUp,

  /// The keys on the server belong to another device of the user. This device
  /// cannot use encrypted chats until the user sets it up here.
  otherDevice,
}

/// An operation that needs something the device does not have yet, such as keys
/// the other person has not published.
class E2eeNotReadyException implements Exception {
  const E2eeNotReadyException(this.message);

  final String message;

  @override
  String toString() => 'E2eeNotReadyException: $message';
}

/// The encryption operations of one signed-in user on this device (E2EE_DESIGN.md,
/// sections 6 and 9): the account and its keys, sessions, one-time keys, key
/// pinning and the stored plaintext.
///
/// Every operation runs one after another, because each message changes the Olm
/// state. The state is saved after each change. The keys are on the server only as
/// public keys, and the messages are only ever sent as ciphertext.
class E2eeService {
  E2eeService({
    required this.userId,
    required OlmEngine engine,
    required E2eeKeyStore keys,
    required E2eeLocalStore local,
    required E2eePickleKeyVault pickleKeys,
    required String Function() newDeviceId,
    required DateTime Function() now,
    this.oneTimeKeyBatch = 20,
    this.oneTimeKeyLowWater = 10,
    this.fallbackLifetime = const Duration(days: 7),
  })  : _engine = engine,
        _keys = keys,
        _local = local,
        _pickleKeys = pickleKeys,
        _newDeviceId = newDeviceId,
        _now = now;

  /// The signed-in user this service works for.
  final String userId;

  /// How many one-time keys are made each time the supply runs low.
  final int oneTimeKeyBatch;

  /// The supply of unclaimed one-time keys below which more are made.
  final int oneTimeKeyLowWater;

  /// How long a published fallback key is kept before it is rotated. The previous
  /// one stays valid for messages already on their way.
  final Duration fallbackLifetime;

  final OlmEngine _engine;
  final E2eeKeyStore _keys;
  final E2eeLocalStore _local;
  final E2eePickleKeyVault _pickleKeys;
  final String Function() _newDeviceId;
  final DateTime Function() _now;

  E2eeDevice? _device;
  Future<void> _queue = Future<void>.value();

  /// Whether this device can use encryption for the user, and whether the keys on
  /// the server are its own.
  Future<E2eeSetupStatus> status() => _serial(_statusNow);

  /// Brings this device's keys up to date when the device is ready: publishes them
  /// if they are not on the server yet, tops up one-time keys, rotates the fallback
  /// key when it is due, and retries removals that failed. Returns the status.
  Future<E2eeSetupStatus> prepare() => _serial(() async {
        final status = await _statusNow();
        if (status != E2eeSetupStatus.ready) {
          return status;
        }
        final device = (await _loadDevice())!;
        if (await _keys.publishedDeviceId(userId) == null) {
          await _publishFirst(device);
        }
        await _replenishIfLow(device);
        await _rotateFallbackIfDue(device);
        await _retryPendingDeletions();
        return E2eeSetupStatus.ready;
      });

  /// Sets this device up as the one holding the user's keys. A new identity is made,
  /// the keys on the server are replaced, and the other devices' one-time keys are
  /// removed. Sessions made with the old identity are dropped, and the history
  /// kept on the device is not touched. Use it for a new account on this device, or
  /// to take the keys over after a reinstall or from another device.
  Future<void> setUpThisDevice() => _serial(() async {
        final device = E2eeDevice.create(
          engine: _engine,
          userId: userId,
          deviceId: _newDeviceId(),
        );
        final bundle = device.buildBundle();
        await _keys.publishBundle(
          uid: userId,
          bundle: bundle,
          withFallback: true,
        );
        await _keys.deleteOneTimeKeysOfOtherDevices(
          uid: userId,
          deviceId: device.deviceId,
        );
        await _keys.uploadOneTimeKeys(
          uid: userId,
          deviceId: device.deviceId,
          keys: bundle.oneTimeKeys,
        );
        device.markPublished();
        await _local.writeDeviceId(device.deviceId);
        await _local.writePendingKeyDeletions(const []);
        await _local.writeFallbackPublishedAt(_now());
        _device?.dispose();
        _device = device;
        await _save(device);
      });

  /// Encrypts [text] for [recipientUid] and returns the envelope to store in place
  /// of the text. The plaintext is kept on this device, because the sender cannot
  /// decrypt its own message later. A new session claims one of the recipient's
  /// one-time keys, so two senders never start from the same key. When none can be
  /// claimed, the recipient's fallback key is used.
  Future<Map<String, Object>> encryptText({
    required String chatId,
    required String messageId,
    required String recipientUid,
    required String text,
    required int sentAtMillis,
  }) =>
      _serial(() async {
        final device = await _readyDevice();
        final bundle = await _keys.fetchBundle(recipientUid);
        if (bundle == null) {
          throw const E2eeNotReadyException(
            'the other person has not set up encryption',
          );
        }
        final current = await _local.readPeerState(recipientUid);
        final (observed, _) = current.observe(bundle);
        await _local.writePeerState(recipientUid, observed);
        E2eeSignedKey? claimed;
        if (!device.hasSessionWith(bundle)) {
          for (final candidate in device.verifiedOneTimeKeys(bundle)) {
            final won = await _keys.claimOneTimeKey(
              ownerUid: recipientUid,
              keyId: candidate.keyId,
              claimerUid: userId,
            );
            if (won) {
              claimed = candidate;
              break;
            }
          }
        }
        final envelope = device.encrypt(
          recipient: bundle,
          payload: E2eePayload(
            chatId: chatId,
            senderUid: userId,
            recipientUid: recipientUid,
            messageId: messageId,
            sentAtMillis: sentAtMillis,
            text: text,
          ),
          oneTimeKey: claimed,
        );
        await _save(device);
        await _local.writePlaintext(chatId, messageId, text);
        return envelope.toJson();
      });

  /// The text of a message from [senderUid]. A message is decrypted once, and the
  /// text is kept on this device, so the same message reads the same next time.
  /// Throws if the message cannot be decrypted, and then nothing from it is used.
  Future<String> decryptMessage({
    required String chatId,
    required String messageId,
    required String senderUid,
    required Map<String, dynamic> envelope,
  }) =>
      _serial(() async {
        final kept = await _local.readPlaintext(chatId, messageId);
        if (kept != null) {
          return kept;
        }
        final device = await _readyDevice();
        final parsed = E2eeEnvelope.fromJson(envelope);
        final bundle = await _keys.fetchBundle(senderUid);
        if (bundle == null) {
          throw const E2eeNotReadyException(
            'the sender has no published keys',
          );
        }
        final current = await _local.readPeerState(senderUid);
        final (observed, _) = current.observe(bundle);
        await _local.writePeerState(senderUid, observed);
        if (parsed.messageType == 0) {
          // The one-time key is used up by this message. It is removed first, so
          // no other sender can claim it while this device is reading.
          final keyId = E2eeSignedKey.idFor(
            _engine.oneTimeKeyOfPreKey(parsed.ciphertext),
          );
          await _removeOneTimeKey(keyId);
        }
        final result = device.decrypt(
          sender: bundle,
          envelope: parsed,
          chatId: chatId,
          messageId: messageId,
        );
        await _save(device);
        final text = result.payload.text;
        await _local.writePlaintext(chatId, messageId, text);
        return text;
      });

  /// The plaintext kept for a message, or null when there is none on this device.
  Future<String?> plaintextFor(String chatId, String messageId) {
    return _local.readPlaintext(chatId, messageId);
  }

  /// The keys this device has pinned for [uid].
  Future<PeerKeyState> peerState(String uid) => _local.readPeerState(uid);

  /// Whether [uid] has published keys, so that an encrypted chat can start with them.
  Future<bool> recipientReady(String uid) => _serial(
        () async => (await _keys.fetchBundle(uid)) != null,
      );

  /// Trusts the changed identity of [uid]. The warning goes away. The contact stays
  /// unverified until the user compares the safety numbers again.
  Future<PeerKeyState> acceptKeyChange(String uid) => _serial(() async {
        final next = (await _local.readPeerState(uid)).acceptChange();
        await _local.writePeerState(uid, next);
        return next;
      });

  /// Records that the user has compared the safety number of [identityBlock].
  Future<PeerKeyState> markVerified(String uid, Uint8List identityBlock) {
    return _serial(() async {
      final next = (await _local.readPeerState(uid)).verified(identityBlock);
      await _local.writePeerState(uid, next);
      return next;
    });
  }

  /// The 60-digit safety number of [uid] for this device: the pinned identity, or
  /// the pending one when [pending] is set. Both sides compute the same number.
  Future<String> safetyNumber(String uid, {bool pending = false}) =>
      _serial(() async {
        final device = await _readyDevice();
        final state = await _local.readPeerState(uid);
        final identity = pending ? state.pending : state.pinned;
        if (identity == null) {
          throw const E2eeNotReadyException('there is no identity for them');
        }
        return SafetyNumber.compute(
          device.identityBlock,
          identity.identityBlock,
        );
      });

  /// Frees the native account and sessions. The service must not be used after.
  void dispose() {
    _device?.dispose();
    _device = null;
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final run = _queue.then((_) => action());
    _queue = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<E2eeSetupStatus> _statusNow() async {
    final device = await _loadDevice();
    final published = await _keys.publishedDeviceId(userId);
    if (device == null) {
      return published == null
          ? E2eeSetupStatus.notSetUp
          : E2eeSetupStatus.otherDevice;
    }
    if (published != null && published != device.deviceId) {
      return E2eeSetupStatus.otherDevice;
    }
    return E2eeSetupStatus.ready;
  }

  Future<E2eeDevice> _readyDevice() async {
    final device = await _loadDevice();
    if (device == null) {
      throw const E2eeNotReadyException(
        'encryption is not set up on this device',
      );
    }
    return device;
  }

  Future<E2eeDevice?> _loadDevice() async {
    final cached = _device;
    if (cached != null) {
      return cached;
    }
    final deviceId = await _local.readDeviceId();
    final pickle = await _local.readAccountPickle();
    if (deviceId == null || pickle == null) {
      return null;
    }
    final key = await _pickleKeys.readOrCreate();
    final device = E2eeDevice.restore(
      engine: _engine,
      userId: userId,
      deviceId: deviceId,
      accountPickle: pickle,
      pickleKey: key,
      sessions: await _local.readSessions(),
    );
    _device = device;
    return device;
  }

  Future<void> _save(E2eeDevice device) async {
    final key = await _pickleKeys.readOrCreate();
    await _local.writeAccountPickle(device.pickleAccount(key));
    await _local.writeSessions(device.snapshotSessions(key));
  }

  /// The first publication: the identity and the fallback key, then the one-time
  /// keys, and only then the keys are marked as published.
  Future<void> _publishFirst(E2eeDevice device) async {
    final bundle = device.buildBundle();
    await _keys.publishBundle(uid: userId, bundle: bundle, withFallback: true);
    await _keys.uploadOneTimeKeys(
      uid: userId,
      deviceId: device.deviceId,
      keys: bundle.oneTimeKeys,
    );
    device.markPublished();
    await _local.writeFallbackPublishedAt(_now());
    await _save(device);
  }

  Future<void> _replenishIfLow(E2eeDevice device) async {
    final unclaimed = await _keys.unclaimedOneTimeKeyCount(
      uid: userId,
      deviceId: device.deviceId,
    );
    if (unclaimed >= oneTimeKeyLowWater) {
      return;
    }
    final fresh = device.newOneTimeKeys(oneTimeKeyBatch);
    await _keys.uploadOneTimeKeys(
      uid: userId,
      deviceId: device.deviceId,
      keys: fresh,
    );
    device.markPublished();
    await _save(device);
  }

  Future<void> _rotateFallbackIfDue(E2eeDevice device) async {
    final last = await _local.readFallbackPublishedAt();
    if (last != null && _now().difference(last) < fallbackLifetime) {
      return;
    }
    // Marking the fallback key published also marks the one-time keys, so any
    // one-time key still waiting goes up first.
    final waiting = device.unpublishedOneTimeKeys();
    if (waiting.isNotEmpty) {
      await _keys.uploadOneTimeKeys(
        uid: userId,
        deviceId: device.deviceId,
        keys: waiting,
      );
    }
    device.rotateFallbackKey();
    await _keys.publishBundle(
      uid: userId,
      bundle: device.buildBundle(),
      withFallback: true,
    );
    device.markPublished();
    await _local.writeFallbackPublishedAt(_now());
    await _save(device);
  }

  /// Removes a used one-time key. If the server cannot be reached, the key is kept
  /// in the pending list, and the next [prepare] tries again.
  Future<void> _removeOneTimeKey(String keyId) async {
    try {
      await _keys.deleteOneTimeKey(uid: userId, keyId: keyId);
    } on Exception {
      final pending = await _local.readPendingKeyDeletions();
      await _local.writePendingKeyDeletions([
        ...pending,
        if (!pending.contains(keyId)) keyId,
      ]);
    }
  }

  Future<void> _retryPendingDeletions() async {
    final pending = await _local.readPendingKeyDeletions();
    if (pending.isEmpty) {
      return;
    }
    final stillPending = <String>[];
    for (final keyId in pending) {
      try {
        await _keys.deleteOneTimeKey(uid: userId, keyId: keyId);
      } on Exception {
        stillPending.add(keyId);
      }
    }
    await _local.writePendingKeyDeletions(stillPending);
  }
}
