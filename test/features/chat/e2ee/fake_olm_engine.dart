import 'dart:convert';
import 'dart:typed_data';

import 'package:bhromon/features/chat/domain/e2ee/olm_engine.dart';
import 'package:crypto/crypto.dart';

// A stand-in for the native engine, so the device logic runs on any platform. It is
// not cryptography. It keeps the calls and the refusals that the device relies on: a
// one-time key the account does not hold, a message for another session, a body
// that no longer matches its MAC, a signature under another key, and a pre-key
// message from another identity key. Secrecy and replay are tested against the
// native engine in olm_native_test.dart.

Uint8List _hash(List<int> bytes) =>
    Uint8List.fromList(sha256.convert(bytes).bytes);

/// Both orders of two keys put in one canonical order, so each side derives the same
/// session from its own view.
List<int> _pair(Uint8List a, Uint8List b) {
  final first = _compare(a, b) <= 0 ? a : b;
  final second = identical(first, a) ? b : a;
  return [...first, ...second];
}

int _compare(Uint8List a, Uint8List b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return a[i] - b[i];
    }
  }
  return 0;
}

bool _same(Uint8List a, Uint8List b) =>
    a.length == b.length && _compare(a, b) == 0;

String _sessionId(Uint8List a, Uint8List b, Uint8List oneTimeKey) {
  return base64.encode(
    _hash([...utf8.encode('sid'), ..._pair(a, b), ...oneTimeKey]),
  );
}

Uint8List _sessionKey(Uint8List a, Uint8List b, Uint8List oneTimeKey) {
  return _hash([...utf8.encode('key'), ..._pair(a, b), ...oneTimeKey]);
}

Uint8List _signature(Uint8List key, Uint8List message) {
  return Uint8List.fromList([
    ..._hash([...key, ...message]),
    ..._hash([...message, ...key]),
  ]);
}

String _mac(Uint8List key, String sessionId, String body) {
  return base64.encode(
    _hash([...key, ...utf8.encode(sessionId), ...utf8.encode(body)]),
  );
}

Uint8List _encodeFields(Map<String, Object> fields) =>
    Uint8List.fromList(utf8.encode(jsonEncode(fields)));

Map<String, dynamic> _decodeFields(Uint8List bytes, String operation) {
  try {
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  } on Object {
    // The native engine reports a message it cannot parse as a decode error.
    throw OlmEngineException(operation, -2);
  }
}

Uint8List _open(
  Uint8List key,
  String sessionId,
  Map<String, dynamic> fields,
  String operation,
) {
  final body = fields['body'];
  final mac = fields['mac'];
  if (fields['sid'] != sessionId ||
      body is! String ||
      mac is! String ||
      mac != _mac(key, sessionId, body)) {
    throw OlmEngineException(operation, -4);
  }
  return base64.decode(body);
}

/// The fake engine. Keys come from a counter, so a test run is repeatable.
class FakeOlmEngine implements OlmEngine {
  int _serial = 0;

  /// A fresh 32-byte value, standing in for a random key.
  Uint8List freshKey(String purpose) {
    _serial++;
    return _hash(utf8.encode('$purpose/$_serial'));
  }

  @override
  OlmAccount createAccount() => _FakeAccount(this);

  @override
  OlmAccount restoreAccount(Uint8List pickle, Uint8List key) {
    throw UnsupportedError('the fake engine does not pickle');
  }

  @override
  OlmSession createOutboundSession({
    required OlmAccount account,
    required Uint8List theirCurve25519Key,
    required Uint8List theirOneTimeKey,
  }) {
    final mine = _asFake(account);
    _checkKeyLength(theirCurve25519Key);
    _checkKeyLength(theirOneTimeKey);
    final ours = mine.curve25519Key;
    return _FakeSession(
      id: _sessionId(ours, theirCurve25519Key, theirOneTimeKey),
      key: _sessionKey(ours, theirCurve25519Key, theirOneTimeKey),
      prekeyIdentity: ours,
      prekeyOneTimeKey: theirOneTimeKey,
    );
  }

  @override
  OlmInbound createInboundSession({
    required OlmAccount account,
    required Uint8List theirCurve25519Key,
    required Uint8List prekeyMessage,
  }) {
    final mine = _asFake(account);
    const operation = 'create_inbound_session';
    final fields = _decodeFields(prekeyMessage, operation);
    final identity = fields['ik'];
    final oneTimeKey = fields['otk'];
    if (identity is! String || oneTimeKey is! String) {
      throw const OlmEngineException(operation, -2);
    }
    final theirIdentity = base64.decode(identity);
    final usedKey = base64.decode(oneTimeKey);
    if (!_same(theirIdentity, theirCurve25519Key) || !mine.holds(usedKey)) {
      throw const OlmEngineException(operation, -3);
    }
    final id = _sessionId(mine.curve25519Key, theirIdentity, usedKey);
    final key = _sessionKey(mine.curve25519Key, theirIdentity, usedKey);
    final plaintext = _open(key, id, fields, operation);
    mine.consume(usedKey);
    return OlmInbound(
      session: _FakeSession(id: id, key: key),
      plaintext: plaintext,
    );
  }

  @override
  OlmSession restoreSession(Uint8List pickle, Uint8List key) {
    throw UnsupportedError('the fake engine does not pickle');
  }

  @override
  bool verifySignature({
    required Uint8List ed25519Key,
    required Uint8List message,
    required Uint8List signature,
  }) {
    _checkKeyLength(ed25519Key);
    if (signature.length != 64) {
      return false;
    }
    return _same(_signature(ed25519Key, message), signature);
  }

  static void _checkKeyLength(Uint8List key) {
    if (key.length != 32) {
      throw const OlmEngineException('key', -7);
    }
  }

  static _FakeAccount _asFake(OlmAccount account) {
    if (account is! _FakeAccount) {
      throw ArgumentError.value(account, 'account', 'not from this fake');
    }
    return account;
  }
}

class _FakeAccount implements OlmAccount {
  _FakeAccount(FakeOlmEngine engine)
      : _curve = engine.freshKey('curve'),
        _ed = engine.freshKey('ed'),
        _engine = engine;

  final FakeOlmEngine _engine;
  final Uint8List _curve;
  final Uint8List _ed;

  /// One-time keys by their base64 value; true once published.
  final Map<String, bool> _oneTime = {};
  Uint8List? _fallback;
  bool _fallbackPublished = false;

  @override
  Uint8List get curve25519Key => Uint8List.fromList(_curve);

  @override
  Uint8List get ed25519Key => Uint8List.fromList(_ed);

  @override
  void generateOneTimeKeys(int count) {
    if (count < 1 || count > 100) {
      throw const OlmEngineException('generate_one_time_keys', -7);
    }
    for (var i = 0; i < count; i++) {
      _oneTime[base64.encode(_engine.freshKey('one-time'))] = false;
    }
  }

  @override
  List<Uint8List> unpublishedOneTimeKeys() => [
        for (final entry in _oneTime.entries)
          if (!entry.value) base64.decode(entry.key),
      ];

  @override
  void markKeysPublished() {
    _oneTime.updateAll((_, __) => true);
    _fallbackPublished = true;
  }

  @override
  Uint8List? unpublishedFallbackKey() {
    final fallback = _fallback;
    if (fallback == null || _fallbackPublished) {
      return null;
    }
    return Uint8List.fromList(fallback);
  }

  @override
  void generateFallbackKey() {
    _fallback = _engine.freshKey('fallback');
    _fallbackPublished = false;
  }

  @override
  Uint8List sign(Uint8List message) => _signature(_ed, message);

  @override
  Uint8List pickle(Uint8List key) {
    throw UnsupportedError('the fake engine does not pickle');
  }

  @override
  void dispose() {}

  /// Whether this account holds [key] as a one-time or fallback key.
  bool holds(Uint8List key) {
    final fallback = _fallback;
    return _oneTime.containsKey(base64.encode(key)) ||
        (fallback != null && _same(fallback, key));
  }

  /// A one-time key is used up once a session is made from it. The fallback key is
  /// kept, as the native engine keeps it.
  void consume(Uint8List key) => _oneTime.remove(base64.encode(key));
}

class _FakeSession implements OlmSession {
  _FakeSession({
    required String id,
    required Uint8List key,
    Uint8List? prekeyIdentity,
    Uint8List? prekeyOneTimeKey,
  })  : _id = id,
        _key = key,
        _prekeyIdentity = prekeyIdentity,
        _prekeyOneTimeKey = prekeyOneTimeKey;

  final String _id;
  final Uint8List _key;

  /// Set until the peer answers. While set, messages are pre-key messages that carry
  /// the identity and the one-time key the session was started from.
  Uint8List? _prekeyIdentity;
  Uint8List? _prekeyOneTimeKey;

  @override
  String get id => _id;

  @override
  OlmMessage encrypt(Uint8List plaintext) {
    final body = base64.encode(plaintext);
    final fields = <String, Object>{
      'sid': _id,
      'body': body,
      'mac': _mac(_key, _id, body),
    };
    final identity = _prekeyIdentity;
    final oneTimeKey = _prekeyOneTimeKey;
    if (identity != null && oneTimeKey != null) {
      fields['ik'] = base64.encode(identity);
      fields['otk'] = base64.encode(oneTimeKey);
      return OlmMessage(messageType: 0, bytes: _encodeFields(fields));
    }
    return OlmMessage(messageType: 1, bytes: _encodeFields(fields));
  }

  @override
  Uint8List decrypt(int messageType, Uint8List message) {
    if (messageType != 0 && messageType != 1) {
      throw const OlmEngineException('decrypt', -2);
    }
    final fields = _decodeFields(message, 'decrypt');
    final plaintext = _open(_key, _id, fields, 'decrypt');
    _prekeyIdentity = null;
    _prekeyOneTimeKey = null;
    return plaintext;
  }

  @override
  Uint8List pickle(Uint8List key) {
    throw UnsupportedError('the fake engine does not pickle');
  }

  @override
  void dispose() {}
}
