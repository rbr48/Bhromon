import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/entities/trip_log.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../../../../core/security/hive_encryption_service.dart';
import '../../domain/repositories/i_feed_repository.dart';
import '../../../../core/value_objects/diary_visibility.dart';

@LazySingleton(as: IFeedRepository)
class FeedRepositoryImpl implements IFeedRepository {
  final FirebaseFirestore _firestore;
  final HiveEncryptionService _encryptionService;

  FeedRepositoryImpl(this._firestore, this._encryptionService);

  @override
  Future<Either<Failure, List<TripLog>>> getFeedItems(ExplorerProfile viewerProfile) async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      List<TripLog> logs = [];
      if (connectivity.isNotEmpty && connectivity.first == ConnectivityResult.none) {
        final cachedResult = await _getCachedFeed();
        logs = cachedResult.getOrElse(() => []);
      } else {
        final snapshots = await Future.wait([
          _firestore.collection('trip_logs').get(),
          _firestore.collection('archived_trip_logs').get(),
        ]);

        for (final snapshot in snapshots) {
          for (final doc in snapshot.docs) {
            try {
              final data = doc.data();
              data['tripId'] = doc.id;
              _sanitizeTripLogData(data);
              logs.add(TripLog.fromJson(data));
            } catch (e) {
              // Skip malformed document instead of crashing the entire feed
              // ignore: avoid_print
              print('[FeedRepo] Skipped malformed trip_log ${doc.id}: $e');
            }
          }
        }
      }

      // Filter out blocked users
      if (viewerProfile.uid.isNotEmpty && viewerProfile.uid != 'explorer_user') {
        try {
          final blockedSnap = await _firestore
              .collection('explorer_profiles')
              .doc(viewerProfile.uid)
              .collection('blocked_users')
              .get(const GetOptions(source: Source.serverAndCache));
          final blockedUids = blockedSnap.docs.map((doc) => doc.id).toSet();
          if (blockedUids.isNotEmpty) {
            logs.removeWhere((log) => blockedUids.contains(log.authorId));
          }
        } catch (_) {}
      }

      // Privacy-aware diary filtering (private/friends/community)
      final Set<String> followedUids = {};
      if (viewerProfile.uid.isNotEmpty && viewerProfile.uid != 'explorer_user') {
        try {
          final followingSnap = await _firestore
              .collection('follows')
              .where('followerId', isEqualTo: viewerProfile.uid)
              .get();
          followedUids.addAll(followingSnap.docs.map((doc) {
            final data = doc.data();
            return (data['followedId'] ?? '').toString();
          }).where((id) => id.isNotEmpty));
        } catch (_) {}
      }

      logs.removeWhere((log) {
        final vis = log.visibility;
        final authorId = log.authorId;

        // Private visibility: only the author can read
        if (vis == DiaryVisibility.private) {
          return authorId != viewerProfile.uid;
        }

        // Friends visibility: only the author and followers can read
        if (vis == DiaryVisibility.friends) {
          return authorId != viewerProfile.uid && !followedUids.contains(authorId);
        }

        // Community visibility is visible to everyone
        return false;
      });

      logs.sort((a, b) {
        final timeA = a.publishedAt ?? a.lastConfirmed;
        final timeB = b.publishedAt ?? b.lastConfirmed;
        return timeB.compareTo(timeA);
      });

      return Right(logs);
    } catch (e) {
      final cachedResult = await _getCachedFeed();
      return cachedResult;
    }
  }

  Future<Either<Failure, List<TripLog>>> _getCachedFeed() async {
    try {
      final box = await _encryptionService.openEncryptedBox<dynamic>('offline_bundles');
      final logs = <TripLog>[];
      for (final val in box.values) {
        final bundleJson = Map<String, dynamic>.from(val as Map);
        if (bundleJson['trips'] is List) {
          final tripsList = bundleJson['trips'] as List;
          for (final tripJson in tripsList) {
            final data = Map<String, dynamic>.from(tripJson as Map);
            _sanitizeTripLogData(data);
            logs.add(TripLog.fromJson(data));
          }
        }
      }
      // Sort offline logs by date just like online logs
      logs.sort((a, b) {
        final timeA = a.publishedAt ?? a.lastConfirmed;
        final timeB = b.publishedAt ?? b.lastConfirmed;
        return timeB.compareTo(timeA);
      });
      return Right(logs);
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
            // Fall back to the 'type' field used by legacy documents
            rawType = block['type'];
          }
          if (rawType == null || !validTypes.contains(rawType.toString())) {
            // Infer type from field presence
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
