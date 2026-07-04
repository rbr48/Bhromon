import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/entities/trip_log.dart';
import '../../domain/repositories/i_guide_repository.dart';

@LazySingleton(as: IGuideRepository)
class GuideRepositoryImpl implements IGuideRepository {
  final FirebaseFirestore _firestore;

  GuideRepositoryImpl(this._firestore);

  @override
  Future<Either<Failure, TripLog>> createPremiumGuide(TripLog tripLog) async {
    try {
      final updatedLog = tripLog.copyWith(isPremiumGuide: true);
      await _firestore
          .collection('trip_logs')
          .doc(tripLog.tripId)
          .set(updatedLog.toJson(), SetOptions(merge: true));
      return Right(updatedLog);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> purchaseGuide(
      String guideId, String userId) async {
    try {
      await _firestore
          .collection('explorer_profiles')
          .doc(userId)
          .collection('purchased_guides')
          .doc(guideId)
          .set({
        'purchasedAt': FieldValue.serverTimestamp(),
        'guideId': guideId,
      });
      return const Right(unit);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
