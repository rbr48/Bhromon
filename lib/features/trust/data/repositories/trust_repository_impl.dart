import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/xp_utils.dart';
import '../../domain/repositories/i_trust_repository.dart';

@LazySingleton(as: ITrustRepository)
class TrustRepositoryImpl implements ITrustRepository {
  final FirebaseFirestore _firestore;
  final int _currentScore = 55;
  final _scoreStreamController =
      StreamController<Either<Failure, int>>.broadcast();

  TrustRepositoryImpl(this._firestore) {
    _scoreStreamController.add(Right(_currentScore));
  }

  @override
  Stream<Either<Failure, int>> getScoreStream(String uid) {
    // Listen to real-time ExplorerScore changes in explorer_scores collection
    try {
      return _firestore
          .collection('explorer_scores')
          .doc(uid)
          .snapshots()
          .map((snapshot) {
        if (snapshot.exists && snapshot.data() != null) {
          final val = snapshot.data()!['score'] as int? ?? 0;
          return Right(val);
        }
        return Right(_currentScore);
      });
    } catch (e) {
      return _scoreStreamController.stream;
    }
  }

  @override
  Future<Either<Failure, Unit>> submitFlag({
    required String targetId,
    required String targetType,
    required String flagType,
    required String reason,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'explorer_user';
      final docId = 'flag_${DateTime.now().millisecondsSinceEpoch}';
      await _firestore.collection('trust_events').doc(docId).set({
        'type': '${flagType}_flag',
        'targetId': targetId,
        'targetType': targetType,
        'actorId': uid,
        'timestamp': FieldValue.serverTimestamp(),
        'reason': reason,
        'weight': 1,
      });

      // Deduct 5 XP for flagging/moderation action
      await XpUtils.awardXp(uid, -5);

      return const Right(unit);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> submitAppeal({
    required String targetId,
    required String justification,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'explorer_user';
      final docId = 'appeal_${DateTime.now().millisecondsSinceEpoch}';
      await _firestore.collection('flag_appeals').doc(docId).set({
        'flagEventId': targetId,
        'appellantUid': uid,
        'reason': justification,
        'status': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),
      });

      // Award 5 XP for submitting a valid appeal
      await XpUtils.awardXp(uid, 5);

      return const Right(unit);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
