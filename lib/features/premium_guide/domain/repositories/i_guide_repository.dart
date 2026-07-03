import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/entities/trip_log.dart';

abstract class IGuideRepository {
  Future<Either<Failure, TripLog>> createPremiumGuide(TripLog tripLog);
  Future<Either<Failure, Unit>> purchaseGuide(String guideId, String userId);
}
