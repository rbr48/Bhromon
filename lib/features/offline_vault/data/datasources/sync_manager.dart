import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/entities/outbox_entry.dart';
import '../../../../core/database/app_database.dart';

@lazySingleton
class SyncManager {
  bool _isProcessing = false;
  final StreamController<bool> _syncStatusController =
      StreamController<bool>.broadcast();

  Stream<bool> get syncStatusStream => _syncStatusController.stream;

  final AppDatabase _database;
  final FirebaseFirestore _firestore;

  SyncManager(this._database, this._firestore) {
    Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      if (results.isNotEmpty && results.first != ConnectivityResult.none) {
        flushOutbox();
      }
    });
  }

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

  Future<void> flushOutbox() async {
    if (_isProcessing) return;

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.isEmpty || connectivity.first == ConnectivityResult.none) {
      return;
    }

    _isProcessing = true;
    _syncStatusController.add(true);

    try {
      final jsonStrings = await _database.getOutboxEntriesOrdered();
      final originalItems = jsonStrings.map((jsonStr) {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        return OutboxEntry.fromJson(map);
      }).toList();

      final items = _compactOutbox(originalItems);

      // Clean up compacted items from DB immediately
      final compactedIds = items.map((item) => item.id).toSet();
      for (final original in originalItems) {
        if (!compactedIds.contains(original.id)) {
          await _database.deleteOutboxEntry(original.id);
        }
      }

      for (final item in items) {
        // Mark as processing in DB to prevent concurrent runs
        final processingItem = item.copyWith(status: 'processing');
        await _database.enqueueOutbox(
          item.id,
          item.enqueuedAt.millisecondsSinceEpoch,
          jsonEncode(processingItem.toJson()),
          status: 'processing',
        );

        try {
          await _processItem(item);
          await _database.deleteOutboxEntry(item.id);
        } catch (e) {
          // ignore: avoid_print
          print(
              '[SyncManager] Sync failed for item ${item.id} (${item.operation} -> ${item.collectionPath}/${item.documentId}): $e');

          if (_isPermanentError(e)) {
            // Isolate permanent errors immediately to conflict table
            final conflictItem = item.copyWith(
              status: 'conflict',
              serverConflictPayload: {
                'error': e.toString(),
                'type': 'permanent_error'
              },
            );
            await _database.saveConflict(
              item.id,
              item.enqueuedAt.millisecondsSinceEpoch,
              jsonEncode(conflictItem.toJson()),
            );
            await _database.deleteOutboxEntry(item.id);
          } else {
            // Transient error: retry up to 5 times
            if (item.retryCount >= 5) {
              final conflictItem = item.copyWith(status: 'conflict');
              await _database.saveConflict(
                item.id,
                item.enqueuedAt.millisecondsSinceEpoch,
                jsonEncode(conflictItem.toJson()),
              );
              await _database.deleteOutboxEntry(item.id);
            } else {
              final updatedItem = item.copyWith(
                retryCount: item.retryCount + 1,
                status: 'failed',
              );
              final jsonStr = jsonEncode(updatedItem.toJson());
              await _database.enqueueOutbox(
                item.id,
                item.enqueuedAt.millisecondsSinceEpoch,
                jsonStr,
                status: 'failed',
              );

              final backoffMs = _calculateBackoff(updatedItem.retryCount);
              await Future<void>.delayed(Duration(milliseconds: backoffMs));
              break; // Stop processing further entries since this one failed
            }
          }
        }
      }
    } catch (_) {}

    _isProcessing = false;
    _syncStatusController.add(false);
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
