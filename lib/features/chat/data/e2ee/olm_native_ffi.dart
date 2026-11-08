import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:bhromon/features/chat/domain/e2ee/olm_engine.dart';

// The C interface of native/e2ee_olm (E2EE_DESIGN.md, section 5). The signatures
// below follow include/e2ee_olm.h, and the library must report ABI version 1.

const int _abiVersion = 1;
const int _ok = 0;
const int _errSignature = -8;
const int _keyLength = 32;
const int _signatureLength = 64;
const int _oneTimeKeyCapacity = 100;

final DynamicLibrary _process = DynamicLibrary.process();

// libc's allocator. The library's buffers are copied in and out through it, so the
// app needs no separate FFI package.
final Pointer<Void> Function(int size) _malloc = _process.lookupFunction<
    Pointer<Void> Function(IntPtr), Pointer<Void> Function(int)>('malloc');
final void Function(Pointer<Void> pointer) _free = _process.lookupFunction<
    Void Function(Pointer<Void>), void Function(Pointer<Void>)>('free');

typedef _AbiVersionC = Uint32 Function();
typedef _AbiVersion = int Function();
typedef _BytesFreeC = Void Function(Pointer<Uint8>, Size);
typedef _BytesFree = void Function(Pointer<Uint8>, int);
typedef _AccountNewC = Pointer<Void> Function();
typedef _AccountNew = Pointer<Void> Function();
typedef _HandleVoidC = Void Function(Pointer<Void>);
typedef _HandleVoid = void Function(Pointer<Void>);
typedef _HandleIntC = Int32 Function(Pointer<Void>);
typedef _HandleInt = int Function(Pointer<Void>);
typedef _KeyOutC = Int32 Function(Pointer<Void>, Pointer<Uint8>);
typedef _KeyOut = int Function(Pointer<Void>, Pointer<Uint8>);
typedef _GenerateC = Int32 Function(Pointer<Void>, Size);
typedef _Generate = int Function(Pointer<Void>, int);
typedef _OneTimeKeysC = Int32 Function(
  Pointer<Void>,
  Pointer<Uint8>,
  Size,
  Pointer<Size>,
);
typedef _OneTimeKeys = int Function(
  Pointer<Void>,
  Pointer<Uint8>,
  int,
  Pointer<Size>,
);
typedef _FallbackC = Int32 Function(
    Pointer<Void>, Pointer<Uint8>, Pointer<Size>);
typedef _Fallback = int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Size>);
typedef _SignC = Int32 Function(
    Pointer<Void>, Pointer<Uint8>, Size, Pointer<Uint8>);
typedef _Sign = int Function(
    Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>);
typedef _VerifyC = Int32 Function(
    Pointer<Uint8>, Pointer<Uint8>, Size, Pointer<Uint8>);
typedef _Verify = int Function(
    Pointer<Uint8>, Pointer<Uint8>, int, Pointer<Uint8>);
typedef _PickleC = Int32 Function(
  Pointer<Void>,
  Pointer<Uint8>,
  Pointer<Pointer<Uint8>>,
  Pointer<Size>,
);
typedef _Pickle = int Function(
  Pointer<Void>,
  Pointer<Uint8>,
  Pointer<Pointer<Uint8>>,
  Pointer<Size>,
);
typedef _FromPickleC = Int32 Function(
  Pointer<Uint8>,
  Size,
  Pointer<Uint8>,
  Pointer<Pointer<Void>>,
);
typedef _FromPickle = int Function(
  Pointer<Uint8>,
  int,
  Pointer<Uint8>,
  Pointer<Pointer<Void>>,
);
typedef _OutboundC = Int32 Function(
  Pointer<Void>,
  Pointer<Uint8>,
  Pointer<Uint8>,
  Pointer<Pointer<Void>>,
);
typedef _Outbound = int Function(
  Pointer<Void>,
  Pointer<Uint8>,
  Pointer<Uint8>,
  Pointer<Pointer<Void>>,
);
typedef _InboundC = Int32 Function(
  Pointer<Void>,
  Pointer<Uint8>,
  Pointer<Uint8>,
  Size,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Uint8>>,
  Pointer<Size>,
);
typedef _Inbound = int Function(
  Pointer<Void>,
  Pointer<Uint8>,
  Pointer<Uint8>,
  int,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Uint8>>,
  Pointer<Size>,
);
typedef _EncryptC = Int32 Function(
  Pointer<Void>,
  Pointer<Uint8>,
  Size,
  Pointer<Size>,
  Pointer<Pointer<Uint8>>,
  Pointer<Size>,
);
typedef _Encrypt = int Function(
  Pointer<Void>,
  Pointer<Uint8>,
  int,
  Pointer<Size>,
  Pointer<Pointer<Uint8>>,
  Pointer<Size>,
);
typedef _DecryptC = Int32 Function(
  Pointer<Void>,
  Size,
  Pointer<Uint8>,
  Size,
  Pointer<Pointer<Uint8>>,
  Pointer<Size>,
);
typedef _Decrypt = int Function(
  Pointer<Void>,
  int,
  Pointer<Uint8>,
  int,
  Pointer<Pointer<Uint8>>,
  Pointer<Size>,
);
typedef _SessionIdC = Int32 Function(
  Pointer<Void>,
  Pointer<Pointer<Uint8>>,
  Pointer<Size>,
);
typedef _SessionId = int Function(
  Pointer<Void>,
  Pointer<Pointer<Uint8>>,
  Pointer<Size>,
);

/// Opens the native library and returns the Olm engine that uses it. [libraryPath]
/// is the library file. Without it the library is looked up as `libe2ee_olm.so`.
OlmEngine openOlmEngine({String? libraryPath}) {
  final bindings = _Bindings(
    DynamicLibrary.open(libraryPath ?? 'libe2ee_olm.so'),
  );
  final version = bindings.abiVersion();
  if (version != _abiVersion) {
    throw OlmEngineException('abi_version', version);
  }
  return _FfiEngine(bindings);
}

class _Bindings {
  _Bindings(DynamicLibrary library)
      : abiVersion = library.lookupFunction<_AbiVersionC, _AbiVersion>(
          'e2ee_abi_version',
        ),
        bytesFree = library.lookupFunction<_BytesFreeC, _BytesFree>(
          'e2ee_bytes_free',
        ),
        accountNew = library.lookupFunction<_AccountNewC, _AccountNew>(
          'e2ee_account_new',
        ),
        accountFree = library.lookupFunction<_HandleVoidC, _HandleVoid>(
          'e2ee_account_free',
        ),
        accountCurve25519Key = library.lookupFunction<_KeyOutC, _KeyOut>(
          'e2ee_account_curve25519_key',
        ),
        accountEd25519Key = library.lookupFunction<_KeyOutC, _KeyOut>(
          'e2ee_account_ed25519_key',
        ),
        generateOneTimeKeys = library.lookupFunction<_GenerateC, _Generate>(
          'e2ee_account_generate_one_time_keys',
        ),
        oneTimeKeys = library.lookupFunction<_OneTimeKeysC, _OneTimeKeys>(
          'e2ee_account_one_time_keys',
        ),
        markKeysPublished = library.lookupFunction<_HandleIntC, _HandleInt>(
          'e2ee_account_mark_keys_published',
        ),
        accountSign = library.lookupFunction<_SignC, _Sign>(
          'e2ee_account_sign',
        ),
        verifySignature = library.lookupFunction<_VerifyC, _Verify>(
          'e2ee_verify_signature',
        ),
        fallbackKey = library.lookupFunction<_FallbackC, _Fallback>(
          'e2ee_account_fallback_key',
        ),
        generateFallbackKey = library.lookupFunction<_HandleIntC, _HandleInt>(
          'e2ee_account_generate_fallback_key',
        ),
        accountPickle = library.lookupFunction<_PickleC, _Pickle>(
          'e2ee_account_pickle',
        ),
        accountFromPickle = library.lookupFunction<_FromPickleC, _FromPickle>(
          'e2ee_account_from_pickle',
        ),
        sessionOutbound = library.lookupFunction<_OutboundC, _Outbound>(
          'e2ee_session_create_outbound',
        ),
        sessionInbound = library.lookupFunction<_InboundC, _Inbound>(
          'e2ee_session_create_inbound',
        ),
        sessionEncrypt = library.lookupFunction<_EncryptC, _Encrypt>(
          'e2ee_session_encrypt',
        ),
        sessionDecrypt = library.lookupFunction<_DecryptC, _Decrypt>(
          'e2ee_session_decrypt',
        ),
        sessionId = library.lookupFunction<_SessionIdC, _SessionId>(
          'e2ee_session_id',
        ),
        sessionPickle = library.lookupFunction<_PickleC, _Pickle>(
          'e2ee_session_pickle',
        ),
        sessionFromPickle = library.lookupFunction<_FromPickleC, _FromPickle>(
          'e2ee_session_from_pickle',
        ),
        sessionFree = library.lookupFunction<_HandleVoidC, _HandleVoid>(
          'e2ee_session_free',
        );

  final _AbiVersion abiVersion;
  final _BytesFree bytesFree;
  final _AccountNew accountNew;
  final _HandleVoid accountFree;
  final _KeyOut accountCurve25519Key;
  final _KeyOut accountEd25519Key;
  final _Generate generateOneTimeKeys;
  final _OneTimeKeys oneTimeKeys;
  final _HandleInt markKeysPublished;
  final _Sign accountSign;
  final _Verify verifySignature;
  final _Fallback fallbackKey;
  final _HandleInt generateFallbackKey;
  final _Pickle accountPickle;
  final _FromPickle accountFromPickle;
  final _Outbound sessionOutbound;
  final _Inbound sessionInbound;
  final _Encrypt sessionEncrypt;
  final _Decrypt sessionDecrypt;
  final _SessionId sessionId;
  final _Pickle sessionPickle;
  final _FromPickle sessionFromPickle;
  final _HandleVoid sessionFree;
}

class _FfiEngine implements OlmEngine {
  _FfiEngine(this._b);

  final _Bindings _b;

  @override
  OlmAccount createAccount() {
    final handle = _b.accountNew();
    if (handle == nullptr) {
      throw const OlmEngineException('account_new', -1);
    }
    return _FfiAccount(_b, handle);
  }

  @override
  OlmAccount restoreAccount(Uint8List pickle, Uint8List key) {
    final handle = _restore(
      _b.accountFromPickle,
      'account_from_pickle',
      pickle,
      key,
    );
    return _FfiAccount(_b, handle);
  }

  @override
  OlmSession createOutboundSession({
    required OlmAccount account,
    required Uint8List theirCurve25519Key,
    required Uint8List theirOneTimeKey,
  }) {
    final accountHandle = _handleOf(account);
    _requireLength(theirCurve25519Key, 'their identity key');
    _requireLength(theirOneTimeKey, 'their one-time key');
    final identity = _copyIn(theirCurve25519Key);
    final oneTime = _copyIn(theirOneTimeKey);
    final out = _malloc(sizeOf<Pointer<Void>>()).cast<Pointer<Void>>();
    try {
      _check(
        'create_outbound_session',
        _b.sessionOutbound(accountHandle, identity, oneTime, out),
      );
      return _FfiSession(_b, out.value);
    } finally {
      _free(identity.cast<Void>());
      _free(oneTime.cast<Void>());
      _free(out.cast<Void>());
    }
  }

  @override
  OlmInbound createInboundSession({
    required OlmAccount account,
    required Uint8List theirCurve25519Key,
    required Uint8List prekeyMessage,
  }) {
    final accountHandle = _handleOf(account);
    _requireLength(theirCurve25519Key, 'their identity key');
    final identity = _copyIn(theirCurve25519Key);
    final message = _copyIn(prekeyMessage);
    final session = _malloc(sizeOf<Pointer<Void>>()).cast<Pointer<Void>>();
    final plainPointer =
        _malloc(sizeOf<Pointer<Uint8>>()).cast<Pointer<Uint8>>();
    final plainLength = _malloc(sizeOf<Size>()).cast<Size>();
    try {
      _check(
        'create_inbound_session',
        _b.sessionInbound(
          accountHandle,
          identity,
          message,
          prekeyMessage.length,
          session,
          plainPointer,
          plainLength,
        ),
      );
      final plaintext = _takeBytes(_b, plainPointer.value, plainLength.value);
      return OlmInbound(
        session: _FfiSession(_b, session.value),
        plaintext: plaintext,
      );
    } finally {
      _free(identity.cast<Void>());
      _free(message.cast<Void>());
      _free(session.cast<Void>());
      _free(plainPointer.cast<Void>());
      _free(plainLength.cast<Void>());
    }
  }

  @override
  OlmSession restoreSession(Uint8List pickle, Uint8List key) {
    final handle = _restore(
      _b.sessionFromPickle,
      'session_from_pickle',
      pickle,
      key,
    );
    return _FfiSession(_b, handle);
  }

  @override
  bool verifySignature({
    required Uint8List ed25519Key,
    required Uint8List message,
    required Uint8List signature,
  }) {
    if (ed25519Key.length != _keyLength ||
        signature.length != _signatureLength) {
      return false;
    }
    final key = _copyIn(ed25519Key);
    final data = _copyIn(message);
    final sig = _copyIn(signature);
    try {
      final code = _b.verifySignature(key, data, message.length, sig);
      if (code == _ok) {
        return true;
      }
      if (code == _errSignature) {
        return false;
      }
      throw OlmEngineException('verify_signature', code);
    } finally {
      _free(key.cast<Void>());
      _free(data.cast<Void>());
      _free(sig.cast<Void>());
    }
  }

  Pointer<Void> _restore(
    _FromPickle fn,
    String operation,
    Uint8List pickle,
    Uint8List key,
  ) {
    _requireLength(key, 'pickle key');
    final data = _copyIn(pickle);
    final keyPointer = _copyIn(key);
    final out = _malloc(sizeOf<Pointer<Void>>()).cast<Pointer<Void>>();
    try {
      _check(operation, fn(data, pickle.length, keyPointer, out));
      return out.value;
    } finally {
      _free(data.cast<Void>());
      _free(keyPointer.cast<Void>());
      _free(out.cast<Void>());
    }
  }
}

class _FfiAccount implements OlmAccount {
  _FfiAccount(this._b, this._handle);

  final _Bindings _b;
  final Pointer<Void> _handle;
  bool _disposed = false;

  @override
  Uint8List get curve25519Key =>
      _readKey(_b.accountCurve25519Key, _handle, 'curve25519_key');

  @override
  Uint8List get ed25519Key =>
      _readKey(_b.accountEd25519Key, _handle, 'ed25519_key');

  @override
  void generateOneTimeKeys(int count) {
    _check(
      'generate_one_time_keys',
      _b.generateOneTimeKeys(_handle, count),
    );
  }

  @override
  List<Uint8List> unpublishedOneTimeKeys() {
    final buffer = _malloc(_oneTimeKeyCapacity * _keyLength).cast<Uint8>();
    final count = _malloc(sizeOf<Size>()).cast<Size>();
    try {
      // The capacity counts keys, not bytes: the buffer holds
      // _oneTimeKeyCapacity keys of _keyLength bytes each.
      _check(
        'one_time_keys',
        _b.oneTimeKeys(_handle, buffer, _oneTimeKeyCapacity, count),
      );
      final keys = count.value;
      final all = buffer.asTypedList(keys * _keyLength);
      return [
        for (var i = 0; i < keys; i++)
          Uint8List.fromList(
            all.sublist(i * _keyLength, (i + 1) * _keyLength),
          ),
      ];
    } finally {
      _free(buffer.cast<Void>());
      _free(count.cast<Void>());
    }
  }

  @override
  void markKeysPublished() {
    _check('mark_keys_published', _b.markKeysPublished(_handle));
  }

  @override
  Uint8List? unpublishedFallbackKey() {
    final out = _malloc(_keyLength).cast<Uint8>();
    final present = _malloc(sizeOf<Size>()).cast<Size>();
    try {
      _check('fallback_key', _b.fallbackKey(_handle, out, present));
      if (present.value == 0) {
        return null;
      }
      return Uint8List.fromList(out.asTypedList(_keyLength));
    } finally {
      _free(out.cast<Void>());
      _free(present.cast<Void>());
    }
  }

  @override
  void generateFallbackKey() {
    _check('generate_fallback_key', _b.generateFallbackKey(_handle));
  }

  @override
  Uint8List sign(Uint8List message) {
    final input = _copyIn(message);
    final out = _malloc(_signatureLength).cast<Uint8>();
    try {
      _check('sign', _b.accountSign(_handle, input, message.length, out));
      return Uint8List.fromList(out.asTypedList(_signatureLength));
    } finally {
      _free(input.cast<Void>());
      _free(out.cast<Void>());
    }
  }

  @override
  Uint8List pickle(Uint8List key) {
    return _pickle(_b, _b.accountPickle, _handle, key, 'account_pickle');
  }

  @override
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      _b.accountFree(_handle);
    }
  }
}

class _FfiSession implements OlmSession {
  _FfiSession(this._b, this._handle);

  final _Bindings _b;
  final Pointer<Void> _handle;
  bool _disposed = false;

  @override
  String get id {
    final out = _malloc(sizeOf<Pointer<Uint8>>()).cast<Pointer<Uint8>>();
    final length = _malloc(sizeOf<Size>()).cast<Size>();
    try {
      _check('session_id', _b.sessionId(_handle, out, length));
      return utf8.decode(_takeBytes(_b, out.value, length.value));
    } finally {
      _free(out.cast<Void>());
      _free(length.cast<Void>());
    }
  }

  @override
  OlmMessage encrypt(Uint8List plaintext) {
    final input = _copyIn(plaintext);
    final type = _malloc(sizeOf<Size>()).cast<Size>();
    final out = _malloc(sizeOf<Pointer<Uint8>>()).cast<Pointer<Uint8>>();
    final length = _malloc(sizeOf<Size>()).cast<Size>();
    try {
      _check(
        'encrypt',
        _b.sessionEncrypt(
          _handle,
          input,
          plaintext.length,
          type,
          out,
          length,
        ),
      );
      final messageType = type.value;
      return OlmMessage(
        messageType: messageType,
        bytes: _takeBytes(_b, out.value, length.value),
      );
    } finally {
      _free(input.cast<Void>());
      _free(type.cast<Void>());
      _free(out.cast<Void>());
      _free(length.cast<Void>());
    }
  }

  @override
  Uint8List decrypt(int messageType, Uint8List message) {
    final input = _copyIn(message);
    final out = _malloc(sizeOf<Pointer<Uint8>>()).cast<Pointer<Uint8>>();
    final length = _malloc(sizeOf<Size>()).cast<Size>();
    try {
      _check(
        'decrypt',
        _b.sessionDecrypt(
          _handle,
          messageType,
          input,
          message.length,
          out,
          length,
        ),
      );
      return _takeBytes(_b, out.value, length.value);
    } finally {
      _free(input.cast<Void>());
      _free(out.cast<Void>());
      _free(length.cast<Void>());
    }
  }

  @override
  Uint8List pickle(Uint8List key) {
    return _pickle(_b, _b.sessionPickle, _handle, key, 'session_pickle');
  }

  @override
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      _b.sessionFree(_handle);
    }
  }
}

Pointer<Void> _handleOf(OlmAccount account) {
  if (account is! _FfiAccount) {
    throw ArgumentError.value(account, 'account', 'not from this engine');
  }
  return account._handle;
}

Uint8List _readKey(_KeyOut fn, Pointer<Void> handle, String operation) {
  final out = _malloc(_keyLength).cast<Uint8>();
  try {
    _check(operation, fn(handle, out));
    return Uint8List.fromList(out.asTypedList(_keyLength));
  } finally {
    _free(out.cast<Void>());
  }
}

Uint8List _pickle(
  _Bindings b,
  _Pickle fn,
  Pointer<Void> handle,
  Uint8List key,
  String operation,
) {
  _requireLength(key, 'pickle key');
  final keyPointer = _copyIn(key);
  final out = _malloc(sizeOf<Pointer<Uint8>>()).cast<Pointer<Uint8>>();
  final length = _malloc(sizeOf<Size>()).cast<Size>();
  try {
    _check(operation, fn(handle, keyPointer, out, length));
    return _takeBytes(b, out.value, length.value);
  } finally {
    _free(keyPointer.cast<Void>());
    _free(out.cast<Void>());
    _free(length.cast<Void>());
  }
}

/// Copies [data] into a buffer from malloc. The caller frees it.
Pointer<Uint8> _copyIn(Uint8List data) {
  final pointer = _malloc(data.isEmpty ? 1 : data.length).cast<Uint8>();
  if (data.isNotEmpty) {
    pointer.asTypedList(data.length).setAll(0, data);
  }
  return pointer;
}

/// Copies a buffer the library returned, then releases it through the library.
Uint8List _takeBytes(_Bindings b, Pointer<Uint8> pointer, int length) {
  final copy = Uint8List.fromList(pointer.asTypedList(length));
  b.bytesFree(pointer, length);
  return copy;
}

void _check(String operation, int code) {
  if (code != _ok) {
    throw OlmEngineException(operation, code);
  }
}

void _requireLength(Uint8List value, String name) {
  if (value.length != _keyLength) {
    throw ArgumentError.value(value.length, name, 'must be 32 bytes');
  }
}
