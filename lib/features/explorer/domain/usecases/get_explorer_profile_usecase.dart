import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../repositories/i_explorer_repository.dart';

@injectable
class GetExplorerProfileUseCase implements UseCase<ExplorerProfile, String> {
  final IExplorerRepository _repository;

  GetExplorerProfileUseCase(this._repository);

  @override
  Future<Either<Failure, ExplorerProfile>> call(String params) {
    return _repository.getProfile(params);
  }
}
