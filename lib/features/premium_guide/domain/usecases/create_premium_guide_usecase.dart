import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../../../../core/entities/trip_log.dart';
import '../../../../core/value_objects/trust_tier.dart';
import '../repositories/i_guide_repository.dart';

class CreatePremiumGuideParams {
  final TripLog tripLog;
  final TrustTier authorTier;

  CreatePremiumGuideParams({required this.tripLog, required this.authorTier});
}

@injectable
class CreatePremiumGuideUseCase
    implements UseCase<TripLog, CreatePremiumGuideParams> {
  final IGuideRepository _repository;

  CreatePremiumGuideUseCase(this._repository);

  @override
  Future<Either<Failure, TripLog>> call(CreatePremiumGuideParams params) async {
    if (!params.authorTier.isVerifiedOrAbove) {
      return const Left(PermissionFailure(
          'Verified tier or above is required to publish premium guides.'));
    }
    return _repository.createPremiumGuide(params.tripLog);
  }
}
