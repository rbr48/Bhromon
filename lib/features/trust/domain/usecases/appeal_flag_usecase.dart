import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../repositories/i_trust_repository.dart';

class AppealFlagParams {
  final String targetId;
  final String justification;

  AppealFlagParams({required this.targetId, required this.justification});
}

@injectable
class AppealFlagUseCase implements UseCase<Unit, AppealFlagParams> {
  final ITrustRepository _repository;

  AppealFlagUseCase(this._repository);

  @override
  Future<Either<Failure, Unit>> call(AppealFlagParams params) {
    return _repository.submitAppeal(
      targetId: params.targetId,
      justification: params.justification,
    );
  }
}
