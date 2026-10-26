import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/tour_group/domain/models/itinerary_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/destination_catalog.dart';
import 'package:bhromon/features/tour_group/domain/services/route_engine.dart';
import 'package:bhromon/features/tour_group/domain/services/route_suggestions.dart';

TourGroup _tour({
  List<TourStop> stops = const [],
  Map<String, LegPlan> legPlans = const {},
  bool returnHome = true,
  String origin = 'Dhaka',
  String destination = "Cox's Bazar",
}) =>
    TourGroup(
      id: 't1',
      name: 'Family trip',
      destination: destination,
      originCity: origin,
      ownerEmail: 'o@x.com',
      inviteCode: 'ABCDEFGH',
      startDate: DateTime(2026, 12, 20),
      endDate: DateTime(2026, 12, 26),
      createdAt: DateTime(2026, 10, 1),
      stops: stops,
      legPlans: legPlans,
      returnHome: returnHome,
    );

TourStop _stop(String id, String name, int fromDay, int toDay,
        {TourType kind = TourType.custom}) =>
    TourStop(
      id: id,
      name: name,
      kind: kind,
      arrive: DateTime(2026, 12, fromDay),
      leave: DateTime(2026, 12, toDay),
    );

void main() {
  group('itinerary', () {
    test('a tour made before itineraries becomes one stop for the whole trip',
        () {
      final t = _tour();
      expect(t.effectiveStops, hasLength(1));
      expect(t.effectiveStops.single.name, "Cox's Bazar");
      expect(t.effectiveStops.single.nights, 6);
      expect(t.routeLegKeys, ['origin>main', 'main>origin']);
    });

    test('several stops make a leg each, plus the way home', () {
      final t = _tour(stops: [
        _stop('a', "Cox's Bazar", 20, 22),
        _stop('b', "Saint Martin's Island", 22, 24),
        _stop('c', 'Bandarban', 24, 26),
      ]);
      expect(t.destinationSummary,
          "Cox's Bazar → Saint Martin's Island → Bandarban");
      expect(t.routeLegKeys, ['origin>a', 'a>b', 'b>c', 'c>origin']);
      expect(_tour(stops: t.stops, returnHome: false).routeLegKeys,
          ['origin>a', 'a>b', 'b>c']);
      expect(t.stopOn(DateTime(2026, 12, 23, 15))!.id, 'b');
      expect(t.stopOn(DateTime(2026, 12, 28)), isNull);
    });

    test('stops, leg plans and the way home survive a save and load', () {
      final t = _tour(
        stops: [_stop('a', 'Sylhet', 20, 23, kind: TourType.nature)],
        legPlans: {
          'origin>a': LegPlan(
            mode: TransportMode.rail,
            distanceKm: 240,
            departAt: DateTime(2026, 12, 20, 6, 40),
            departedAt: DateTime(2026, 12, 20, 6, 50),
            notes: 'Parabat Express',
          ),
        },
        returnHome: false,
      );
      final back = TourGroup.fromMap('t1', t.toMap());
      expect(back.stops.single.kind, TourType.nature);
      expect(back.stops.single.nights, 3);
      final leg = back.legPlans['origin>a']!;
      expect(leg.mode, TransportMode.rail);
      expect(leg.distanceKm, 240);
      expect(leg.departedAt, DateTime(2026, 12, 20, 6, 50));
      expect(leg.notes, 'Parabat Express');
      expect(back.returnHome, isFalse);
    });

    test('suggested spots cover every stop', () {
      final t = _tour(stops: [
        _stop('a', "Cox's Bazar", 20, 22),
        _stop('b', 'Bandarban', 22, 24),
      ]);
      expect(t.allSpots.any((s) => s.contains('Himchari')), isTrue);
      expect(t.allSpots.any((s) => s.contains('Nilgiri')), isTrue);
    });
  });

  group('catalog', () {
    test('typed names find their place, the longest match first', () {
      expect(presetForName('ঢাকা')!.id, 'dhaka');
      expect(presetForName("Cox's Bazar")!.id, 'coxs_bazar');
      expect(presetForName('Old Dhaka')!.id, 'puran_dhaka');
      expect(presetForName('St Martin')!.id, 'saint_martin');
      expect(presetForName('Mars'), isNull);
    });

    test('every entry has a unique id and a place in Bangladesh', () {
      final ids = kDestinationCatalog.map((p) => p.id).toSet();
      expect(ids.length, kDestinationCatalog.length);
      for (final p in kDestinationCatalog) {
        expect(p.lat, inInclusiveRange(20.5, 26.7), reason: p.id);
        expect(p.lng, inInclusiveRange(88.0, 92.7), reason: p.id);
      }
    });
  });

  group('route', () {
    test('distances are estimated from coordinates, or taken as typed', () {
      final plan =
          RoutePlan.of(_tour(stops: [_stop('a', "Cox's Bazar", 20, 26)]));
      final out = plan.legs.first;
      // Dhaka to Cox's Bazar is about 400 km by road.
      expect(out.km, inInclusiveRange(360, 460));
      expect(out.isEstimated, isTrue);
      expect(out.estimatedDuration!.inHours, inInclusiveRange(7, 11));

      final typed = RoutePlan.of(_tour(
        stops: [_stop('a', "Cox's Bazar", 20, 26)],
        legPlans: {'origin>a': const LegPlan(distanceKm: 395)},
      ));
      expect(typed.legs.first.km, 395);
      expect(typed.legs.first.isEstimated, isFalse);
    });

    test('a flight is quicker but carries airport time', () {
      final plan = RoutePlan.of(_tour(
        stops: [_stop('a', "Cox's Bazar", 20, 26)],
        legPlans: {'origin>a': const LegPlan(mode: TransportMode.air)},
      ));
      final d = plan.legs.first.estimatedDuration!;
      expect(d.inMinutes, greaterThan(90));
      expect(d.inMinutes, lessThan(200));
    });

    test('an unknown place has no distance, and the route still builds', () {
      final plan =
          RoutePlan.of(_tour(stops: [_stop('a', 'Grandma village', 20, 26)]));
      expect(plan.legs.first.km, isNull);
      expect(plan.totalKm, 0);
    });

    test('progress follows the legs an admin has marked', () {
      final plan = RoutePlan.of(_tour(
        stops: [
          _stop('a', "Cox's Bazar", 20, 22),
          _stop('b', 'Bandarban', 22, 26)
        ],
        legPlans: {
          'origin>a': LegPlan(
              departedAt: DateTime(2026, 12, 20, 22),
              arrivedAt: DateTime(2026, 12, 21, 7)),
          'a>b': LegPlan(departedAt: DateTime(2026, 12, 22, 9)),
        },
      ));
      expect(plan.legs[0].status, LegStatus.done);
      expect(plan.currentLeg!.key, 'a>b');
      expect(plan.nextLeg!.key, 'b>origin');
      expect(plan.progress, closeTo(1 / 3, 0.001));
      expect(plan.currentLeg!.eta, isNotNull);
      expect(plan.isFinished, isFalse);
    });

    test('a GPS fix halfway along the leg reads about halfway', () {
      final plan = RoutePlan.of(_tour(
        stops: [_stop('a', 'Sylhet', 20, 26)],
        legPlans: {'origin>a': LegPlan(departedAt: DateTime(2026, 12, 20, 6))},
      ));
      final dhaka = presetById('dhaka')!, sylhet = presetById('sylhet')!;
      final live = plan.locate((dhaka.lat + sylhet.lat) / 2,
          (dhaka.lng + sylhet.lng) / 2, DateTime(2026, 12, 20, 9))!;
      expect(live.fraction, closeTo(0.5, 0.05));
      expect(live.kmToNext, inInclusiveRange(80, 160));
      expect(live.eta.isAfter(DateTime(2026, 12, 20, 9)), isTrue);
    });

    test('directions link every stop in order', () {
      final plan = RoutePlan.of(_tour(stops: [
        _stop('a', "Cox's Bazar", 20, 22),
        _stop('b', 'Bandarban', 22, 26),
      ]));
      final uri = plan.directionsUri!;
      expect(uri.queryParameters['origin'], startsWith('23.81'));
      expect(uri.queryParameters['waypoints']!.split('|'), hasLength(2));
      expect(uri.queryParameters['destination'], startsWith('23.81'));
    });

    test('stop suggestions appear only for road legs out of Dhaka', () {
      final fromDhaka =
          RoutePlan.of(_tour(stops: [_stop('a', 'Sajek Valley', 20, 26)]));
      expect(
          suggestedStopsFor(fromDhaka.legs.first, toPresetId: 'sajek')
              .any((s) => s.name.contains('Dighinala')),
          isTrue);
      final fromRangpur = RoutePlan.of(_tour(
          origin: 'Rangpur', stops: [_stop('a', 'Sajek Valley', 20, 26)]));
      expect(suggestedStopsFor(fromRangpur.legs.first, toPresetId: 'sajek'),
          isEmpty);
    });

    test('a nearby search names the place and the position', () {
      final uri = nearbySearchUri('hospital', lat: 21.4, lng: 92.0);
      expect(uri.queryParameters['query'], 'hospital near 21.4,92.0');
      expect(
          nearbySearchUri('police').queryParameters['query'], 'police near me');
    });
  });
}
