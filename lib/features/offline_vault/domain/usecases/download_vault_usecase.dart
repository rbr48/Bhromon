import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../repositories/i_offline_repository.dart';

@injectable
class DownloadVaultUseCase implements UseCase<Unit, String> {
  final IOfflineRepository _repository;

  DownloadVaultUseCase(this._repository);

  @override
  Future<Either<Failure, Unit>> call(String params) {
    return _repository.downloadBundle(params);
  }
}
