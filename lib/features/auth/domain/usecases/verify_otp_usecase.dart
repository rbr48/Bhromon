import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../repositories/i_auth_repository.dart';

@injectable
class VerifyOtpUseCase implements UseCase<ExplorerProfile, String> {
  final IAuthRepository _repository;

  VerifyOtpUseCase(this._repository);

  @override
  Future<Either<Failure, ExplorerProfile>> call(String params) {
    return _repository.verifyOtp(params);
  }
}
