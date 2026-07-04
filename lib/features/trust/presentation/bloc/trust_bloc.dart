import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/usecases/flag_content_usecase.dart';
import '../../domain/usecases/appeal_flag_usecase.dart';
import '../../domain/usecases/get_explorer_score_usecase.dart';
import 'trust_event.dart';
import 'trust_state.dart';

@injectable
class TrustBloc extends Bloc<TrustEvent, TrustState> {
  final FlagContentUseCase _flagContent;
  final AppealFlagUseCase _appealFlag;
  final GetExplorerScoreUseCase _getExplorerScore;
  StreamSubscription<Either<Failure, int>>? _scoreSubscription;

  TrustBloc(
    this._flagContent,
    this._appealFlag,
    this._getExplorerScore,
  ) : super(const TrustState()) {
    on<SubscribeScoreEvent>((event, emit) async {
      emit(state.copyWith(uid: event.uid, status: TrustStatus.loading));
      await _scoreSubscription?.cancel();
      _scoreSubscription = _getExplorerScore.watch(event.uid).listen((result) {
        result.fold(
          (failure) => add(
              const RefreshScoreEvent()), // fallback: try a re-subscribe / refresh
          (score) => add(UpdateScoreEvent(score)),
        );
      });
    });

    on<RefreshScoreEvent>((event, emit) async {
      final uid = state.uid;
      if (uid != null) {
        emit(state.copyWith(status: TrustStatus.loading));
        await _scoreSubscription?.cancel();
        _scoreSubscription = _getExplorerScore.watch(uid).listen((result) {
          result.fold(
            (failure) => emit(state.copyWith(
                status: TrustStatus.error, errorMessage: failure.message)),
            (score) => add(UpdateScoreEvent(score)),
          );
        });
      }
    });

    on<UpdateScoreEvent>((event, emit) {
      emit(state.copyWith(score: event.score, status: TrustStatus.loaded));
    });

    on<SubmitFlagEvent>((event, emit) async {
      emit(state.copyWith(status: TrustStatus.loading));
      final result = await _flagContent(FlagContentParams(
        targetId: event.targetId,
        targetType: event.targetType,
        flagType: event.flagType,
        reason: event.reason,
      ));
      result.fold(
        (failure) => emit(state.copyWith(
            status: TrustStatus.error, errorMessage: failure.message)),
        (_) => emit(state.copyWith(status: TrustStatus.loaded)),
      );
    });

    on<SubmitAppealEvent>((event, emit) async {
      emit(state.copyWith(appealStatus: AppealStatus.submitting));
      final result = await _appealFlag(AppealFlagParams(
        targetId: event.targetId,
        justification: event.justification,
      ));
      result.fold(
        (failure) => emit(state.copyWith(
            appealStatus: AppealStatus.error, errorMessage: failure.message)),
        (_) => emit(state.copyWith(appealStatus: AppealStatus.success)),
      );
    });
  }

  @override
  Future<void> close() {
    _scoreSubscription?.cancel();
    return super.close();
  }
}
