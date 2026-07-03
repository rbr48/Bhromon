import 'package:equatable/equatable.dart';

abstract class TrustEvent extends Equatable {
  const TrustEvent();
  @override
  List<Object?> get props => [];
}

class SubscribeScoreEvent extends TrustEvent {
  final String uid;
  const SubscribeScoreEvent(this.uid);
  @override
  List<Object?> get props => [uid];
}

/// Refresh the score once (e.g., on pull-to-refresh)
class RefreshScoreEvent extends TrustEvent {
  const RefreshScoreEvent();
}

class UpdateScoreEvent extends TrustEvent {
  final int score;
  const UpdateScoreEvent(this.score);
  @override
  List<Object?> get props => [score];
}

class SubmitFlagEvent extends TrustEvent {
  final String targetId;
  final String targetType;
  final String flagType;
  final String reason;

  const SubmitFlagEvent({
    required this.targetId,
    required this.targetType,
    required this.flagType,
    required this.reason,
  });

  @override
  List<Object?> get props => [targetId, targetType, flagType, reason];
}

class SubmitAppealEvent extends TrustEvent {
  final String targetId;
  final String justification;

  const SubmitAppealEvent({
    required this.targetId,
    required this.justification,
  });

  @override
  List<Object?> get props => [targetId, justification];
}
