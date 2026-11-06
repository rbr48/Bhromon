import '../models/tour_group.dart';
import 'hub_alert_engine.dart';
import 'journey_geometry.dart';
import 'route_engine.dart';

/// The default approach notices for a stop (roadmap D-6): 5 km and 1 km.
const List<double> kHubApproachM = [5000, 1000];

/// The default approach notices for the final destination (roadmap D-6).
const List<double> kDestinationApproachM = [10000, 3000, 1000];

/// The arrival radius of a stop (roadmap D-6).
const double kStopArriveM = 1000;

/// The arrival radius of the final destination (roadmap D-6).
const double kDestinationArriveM = 500;

/// What a live journey watches on one trip: the route, the hubs and the final
/// destination (roadmap product rules 4 to 7 and 12).
class JourneyTargets {
  const JourneyTargets({
    required this.route,
    required this.stops,
    required this.destination,
  });

  /// Nothing to watch: no stop of the outbound trip has coordinates.
  static const JourneyTargets none =
      JourneyTargets(route: null, stops: [], destination: null);

  /// The outbound route as straight segments, from the origin through each
  /// located stop to the final destination. Null when it has fewer than two
  /// points.
  final RoutePolyline? route;

  /// The hubs with approach and arrival notices, in trip order. Excludes the
  /// final destination.
  final List<AlertTarget> stops;

  /// The final destination: the last outbound stop with coordinates. Null when
  /// no stop has them.
  final AlertTarget? destination;

  bool get isEmpty => stops.isEmpty && destination == null;
}

/// The targets for [group]. The wake-up destination is the last stop of the
/// outbound trip, not the home a route may return to (rule 12). A stop without
/// coordinates is left out, because the group cannot be placed near it.
///
/// [hubApproachM] and [destinationApproachM] are the approach notices in metres,
/// from the user's alarm settings.
JourneyTargets journeyTargetsFor(
  TourGroup group, {
  List<double> hubApproachM = kHubApproachM,
  List<double> destinationApproachM = kDestinationApproachM,
}) {
  final points = RoutePlan.of(group).points;
  // With "return home", the last point is the origin again. The trip watched
  // here ends at the last outbound stop.
  final outbound = group.returnHome && points.length > 1
      ? points.sublist(0, points.length - 1)
      : points;
  final located = [
    for (final p in outbound)
      if (p.hasLocation) p,
  ];
  final stopPoints = [
    for (final p in located)
      if (!p.isOrigin) p,
  ];
  if (stopPoints.isEmpty) return JourneyTargets.none;

  AlertTarget target(
    RoutePoint p,
    AlertTargetKind kind,
    List<double> approach,
    double arrive,
  ) {
    return AlertTarget(
      id: p.id,
      name: p.name,
      point: GeoPoint(p.lat!, p.lng!),
      kind: kind,
      approachThresholdsM: approach,
      arriveRadiusM: arrive,
    );
  }

  final destination = target(
    stopPoints.last,
    AlertTargetKind.finalDestination,
    destinationApproachM,
    kDestinationArriveM,
  );
  final stops = [
    for (final p in stopPoints.take(stopPoints.length - 1))
      target(p, AlertTargetKind.stop, hubApproachM, kStopArriveM),
  ];
  final route = RoutePolyline([
    for (final p in located) GeoPoint(p.lat!, p.lng!),
  ]);
  return JourneyTargets(
    route: route.isUsable ? route : null,
    stops: stops,
    destination: destination,
  );
}

/// The planned arrival at the final destination, from the route plan's leg
/// that ends there. Null when the plan has no time for that leg. It is the
/// time alarm's ETA before the first GPS reading (rule 8).
DateTime? plannedArrivalAt(TourGroup group) {
  final destination = journeyTargetsFor(group).destination;
  if (destination == null) return null;
  for (final leg in RoutePlan.of(group).legs) {
    if (leg.to.id == destination.id) return leg.eta;
  }
  return null;
}
