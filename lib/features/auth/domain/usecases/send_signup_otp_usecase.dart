import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../repositories/i_auth_repository.dart';

/// Requests a 6-digit OTP verification email before creating a new account.
@injectable
class SendSignUpOtpUseCase implements UseCase<String, String> {
  final IAuthRepository _repository;

  SendSignUpOtpUseCase(this._repository);

  @override
  Future<Either<Failure, String>> call(String email) {
    return _repository.sendSignUpOtp(email);
  }
}
