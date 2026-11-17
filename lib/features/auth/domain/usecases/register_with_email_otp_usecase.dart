import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/entities/explorer_profile.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../repositories/i_auth_repository.dart';

/// Input credentials for creating a verified Email/Password account with 6-digit OTP.
class RegisterWithEmailOtpParams extends Equatable {
  const RegisterWithEmailOtpParams({
    required this.email,
    required this.password,
    required this.otp,
    this.displayName,
  });

  final String email;
  final String password;
  final String otp;
  final String? displayName;

  @override
  List<Object?> get props => [email, password, otp, displayName];
}

/// Verifies the 6-digit OTP and creates + signs into a verified Email/Password user.
@injectable
class RegisterWithEmailOtpUseCase
    implements UseCase<ExplorerProfile, RegisterWithEmailOtpParams> {
  final IAuthRepository _repository;

  RegisterWithEmailOtpUseCase(this._repository);

  @override
  Future<Either<Failure, ExplorerProfile>> call(
      RegisterWithEmailOtpParams params) {
    return _repository.registerWithEmailOtp(
      email: params.email,
      password: params.password,
      otp: params.otp,
      displayName: params.displayName,
    );
  }
}
