import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../../../../core/entities/pro_tip.dart';
import '../repositories/i_pro_tip_repository.dart';

class VoteTipParams {
  final String tipId;
  final int voteIncrement;

  VoteTipParams({required this.tipId, required this.voteIncrement});
}

@injectable
class VoteTipUseCase implements UseCase<ProTip, VoteTipParams> {
  final IProTipRepository _repository;

  VoteTipUseCase(this._repository);

  @override
  Future<Either<Failure, ProTip>> call(VoteTipParams params) {
    return _repository.voteTip(params.tipId, params.voteIncrement);
  }
}
