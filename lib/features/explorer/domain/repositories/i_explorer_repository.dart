import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/entities/explorer_profile.dart';

abstract class IExplorerRepository {
  Future<Either<Failure, ExplorerProfile>> getProfile(String uid);
  Future<Either<Failure, List<ExplorerProfile>>> getTopExplorers({int limit});
}
