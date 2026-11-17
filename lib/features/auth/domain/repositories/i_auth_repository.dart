import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/entities/explorer_profile.dart';

abstract class IAuthRepository {
  Future<Either<Failure, String>> signInWithEmail(String email);
  Future<Either<Failure, String>> sendSignUpOtp(String email);
  Future<Either<Failure, ExplorerProfile>> registerWithEmailOtp({
    required String email,
    required String password,
    required String otp,
    String? displayName,
  });
  Future<Either<Failure, ExplorerProfile>> signInWithEmailPassword({
    required String email,
    required String password,
  });
  Future<Either<Failure, ExplorerProfile>> verifyOtp(String smsCode);
  Future<Either<Failure, ExplorerProfile>> signInWithGoogle();
  Future<Either<Failure, Unit>> signOut();
  Future<Either<Failure, ExplorerProfile?>> getCurrentProfile();
  Future<Either<Failure, ExplorerProfile>> updateProfile(
      ExplorerProfile profile);
}
