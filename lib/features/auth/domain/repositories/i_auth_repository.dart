import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/entities/explorer_profile.dart';

abstract class IAuthRepository {
  Future<Either<Failure, String>> signInWithEmail(String email);
  Future<Either<Failure, ExplorerProfile>> verifyOtp(String smsCode);
  Future<Either<Failure, ExplorerProfile>> signInWithGoogle();
  Future<Either<Failure, Unit>> signOut();
  Future<Either<Failure, ExplorerProfile?>> getCurrentProfile();
  Future<Either<Failure, ExplorerProfile>> updateProfile(
      ExplorerProfile profile);
}
