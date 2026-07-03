import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../repositories/i_map_repository.dart';

@injectable
class ConfirmPinUseCase implements UseCase<Unit, String> {
  final IMapRepository _repository;

  ConfirmPinUseCase(this._repository);

  @override
  Future<Either<Failure, Unit>> call(String params) {
    return _repository.confirmPin(params);
  }
}
