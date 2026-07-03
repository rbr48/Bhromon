import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../repositories/i_explorer_repository.dart';

@injectable
class GetTopExplorersUseCase implements UseCase<List<ExplorerProfile>, int?> {
  final IExplorerRepository _repository;

  GetTopExplorersUseCase(this._repository);

  @override
  Future<Either<Failure, List<ExplorerProfile>>> call(int? limit) {
    return _repository.getTopExplorers(limit: limit ?? 10);
  }
}
