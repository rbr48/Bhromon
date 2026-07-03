import 'package:equatable/equatable.dart';
import '../../../../core/entities/pro_tip.dart';

abstract class TipListState extends Equatable {
  const TipListState();
  @override
  List<Object?> get props => [];
}

class TipListInitial extends TipListState {
  const TipListInitial();
}

class TipListLoading extends TipListState {
  const TipListLoading();
}

class TipListLoaded extends TipListState {
  final List<ProTip> tips;
  const TipListLoaded(this.tips);

  @override
  List<Object?> get props => [tips];
}

class TipListError extends TipListState {
  final String message;
  const TipListError(this.message);

  @override
  List<Object?> get props => [message];
}
