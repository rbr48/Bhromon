import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../../../../core/entities/trip_log.dart';
import '../repositories/i_trip_log_repository.dart';

@injectable
class GetTripLogsForPinUseCase implements UseCase<List<TripLog>, String> {
  final ITripLogRepository _repository;

  GetTripLogsForPinUseCase(this._repository);

  @override
  Future<Either<Failure, List<TripLog>>> call(String params) {
    return _repository.getTripLogsForPin(params);
  }
}
