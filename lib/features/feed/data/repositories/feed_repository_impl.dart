import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/entities/trip_log.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../../../../core/network/connectivity_check.dart';
import '../../../../core/security/hive_encryption_service.dart';
import '../../domain/repositories/i_feed_repository.dart';
import '../../../../core/value_objects/diary_visibility.dart';

/// Firestore caps `whereIn` at 30 values.
const int _kWhereInLimit = 30;

@LazySingleton(as: IFeedRepository)
class FeedRepositoryImpl implements IFeedRepository {
  final FirebaseFirestore _firestore;
  final HiveEncryptionService _encryptionService;
  final OnlineCheck _isOnline;

  FeedRepositoryImpl(this._firestore, this._encryptionService)
      : _isOnline = deviceIsOnline;

  @visibleForTesting
  FeedRepositoryImpl.withOnlineCheck(
      this._firestore, this._encryptionService, this._isOnline);

  static bool _isGuest(ExplorerProfile viewer) =>
      viewer.uid.isEmpty ||
      viewer.uid == 'explorer_user' ||
      viewer.uid == 'guest';

  @override
  Future<FeedViewerContext> loadViewerContext(
      ExplorerProfile viewerProfile) async {
    if (_isGuest(viewerProfile)) return FeedViewerContext.empty;

    Future<Set<String>> blocked() async {
      try {
        final snap = await _firestore
            .collection('explorer_profiles')
            .doc(viewerProfile.uid)
            .collection('blocked_users')
            .get(const GetOptions(source: Source.serverAndCache));
        return snap.docs.map((doc) => doc.id).toSet();
      } catch (_) {
        return <String>{};
      }
    }

    Future<Set<String>> followed() async {
      try {
        final snap = await _firestore
            .collection('follows')
            .where('followerId', isEqualTo: viewerProfile.uid)
            .get(const GetOptions(source: Source.serverAndCache));
        return snap.docs
            .map((doc) => (doc.data()['followedId'] ?? '').toString())
            .where((id) => id.isNotEmpty)
            .toSet();
      } catch (_) {
        return <String>{};
      }
    }

    final results = await Future.wait([blocked(), followed()]);
    return FeedViewerContext(
      blockedUids: results[0],
      followedUids: results[1],
    );
  }

  @override
  Future<Either<Failure, FeedPage>> getFeedPage(
    ExplorerProfile viewerProfile,
    FeedViewerContext viewerContext, {
    int pageSize = kFeedPageSize,
    FeedCursor? after,
  }) =>
      _getPage('trip_logs', viewerProfile, viewerContext,
          pageSize: pageSize, after: after, cacheFallback: true);

  @override
  Future<Either<Failure, FeedPage>> getArchivedPage(
    ExplorerProfile viewerProfile,
    FeedViewerContext viewerContext, {
    int pageSize = kFeedPageSize,
    FeedCursor? after,
  }) =>
      _getPage('archived_trip_logs', viewerProfile, viewerContext,
          pageSize: pageSize, after: after, cacheFallback: false);

  Future<Either<Failure, FeedPage>> _getPage(
    String collection,
    ExplorerProfile viewerProfile,
    FeedViewerContext viewerContext, {
    required int pageSize,
    required FeedCursor? after,
    required bool cacheFallback,
  }) async {
    Future<Either<Failure, FeedPage>> fromCache() async {
      // Offline bundles hold every downloaded trip, live and archived alike,
      // so only the first page of the live feed serves them.
      if (!cacheFallback || after != null) {
        return const Right(FeedPage(logs: []));
      }
      final cached = await _getCachedFeed();
      return cached.map((logs) => FeedPage(
          logs: _applyViewerFilters(logs, viewerProfile, viewerContext)));
    }

    try {
      if (!await _isOnline()) return await fromCache();

      Query<Map<String, dynamic>> query = _firestore
          .collection(collection)
          .orderBy('lastConfirmed', descending: true)
          .limit(pageSize);
      final cursor = after?.token;
      if (cursor is DocumentSnapshot) {
        query = query.startAfterDocument(cursor);
      }
      final snapshot = await query.get();

      final logs = _parseDocs(snapshot.docs);
      _sortNewestFirst(logs);
      return Right(FeedPage(
        logs: _applyViewerFilters(logs, viewerProfile, viewerContext),
        next: snapshot.docs.length == pageSize
            ? FeedCursor(snapshot.docs.last)
            : null,
      ));
    } catch (e) {
      if (after == null && cacheFallback) return fromCache();
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<TripLog>>> getTripLogsByIds(
    ExplorerProfile viewerProfile,
    FeedViewerContext viewerContext,
    List<String> tripIds,
  ) async {
    final wanted = tripIds.toSet().toList();
    if (wanted.isEmpty) return const Right([]);

    try {
      final List<TripLog> found;
      if (!await _isOnline()) {
        final cached = await _getCachedFeed();
        found = cached
            .getOrElse(() => [])
            .where((log) => wanted.contains(log.tripId))
            .toList();
      } else {
        found = await _fetchByIds('trip_logs', wanted);
        final missing = wanted
            .toSet()
            .difference(found.map((l) => l.tripId).toSet())
            .toList();
        if (missing.isNotEmpty) {
          found.addAll(await _fetchByIds('archived_trip_logs', missing));
        }
      }

      // Keep the caller's order (the order the logs were saved in).
      final byId = {for (final log in found) log.tripId: log};
      final ordered = [
        for (final id in wanted)
          if (byId[id] != null) byId[id]!,
      ];
      return Right(_applyViewerFilters(ordered, viewerProfile, viewerContext));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<List<TripLog>> _fetchByIds(String collection, List<String> ids) async {
    final chunks = <List<String>>[
      for (var i = 0; i < ids.length; i += _kWhereInLimit)
        ids.sublist(i, (i + _kWhereInLimit).clamp(0, ids.length)),
    ];
    final snapshots = await Future.wait(chunks.map((chunk) => _firestore
        .collection(collection)
        .where(FieldPath.documentId, whereIn: chunk)
        .get()));
    return [for (final snap in snapshots) ..._parseDocs(snap.docs)];
  }

  List<TripLog> _parseDocs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final logs = <TripLog>[];
    for (final doc in docs) {
      try {
        final data = Map<String, dynamic>.from(doc.data());
        data['tripId'] = doc.id;
        _sanitizeTripLogData(data);
        logs.add(TripLog.fromJson(data));
      } catch (e) {
        // Skip a malformed document instead of failing the whole page.
        debugPrint('[FeedRepo] Skipped malformed trip_log ${doc.id}: $e');
      }
    }
    return logs;
  }

  static void _sortNewestFirst(List<TripLog> logs) {
    logs.sort((a, b) {
      final timeA = a.publishedAt ?? a.lastConfirmed;
      final timeB = b.publishedAt ?? b.lastConfirmed;
      return timeB.compareTo(timeA);
    });
  }

  /// Drops blocked authors and diaries the viewer may not read.
  List<TripLog> _applyViewerFilters(
    List<TripLog> logs,
    ExplorerProfile viewerProfile,
    FeedViewerContext viewerContext,
  ) {
    return logs.where((log) {
      final authorId = log.authorId;
      if (viewerContext.blockedUids.contains(authorId)) return false;

      switch (log.visibility) {
        case DiaryVisibility.private:
          // Only the author can read a private diary.
          return authorId == viewerProfile.uid;
        case DiaryVisibility.friends:
          // Only the author and their followers can read it.
          return authorId == viewerProfile.uid ||
              viewerContext.followedUids.contains(authorId);
        case DiaryVisibility.community:
          return true;
      }
    }).toList();
  }

  Future<Either<Failure, List<TripLog>>> _getCachedFeed() async {
    try {
      final box =
          await _encryptionService.openEncryptedBox<dynamic>('offline_bundles');
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
      _sortNewestFirst(logs);
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

          const validTypes = {
            'text',
            'image',
            'video',
            'costEntry',
            'route',
            'safetyNote',
            'voiceNote'
          };
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
            } else if (block['storageUrl'] != null ||
                block['localPath'] != null) {
              final path = (block['storageUrl'] ?? block['localPath'])
                  .toString()
                  .toLowerCase();
              if (path.contains('.mp4') ||
                  path.contains('.mov') ||
                  path.contains('.avi') ||
                  path.contains('.mkv') ||
                  path.contains('video')) {
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
      data['lastConfirmed'] =
          (data['lastConfirmed'] as Timestamp).toDate().toIso8601String();
    } else if (data['lastConfirmed'] is! String) {
      data['lastConfirmed'] = DateTime.now().toIso8601String();
    }

    if (data['publishedAt'] is Timestamp) {
      data['publishedAt'] =
          (data['publishedAt'] as Timestamp).toDate().toIso8601String();
    }
  }
}
