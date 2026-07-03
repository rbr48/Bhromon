import 'package:freezed_annotation/freezed_annotation.dart';
import '../value_objects/trust_tier.dart';

part 'location_pin.freezed.dart';
part 'location_pin.g.dart';

@freezed
class LocationPin with _$LocationPin {
  const factory LocationPin({
    required String pinId,
    required String name,
    required String geoHash,
    required double lat,
    required double lng,
    required TrustTier trustTier,
    required DateTime lastConfirmed,
    required List<String> linkedTripIds,
    required List<String> linkedTipIds,
    required String division,
    required String district,
    required String createdByUid,
    @Default(false) bool hidden,
    String? businessProfileId,
    // Rich metadata fields (optional, populated by enrichment bot / user edit)
    String? imageUrl,
    String? description,
    @Default('place') String category, // e.g. waterfall, beach, temple, forest, market, heritage, hill, place
    @Default(0.0) double averageRating,
    @Default(0) int visitCount,
    @Default([]) List<String> photos,
  }) = _LocationPin;

  factory LocationPin.fromJson(Map<String, dynamic> json) =>
      _$LocationPinFromJson(json);
}
