import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../repositories/i_offline_repository.dart';

@injectable
class SyncOutboxUseCase implements NoParamsUseCase<Unit> {
  final IOfflineRepository _repository;

  SyncOutboxUseCase(this._repository);

  @override
  Future<Either<Failure, Unit>> call() {
    return _repository.syncOutbox();
  }
}
