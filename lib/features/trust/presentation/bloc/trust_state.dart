import 'package:equatable/equatable.dart';
import '../../../../core/value_objects/trust_tier.dart';

enum TrustStatus { initial, loading, loaded, error }
enum AppealStatus { idle, submitting, success, error }

class TrustState extends Equatable {
  final String? uid;
  final int score;
  final TrustStatus status;
  final AppealStatus appealStatus;
  final String? errorMessage;

  const TrustState({
    this.uid,
    this.score = 0,
    this.status = TrustStatus.initial,
    this.appealStatus = AppealStatus.idle,
    this.errorMessage,
  });

  /// Derive the TrustTier from the current score
  TrustTier get tier {
    if (score >= 500) return TrustTier.regionExpert;
    if (score >= 200) return TrustTier.verified;
    if (score >= 50) return TrustTier.community;
    return TrustTier.unverified;
  }

  /// Human-readable tier name (kept for backward compatibility)
  String get tierName => tier.displayName;

  TrustState copyWith({
    String? uid,
    int? score,
    TrustStatus? status,
    AppealStatus? appealStatus,
    String? errorMessage,
  }) {
    return TrustState(
      uid: uid ?? this.uid,
      score: score ?? this.score,
      status: status ?? this.status,
      appealStatus: appealStatus ?? this.appealStatus,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [uid, score, status, appealStatus, errorMessage];
}
