import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/entities/location_pin.dart';

abstract class IMapRepository {
  Future<Either<Failure, List<LocationPin>>> getPinsInProximity(
    double lat,
    double lng,
    double radiusKm,
  );
  Future<Either<Failure, LocationPin>> addPin(LocationPin pin);
  Future<Either<Failure, Unit>> confirmPin(String pinId);
}
