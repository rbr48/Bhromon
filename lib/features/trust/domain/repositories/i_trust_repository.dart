import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';

abstract class ITrustRepository {
  Stream<Either<Failure, int>> getScoreStream(String uid);
  Future<Either<Failure, Unit>> submitFlag({
    required String targetId,
    required String targetType,
    required String flagType,
    required String reason,
  });
  Future<Either<Failure, Unit>> submitAppeal({
    required String targetId,
    required String justification,
  });
}
