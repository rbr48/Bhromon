import 'dart:convert';
import 'dart:typed_data';

import 'package:bhromon/features/chat/domain/e2ee/e2ee_exceptions.dart';
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

/// A pickle is the state, its MAC under the key, so another key or an altered pickle
/// is refused. It is not encryption: the fake is only for the device logic.
Uint8List _pickle(Uint8List key, Map<String, Object?> state) {
  final body = utf8.encode(jsonEncode(state));
  return _encodeFields({
    'body': base64.encode(body),
    'mac': base64.encode(_hash([...key, ...body])),
  });
}

Map<String, dynamic> _unpickle(
    Uint8List pickle, Uint8List key, String operation) {
  final fields = _decodeFields(pickle, operation);
  final body = fields['body'];
  final mac = fields['mac'];
  if (body is! String || mac is! String) {
    throw OlmEngineException(operation, -2);
  }
  final bytes = base64.decode(body);
  if (base64.encode(_hash([...key, ...bytes])) != mac) {
    throw OlmEngineException(operation, -4);
  }
  return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
}

Uint8List _bytesOf(Object? value) => base64.decode(value as String);

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
    FakeOlmEngine._checkKeyLength(key);
    final state = _unpickle(pickle, key, 'account_from_pickle');
    return _FakeAccount.fromState(this, state);
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
    FakeOlmEngine._checkKeyLength(key);
    final state = _unpickle(pickle, key, 'session_from_pickle');
    return _FakeSession.fromState(state);
  }

  @override
  Uint8List oneTimeKeyOfPreKey(Uint8List prekeyMessage) {
    final Map<String, dynamic> fields;
    try {
      fields = _decodeFields(prekeyMessage, 'one_time_key_of_pre_key');
    } on OlmEngineException {
      throw const E2eeFormatException('the message is not a pre-key message');
    }
    final oneTimeKey = fields['otk'];
    if (oneTimeKey is! String) {
      throw const E2eeFormatException('the message is not a pre-key message');
    }
    return base64.decode(oneTimeKey);
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

  _FakeAccount.fromState(FakeOlmEngine engine, Map<String, dynamic> state)
      : _engine = engine,
        _curve = _bytesOf(state['curve']),
        _ed = _bytesOf(state['ed']),
        _fallback =
            state['fallback'] == null ? null : _bytesOf(state['fallback']),
        _previousFallback = state['previousFallback'] == null
            ? null
            : _bytesOf(state['previousFallback']),
        _fallbackPublished = state['fallbackPublished'] as bool {
    final oneTime = state['oneTime'] as Map<String, dynamic>;
    _oneTime.addAll({
      for (final entry in oneTime.entries) entry.key: entry.value as bool,
    });
  }

  final FakeOlmEngine _engine;
  final Uint8List _curve;
  final Uint8List _ed;

  /// One-time keys by their base64 value; true once published.
  final Map<String, bool> _oneTime = {};
  Uint8List? _fallback;
  Uint8List? _previousFallback;
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

  /// As the native engine does, the fallback key being replaced stays valid for
  /// messages already on their way.
  @override
  void generateFallbackKey() {
    _previousFallback = _fallback;
    _fallback = _engine.freshKey('fallback');
    _fallbackPublished = false;
  }

  @override
  Uint8List sign(Uint8List message) => _signature(_ed, message);

  @override
  Uint8List pickle(Uint8List key) {
    FakeOlmEngine._checkKeyLength(key);
    return _pickle(key, {
      'curve': base64.encode(_curve),
      'ed': base64.encode(_ed),
      'oneTime': _oneTime,
      'fallback': _fallback == null ? null : base64.encode(_fallback!),
      'previousFallback':
          _previousFallback == null ? null : base64.encode(_previousFallback!),
      'fallbackPublished': _fallbackPublished,
    });
  }

  @override
  void dispose() {}

  /// Whether this account holds [key] as a one-time or fallback key.
  bool holds(Uint8List key) {
    final fallback = _fallback;
    final previous = _previousFallback;
    return _oneTime.containsKey(base64.encode(key)) ||
        (fallback != null && _same(fallback, key)) ||
        (previous != null && _same(previous, key));
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

  _FakeSession.fromState(Map<String, dynamic> state)
      : _id = state['id'] as String,
        _key = _bytesOf(state['key']),
        _prekeyIdentity = state['ik'] == null ? null : _bytesOf(state['ik']),
        _prekeyOneTimeKey =
            state['otk'] == null ? null : _bytesOf(state['otk']);

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
    FakeOlmEngine._checkKeyLength(key);
    return _pickle(key, {
      'id': _id,
      'key': base64.encode(_key),
      'ik': _prekeyIdentity == null ? null : base64.encode(_prekeyIdentity!),
      'otk':
          _prekeyOneTimeKey == null ? null : base64.encode(_prekeyOneTimeKey!),
    });
  }

  @override
  void dispose() {}
}
