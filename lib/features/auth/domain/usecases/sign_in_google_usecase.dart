import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../repositories/i_auth_repository.dart';

@injectable
class SignInGoogleUseCase implements NoParamsUseCase<ExplorerProfile> {
  final IAuthRepository _repository;

  SignInGoogleUseCase(this._repository);

  @override
  Future<Either<Failure, ExplorerProfile>> call() {
    return _repository.signInWithGoogle();
  }
}
