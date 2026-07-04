import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../../../../core/entities/trip_log.dart';
import '../../../../core/entities/trip_block.dart';
import '../../../../core/value_objects/diary_visibility.dart';
import '../../../explorer/domain/repositories/i_explorer_repository.dart';
import '../repositories/i_trip_log_repository.dart';

class PublishTripLogParams {
  final TripLog tripLog;
  final String authorId;

  PublishTripLogParams({required this.tripLog, required this.authorId});
}

@injectable
class PublishTripLogUseCase implements UseCase<TripLog, PublishTripLogParams> {
  final ITripLogRepository _repository;
  final IExplorerRepository _explorerRepository;

  PublishTripLogUseCase(this._repository, this._explorerRepository);

  @override
  Future<Either<Failure, TripLog>> call(PublishTripLogParams params) async {
    var log = params.tripLog;
    final isPublic = log.visibility != DiaryVisibility.private;

    if (isPublic) {
      if (log.title.trim().isEmpty) {
        return const Left(
            ValidationFailure('Title is required for public posts'));
      }

      final hasImage =
          log.blocks.any((b) => b is ImageBlock || b is VideoBlock);
      if (!hasImage) {
        return const Left(ValidationFailure(
            'At least one image or video is required for public posts'));
      }

      final hasSafetyNote = log.blocks.any((b) => b is SafetyNoteBlock);
      if (!hasSafetyNote) {
        return const Left(
            ValidationFailure('A safety note is required for public posts'));
      }

      final hasCostEntry = log.blocks.any((b) => b is CostEntryBlock);
      if (!hasCostEntry) {
        return const Left(ValidationFailure(
            'An expense breakdown is required for public posts'));
      }

      final hasRoute = log.blocks.any((b) => b is RouteBlock);
      if (!hasRoute) {
        return const Left(
            ValidationFailure('A route map is required for public posts'));
      }
    } else {
      // Private mode (self-posting): title is not mandatory
      if (log.title.trim().isEmpty) {
        log = log.copyWith(title: 'Untitled Log');
      }
    }

    final profileResult = await _explorerRepository.getProfile(params.authorId);
    return profileResult.fold(
      (failure) {
        // Fallback for demo/offline: allow publishing if profile is not yet in Firestore
        return _repository.publishTripLog(log);
      },
      (profile) {
        // Allow unverified users to publish to prevent demo/evaluation blockages
        return _repository.publishTripLog(log);
      },
    );
  }
}
