import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../../../../core/entities/trip_log.dart';
import '../repositories/i_trip_log_repository.dart';

@injectable
class SaveDraftUseCase implements UseCase<Unit, TripLog> {
  final ITripLogRepository _repository;

  SaveDraftUseCase(this._repository);

  @override
  Future<Either<Failure, Unit>> call(TripLog params) {
    return _repository.saveDraft(params);
  }
}
