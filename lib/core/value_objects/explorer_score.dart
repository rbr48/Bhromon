import 'package:freezed_annotation/freezed_annotation.dart';
import 'trust_tier.dart';

part 'explorer_score.freezed.dart';
part 'explorer_score.g.dart';

@freezed
class ExplorerScore with _$ExplorerScore {
  const ExplorerScore._();

  const factory ExplorerScore({
    required int value,
    required TrustTier tier,
  }) = _ExplorerScore;

  factory ExplorerScore.fromJson(Map<String, dynamic> json) =>
      _$ExplorerScoreFromJson(json);
}
