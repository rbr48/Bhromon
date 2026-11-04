import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/tour_group/domain/services/journey_geometry.dart';
import 'package:bhromon/features/tour_group/domain/services/leg_suggestions.dart';

import 'live_journey_test_support.dart';

void main() {
  final start = kRouteA;
  final end = kRouteC;
  final t0 = DateTime.utc(2027, 1, 13, 8);

  LegSuggestion? depart(LegSuggestionEngine e, GeoPoint at, DateTime now) =>
      e.observe(
        legKey: 'origin>end',
        underway: false,
        from: start,
        to: end,
        at: at,
        now: now,
      );

  LegSuggestion? arrive(LegSuggestionEngine e, GeoPoint at, DateTime now) =>
      e.observe(
        legKey: 'origin>end',
        underway: true,
        from: start,
        to: end,
        at: at,
        now: now,
      );

  test('a planned leg is suggested as departed only after two stable minutes',
      () {
    final engine = LegSuggestionEngine();
    final away = eastOf(start, 3000);
    expect(depart(engine, away, t0), isNull);
    expect(depart(engine, away, t0.add(const Duration(minutes: 1))), isNull);
    final due = depart(engine, away, t0.add(const Duration(minutes: 2)));
    expect(due?.kind, LegSuggestionKind.depart);
    expect(due?.legKey, 'origin>end');
  });

  test('a single stray reading far from the start raises nothing', () {
    final engine = LegSuggestionEngine();
    expect(depart(engine, eastOf(start, 3000), t0), isNull);
    // Back at the start, so the candidate is dropped.
    expect(depart(engine, start, t0.add(const Duration(minutes: 1))), isNull);
    expect(
        depart(engine, eastOf(start, 3000), t0.add(const Duration(minutes: 2))),
        isNull,
        reason: 'the wait starts again');
    expect(
        depart(engine, eastOf(start, 3000), t0.add(const Duration(minutes: 4))),
        isNotNull);
  });

  test('an underway leg is suggested as arrived once the group is at its end',
      () {
    final engine = LegSuggestionEngine();
    final near = eastOf(end, -300);
    expect(arrive(engine, near, t0), isNull);
    final due = arrive(engine, near, t0.add(const Duration(minutes: 2)));
    expect(due?.kind, LegSuggestionKind.arrive);
  });

  test('each suggestion is raised once for its leg', () {
    final engine = LegSuggestionEngine();
    final away = eastOf(start, 3000);
    depart(engine, away, t0);
    expect(depart(engine, away, t0.add(const Duration(minutes: 2))), isNotNull);
    expect(depart(engine, away, t0.add(const Duration(minutes: 9))), isNull);
  });

  test('a leg with no place to measure from raises nothing', () {
    final engine = LegSuggestionEngine();
    final result = engine.observe(
      legKey: 'origin>end',
      underway: false,
      from: null,
      to: end,
      at: eastOf(start, 9000),
      now: t0,
    );
    expect(result, isNull);
  });
}
