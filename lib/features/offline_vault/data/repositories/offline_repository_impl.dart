import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/entities/offline_bundle.dart';
import '../../../../core/entities/outbox_entry.dart';
import '../../../../core/entities/location_pin.dart';
import '../../../../core/entities/trip_log.dart';
import '../../../../core/entities/pro_tip.dart';
import '../../../../core/security/hive_encryption_service.dart';
import '../../../../core/services/offline_map_service.dart';
import '../../../../core/database/app_database.dart';
import '../datasources/sync_manager.dart';
import '../../domain/repositories/i_offline_repository.dart';
 
@LazySingleton(as: IOfflineRepository)
class OfflineRepositoryImpl implements IOfflineRepository {
  final HiveEncryptionService _encryptionService;
  final SyncManager _syncManager;
  final FirebaseFirestore _firestore;
  final AppDatabase _database;
  final String _bundleBoxName = 'offline_bundles';
  // ignore: unused_field
  final String _outboxBoxName = 'sync_outbox';
 
  OfflineRepositoryImpl(
    this._encryptionService,
    this._syncManager,
    this._firestore,
    this._database,
  );

  @override
  Future<Either<Failure, List<OfflineBundle>>> getDownloadedBundles() async {
    try {
      final box = await _encryptionService.openEncryptedBox<dynamic>(_bundleBoxName);
      final bundles = box.values.map((v) {
        return OfflineBundle.fromJson(Map<String, dynamic>.from(v as Map));
      }).toList();
      return Right(bundles);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> downloadBundle(String districtId) async {
    try {
      // 1. Download the offline map region (style + glyphs + sprites + tiles
      // into MapLibre's native cache). A map failure doesn't abort the bundle:
      // the pins/logs/tips below are still valuable offline.
      final mapDownloaded = await OfflineMapService.downloadRegion(districtId);
      if (!mapDownloaded) {
        // ignore: avoid_print
        print('[OfflineRepo] Map region download failed for $districtId; continuing with data bundle');
      }

      final box = await _encryptionService.openEncryptedBox<dynamic>(_bundleBoxName);
      
      // 2. Fetch Pins for this district or division from Firestore
      final pinsSnapshot = await _firestore
          .collection('location_pins')
          .where('district', isEqualTo: districtId)
          .get();
      var docs = pinsSnapshot.docs;
      if (docs.isEmpty) {
        final divSnapshot = await _firestore
            .collection('location_pins')
            .where('division', isEqualTo: districtId)
            .get();
        docs = divSnapshot.docs;
      }

      final pins = <LocationPin>[];
      final pinIds = <String>[];
      for (final doc in docs) {
        try {
          final data = doc.data();
          data['pinId'] = doc.id;
          if (data['lastConfirmed'] is Timestamp) {
            data['lastConfirmed'] = (data['lastConfirmed'] as Timestamp).toDate().toIso8601String();
          }
          pins.add(LocationPin.fromJson(data));
          pinIds.add(doc.id);
        } catch (e) {
          // ignore: avoid_print
          print('[OfflineRepo] Failed to parse location pin ${doc.id}: $e');
        }
      }

      // 2. Fetch Trip Logs for this district or division from Firestore
      final logsSnapshot = await _firestore
          .collection('trip_logs')
          .where('district', isEqualTo: districtId)
          .get();
      var logDocs = logsSnapshot.docs;
      if (logDocs.isEmpty) {
        final divLogsSnapshot = await _firestore
            .collection('trip_logs')
            .where('division', isEqualTo: districtId)
            .get();
        logDocs = divLogsSnapshot.docs;
      }

      final trips = <TripLog>[];
      for (final doc in logDocs) {
        try {
          final data = doc.data();
          data['tripId'] = doc.id;
          _sanitizeTripLogData(data);
          trips.add(TripLog.fromJson(data));
        } catch (e) {
          // ignore: avoid_print
          print('[OfflineRepo] Failed to parse trip log ${doc.id}: $e');
        }
      }

      // 3. Fetch ProTips linked to the pins from Firestore
      final tips = <ProTip>[];
      if (pinIds.isNotEmpty) {
        final tipsSnapshot = await _firestore.collection('pro_tips').get();
        for (final doc in tipsSnapshot.docs) {
          try {
            final data = doc.data();
            data['tipId'] = doc.id;
            if (data['lastConfirmed'] is Timestamp) {
              data['lastConfirmed'] = (data['lastConfirmed'] as Timestamp).toDate().toIso8601String();
            }
            final tip = ProTip.fromJson(data);
            if (pinIds.contains(tip.locationPinId)) {
              tips.add(tip);
            }
          } catch (e) {
            // ignore: avoid_print
            print('[OfflineRepo] Failed to parse pro tip ${doc.id}: $e');
          }
        }
      }

      // Calculate a dynamic size based on items (roughly, plus simulated tile data)
      final int size = 150 * 1024 + (pins.length * 15 * 1024) + (trips.length * 90 * 1024) + (tips.length * 8 * 1024);

      final bundle = OfflineBundle(
        districtId: districtId,
        districtName: districtId,
        pins: pins,
        trips: trips,
        tips: tips,
        tileKeys: pins.map((p) => 'tile_${p.pinId}').toList(),
        downloadedAt: DateTime.now(),
        sizeBytes: size,
      );

      // Pre-cache media assets associated with downloaded trip logs
      await _preCacheBundleMedia(trips);

      await box.put(districtId, bundle.toJson());
      return const Right(unit);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteBundle(String districtId) async {
    try {
      await OfflineMapService.deleteRegion(districtId);
      final box = await _encryptionService.openEncryptedBox<dynamic>(_bundleBoxName);
      await box.delete(districtId);
      return const Right(unit);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<OutboxEntry>>> getPendingOutboxEntries() async {
    try {
      final jsonStrings = await _database.getOutboxEntriesOrdered();
      final entries = jsonStrings.map((jsonStr) {
        return OutboxEntry.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
      }).toList();
      return Right(entries);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> syncOutbox() async {
    try {
      await _syncManager.flushOutbox();
      return const Right(unit);
    } catch (e) {
      return Left(NetworkFailure(e.toString()));
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
          dynamic rawType = block['runtimeType'] ?? block['type'];
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

  Future<void> _preCacheBundleMedia(List<TripLog> trips) async {
    try {
      final cacheManager = DefaultCacheManager();
      final List<String> imageUrls = [];

      for (final trip in trips) {
        for (final block in trip.blocks) {
          final String? storageUrl = block.mapOrNull(
            image: (img) => img.storageUrl,
            video: (vid) => vid.storageUrl,
          );
          if (storageUrl != null && storageUrl.isNotEmpty) {
            if (storageUrl.startsWith('http://') || storageUrl.startsWith('https://')) {
              imageUrls.add(storageUrl);
            }
          }
        }
      }

      if (imageUrls.isNotEmpty) {
        await Future.wait(
          imageUrls.map((url) async {
            try {
              await cacheManager.downloadFile(url);
            } catch (_) {}
          }),
        );
      }
    } catch (_) {}
  }
}
