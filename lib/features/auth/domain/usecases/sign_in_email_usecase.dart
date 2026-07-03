import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../repositories/i_auth_repository.dart';

@injectable
class SignInEmailUseCase implements UseCase<String, String> {
  final IAuthRepository _repository;

  SignInEmailUseCase(this._repository);

  @override
  Future<Either<Failure, String>> call(String params) {
    return _repository.signInWithEmail(params);
  }
}
