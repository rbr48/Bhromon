import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../../../../core/entities/trip_log.dart';
import '../../../../core/entities/pro_tip.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/usecases/get_smart_feed_usecase.dart';
import '../../../pro_tip/domain/usecases/get_latest_tips_usecase.dart';
import '../../../explorer/domain/usecases/get_top_explorers_usecase.dart';
import 'feed_state.dart';

@injectable
class FeedCubit extends Cubit<FeedState> {
  final GetSmartFeedUseCase _getSmartFeed;
  final GetLatestTipsUseCase _getLatestTips;
  final GetTopExplorersUseCase _getTopExplorers;

  FeedCubit(
    this._getSmartFeed,
    this._getLatestTips,
    this._getTopExplorers,
  ) : super(const FeedInitial());

  Future<void> loadFeed(ExplorerProfile viewerProfile) async {
    emit(const FeedLoading());

    final results = await Future.wait([
      _getSmartFeed(viewerProfile),
      _getLatestTips(20),
      _getTopExplorers(10),
    ]);

    final logsRes = results[0] as Either<Failure, List<TripLog>>;
    final tipsRes = results[1] as Either<Failure, List<ProTip>>;
    final explorersRes = results[2] as Either<Failure, List<ExplorerProfile>>;

    logsRes.fold(
      (failure) => emit(FeedError(failure.message)),
      (logs) {
        tipsRes.fold(
          (failure) => emit(FeedError(failure.message)),
          (tips) {
            explorersRes.fold(
              (failure) => emit(FeedError(failure.message)),
              (explorers) => emit(FeedLoaded(
                logs: logs,
                tips: tips,
                explorers: explorers,
              )),
            );
          },
        );
      },
    );
  }
}
