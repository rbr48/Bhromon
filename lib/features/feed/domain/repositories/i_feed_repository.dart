import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/entities/trip_log.dart';
import '../../../../core/entities/explorer_profile.dart';

abstract class IFeedRepository {
  Future<Either<Failure, List<TripLog>>> getFeedItems(ExplorerProfile viewerProfile);
}
