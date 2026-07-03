import 'package:freezed_annotation/freezed_annotation.dart';
import '../value_objects/freshness_age.dart';

part 'pro_tip.freezed.dart';
part 'pro_tip.g.dart';

@freezed
class ProTip with _$ProTip {
  const factory ProTip({
    required String tipId,
    required String locationPinId,
    required String authorId,
    required String text,
    required String category, // transport|food|safety|accommodation|general
    required int helpfulVotes,
    required int outdatedVotes,
    required DateTime lastConfirmed,
    required DecayStatus decayStatus,
    @Default(false) bool hidden,
  }) = _ProTip;

  factory ProTip.fromJson(Map<String, dynamic> json) =>
      _$ProTipFromJson(json);
}
