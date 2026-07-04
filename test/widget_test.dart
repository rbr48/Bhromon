import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_state.dart';
import 'package:bhromon/features/auth/domain/repositories/i_auth_repository.dart';
import 'package:bhromon/core/entities/explorer_profile.dart';
import 'package:bhromon/core/errors/failures.dart';
import 'package:bhromon/features/auth/domain/usecases/get_current_profile_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/sign_in_email_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/verify_otp_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/sign_in_google_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/sign_out_usecase.dart';
import 'package:bhromon/features/auth/domain/usecases/update_profile_usecase.dart';

class FakeAuthRepository implements IAuthRepository {
  @override
  Future<Either<Failure, ExplorerProfile?>> getCurrentProfile() async {
    return const Right(null);
  }

  @override
  Future<Either<Failure, ExplorerProfile>> signInWithGoogle() async {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, String>> signInWithEmail(String email) async {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, Unit>> signOut() async {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, ExplorerProfile>> updateProfile(
      ExplorerProfile profile) async {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, ExplorerProfile>> verifyOtp(String smsCode) async {
    throw UnimplementedError();
  }
}

void main() {
  test('AuthCubit initial state is AuthInitial', () {
    final repo = FakeAuthRepository();
    final cubit = AuthCubit(
      GetCurrentProfileUseCase(repo),
      SignInEmailUseCase(repo),
      VerifyOtpUseCase(repo),
      SignInGoogleUseCase(repo),
      SignOutUseCase(repo),
      UpdateProfileUseCase(repo),
    );
    expect(cubit.state, isA<AuthInitial>());
  });
}
