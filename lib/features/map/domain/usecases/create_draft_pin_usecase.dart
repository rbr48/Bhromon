import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../../../../core/entities/location_pin.dart';
import '../repositories/i_map_repository.dart';

@injectable
class CreateDraftPinUseCase implements UseCase<LocationPin, LocationPin> {
  final IMapRepository _repository;

  CreateDraftPinUseCase(this._repository);

  @override
  Future<Either<Failure, LocationPin>> call(LocationPin params) {
    return _repository.addPin(params);
  }
}
