import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/entities/outbox_entry.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/network/connectivity_check.dart';

/// Firestore commits at most 500 writes per batch.
const int kOutboxBatchSize = 500;

/// Attempts per entry before it is moved to the conflict table.
const int kOutboxMaxRetries = 5;

/// A claimed entry older than this is assumed abandoned and sent again.
const Duration kStaleClaimAge = Duration(minutes: 10);

@lazySingleton
class SyncManager {
  bool _isProcessing = false;
  final StreamController<bool> _syncStatusController =
      StreamController<bool>.broadcast();

  Stream<bool> get syncStatusStream => _syncStatusController.stream;

  final AppDatabase _database;
  final FirebaseFirestore _firestore;
  final OnlineCheck _isOnline;
  final DateTime Function() _now;

  /// Entries waiting out a retry backoff: id -> earliest next attempt.
  /// Kept in memory; a fresh process simply retries once straight away.
  final Map<String, DateTime> _notBefore = {};
  Timer? _retryTimer;

  SyncManager(this._database, this._firestore)
      : _isOnline = deviceIsOnline,
        _now = DateTime.now {
    Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      if (results.isNotEmpty && results.first != ConnectivityResult.none) {
        flushOutbox();
      }
    });
  }

  @visibleForTesting
  SyncManager.withDependencies(
    this._database,
    this._firestore, {
    required OnlineCheck isOnline,
    DateTime Function()? now,
  })  : _isOnline = isOnline,
        _now = now ?? DateTime.now;

  /// Backoff before retry [retryCount] (1-based). For tests.
  @visibleForTesting
  int backoffFor(int retryCount) => _calculateBackoff(retryCount);

  int _calculateBackoff(int retryCount) {
    final double exp = pow(2, retryCount).toDouble();
    // Jitter between 75% and 125%
    final double jitter = Random().nextDouble() * 0.5 + 0.75;
    return (exp * 1000 * jitter).toInt(); // returns milliseconds
  }

  Future<void> enqueue(OutboxEntry item) async {
    final jsonStr = jsonEncode(item.toJson());
    await _database.enqueueOutbox(
        item.id, item.enqueuedAt.millisecondsSinceEpoch, jsonStr,
        status: 'pending');
    flushOutbox();
  }

  List<OutboxEntry> _compactOutbox(List<OutboxEntry> entries) {
    if (entries.isEmpty) return entries;

    // Group entries by document reference: "collectionPath/documentId"
    final Map<String, List<OutboxEntry>> grouped = {};
    for (final entry in entries) {
      final key = '${entry.collectionPath}/${entry.documentId}';
      grouped.putIfAbsent(key, () => []).add(entry);
    }

    final List<OutboxEntry> compacted = [];

    for (final group in grouped.values) {
      if (group.isEmpty) continue;

      if (group.length == 1) {
        compacted.add(group.first);
        continue;
      }

      // Sort by enqueuedAt to maintain order of edits
      group.sort((a, b) => a.enqueuedAt.compareTo(b.enqueuedAt));

      final firstOp = group.first.operation;
      final lastEntry = group.last;

      if (lastEntry.operation == 'delete') {
        if (firstOp == 'create') {
          // Created and deleted offline, discard entirely
          continue;
        } else {
          // Keep only the delete operation
          compacted.add(lastEntry);
        }
      } else if (firstOp == 'create') {
        // Merge all payloads in order into the first create payload
        final mergedPayload = <String, dynamic>{};
        for (final entry in group) {
          mergedPayload.addAll(entry.payload);
        }
        compacted.add(group.first.copyWith(payload: mergedPayload));
      } else {
        // Merge all update payloads in order
        final mergedPayload = <String, dynamic>{};
        for (final entry in group) {
          mergedPayload.addAll(entry.payload);
        }
        compacted.add(lastEntry.copyWith(payload: mergedPayload));
      }
    }

    compacted.sort((a, b) => a.enqueuedAt.compareTo(b.enqueuedAt));
    return compacted;
  }

  bool _isPermanentError(Object exception) {
    if (exception is FirebaseException) {
      switch (exception.code) {
        case 'permission-denied':
        case 'invalid-argument':
        case 'already-exists':
        case 'not-found':
        case 'failed-precondition':
        case 'out-of-range':
        case 'unimplemented':
        case 'data-loss':
          return true;
        default:
          return false;
      }
    }
    if (exception is SocketException || exception is TimeoutException) {
      return false;
    }
    return false; // Treat other/unknown exceptions as retryable
  }

  /// Sends every pending entry to Firestore.
  ///
  /// Entries go out in WriteBatches of up to [kOutboxBatchSize] (one round
  /// trip per batch instead of per entry). If a batch is rejected, its
  /// entries are retried one by one so a single bad entry can't hold back
  /// the rest. A failed entry backs off on its own; later entries still go
  /// out, and the retry is scheduled instead of awaited here.
  Future<void> flushOutbox() async {
    if (_isProcessing) return;
    if (!await _isOnline()) return;

    _isProcessing = true;
    _syncStatusController.add(true);

    try {
      // Claims older than this belong to a flush that never finished.
      await _database.releaseStaleOutboxClaims(
          _now().subtract(kStaleClaimAge).millisecondsSinceEpoch);

      final jsonStrings = await _database.getOutboxEntriesOrdered();
      final originalItems = jsonStrings.map((jsonStr) {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        return OutboxEntry.fromJson(map);
      }).toList();

      final compacted = _compactOutbox(originalItems);
      final now = _now();
      final due = compacted.where((item) {
        final notBefore = _notBefore[item.id];
        return notBefore == null || !notBefore.isAfter(now);
      }).toList();

      // One transaction: drop entries folded into others and store merged
      // payloads, so a crash mid-flush loses nothing.
      final keptIds = compacted.map((item) => item.id).toSet();
      final originalsById = {for (final o in originalItems) o.id: o};
      await _database.applyOutboxChanges(
        deleteIds: [
          for (final o in originalItems)
            if (!keptIds.contains(o.id)) o.id,
        ],
        upserts: [
          for (final item in compacted)
            if (!identical(item, originalsById[item.id]))
              _row(item.copyWith(status: 'pending'), 'pending'),
        ],
      );

      for (var i = 0; i < due.length; i += kOutboxBatchSize) {
        final chunk = due.sublist(
            i,
            i + kOutboxBatchSize > due.length
                ? due.length
                : i + kOutboxBatchSize);
        await _sendChunk(chunk);
      }
    } catch (e, st) {
      logError('[SyncManager] Flush failed', e, st);
    }

    _isProcessing = false;
    _syncStatusController.add(false);
    _scheduleRetry();
  }

  SyncOutboxTableCompanion _row(OutboxEntry item, String status) =>
      SyncOutboxTableCompanion(
        id: Value(item.id),
        enqueuedAt: Value(item.enqueuedAt.millisecondsSinceEpoch),
        status: Value(status),
        processingSince: const Value(null),
        jsonData: Value(jsonEncode(item.toJson())),
      );

  Future<void> _sendChunk(List<OutboxEntry> chunk) async {
    // Claim just this chunk, right before sending it, so another isolate
    // doesn't send it too and a crash strands as little as possible.
    await _database.applyOutboxChanges(
      statusIds: [for (final item in chunk) item.id],
      status: 'processing',
    );
    try {
      final batch = _firestore.batch();
      for (final item in chunk) {
        _addToBatch(batch, item);
      }
      await batch.commit();
      await _database
          .applyOutboxChanges(deleteIds: [for (final item in chunk) item.id]);
      for (final item in chunk) {
        _notBefore.remove(item.id);
      }
      return;
    } catch (e) {
      if (chunk.length == 1) {
        await _handleFailure(chunk.single, e);
        return;
      }
      logWarning(
          '[SyncManager] Batch of ${chunk.length} rejected ($e); retrying entries individually');
    }

    final sent = <String>[];
    for (final item in chunk) {
      try {
        await _processItem(item);
        sent.add(item.id);
        _notBefore.remove(item.id);
      } catch (e) {
        await _handleFailure(item, e);
      }
    }
    await _database.applyOutboxChanges(deleteIds: sent);
  }

  Future<void> _handleFailure(OutboxEntry item, Object error) async {
    logWarning(
        '[SyncManager] Sync failed for item ${item.id} (${item.operation} -> ${item.collectionPath}/${item.documentId})',
        error);

    final permanent = _isPermanentError(error);
    if (permanent || item.retryCount >= kOutboxMaxRetries) {
      final conflictItem = item.copyWith(
        status: 'conflict',
        serverConflictPayload: permanent
            ? {'error': error.toString(), 'type': 'permanent_error'}
            : item.serverConflictPayload,
      );
      await _database.saveConflict(
        item.id,
        item.enqueuedAt.millisecondsSinceEpoch,
        jsonEncode(conflictItem.toJson()),
      );
      await _database.deleteOutboxEntry(item.id);
      _notBefore.remove(item.id);
      return;
    }

    final updated = item.copyWith(
      retryCount: item.retryCount + 1,
      status: 'failed',
    );
    await _database.applyOutboxChanges(upserts: [_row(updated, 'failed')]);
    _notBefore[item.id] = _now()
        .add(Duration(milliseconds: _calculateBackoff(updated.retryCount)));
  }

  /// Flushes again when the earliest backed-off entry becomes due.
  void _scheduleRetry() {
    _retryTimer?.cancel();
    if (_notBefore.isEmpty) return;
    final earliest = _notBefore.values.reduce((a, b) => a.isBefore(b) ? a : b);
    final wait = earliest.difference(_now());
    _retryTimer =
        Timer(wait.isNegative ? Duration.zero : wait, () => flushOutbox());
  }

  void _addToBatch(WriteBatch batch, OutboxEntry item) {
    final ref = _firestore.collection(item.collectionPath).doc(item.documentId);
    final payload = _processPayload(item.payload);
    switch (item.operation) {
      case 'delete':
        batch.delete(ref);
      case 'create':
        batch.set(ref, payload);
      case 'update':
        batch.update(ref, payload);
      default:
        batch.set(ref, payload, SetOptions(merge: true));
    }
  }

  /// Whether a retry flush is scheduled. For tests.
  @visibleForTesting
  bool get hasScheduledRetry => _retryTimer?.isActive ?? false;

  @visibleForTesting
  void dispose() {
    _retryTimer?.cancel();
  }

  Future<void> _processItem(OutboxEntry item) async {
    final processedPayload = _processPayload(item.payload);

    if (item.operation == 'delete') {
      await _firestore
          .collection(item.collectionPath)
          .doc(item.documentId)
          .delete();
    } else if (item.operation == 'create') {
      await _firestore
          .collection(item.collectionPath)
          .doc(item.documentId)
          .set(processedPayload);
    } else if (item.operation == 'update') {
      await _firestore
          .collection(item.collectionPath)
          .doc(item.documentId)
          .update(processedPayload);
    } else {
      await _firestore.collection(item.collectionPath).doc(item.documentId).set(
            processedPayload,
            SetOptions(merge: true),
          );
    }
  }

  dynamic _processPayloadValue(dynamic value) {
    if (value is Map) {
      if (value['_type'] == 'increment') {
        return FieldValue.increment(value['value'] as num);
      } else if (value['_type'] == 'serverTimestamp') {
        return FieldValue.serverTimestamp();
      } else {
        return value
            .map((k, v) => MapEntry(k.toString(), _processPayloadValue(v)));
      }
    } else if (value is List) {
      return value.map(_processPayloadValue).toList();
    }
    return value;
  }

  Map<String, dynamic> _processPayload(Map<String, dynamic> payload) {
    return payload.map((k, v) => MapEntry(k, _processPayloadValue(v)));
  }
}
