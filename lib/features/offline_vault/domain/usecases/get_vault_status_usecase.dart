import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../../../../core/entities/offline_bundle.dart';
import '../repositories/i_offline_repository.dart';

@injectable
class GetVaultStatusUseCase implements NoParamsUseCase<List<OfflineBundle>> {
  final IOfflineRepository _repository;

  GetVaultStatusUseCase(this._repository);

  @override
  Future<Either<Failure, List<OfflineBundle>>> call() {
    return _repository.getDownloadedBundles();
  }
}
