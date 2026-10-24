import '../../../../core/entities/location_pin.dart';

/// How eagerly the map tracks the device location.
enum MapTrackingMode { stationary, moving, fast }

/// Picks the tracking mode for a GPS fix moving at [speedMps] metres/second.
///
/// The thresholds overlap (hysteresis): a mode is entered above one speed
/// and left only below a lower one. With a single cut-off, GPS speed noise
/// near the boundary flips the mode on every fix, and each flip restarts the
/// location stream.
MapTrackingMode nextTrackingMode(MapTrackingMode current, double speedMps) {
  if (speedMps.isNaN || speedMps < 0) return current;
  switch (current) {
    case MapTrackingMode.stationary:
      if (speedMps >= 9.0) return MapTrackingMode.fast;
      if (speedMps >= 1.5) return MapTrackingMode.moving;
      return MapTrackingMode.stationary;
    case MapTrackingMode.moving:
      if (speedMps >= 9.0) return MapTrackingMode.fast;
      if (speedMps < 0.6) return MapTrackingMode.stationary;
      return MapTrackingMode.moving;
    case MapTrackingMode.fast:
      if (speedMps < 0.6) return MapTrackingMode.stationary;
      if (speedMps < 7.0) return MapTrackingMode.moving;
      return MapTrackingMode.fast;
  }
}

/// A lat/lng rectangle (degrees).
class GeoBounds {
  final double south;
  final double west;
  final double north;
  final double east;

  const GeoBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  /// These bounds grown by [fraction] of their size on every side, so small
  /// pans don't change which pins are drawn.
  GeoBounds expandedBy(double fraction) {
    final latPad = (north - south) * fraction;
    final lngPad = (east - west) * fraction;
    return GeoBounds(
      south: south - latPad,
      west: west - lngPad,
      north: north + latPad,
      east: east + lngPad,
    );
  }

  bool contains(double lat, double lng) =>
      lat >= south && lat <= north && lng >= west && lng <= east;
}

/// The pins inside [bounds]; all of [pins] when [bounds] is null.
List<LocationPin> pinsInBounds(List<LocationPin> pins, GeoBounds? bounds) {
  if (bounds == null) return pins;
  return [
    for (final pin in pins)
      if (bounds.contains(pin.lat, pin.lng)) pin,
  ];
}

/// Pins drawn as one marker.
class PinCluster {
  final double lat;
  final double lng;
  final List<LocationPin> pins;

  const PinCluster(this.lat, this.lng, this.pins);
}

/// Groups [pins] that fall in the same grid cell at [zoom].
///
/// One pass with a hash map: O(pins). The previous approach compared each
/// pin with every cluster found so far, O(pins x clusters), on every camera
/// idle.
List<PinCluster> clusterPins(List<LocationPin> pins, double zoom) {
  // Same scale as before: cells shrink as the map zooms in.
  final cell = 1.2 / (zoom < 1 ? 1 : zoom);
  final cells = <(int, int), List<LocationPin>>{};
  for (final pin in pins) {
    final key = ((pin.lat / cell).floor(), (pin.lng / cell).floor());
    (cells[key] ??= []).add(pin);
  }
  return [
    for (final members in cells.values)
      PinCluster(
        members.fold<double>(0, (sum, p) => sum + p.lat) / members.length,
        members.fold<double>(0, (sum, p) => sum + p.lng) / members.length,
        members,
      ),
  ];
}
