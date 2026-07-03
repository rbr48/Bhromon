import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../repositories/i_guide_repository.dart';

@injectable
class PurchaseGuideParams {
  final String guideId;
  final String userId;

  PurchaseGuideParams({required this.guideId, required this.userId});
}

class PurchaseGuideUseCase implements UseCase<Unit, PurchaseGuideParams> {
  final IGuideRepository _repository;

  PurchaseGuideUseCase(this._repository);

  @override
  Future<Either<Failure, Unit>> call(PurchaseGuideParams params) {
    return _repository.purchaseGuide(params.guideId, params.userId);
  }
}
