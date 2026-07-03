import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../repositories/i_trust_repository.dart';

@injectable
class GetExplorerScoreUseCase {
  final ITrustRepository _repository;

  GetExplorerScoreUseCase(this._repository);

  Stream<Either<Failure, int>> watch(String uid) {
    return _repository.getScoreStream(uid);
  }
}
