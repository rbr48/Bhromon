import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Session cache of one-off document reads, keyed by path.
///
/// List rows that call `doc(id).get()` inside build() fire a billed read on
/// every rebuild and every time they scroll back into view. Rows that go
/// through this share one future per document until it goes stale.
class DocFutureCache {
  DocFutureCache({
    this.ttl = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static final DocFutureCache instance = DocFutureCache();

  final Duration ttl;
  final DateTime Function() _now;
  final Map<
      String,
      ({
        Future<DocumentSnapshot<Map<String, dynamic>>> future,
        DateTime at
      })> _entries = {};

  Future<DocumentSnapshot<Map<String, dynamic>>> get(
      DocumentReference<Map<String, dynamic>> ref) {
    final existing = _entries[ref.path];
    if (existing != null && _now().difference(existing.at) < ttl) {
      return existing.future;
    }
    final future = ref.get();
    _entries[ref.path] = (future: future, at: _now());
    // A failed read shouldn't be served from the cache.
    future.catchError((Object _) {
      _entries.remove(ref.path);
      return future;
    });
    return future;
  }

  @visibleForTesting
  void clear() => _entries.clear();
}
