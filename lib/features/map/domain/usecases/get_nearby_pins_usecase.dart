import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../../../../core/entities/location_pin.dart';
import '../repositories/i_map_repository.dart';

class GetNearbyPinsParams {
  final double lat;
  final double lng;
  final double radiusKm;

  GetNearbyPinsParams({required this.lat, required this.lng, required this.radiusKm});
}

@injectable
class GetNearbyPinsUseCase implements UseCase<List<LocationPin>, GetNearbyPinsParams> {
  final IMapRepository _repository;

  GetNearbyPinsUseCase(this._repository);

  @override
  Future<Either<Failure, List<LocationPin>>> call(GetNearbyPinsParams params) {
    return _repository.getPinsInProximity(params.lat, params.lng, params.radiusKm);
  }
}
