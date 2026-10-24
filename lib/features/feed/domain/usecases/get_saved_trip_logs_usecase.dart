import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../../../../core/entities/trip_log.dart';
import '../repositories/i_feed_repository.dart';

class SavedTripLogsRequest {
  final ExplorerProfile viewer;
  final FeedViewerContext viewerContext;
  final List<String> tripIds;

  const SavedTripLogsRequest({
    required this.viewer,
    required this.viewerContext,
    required this.tripIds,
  });
}

/// Loads the trip logs a viewer bookmarked, by id.
@injectable
class GetSavedTripLogsUseCase {
  final IFeedRepository _repository;

  GetSavedTripLogsUseCase(this._repository);

  Future<Either<Failure, List<TripLog>>> call(SavedTripLogsRequest request) =>
      _repository.getTripLogsByIds(
          request.viewer, request.viewerContext, request.tripIds);
}
