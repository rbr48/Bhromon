import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../../../../core/entities/pro_tip.dart';
import '../repositories/i_pro_tip_repository.dart';

@injectable
class GetTipsForLocationUseCase implements UseCase<List<ProTip>, String> {
  final IProTipRepository _repository;

  GetTipsForLocationUseCase(this._repository);

  @override
  Future<Either<Failure, List<ProTip>>> call(String params) {
    return _repository.getTipsForPin(params);
  }
}
