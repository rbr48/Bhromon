import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/entities/trip_log.dart';

abstract class ITripLogRepository {
  Future<Either<Failure, List<TripLog>>> getTripLogsForPin(String pinId);
  Future<Either<Failure, TripLog>> publishTripLog(TripLog tripLog);
  Future<Either<Failure, Unit>> saveDraft(TripLog tripLog);
  Future<Either<Failure, TripLog?>> getDraft(String pinId);
  Future<Either<Failure, TripLog>> getById(String id);
}
