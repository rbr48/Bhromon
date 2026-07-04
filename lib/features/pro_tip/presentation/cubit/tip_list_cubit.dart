import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/entities/pro_tip.dart';
import '../../../../core/value_objects/freshness_age.dart';
import '../../domain/usecases/add_pro_tip_usecase.dart';
import '../../domain/usecases/vote_tip_usecase.dart';
import '../../domain/usecases/get_tips_for_location_usecase.dart';
import 'tip_list_state.dart';

@injectable
class TipListCubit extends Cubit<TipListState> {
  final AddProTipUseCase _addProTip;
  final VoteTipUseCase _voteTip;
  final GetTipsForLocationUseCase _getTipsForLocation;

  TipListCubit(
    this._addProTip,
    this._voteTip,
    this._getTipsForLocation,
  ) : super(const TipListInitial());

  Future<void> loadTips(String pinId) async {
    emit(const TipListLoading());
    final result = await _getTipsForLocation(pinId);
    result.fold(
      (failure) => emit(TipListError(failure.message)),
      (tips) {
        final sorted = List<ProTip>.from(tips);
        sorted.sort((a, b) => b.helpfulVotes.compareTo(a.helpfulVotes));
        emit(TipListLoaded(sorted));
      },
    );
  }

  Future<void> voteTip(String tipId, int increment) async {
    final currentState = state;
    if (currentState is TipListLoaded) {
      final oldTipsList = List<ProTip>.from(currentState.tips);

      final updatedTips = currentState.tips.map((t) {
        if (t.tipId == tipId) {
          return t.copyWith(helpfulVotes: t.helpfulVotes + increment);
        }
        return t;
      }).toList();
      emit(TipListLoaded(updatedTips));

      final result =
          await _voteTip(VoteTipParams(tipId: tipId, voteIncrement: increment));
      result.fold(
        (failure) {
          emit(TipListLoaded(oldTipsList));
        },
        (updatedTip) {},
      );
    }
  }

  Future<void> addNewTip(String pinId, String text) async {
    final currentState = state;
    if (currentState is TipListLoaded) {
      final newTip = ProTip(
        tipId: 'tip_${DateTime.now().millisecondsSinceEpoch}',
        locationPinId: pinId,
        authorId: 'explorer_user',
        text: text,
        category: 'general',
        helpfulVotes: 0,
        outdatedVotes: 0,
        lastConfirmed: DateTime.now(),
        decayStatus: DecayStatus.fresh,
      );

      final result = await _addProTip(newTip);
      result.fold(
        (failure) => emit(TipListError(failure.message)),
        (added) {
          final updated = List<ProTip>.from(currentState.tips)..add(added);
          emit(TipListLoaded(updated));
        },
      );
    }
  }
}
