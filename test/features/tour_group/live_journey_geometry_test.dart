import 'package:bhromon/features/tour_group/domain/services/journey_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('distanceM', () {
    test('Dhaka to Chattogram is about 214 km in a straight line', () {
      final d = distanceM(
        const GeoPoint(23.8103, 90.4125),
        const GeoPoint(22.3569, 91.7832),
      );
      expect(d / 1000, inInclusiveRange(210, 218));
    });

    test('is zero between the same point', () {
      expect(distanceM(const GeoPoint(23, 90), const GeoPoint(23, 90)), 0);
    });

    test('one degree of latitude is about 111.2 km', () {
      final d = distanceM(const GeoPoint(23, 90), const GeoPoint(24, 90));
      expect(d, closeTo(111195, 50));
    });
  });

  group('projectOntoSegment', () {
    const a = GeoPoint(0, 0);
    const b = GeoPoint(0, 1);

    test('a point beside the middle projects to the middle', () {
      final seg = projectOntoSegment(const GeoPoint(0.01, 0.5), a, b);
      expect(seg.t, closeTo(0.5, 1e-9));
      expect(seg.crossTrackM, closeTo(1111.95, 2));
    });

    test('a point past the end projects beyond 1 and measures to the end', () {
      final seg = projectOntoSegment(const GeoPoint(0, 2), a, b);
      expect(seg.t, closeTo(2, 1e-9));
      expect(seg.crossTrackM, closeTo(111195, 5));
    });

    test('a zero-length segment measures to its single point', () {
      final seg = projectOntoSegment(const GeoPoint(0.01, 0), a, a);
      expect(seg.t, 0);
      expect(seg.crossTrackM, closeTo(1111.95, 2));
    });
  });

  group('RoutePolyline', () {
    final route = RoutePolyline(const [
      GeoPoint(0, 0),
      GeoPoint(0, 0.5),
      GeoPoint(0, 1),
    ]);

    test('its length is the sum of its segments', () {
      expect(route.lengthM, closeTo(111195, 5));
      expect(route.alongOf(1), closeTo(55597, 3));
    });

    test('a point on the route projects to its place along it', () {
      final p = route.project(const GeoPoint(0, 0.25));
      expect(p.alongM, closeTo(27799, 5));
      expect(p.crossTrackM, closeTo(0, 1e-6));
      expect(p.pastEndM, 0);
    });

    test('a point past the end keeps counting and reports how far past', () {
      final p = route.project(const GeoPoint(0, 1.2));
      expect(p.pastEndM, closeTo(22239, 5));
      expect(p.alongM, closeTo(route.lengthM + 22239, 5));
    });

    test('a point before the start is clamped to zero along the route', () {
      final p = route.project(const GeoPoint(0, -0.3));
      expect(p.alongM, 0);
      expect(p.pastEndM, 0);
    });

    test('a route with one point is not usable', () {
      expect(RoutePolyline(const [GeoPoint(0, 0)]).isUsable, isFalse);
    });
  });
}
