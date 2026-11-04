import 'tour_group.dart';

/// A verified tourist destination or scenic spot in Bangladesh loaded from
/// `assets/bd_predefined_spots.json`.
class PredefinedSpot {
  const PredefinedSpot({
    required this.pinId,
    required this.name,
    required this.lat,
    required this.lng,
    required this.description,
    required this.category,
    required this.district,
    required this.division,
    required this.trustTier,
    required this.geoHash,
  });

  final String pinId;
  final String name;
  final double lat;
  final double lng;
  final String description;
  final String category;
  final String district;
  final String division;
  final String trustTier;
  final String geoHash;

  /// Maps the spot's category to the tour engine's [TourType].
  TourType get kind => switch (category.toLowerCase().trim()) {
        'beach' => TourType.beach,
        'hill' || 'hills' => TourType.hill,
        'nature' => TourType.nature,
        'historical' || 'heritage' => TourType.heritage,
        'city' => TourType.city,
        _ => TourType.custom,
      };

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        district.toLowerCase().contains(q) ||
        division.toLowerCase().contains(q) ||
        category.toLowerCase().contains(q) ||
        description.toLowerCase().contains(q);
  }

  factory PredefinedSpot.fromJson(Map<String, dynamic> json) {
    return PredefinedSpot(
      pinId: json['pinId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? '',
      district: json['district'] as String? ?? '',
      division: json['division'] as String? ?? '',
      trustTier: json['trustTier'] as String? ?? 'verified',
      geoHash: json['geoHash'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'pinId': pinId,
        'name': name,
        'lat': lat,
        'lng': lng,
        'description': description,
        'category': category,
        'district': district,
        'division': division,
        'trustTier': trustTier,
        'geoHash': geoHash,
      };
}
