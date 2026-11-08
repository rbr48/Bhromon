import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_device.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_exceptions.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_stores.dart';
import 'package:bhromon/features/chat/domain/e2ee/peer_key_state.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// The device's own state, kept in one encrypted Hive box. The box is encrypted
/// by [HiveEncryptionService], and the Olm pickles inside it are encrypted again
/// under the pickle key from [SecureE2eePickleKeyVault].
class HiveE2eeLocalStore implements E2eeLocalStore {
  /// The state of one account. Each account on the device has its own box, so
  /// accounts that share a device never read each other's keys.
  HiveE2eeLocalStore(this._encryption, {required String userId})
      : _boxName = 'e2ee_state_$userId';

  final HiveEncryptionService _encryption;
  final String _boxName;
  Future<Box<dynamic>>? _box;

  Future<Box<dynamic>> _open() =>
      _box ??= _encryption.openEncryptedBox<dynamic>(_boxName);

  @override
  Future<String?> readDeviceId() async {
    final value = (await _open()).get('deviceId');
    return value is String ? value : null;
  }

  @override
  Future<void> writeDeviceId(String deviceId) async {
    await (await _open()).put('deviceId', deviceId);
  }

  @override
  Future<Uint8List?> readAccountPickle() async {
    final value = (await _open()).get('account');
    return value is String ? base64.decode(value) : null;
  }

  @override
  Future<void> writeAccountPickle(Uint8List pickle) async {
    await (await _open()).put('account', base64.encode(pickle));
  }

  @override
  Future<List<SessionSnapshot>> readSessions() async {
    final value = (await _open()).get('sessions');
    if (value == null) {
      return const [];
    }
    if (value is! List) {
      throw const E2eeFormatException('the stored sessions are malformed');
    }
    return [
      for (final item in value)
        if (item is Map)
          SessionSnapshot(
            userId: item['u'] as String,
            identityKey: base64.decode(item['i'] as String),
            pickle: base64.decode(item['p'] as String),
            confirmed: item['c'] as bool,
          ),
    ];
  }

  @override
  Future<void> writeSessions(List<SessionSnapshot> sessions) async {
    await (await _open()).put('sessions', [
      for (final session in sessions)
        {
          'u': session.userId,
          'i': base64.encode(session.identityKey),
          'p': base64.encode(session.pickle),
          'c': session.confirmed,
        },
    ]);
  }

  @override
  Future<PeerKeyState> readPeerState(String uid) async {
    final value = (await _open()).get('peer:$uid');
    if (value is! String) {
      return const PeerKeyState();
    }
    return PeerKeyState.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  @override
  Future<void> writePeerState(String uid, PeerKeyState state) async {
    await (await _open()).put('peer:$uid', jsonEncode(state.toJson()));
  }

  @override
  Future<String?> readPlaintext(String chatId, String messageId) async {
    final value = (await _open()).get(_plaintextKey(chatId, messageId));
    return value is String ? value : null;
  }

  @override
  Future<void> writePlaintext(
      String chatId, String messageId, String text) async {
    await (await _open()).put(_plaintextKey(chatId, messageId), text);
  }

  @override
  Future<DateTime?> readFallbackPublishedAt() async {
    final value = (await _open()).get('fallbackPublishedAt');
    return value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;
  }

  @override
  Future<void> writeFallbackPublishedAt(DateTime at) async {
    await (await _open()).put('fallbackPublishedAt', at.millisecondsSinceEpoch);
  }

  @override
  Future<List<String>> readPendingKeyDeletions() async {
    final value = (await _open()).get('pendingKeyDeletions');
    return value is List ? [for (final id in value) id as String] : const [];
  }

  @override
  Future<void> writePendingKeyDeletions(List<String> keyIds) async {
    await (await _open()).put('pendingKeyDeletions', keyIds);
  }

  static String _plaintextKey(String chatId, String messageId) =>
      'plain:$chatId:$messageId';
}

/// The pickle key, kept in the platform keystore. It is made once, and it is never
/// written anywhere else. If the stored key is damaged, this throws rather than
/// making a new one, because a new key would make the stored pickles unreadable.
class SecureE2eePickleKeyVault implements E2eePickleKeyVault {
  SecureE2eePickleKeyVault([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _name = 'e2ee.pickle_key';
  static const int _length = 32;

  final FlutterSecureStorage _storage;
  Uint8List? _cached;

  @override
  Future<Uint8List> readOrCreate() async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    final stored = await _storage.read(key: _name);
    if (stored != null) {
      final key = Uint8List.fromList(base64.decode(stored));
      if (key.length != _length) {
        throw StateError('the stored pickle key is damaged');
      }
      return _cached = key;
    }
    final random = Random.secure();
    final fresh = Uint8List.fromList(
      List<int>.generate(_length, (_) => random.nextInt(256)),
    );
    await _storage.write(key: _name, value: base64.encode(fresh));
    return _cached = fresh;
  }
}
