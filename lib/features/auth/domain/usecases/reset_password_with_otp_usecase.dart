import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/entities/explorer_profile.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../repositories/i_auth_repository.dart';

/// Input credentials for resetting a forgotten password with 6-digit OTP.
class ResetPasswordWithOtpParams extends Equatable {
  const ResetPasswordWithOtpParams({
    required this.email,
    required this.password,
    required this.otp,
  });

  final String email;
  final String password;
  final String otp;

  @override
  List<Object?> get props => [email, password, otp];
}

/// Verifies the 6-digit OTP, sets a new password, and signs the user in.
@injectable
class ResetPasswordWithOtpUseCase
    implements UseCase<ExplorerProfile, ResetPasswordWithOtpParams> {
  final IAuthRepository _repository;

  ResetPasswordWithOtpUseCase(this._repository);

  @override
  Future<Either<Failure, ExplorerProfile>> call(
      ResetPasswordWithOtpParams params) {
    return _repository.resetPasswordWithOtp(
      email: params.email,
      password: params.password,
      otp: params.otp,
    );
  }
}
