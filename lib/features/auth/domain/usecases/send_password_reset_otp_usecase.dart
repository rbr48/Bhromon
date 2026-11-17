import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../repositories/i_auth_repository.dart';

/// Requests a 6-digit OTP email for resetting a forgotten password.
@injectable
class SendPasswordResetOtpUseCase implements UseCase<String, String> {
  final IAuthRepository _repository;

  SendPasswordResetOtpUseCase(this._repository);

  @override
  Future<Either<Failure, String>> call(String email) {
    return _repository.sendPasswordResetOtp(email);
  }
}
