import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../../../../core/entities/pro_tip.dart';
import '../repositories/i_pro_tip_repository.dart';

@injectable
class AddProTipUseCase implements UseCase<ProTip, ProTip> {
  final IProTipRepository _repository;

  AddProTipUseCase(this._repository);

  @override
  Future<Either<Failure, ProTip>> call(ProTip params) {
    return _repository.addTip(params);
  }
}
