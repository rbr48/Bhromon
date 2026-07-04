import 'dart:convert';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/entities/trip_log.dart';
import '../../domain/repositories/i_trip_log_repository.dart';

class MockOfflineTripLogRepository implements ITripLogRepository {
  final AppDatabase _database;

  MockOfflineTripLogRepository(this._database);

  @override
  Future<Either<Failure, List<TripLog>>> getTripLogsForPin(String pinId) async {
    try {
      final jsonStrings = await _database.getTripLogsForPin(pinId, false);
      final List<TripLog> logs = jsonStrings.map((jsonStr) {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        return TripLog.fromJson(map);
      }).toList();
      return Right(logs);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, TripLog>> publishTripLog(TripLog tripLog) async {
    try {
      final jsonStr = jsonEncode(tripLog.toJson());
      await _database.saveTripLog(
          tripLog.tripId, tripLog.locationPinId, false, jsonStr);
      await _database.deleteTripLogDraft(tripLog.locationPinId);
      return Right(tripLog);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> saveDraft(TripLog tripLog) async {
    try {
      final jsonStr = jsonEncode(tripLog.toJson());
      // For drafts, we use the pinId as draft identity to ensure one draft per pin
      await _database.saveTripLog(
          tripLog.tripId, tripLog.locationPinId, true, jsonStr);
      return const Right(unit);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, TripLog?>> getDraft(String pinId) async {
    try {
      final jsonStrings = await _database.getTripLogsForPin(pinId, true);
      if (jsonStrings.isNotEmpty) {
        final map = jsonDecode(jsonStrings.first) as Map<String, dynamic>;
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
      final jsonStr = await _database.getTripLogById(id);
      if (jsonStr == null) {
        return Left(NotFoundFailure('Trip log not found', resourceId: id));
      }
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return Right(TripLog.fromJson(map));
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }
}
