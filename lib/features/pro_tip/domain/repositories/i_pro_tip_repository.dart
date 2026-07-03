import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/entities/pro_tip.dart';

abstract class IProTipRepository {
  Future<Either<Failure, List<ProTip>>> getTipsForPin(String pinId);
  Future<Either<Failure, ProTip>> voteTip(String tipId, int voteIncrement);
  Future<Either<Failure, ProTip>> addTip(ProTip tip);
  Future<Either<Failure, List<ProTip>>> getLatestTips({int limit});
}
