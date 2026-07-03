import 'package:flutter/foundation.dart' show debugPrint;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/security/hive_encryption_service.dart';
import '../../../../core/entities/trip_log.dart';
import '../../../../core/entities/outbox_entry.dart';
import '../../../../core/utils/xp_utils.dart';
import '../../../offline_vault/data/datasources/sync_manager.dart';
import '../../domain/repositories/i_trip_log_repository.dart';

@LazySingleton(as: ITripLogRepository)
class TripLogRepositoryImpl implements ITripLogRepository {
  final FirebaseFirestore _firestore;
  final HiveEncryptionService _encryptionService;
  final SyncManager _syncManager;
  final String _draftBoxName = 'triplogs_drafts';

  TripLogRepositoryImpl(this._firestore, this._encryptionService, this._syncManager);

  @override
  Future<Either<Failure, List<TripLog>>> getTripLogsForPin(String pinId) async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.isNotEmpty && connectivity.first == ConnectivityResult.none) {
        return _getCachedTripLogsForPin(pinId);
      }

      final snapshots = await Future.wait([
        _firestore
            .collection('trip_logs')
            .where('locationPinId', isEqualTo: pinId)
            .where('hidden', isEqualTo: false)
            .get(),
        _firestore
            .collection('archived_trip_logs')
            .where('locationPinId', isEqualTo: pinId)
            .where('hidden', isEqualTo: false)
            .get(),
      ]);

      final logs = <TripLog>[];
      for (final snapshot in snapshots) {
        for (final doc in snapshot.docs) {
          try {
            final data = doc.data();
            data['tripId'] = doc.id;
            _sanitizeTripLogData(data);
            logs.add(TripLog.fromJson(data));
          } catch (e) {
            // ignore: avoid_print
            print('[TripLogRepo] Skipped malformed trip_log ${doc.id}: $e');
          }
        }
      }

      logs.sort((a, b) => b.trustScore.compareTo(a.trustScore));

      return Right(logs);
    } catch (e) {
      return _getCachedTripLogsForPin(pinId);
    }
  }

  Future<Either<Failure, List<TripLog>>> _getCachedTripLogsForPin(String pinId) async {
    try {
      final box = await _encryptionService.openEncryptedBox<dynamic>('offline_bundles');
      final logs = <TripLog>[];
      for (final val in box.values) {
        final bundleJson = Map<String, dynamic>.from(val as Map);
        if (bundleJson['trips'] is List) {
          final tripsList = bundleJson['trips'] as List;
          for (final tripJson in tripsList) {
            final data = Map<String, dynamic>.from(tripJson as Map);
            if (data['locationPinId'] == pinId && data['hidden'] != true) {
              _sanitizeTripLogData(data);
              logs.add(TripLog.fromJson(data));
            }
          }
        }
      }
      logs.sort((a, b) => b.trustScore.compareTo(a.trustScore));
      return Right(logs);
    } catch (cacheError) {
      return Left(CacheFailure(cacheError.toString()));
    }
  }

  @override
  Future<Either<Failure, TripLog>> publishTripLog(TripLog tripLog) async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      final isOffline = connectivity.isNotEmpty && connectivity.first == ConnectivityResult.none;

      final logData = tripLog.toJson();
      if (isOffline) {
        logData['lastConfirmed'] = {'_type': 'serverTimestamp'};
        final outboxEntry = OutboxEntry(
          id: 'sync_${DateTime.now().microsecondsSinceEpoch}',
          operation: 'create',
          collectionPath: 'trip_logs',
          documentId: tripLog.tripId,
          payload: logData,
          enqueuedAt: DateTime.now(),
          retryCount: 0,
          status: 'pending',
        );
        await _syncManager.enqueue(outboxEntry);
        
        final draftBox = await _encryptionService.openEncryptedBox<dynamic>(_draftBoxName);
        await draftBox.delete(tripLog.locationPinId);
        
        return Right(tripLog);
      }

      logData['lastConfirmed'] = FieldValue.serverTimestamp();
      await _firestore.collection('trip_logs').doc(tripLog.tripId).set(logData);

      final box = await _encryptionService.openEncryptedBox<dynamic>(_draftBoxName);
      await box.delete(tripLog.locationPinId);

      // Award 25 XP for posting a trip log
      await XpUtils.awardXp(tripLog.authorId, 25);

      return Right(tripLog);
    } catch (e) {
      debugPrint('[TripLogRepo] Direct publish failed: $e');
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> saveDraft(TripLog tripLog) async {
    try {
      final box = await _encryptionService.openEncryptedBox<dynamic>(_draftBoxName);
      await box.put(tripLog.locationPinId, tripLog.toJson());
      return const Right(unit);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, TripLog?>> getDraft(String pinId) async {
    try {
      final box = await _encryptionService.openEncryptedBox<dynamic>(_draftBoxName);
      final data = box.get(pinId);
      if (data != null) {
        final map = Map<String, dynamic>.from(data as Map);
        _sanitizeTripLogData(map);
        return Right(TripLog.fromJson(map));
      }
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, TripLog>> getById(String id) async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.isNotEmpty && connectivity.first == ConnectivityResult.none) {
        return _getCachedById(id);
      }

      var doc = await _firestore.collection('trip_logs').doc(id).get();
      if (!doc.exists) {
        doc = await _firestore.collection('archived_trip_logs').doc(id).get();
      }
      if (!doc.exists) {
        return Left(NotFoundFailure('Trip log not found', resourceId: id));
      }
      final data = doc.data()!;
      data['tripId'] = doc.id;
      _sanitizeTripLogData(data);
      return Right(TripLog.fromJson(data));
    } catch (e) {
      return _getCachedById(id);
    }
  }

  Future<Either<Failure, TripLog>> _getCachedById(String id) async {
    try {
      final box = await _encryptionService.openEncryptedBox<dynamic>('offline_bundles');
      for (final val in box.values) {
        final bundleJson = Map<String, dynamic>.from(val as Map);
        if (bundleJson['trips'] is List) {
          final tripsList = bundleJson['trips'] as List;
          for (final tripJson in tripsList) {
            final data = Map<String, dynamic>.from(tripJson as Map);
            if (data['tripId'] == id) {
              _sanitizeTripLogData(data);
              return Right(TripLog.fromJson(data));
            }
          }
        }
      }
      return Left(NotFoundFailure('Trip log not found offline', resourceId: id));
    } catch (cacheError) {
      return Left(CacheFailure(cacheError.toString()));
    }
  }

  void _sanitizeTripLogData(Map<String, dynamic> data) {
    data['tripId'] = data['tripId']?.toString() ?? 'unknown_trip';
    data['authorId'] = data['authorId']?.toString() ?? 'unknown_author';
    data['title'] = data['title']?.toString() ?? 'Untitled Trip';
    data['locationPinId'] = data['locationPinId']?.toString() ?? 'pin_sajek';
    data['division'] = data['division']?.toString() ?? 'Dhaka';
    data['district'] = data['district']?.toString() ?? 'Dhaka';

    if (data['blocks'] is List) {
      final List<dynamic> rawBlocks = data['blocks'] as List<dynamic>;
      final List<Map<String, dynamic>> sanitizedBlocks = [];
      for (final rawBlock in rawBlocks) {
        if (rawBlock is Map) {
          final block = Map<String, dynamic>.from(rawBlock);
          
          const validTypes = {'text', 'image', 'video', 'costEntry', 'route', 'safetyNote', 'voiceNote'};
          // Firestore docs may use 'type' instead of 'runtimeType' — normalise both
          dynamic rawType = block['runtimeType'];
          if (rawType == null || !validTypes.contains(rawType.toString())) {
            rawType = block['type'];
          }
          if (rawType == null || !validTypes.contains(rawType.toString())) {
            if (block['durationSeconds'] != null) {
              rawType = 'voiceNote';
            } else if (block['storageUrl'] != null || block['localPath'] != null) {
              final path = (block['storageUrl'] ?? block['localPath']).toString().toLowerCase();
              if (path.contains('.mp4') || path.contains('.mov') || path.contains('.avi') || path.contains('.mkv') || path.contains('video')) {
                rawType = 'video';
              } else {
                rawType = 'image';
              }
            } else if (block['items'] != null || block['currency'] != null) {
              rawType = 'costEntry';
            } else if (block['points'] != null) {
              rawType = 'route';
            } else if (block['text'] != null || block['level'] != null) {
              rawType = 'safetyNote';
            } else {
              rawType = 'text';
            }
          }
          block['runtimeType'] = rawType;
          
          block['id'] ??= 'blk_${DateTime.now().microsecondsSinceEpoch}';
          
          final type = block['runtimeType'];
          if (type == 'text') {
            block['content'] ??= '';
            block['isBold'] ??= false;
          } else if (type == 'image' || type == 'video') {
            block['storageUrl'] ??= '';
            block['caption'] ??= '';
          } else if (type == 'costEntry') {
            block['items'] ??= <dynamic>[];
            block['currency'] ??= 'BDT';
          } else if (type == 'route') {
            block['points'] ??= <dynamic>[];
            block['description'] ??= '';
          } else if (type == 'safetyNote') {
            block['text'] ??= '';
            block['level'] ??= 'warning';
          } else if (type == 'voiceNote') {
            block['storageUrl'] ??= '';
            block['durationSeconds'] ??= 0;
          }
          
          sanitizedBlocks.add(block);
        }
      }
      data['blocks'] = sanitizedBlocks;
    } else {
      data['blocks'] = <dynamic>[];
    }

    data['routePoints'] ??= <dynamic>[];
    data['costItems'] ??= <dynamic>[];

    data['trustScore'] = (data['trustScore'] as num?)?.toInt() ?? 50;
    data['helpfulVotes'] = (data['helpfulVotes'] as num?)?.toInt() ?? 0;

    if (data['lastConfirmed'] == null) {
      data['lastConfirmed'] = DateTime.now().toIso8601String();
    } else if (data['lastConfirmed'] is Timestamp) {
      data['lastConfirmed'] = (data['lastConfirmed'] as Timestamp).toDate().toIso8601String();
    } else if (data['lastConfirmed'] is! String) {
      data['lastConfirmed'] = DateTime.now().toIso8601String();
    }

    if (data['publishedAt'] is Timestamp) {
      data['publishedAt'] = (data['publishedAt'] as Timestamp).toDate().toIso8601String();
    }
  }
}
