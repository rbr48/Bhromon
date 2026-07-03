import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../repositories/i_trust_repository.dart';

class FlagContentParams {
  final String targetId;
  final String targetType;
  final String flagType;
  final String reason;

  FlagContentParams({
    required this.targetId,
    required this.targetType,
    required this.flagType,
    required this.reason,
  });
}

@injectable
class FlagContentUseCase implements UseCase<Unit, FlagContentParams> {
  final ITrustRepository _repository;

  FlagContentUseCase(this._repository);

  @override
  Future<Either<Failure, Unit>> call(FlagContentParams params) {
    return _repository.submitFlag(
      targetId: params.targetId,
      targetType: params.targetType,
      flagType: params.flagType,
      reason: params.reason,
    );
  }
}
