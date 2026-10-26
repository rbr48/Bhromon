// A tour's itinerary: the places it visits in order (Cox's Bazar, then
// Saint Martin's, then Bandarban…) and how the group travels between them.
// Both live on the tour document, so every screen reads the same plan.

import 'date_codec.dart';
import 'tour_group.dart';

/// One place the tour stays at or visits.
class TourStop {
  const TourStop({
    required this.id,
    required this.name,
    this.kind = TourType.custom,
    required this.arrive,
    required this.leave,
    this.stay = '',
    this.notes = '',
    this.lat,
    this.lng,
    this.presetId,
  });

  final String id;
  final String name;
  final TourType kind;

  /// The day the group arrives and the day it leaves. The same day for a
  /// day trip.
  final DateTime arrive;
  final DateTime leave;

  /// Hotel, resort or camp.
  final String stay;
  final String notes;
  final double? lat;
  final double? lng;

  /// The catalog entry the stop was picked from, if any.
  final String? presetId;

  bool get hasLocation => lat != null && lng != null;

  /// Nights spent here: 0 for a stop the group passes through in a day.
  int get nights {
    final a = DateTime(arrive.year, arrive.month, arrive.day);
    final l = DateTime(leave.year, leave.month, leave.day);
    final n = l.difference(a).inDays;
    return n < 0 ? 0 : n;
  }

  /// Whether [day] falls on one of the stop's calendar days.
  bool covers(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final a = DateTime(arrive.year, arrive.month, arrive.day);
    final l = DateTime(leave.year, leave.month, leave.day);
    return !d.isBefore(a) && !d.isAfter(l);
  }

  TourStop copyWith({
    String? name,
    TourType? kind,
    DateTime? arrive,
    DateTime? leave,
    String? stay,
    String? notes,
    Object? lat = _keep,
    Object? lng = _keep,
    Object? presetId = _keep,
  }) {
    return TourStop(
      id: id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      arrive: arrive ?? this.arrive,
      leave: leave ?? this.leave,
      stay: stay ?? this.stay,
      notes: notes ?? this.notes,
      lat: identical(lat, _keep) ? this.lat : lat as double?,
      lng: identical(lng, _keep) ? this.lng : lng as double?,
      presetId:
          identical(presetId, _keep) ? this.presetId : presetId as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'kind': kind.toValue(),
        'arrive': writeDate(arrive),
        'leave': writeDate(leave),
        'stay': stay,
        'notes': notes,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (presetId != null) 'presetId': presetId,
      };

  factory TourStop.fromMap(Map<String, dynamic> map) {
    final arrive = readDate(map['arrive']) ?? DateTime.now();
    return TourStop(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      kind: TourType.fromString(map['kind'] as String?),
      arrive: arrive,
      leave: readDate(map['leave']) ?? arrive,
      stay: map['stay'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      presetId: map['presetId'] as String?,
    );
  }
}

/// How the group travels a leg.
enum TransportMode {
  road,
  rail,
  air,

  /// A river launch or steamer.
  river,

  /// A sea ship, such as to Saint Martin's.
  sea,

  /// A hill jeep ("chander gari").
  jeep,

  /// A small boat or trawler (haor, Sundarbans, Ratargul).
  boat,

  /// On foot.
  trek;

  static TransportMode fromString(String? value) {
    for (final m in values) {
      if (m.name == value) return m;
    }
    return TransportMode.road;
  }

  /// A typical moving speed in km/h, stops included.
  double get averageKmh => switch (this) {
        road => 45,
        rail => 50,
        air => 400,
        river => 18,
        sea => 20,
        jeep => 25,
        boat => 12,
        trek => 3.5,
      };

  /// How much longer the real way is than a straight line.
  double get detourFactor => switch (this) {
        road => 1.35,
        rail => 1.3,
        air => 1.05,
        river => 1.4,
        sea => 1.2,
        jeep => 1.5,
        boat => 1.3,
        trek => 1.4,
      };

  /// Fixed time on top of moving time, in minutes: check-in and boarding for
  /// flights, boarding and ghat time for boats.
  int get overheadMinutes => switch (this) {
        air => 90,
        river || sea => 30,
        boat => 15,
        _ => 0,
      };

  /// The Google Maps travel mode that fits best.
  String get mapsTravelMode => switch (this) {
        rail => 'transit',
        trek => 'walking',
        _ => 'driving',
      };
}

/// The plan and the progress for one leg, keyed by "<fromId>><toId>".
class LegPlan {
  const LegPlan({
    this.mode = TransportMode.road,
    this.distanceKm,
    this.departAt,
    this.arriveAt,
    this.departedAt,
    this.arrivedAt,
    this.notes = '',
  });

  final TransportMode mode;

  /// The distance when someone knows it. Otherwise it is estimated from the
  /// two places' coordinates.
  final int? distanceKm;

  /// Planned departure and arrival.
  final DateTime? departAt;
  final DateTime? arriveAt;

  /// When the group actually left and arrived, set by an admin.
  final DateTime? departedAt;
  final DateTime? arrivedAt;

  final String notes;

  LegPlan copyWith({
    TransportMode? mode,
    Object? distanceKm = _keep,
    Object? departAt = _keep,
    Object? arriveAt = _keep,
    Object? departedAt = _keep,
    Object? arrivedAt = _keep,
    String? notes,
  }) {
    return LegPlan(
      mode: mode ?? this.mode,
      distanceKm:
          identical(distanceKm, _keep) ? this.distanceKm : distanceKm as int?,
      departAt:
          identical(departAt, _keep) ? this.departAt : departAt as DateTime?,
      arriveAt:
          identical(arriveAt, _keep) ? this.arriveAt : arriveAt as DateTime?,
      departedAt: identical(departedAt, _keep)
          ? this.departedAt
          : departedAt as DateTime?,
      arrivedAt:
          identical(arrivedAt, _keep) ? this.arrivedAt : arrivedAt as DateTime?,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toMap() => {
        'mode': mode.name,
        if (distanceKm != null) 'distanceKm': distanceKm,
        if (departAt != null) 'departAt': writeDate(departAt!),
        if (arriveAt != null) 'arriveAt': writeDate(arriveAt!),
        if (departedAt != null) 'departedAt': writeDate(departedAt!),
        if (arrivedAt != null) 'arrivedAt': writeDate(arrivedAt!),
        'notes': notes,
      };

  factory LegPlan.fromMap(Map<String, dynamic> map) => LegPlan(
        mode: TransportMode.fromString(map['mode'] as String?),
        distanceKm: (map['distanceKm'] as num?)?.toInt(),
        departAt: readDate(map['departAt']),
        arriveAt: readDate(map['arriveAt']),
        departedAt: readDate(map['departedAt']),
        arrivedAt: readDate(map['arrivedAt']),
        notes: map['notes'] as String? ?? '',
      );
}

/// Reads the `stops` list from a tour document, oldest arrival first.
List<TourStop> readStops(Object? value) {
  if (value is! List) return const [];
  final stops = [
    for (final e in value)
      if (e is Map) TourStop.fromMap(Map<String, dynamic>.from(e)),
  ]..sort((a, b) => a.arrive.compareTo(b.arrive));
  return stops;
}

/// Reads the `legPlans` map from a tour document.
Map<String, LegPlan> readLegPlans(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final e in value.entries)
      if (e.value is Map)
        e.key.toString():
            LegPlan.fromMap(Map<String, dynamic>.from(e.value as Map)),
  };
}

const Object _keep = Object();
