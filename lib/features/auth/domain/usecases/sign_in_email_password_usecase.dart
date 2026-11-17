import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/entities/explorer_profile.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../repositories/i_auth_repository.dart';

/// Input credentials for Firebase Email/Password authentication.
class SignInEmailPasswordParams extends Equatable {
  const SignInEmailPasswordParams({
    required this.email,
    required this.password,
  });

  final String email;
  final String password;

  @override
  List<Object?> get props => [email, password];
}

/// Signs in an existing account using email and password.
@injectable
class SignInEmailPasswordUseCase
    implements UseCase<ExplorerProfile, SignInEmailPasswordParams> {
  final IAuthRepository _repository;

  SignInEmailPasswordUseCase(this._repository);

  @override
  Future<Either<Failure, ExplorerProfile>> call(
      SignInEmailPasswordParams params) {
    return _repository.signInWithEmailPassword(
      email: params.email,
      password: params.password,
    );
  }
}
