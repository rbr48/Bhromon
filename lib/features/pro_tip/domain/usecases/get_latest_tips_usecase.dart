import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../../../../core/entities/pro_tip.dart';
import '../repositories/i_pro_tip_repository.dart';

@injectable
class GetLatestTipsUseCase implements UseCase<List<ProTip>, int?> {
  final IProTipRepository _repository;

  GetLatestTipsUseCase(this._repository);

  @override
  Future<Either<Failure, List<ProTip>>> call(int? limit) {
    return _repository.getLatestTips(limit: limit ?? 20);
  }
}
