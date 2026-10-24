import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/geo/geohash.dart';

/// Pin documents within [radiusMeters] of ([lat], [lng]).
///
/// Uses geohash range queries on `location_pins.geoHash` (kept current by the
/// `maintainPinGeohash` Cloud Function), so it reads only pins in the cells
/// around the point instead of the whole collection. Until existing pins are
/// backfilled (`backfillPinGeohashes`) the ranges can come back empty; then a
/// latitude-band query is used so nearby pins are still found.
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> queryPinsNear(
  FirebaseFirestore firestore,
  double lat,
  double lng,
  double radiusMeters,
) async {
  final pins = firestore.collection('location_pins');
  final snapshots = await Future.wait([
    for (final (start, end) in geohashQueryBounds(lat, lng, radiusMeters))
      pins.orderBy('geoHash').startAt([start]).endAt([end]).get(),
  ]);
  var docs = [for (final snap in snapshots) ...snap.docs];

  if (docs.isEmpty) {
    // One degree of latitude is ~111 km.
    final band = radiusMeters / 111000 + 0.001;
    final snap = await pins
        .where('lat', isGreaterThanOrEqualTo: lat - band)
        .where('lat', isLessThanOrEqualTo: lat + band)
        .limit(300)
        .get();
    docs = snap.docs;
  }

  final seen = <String>{};
  return [
    for (final doc in docs)
      if (seen.add(doc.id) && _within(doc.data(), lat, lng, radiusMeters)) doc,
  ];
}

bool _within(Map<String, dynamic> data, double lat, double lng, double radius) {
  final pLat = (data['lat'] as num?)?.toDouble();
  final pLng = (data['lng'] as num?)?.toDouble();
  if (pLat == null || pLng == null) return false;
  return distanceInMeters(lat, lng, pLat, pLng) <= radius;
}
