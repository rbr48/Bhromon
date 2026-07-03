import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/entities/pro_tip.dart';
import '../../../../core/entities/outbox_entry.dart';
import '../../../../core/security/hive_encryption_service.dart';
import '../../../../core/utils/xp_utils.dart';
import '../../../offline_vault/data/datasources/sync_manager.dart';
import '../../domain/repositories/i_pro_tip_repository.dart';

@LazySingleton(as: IProTipRepository)
class ProTipRepositoryImpl implements IProTipRepository {
  final FirebaseFirestore _firestore;
  final HiveEncryptionService _encryptionService;
  final SyncManager _syncManager;

  ProTipRepositoryImpl(this._firestore, this._encryptionService, this._syncManager);

  @override
  Future<Either<Failure, List<ProTip>>> getTipsForPin(String pinId) async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.isNotEmpty && connectivity.first == ConnectivityResult.none) {
        return _getCachedTipsForPin(pinId);
      }

      final snapshot = await _firestore
          .collection('pro_tips')
          .where('locationPinId', isEqualTo: pinId)
          .get();

      final tips = snapshot.docs.map((doc) {
        final data = doc.data();
        data['tipId'] = doc.id;
        _fixTimestamp(data);
        return ProTip.fromJson(data);
      }).toList();

      return Right(tips);
    } catch (e) {
      return _getCachedTipsForPin(pinId);
    }
  }

  Future<Either<Failure, List<ProTip>>> _getCachedTipsForPin(String pinId) async {
    try {
      final box = await _encryptionService.openEncryptedBox<dynamic>('offline_bundles');
      final tips = <ProTip>[];
      for (final val in box.values) {
        final bundleJson = Map<String, dynamic>.from(val as Map);
        if (bundleJson['tips'] is List) {
          final tipsList = bundleJson['tips'] as List;
          for (final tipJson in tipsList) {
            final data = Map<String, dynamic>.from(tipJson as Map);
            if (data['locationPinId'] == pinId) {
              _fixTimestamp(data);
              tips.add(ProTip.fromJson(data));
            }
          }
        }
      }
      return Right(tips);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, ProTip>> voteTip(String tipId, int voteIncrement) async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      final isOffline = connectivity.isNotEmpty && connectivity.first == ConnectivityResult.none;

      if (isOffline) {
        final cachedTip = await _getCachedTipById(tipId);
        if (cachedTip != null) {
          final updatedTip = cachedTip.copyWith(
            helpfulVotes: cachedTip.helpfulVotes + voteIncrement,
          );
          
          final outboxEntry = OutboxEntry(
            id: 'sync_${DateTime.now().microsecondsSinceEpoch}',
            operation: 'update',
            collectionPath: 'pro_tips',
            documentId: tipId,
            payload: {
              'helpfulVotes': {'_type': 'increment', 'value': voteIncrement},
            },
            enqueuedAt: DateTime.now(),
            retryCount: 0,
            status: 'pending',
          );
          
          await _syncManager.enqueue(outboxEntry);
          return Right(updatedTip);
        }
        return const Left(CacheFailure('Tip not found in offline cache'));
      }

      await _firestore.collection('pro_tips').doc(tipId).update({
        'helpfulVotes': FieldValue.increment(voteIncrement),
      });
      final doc = await _firestore.collection('pro_tips').doc(tipId).get();
      final data = doc.data()!;
      data['tipId'] = doc.id;
      _fixTimestamp(data);
      return Right(ProTip.fromJson(data));
    } catch (e) {
      try {
        final cachedTip = await _getCachedTipById(tipId);
        if (cachedTip != null) {
          final updatedTip = cachedTip.copyWith(
            helpfulVotes: cachedTip.helpfulVotes + voteIncrement,
          );
          
          final outboxEntry = OutboxEntry(
            id: 'sync_${DateTime.now().microsecondsSinceEpoch}',
            operation: 'update',
            collectionPath: 'pro_tips',
            documentId: tipId,
            payload: {
              'helpfulVotes': {'_type': 'increment', 'value': voteIncrement},
            },
            enqueuedAt: DateTime.now(),
            retryCount: 0,
            status: 'pending',
          );
          
          await _syncManager.enqueue(outboxEntry);
          return Right(updatedTip);
        }
        return Left(ServerFailure(e.toString()));
      } catch (_) {
        return Left(ServerFailure(e.toString()));
      }
    }
  }

  Future<ProTip?> _getCachedTipById(String tipId) async {
    try {
      final box = await _encryptionService.openEncryptedBox<dynamic>('offline_bundles');
      for (final val in box.values) {
        final bundleJson = Map<String, dynamic>.from(val as Map);
        if (bundleJson['tips'] is List) {
          final tipsList = bundleJson['tips'] as List;
          for (final tipJson in tipsList) {
            final data = Map<String, dynamic>.from(tipJson as Map);
            if (data['tipId'] == tipId) {
              _fixTimestamp(data);
              return ProTip.fromJson(data);
            }
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Either<Failure, ProTip>> addTip(ProTip tip) async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      final isOffline = connectivity.isNotEmpty && connectivity.first == ConnectivityResult.none;

      final json = tip.toJson();

      if (isOffline) {
        json['lastConfirmed'] = {'_type': 'serverTimestamp'};
        final outboxEntry = OutboxEntry(
          id: 'sync_${DateTime.now().microsecondsSinceEpoch}',
          operation: 'create',
          collectionPath: 'pro_tips',
          documentId: tip.tipId,
          payload: json,
          enqueuedAt: DateTime.now(),
          retryCount: 0,
          status: 'pending',
        );
        await _syncManager.enqueue(outboxEntry);
        return Right(tip);
      }

      json['lastConfirmed'] = FieldValue.serverTimestamp();
      await _firestore.collection('pro_tips').doc(tip.tipId).set(json);
      
      // Award 10 XP for posting a pro tip
      await XpUtils.awardXp(tip.authorId, 10);
      
      return Right(tip);
    } catch (e) {
      try {
        final json = tip.toJson();
        json['lastConfirmed'] = {'_type': 'serverTimestamp'};
        final outboxEntry = OutboxEntry(
          id: 'sync_${DateTime.now().microsecondsSinceEpoch}',
          operation: 'create',
          collectionPath: 'pro_tips',
          documentId: tip.tipId,
          payload: json,
          enqueuedAt: DateTime.now(),
          retryCount: 0,
          status: 'pending',
        );
        await _syncManager.enqueue(outboxEntry);
        return Right(tip);
      } catch (_) {
        return Left(ServerFailure(e.toString()));
      }
    }
  }

  @override
  Future<Either<Failure, List<ProTip>>> getLatestTips({int? limit}) async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.isNotEmpty && connectivity.first == ConnectivityResult.none) {
        return _getCachedLatestTips(limit: limit);
      }

      final snapshot = await _firestore
          .collection('pro_tips')
          .get();

      var tips = snapshot.docs.map((doc) {
        final data = doc.data();
        data['tipId'] = doc.id;
        _fixTimestamp(data);
        return ProTip.fromJson(data);
      }).toList();

      // Sort locally by helpfulVotes descending
      tips.sort((a, b) => b.helpfulVotes.compareTo(a.helpfulVotes));

      if (limit != null && tips.length > limit) {
        tips = tips.sublist(0, limit);
      }

      return Right(tips);
    } catch (e) {
      return _getCachedLatestTips(limit: limit);
    }
  }

  Future<Either<Failure, List<ProTip>>> _getCachedLatestTips({int? limit}) async {
    try {
      final box = await _encryptionService.openEncryptedBox<dynamic>('offline_bundles');
      var tips = <ProTip>[];
      for (final val in box.values) {
        final bundleJson = Map<String, dynamic>.from(val as Map);
        if (bundleJson['tips'] is List) {
          final tipsList = bundleJson['tips'] as List;
          for (final tipJson in tipsList) {
            final data = Map<String, dynamic>.from(tipJson as Map);
            _fixTimestamp(data);
            tips.add(ProTip.fromJson(data));
          }
        }
      }
      // Sort locally by helpfulVotes descending
      tips.sort((a, b) => b.helpfulVotes.compareTo(a.helpfulVotes));

      if (limit != null && tips.length > limit) {
        tips = tips.sublist(0, limit);
      }
      return Right(tips);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }


  void _fixTimestamp(Map<String, dynamic> data) {
    if (data['lastConfirmed'] is Timestamp) {
      data['lastConfirmed'] = (data['lastConfirmed'] as Timestamp).toDate().toIso8601String();
    }
  }
}
