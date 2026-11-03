import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:injectable/injectable.dart';

import '../utils/app_logger.dart';

/// Opens Hive boxes encrypted with a key kept in the platform keystore.
///
/// What it guarantees:
/// - It never encrypts with a key anyone can read. Earlier versions fell back to a
///   fixed key, compiled into the app, whenever secure storage failed. Without a key
///   now, boxes are kept in memory for the session and nothing is written to disk.
/// - A box is checked before it is opened: the device key must read it, or an older
///   key must, and then its entries move to the device key through a temporary copy,
///   so a crash can't lose them. A box the device key opened last time
///   (marked in `hive_key_marks`) opens directly.
/// - A box that no known key can read (a wrong key, a damaged file) is recreated
///   empty under the device key. Any other failure, such as a file that cannot be
///   read or a storage error, throws to the caller and leaves the file as it is.
@lazySingleton
class HiveEncryptionService {
  final FlutterSecureStorage _secureStorage;
  final String _keyName = 'hive_encryption_key';

  // On web, boxes live in IndexedDB, which cannot be copied, so they are probed
  // where they are (see _probe). Tests run that path on files through `webStorage`.
  final bool _webStorage;

  HiveEncryptionService()
      : _secureStorage = const FlutterSecureStorage(),
        _webStorage = kIsWeb;

  @visibleForTesting
  HiveEncryptionService.withStorage(this._secureStorage, {bool? webStorage})
      : _webStorage = webStorage ?? kIsWeb;

  /// The key older versions used when secure storage failed. Only ever used
  /// to read (and migrate away from) data written that way.
  static final HiveAesCipher _legacyFallbackCipher =
      HiveAesCipher(List<int>.generate(32, (i) => (i * 7 + 13) % 256));

  static const String _migrationSuffix = '__rekey';
  static const String _probeSuffix = '__probe';

  /// Unencrypted box mapping box name -> fingerprint of the key it was last
  /// opened with, so the probing happens once per box, not on every launch.
  static const String _keyMarksBox = 'hive_key_marks';

  // The key lives in the platform keystore; reading it is a platform-channel
  // round trip, so it's read once per process instead of on every box open.
  Future<_DeviceKey?>? _key;

  // In-flight and completed opens, so concurrent callers share one open.
  final Map<String, Future<Box<dynamic>>> _boxes = {};

  final Set<String> _inMemoryBoxes = {};

  int _probes = 0;

  String? _hiveHome;

  /// True once any box was kept in memory because there was no device key.
  @visibleForTesting
  bool get usedInMemoryFallback => _inMemoryBoxes.isNotEmpty;

  /// The app's encryption key, or null if secure storage can't provide one.
  Future<HiveAesCipher?> getCipher() async => (await _deviceKey())?.cipher;

  Future<_DeviceKey?> _deviceKey() => _key ??= _readKey();

  Future<_DeviceKey?> _readKey() async {
    String? base64Key;
    try {
      base64Key = await _secureStorage.read(key: _keyName);
    } catch (e, st) {
      // Can't tell whether a key exists. Generating one could orphan data
      // encrypted with the real key, so run without one this session.
      logWarning('[HiveEncryption] Secure storage read failed', e, st);
      return null;
    }
    if (base64Key != null) {
      try {
        return _DeviceKey(base64Decode(base64Key));
      } catch (e, st) {
        logWarning('[HiveEncryption] Stored key is unreadable', e, st);
        return null;
      }
    }
    // First run: create the key, and use it only once it's safely stored.
    final key = Hive.generateSecureKey();
    try {
      await _secureStorage.write(key: _keyName, value: base64Encode(key));
    } catch (e, st) {
      logWarning('[HiveEncryption] Could not store a new key', e, st);
      return null;
    }
    return _DeviceKey(key);
  }

  /// The boxes the app opens through this service.
  static const List<String> encryptedBoxNames = [
    'auth_box',
    'offline_bundles',
    'sync_outbox',
    'geofence_triggers',
    'saved_logs',
    'user_search_history',
    'user_preferences',
    'triplogs_drafts',
  ];

  /// Opens each box the app uses, so one that still depends on the old fixed key is
  /// re-encrypted at launch rather than whenever it is next used. A box that cannot
  /// be opened is logged and left as it is.
  Future<void> migrateEncryptedBoxes() async {
    for (final name in encryptedBoxNames) {
      try {
        await openEncryptedBox<dynamic>(name);
      } catch (error, stackTrace) {
        logWarning('[HiveEncryption] Could not check $name', error, stackTrace);
      }
    }
  }

  /// Opens an encrypted Hive box. A box no known key can read is recreated empty
  /// under the device key; any other failure throws and leaves the box on disk as it
  /// was. A box is never kept in memory for a lack of a readable key, because that
  /// would lose what it holds at the end of the session.
  Future<Box<T>> openEncryptedBox<T>(String boxName) async {
    final cached = _boxes[boxName];
    if (cached != null) {
      final box = await cached;
      if (box.isOpen) return box as Box<T>;
      _boxes.remove(boxName);
    }
    final opening = _open<T>(boxName);
    _boxes[boxName] = opening;
    try {
      return await opening;
    } catch (_) {
      _boxes.remove(boxName);
      rethrow;
    }
  }

  Future<Box<T>> _open<T>(String boxName) async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<T>(boxName);

    final key = await _deviceKey();
    if (key == null) return _openInMemory<T>(boxName);

    await _finishInterruptedMigration(boxName, key);
    if (_webStorage) return _openWeb<T>(boxName, key);

    final marks = await Hive.openBox<dynamic>(_keyMarksBox);
    await _resolveHome();
    final knownGood = marks.get(boxName) == key.fingerprint;
    if (knownGood || !await Hive.boxExists(boxName)) {
      // Opened with the device key directly: it was the last key that opened this
      // box, or there is no file yet.
      final box = await Hive.openBox<T>(boxName, encryptionCipher: key.cipher);
      await marks.put(boxName, key.fingerprint);
      return box;
    }

    // First open of an existing box since it was last marked: find out which key
    // reads it before opening it with one.
    final Box<T> box;
    if (await _probe(boxName, key.cipher) != null) {
      box = await Hive.openBox<T>(boxName, encryptionCipher: key.cipher);
    } else {
      box = await _moveOrRecreate<T>(boxName, key);
    }
    await marks.put(boxName, key.fingerprint);
    return box;
  }

  /// Opens a box on web. Web storage cannot be copied, so the box is probed where it
  /// is: a probe that fails writes nothing.
  Future<Box<T>> _openWeb<T>(String boxName, _DeviceKey key) async {
    final marks = await Hive.openBox<dynamic>(_keyMarksBox);
    final knownGood = marks.get(boxName) == key.fingerprint;
    Box<T>? box;
    if (knownGood) {
      // Opened with the device key last time, so it is opened directly. A failed
      // open falls through to the same checks as any other box.
      box = await _openIfReadable<T>(boxName, key.cipher);
    } else if (await _probe(boxName, key.cipher) != null) {
      box = await Hive.openBox<T>(boxName, encryptionCipher: key.cipher);
      // Text and numbers saved before encryption open with any key. Writing them
      // back encrypts them.
      await box.putAll(box.toMap().cast<dynamic, T>());
    }
    box ??= await _moveOrRecreate<T>(boxName, key);
    await marks.put(boxName, key.fingerprint);
    return box;
  }

  /// Opens [boxName] with [cipher] without reading it first. Null when [cipher]
  /// cannot read it; any other failure throws. The open runs in a zone of its own,
  /// for the same reason as [_readEntries].
  Future<Box<T>?> _openIfReadable<T>(String boxName, HiveCipher cipher) {
    final result = Completer<Box<T>?>();
    runZonedGuarded(() async {
      try {
        result.complete(await Hive.openBox<T>(boxName,
            encryptionCipher: cipher, crashRecovery: false));
      } catch (error, stackTrace) {
        if (result.isCompleted) return;
        if (_isDecodeFailure(error)) {
          result.complete(null);
        } else {
          result.completeError(error, stackTrace);
        }
      }
    }, (error, stackTrace) => logSkipped(error, stackTrace));
    return result.future;
  }

  /// The box is not readable with the device key. If an older key reads it, its
  /// entries move to the device key; if none does, no known key can read it and it
  /// is recreated empty.
  Future<Box<T>> _moveOrRecreate<T>(String boxName, _DeviceKey key) async {
    final older = await _readWithOlderKey(boxName);
    if (older != null) return _reencrypt<T>(boxName, key, older);
    return _recreate<T>(boxName, key);
  }

  /// The entries of [boxName] read with the fixed key that older versions used, or
  /// else with no key (the box was never encrypted). Null when neither reads it.
  Future<Map<dynamic, dynamic>?> _readWithOlderKey(String boxName) async =>
      await _probe(boxName, _legacyFallbackCipher) ??
      await _probe(boxName, null);

  /// Recreates a box that no known key can read: empty, under the device key. On web
  /// the old box is deleted first. On native, Hive's crash recovery empties it and
  /// keeps the valid frames of a partly damaged file.
  Future<Box<T>> _recreate<T>(String boxName, _DeviceKey key) async {
    logWarning(
        '[HiveEncryption] $boxName cannot be read with the device key or an '
        'older key; recreating it empty');
    if (_webStorage) await _deleteBox(boxName);
    return Hive.openBox<T>(boxName, encryptionCipher: key.cipher);
  }

  /// The entries of [boxName] if [cipher] reads it (null = no encryption), else
  /// null. A box with no file reads as empty.
  ///
  /// The whole box is read, so a value that does not decode counts as unreadable
  /// too. A failure that is not a decoding error (a file that cannot be read, a
  /// storage error) throws, and nothing is changed. Native reads a copy of the file,
  /// so a failed open leaves the real one alone.
  Future<Map<dynamic, dynamic>?> _probe(
      String boxName, HiveCipher? cipher) async {
    if (_webStorage) return _readEntries(boxName, cipher);
    await _resolveHome();
    final source = _sourceFile(boxName);
    if (source == null) return const {};
    final copyName = '$boxName$_probeSuffix${_probes++}';
    try {
      source.copySync(_fileFor(copyName).path);
      return await _readEntries(copyName, cipher);
    } finally {
      await _discardProbe(copyName);
    }
  }

  /// Opens [name] with [cipher] and reads every entry. The open runs in a zone of
  /// its own: a failed Hive open leaves an unawaited close and an unlistened error
  /// behind, and those must not reach the app's error reporting. The awaited result
  /// decides, so the zone only logs what it catches.
  Future<Map<dynamic, dynamic>?> _readEntries(String name, HiveCipher? cipher) {
    // An open box would be handed back as it is, and closed here: never probe one.
    assert(!Hive.isBoxOpen(name));
    final result = Completer<Map<dynamic, dynamic>?>();
    runZonedGuarded(() async {
      try {
        result.complete(await _readOpened(name, cipher));
      } catch (error, stackTrace) {
        if (result.isCompleted) return;
        if (_isDecodeFailure(error)) {
          result.complete(null);
        } else {
          result.completeError(error, stackTrace);
        }
      }
    }, (error, stackTrace) => logSkipped(error, stackTrace));
    return result.future;
  }

  /// Reads every entry of [name] with crash recovery off, so a damaged file fails
  /// the open instead of being truncated, and closes the box again.
  Future<Map<dynamic, dynamic>> _readOpened(
      String name, HiveCipher? cipher) async {
    final box = await Hive.openBox<dynamic>(name,
        encryptionCipher: cipher, crashRecovery: false);
    try {
      return box.toMap();
    } finally {
      await box.close();
    }
  }

  /// Whether [error] says the bytes do not decode with the key or format tried: a
  /// checksum or format error from Hive, a bad padding block, or a short read. Any
  /// other error is a failure to read, not a verdict on the key.
  bool _isDecodeFailure(Object error) =>
      error is HiveError || error is ArgumentError || error is FormatException;

  Future<void> _discardProbe(String copyName) async {
    try {
      await _deleteBox(copyName);
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
  }

  /// Deletes [name] from disk. A failed open is closed by Hive in the background,
  /// and that close deletes the box's lock file: a delete that runs in the same
  /// moment finds the file gone. The delete is then run again once that close has
  /// finished, which removes whatever is left.
  Future<void> _deleteBox(String name) async {
    var attempts = 0;
    while (true) {
      try {
        await Hive.deleteBoxFromDisk(name);
        return;
      } on PathNotFoundException {
        attempts++;
        if (attempts >= 3) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
  }

  /// The file Hive reads for [boxName]: the box file, or a compacted file that Hive
  /// renames into place when it opens. Null when neither exists. A folder in the way
  /// is a failure, not a missing file.
  File? _sourceFile(String boxName) {
    for (final extension in const ['.hive', '.hivec']) {
      final file = _fileFor(boxName, extension: extension);
      final type = FileSystemEntity.typeSync(file.path);
      if (type == FileSystemEntityType.notFound) continue;
      if (type == FileSystemEntityType.file) return file;
      throw FileSystemException(
          'Not a file, so the box cannot be read', file.path);
    }
    return null;
  }

  /// The file Hive uses for [name]. Hive lower-cases box names, and so does this.
  File _fileFor(String name, {String extension = '.hive'}) {
    final home = _hiveHome;
    if (home == null) {
      throw StateError('[HiveEncryption] Hive has no folder for $name yet');
    }
    return File('$home/${name.toLowerCase()}$extension');
  }

  /// Records where Hive keeps its files (`Hive.init` / `Hive.initFlutter`).
  Future<void> _resolveHome() async {
    if (_hiveHome != null) return;
    final marks = await Hive.openBox<dynamic>(_keyMarksBox);
    final path = marks.path;
    if (path != null) _hiveHome = File(path).parent.path;
  }

  Future<Box<T>> _reencrypt<T>(
      String boxName, _DeviceKey key, Map<dynamic, dynamic> entries) async {
    final temp = '$boxName$_migrationSuffix';
    // 1. A durable copy under the device key...
    final copy =
        await Hive.openBox<dynamic>(temp, encryptionCipher: key.cipher);
    await copy.clear();
    await copy.putAll(entries);
    await copy.close();
    // 2. ...then replace the original with it...
    await _deleteBox(boxName);
    final box = await Hive.openBox<T>(boxName, encryptionCipher: key.cipher);
    await box.putAll(entries.cast<dynamic, T>());
    // 3. ...and drop the copy.
    await _deleteBox(temp);
    logInfo('[HiveEncryption] Re-encrypted $boxName with the device key');
    return box;
  }

  /// Completes a re-encryption that was cut short. A copy the device key reads is
  /// restored over the original. A copy it cannot read was cut short before the
  /// original was replaced, so it is dropped. A copy that cannot be read for another
  /// reason throws, and nothing is changed.
  Future<void> _finishInterruptedMigration(
      String boxName, _DeviceKey key) async {
    final temp = '$boxName$_migrationSuffix';
    // On web, Hive.boxExists leaves a database connection open, and that connection
    // would block the deletes below. There, a missing copy reads as empty, and an
    // empty copy restores nothing.
    if (!_webStorage && !await Hive.boxExists(temp)) return;
    final entries = await _probe(temp, key.cipher);
    if (entries != null && entries.isNotEmpty) {
      await _deleteBox(boxName);
      final box =
          await Hive.openBox<dynamic>(boxName, encryptionCipher: key.cipher);
      await box.putAll(entries);
      await box.close();
      final marks = await Hive.openBox<dynamic>(_keyMarksBox);
      await marks.put(boxName, key.fingerprint);
    }
    await _deleteBox(temp);
  }

  /// A session-only box when there's no device key. Data readable with the old
  /// fixed key (or unencrypted) is loaded into it; the file isn't touched. A box
  /// nothing can read opens empty, and its file is still left as it was.
  Future<Box<T>> _openInMemory<T>(String boxName) async {
    logWarning(
        '[HiveEncryption] No device key; keeping $boxName in memory this session');
    if (kIsWeb) {
      // Without bytes, Hive keeps this box in IndexedDB as plain text.
      final box = await Hive.openBox<T>(boxName, bytes: Uint8List(0));
      _inMemoryBoxes.add(boxName);
      return box;
    }
    Map<dynamic, dynamic>? existing;
    if (await Hive.boxExists(boxName)) {
      existing = await _readWithOlderKey(boxName);
    }
    final box = await Hive.openBox<T>(boxName, bytes: Uint8List(0));
    if (existing != null) await box.putAll(existing.cast<dynamic, T>());
    _inMemoryBoxes.add(boxName);
    return box;
  }
}

class _DeviceKey {
  _DeviceKey(List<int> bytes)
      : cipher = HiveAesCipher(bytes),
        // Identifies the key in the (unencrypted) marks box without
        // revealing it.
        fingerprint = sha256
            .convert(utf8.encode('bhromon-hive-key:') + bytes)
            .toString()
            .substring(0, 16);

  final HiveAesCipher cipher;
  final String fingerprint;
}
