import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';

import '../../../../core/utils/app_logger.dart';

/// A file on the media server, named by the client so its URL is known before
/// the upload returns.
class TourMediaRef {
  final String tourId;
  final String folder;
  final String filename;

  const TourMediaRef({
    required this.tourId,
    required this.folder,
    required this.filename,
  });

  /// The public URL the server returns for this file.
  String get url => '$publicBaseUrl/$tourId/$folder/$filename';

  static const String publicBaseUrl = 'https://bhromon.fun/media';

  /// The file a media-server URL points to, or null for any other URL.
  static TourMediaRef? tryParse(String url) {
    const prefix = '$publicBaseUrl/';
    if (!url.startsWith(prefix)) return null;
    final parts = url.substring(prefix.length).split('/');
    if (parts.length != 3 || parts.any((part) => part.isEmpty)) return null;
    return TourMediaRef(tourId: parts[0], folder: parts[1], filename: parts[2]);
  }
}

/// Why the journal is holding a file.
enum JournalKind {
  /// Uploaded (or uploading) and not yet saved in a post or story. If the app
  /// dies first, the file is removed once it is old and unreferenced.
  pending,

  /// Known to be unwanted. Removed as soon as the server confirms it is gone.
  delete,
}

class JournalEntry {
  final String url;
  final String tourId;
  final String folder;
  final String filename;
  final JournalKind kind;
  final DateTime since;

  const JournalEntry({
    required this.url,
    required this.tourId,
    required this.folder,
    required this.filename,
    required this.kind,
    required this.since,
  });

  factory JournalEntry.forRef(
      TourMediaRef ref, JournalKind kind, DateTime now) {
    return JournalEntry(
      url: ref.url,
      tourId: ref.tourId,
      folder: ref.folder,
      filename: ref.filename,
      kind: kind,
      since: now,
    );
  }

  JournalEntry asKind(JournalKind next) => JournalEntry(
        url: url,
        tourId: tourId,
        folder: folder,
        filename: filename,
        kind: next,
        since: since,
      );

  Map<String, dynamic> toMap() => {
        'url': url,
        'tourId': tourId,
        'folder': folder,
        'filename': filename,
        'kind': kind.name,
        'since': since.millisecondsSinceEpoch,
      };

  static JournalEntry? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final url = raw['url'];
    final tourId = raw['tourId'];
    final folder = raw['folder'];
    final filename = raw['filename'];
    final since = raw['since'];
    if (url is! String ||
        tourId is! String ||
        folder is! String ||
        filename is! String ||
        since is! int) {
      return null;
    }
    return JournalEntry(
      url: url,
      tourId: tourId,
      folder: folder,
      filename: filename,
      kind: raw['kind'] == JournalKind.delete.name
          ? JournalKind.delete
          : JournalKind.pending,
      since: DateTime.fromMillisecondsSinceEpoch(since),
    );
  }
}

/// What the sweep does with one entry.
enum SweepDecision { deleteFile, keep, drop }

/// A pending upload is left alone for this long, so an upload that is still
/// running is never mistaken for an orphan. Uploads may take up to 20 minutes.
const Duration kPendingGrace = Duration(minutes: 30);

/// Decides what to do with [entry]. [inFlight] is true for an upload this
/// session is still running. [referenced] is true when a post or story uses
/// the file, false when nothing does, and null when the check could not run.
SweepDecision planSweepEntry(
  JournalEntry entry, {
  required DateTime now,
  required bool inFlight,
  required bool? referenced,
}) {
  // Both kinds wait out the grace period: a file discarded while its upload was
  // still running may only appear on the server after the delete was sent.
  if (now.difference(entry.since) < kPendingGrace) return SweepDecision.keep;
  if (entry.kind == JournalKind.delete) return SweepDecision.deleteFile;
  if (inFlight) return SweepDecision.keep;
  if (referenced == null) return SweepDecision.keep;
  return referenced ? SweepDecision.drop : SweepDecision.deleteFile;
}

/// Where journal entries are kept between launches.
abstract class JournalStore {
  Future<List<Object?>> read();
  Future<void> write(List<Map<String, dynamic>> entries);
}

class HiveJournalStore implements JournalStore {
  static const String _boxName = 'media_journal';
  static const String _key = 'entries';

  Box<dynamic>? _box;

  Future<Box<dynamic>?> _open() async {
    if (_box != null) return _box;
    try {
      _box = await Hive.openBox<dynamic>(_boxName);
    } catch (e, st) {
      logWarning('[TourMediaJournal] could not open $_boxName', e, st);
    }
    return _box;
  }

  @override
  Future<List<Object?>> read() async {
    final box = await _open();
    final raw = box?.get(_key);
    return raw is List ? raw.cast<Object?>() : const [];
  }

  @override
  Future<void> write(List<Map<String, dynamic>> entries) async {
    final box = await _open();
    await box?.put(_key, entries);
  }
}

class MemoryJournalStore implements JournalStore {
  List<Map<String, dynamic>> saved = const [];

  @override
  Future<List<Object?>> read() async => List<Object?>.of(saved);

  @override
  Future<void> write(List<Map<String, dynamic>> entries) async {
    saved = List<Map<String, dynamic>>.of(entries);
  }
}

/// Tracks media files the app has put on the server and not yet settled, so
/// files left behind by a crash, a cancel or a failed save can be removed.
///
/// Every change runs one at a time, so two uploads recording at once cannot
/// overwrite each other's entries.
class TourMediaJournal {
  TourMediaJournal({
    required JournalStore store,
    DateTime Function()? clock,
  })  : _store = store,
        _clock = clock ?? DateTime.now;

  static final TourMediaJournal instance =
      TourMediaJournal(store: HiveJournalStore());

  /// For uploads the sweep cannot check, such as channel attachments. Entries
  /// live in memory only and are never swept; commit or discard settles them.
  static final TourMediaJournal untracked =
      TourMediaJournal(store: MemoryJournalStore());

  final JournalStore _store;
  final DateTime Function() _clock;

  Map<String, JournalEntry>? _entries;
  final Set<String> _inFlight = {};
  Future<void> _tail = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<Map<String, JournalEntry>> _load() async {
    final existing = _entries;
    if (existing != null) return existing;
    final loaded = <String, JournalEntry>{};
    try {
      for (final raw in await _store.read()) {
        final entry = JournalEntry.fromMap(raw);
        if (entry != null) loaded[entry.url] = entry;
      }
    } catch (e, st) {
      logWarning('[TourMediaJournal] could not read entries', e, st);
    }
    return _entries = loaded;
  }

  Future<void> _save() async {
    final entries = _entries ?? const {};
    try {
      await _store.write(entries.values.map((e) => e.toMap()).toList());
    } catch (e, st) {
      logWarning('[TourMediaJournal] could not save entries', e, st);
    }
  }

  /// Records an upload that is starting. Its file is protected from the sweep
  /// until [resolve] is called.
  Future<void> recordPending(TourMediaRef ref) {
    return _serial(() async {
      final entries = await _load();
      entries[ref.url] =
          JournalEntry.forRef(ref, JournalKind.pending, _clock());
      _inFlight.add(ref.url);
      await _save();
    });
  }

  /// Marks a file for deletion. It is removed by [sweep] if it cannot be
  /// removed right away.
  Future<void> markDelete(TourMediaRef ref) {
    return _serial(() async {
      final entries = await _load();
      // The grace period starts now, not when the upload began: the upload may
      // still be running when it is discarded.
      entries[ref.url] = JournalEntry.forRef(ref, JournalKind.delete, _clock());
      await _save();
    });
  }

  /// Forgets a file: it was saved in a post or story, or it is gone from the server.
  Future<void> resolve(String url) {
    return _serial(() async {
      final entries = await _load();
      _inFlight.remove(url);
      if (entries.remove(url) != null) await _save();
    });
  }

  /// Forgets every entry of [tourId]. Used once the user has left the tour: the
  /// server refuses deletes from a non-member, so nothing could be swept.
  Future<void> dropTour(String tourId) {
    return _serial(() async {
      final entries = await _load();
      final urls = [
        for (final entry in entries.values)
          if (entry.tourId == tourId) entry.url,
      ];
      if (urls.isEmpty) return;
      for (final url in urls) {
        entries.remove(url);
        _inFlight.remove(url);
      }
      await _save();
    });
  }

  int get pendingCount => _entries?.length ?? 0;

  /// Removes what the journal says should go, and leaves in place what is still
  /// in use or still uploading. [isReferenced] returns null when it cannot tell.
  /// [deleteRemote] returns true once the file is gone from the server.
  Future<void> sweep({
    required Future<bool?> Function(JournalEntry entry) isReferenced,
    required Future<bool> Function(String url) deleteRemote,
  }) {
    return _serial(() async {
      final entries = await _load();
      final now = _clock();
      for (final entry in entries.values.toList()) {
        final referenced = entry.kind == JournalKind.pending &&
                !_inFlight.contains(entry.url) &&
                now.difference(entry.since) >= kPendingGrace
            ? await isReferenced(entry)
            : null;
        // A removal decided by grace alone needs no reference check.
        final decision = planSweepEntry(
          entry,
          now: now,
          inFlight: _inFlight.contains(entry.url),
          referenced: referenced,
        );
        switch (decision) {
          case SweepDecision.keep:
            break;
          case SweepDecision.drop:
            entries.remove(entry.url);
            break;
          case SweepDecision.deleteFile:
            if (await deleteRemote(entry.url)) {
              entries.remove(entry.url);
            }
            break;
        }
      }
      await _save();
    });
  }
}
