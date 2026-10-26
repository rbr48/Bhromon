import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/widgets/journey_timeline.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  final entries = [
    JourneyEntry(
      tripId: 'a',
      destination: 'Sajek',
      district: 'Rangamati',
      date: DateTime(2026, 3, 7),
      tripDays: 3,
      totalSpent: 4500,
    ),
    JourneyEntry(
      tripId: 'b',
      destination: 'Sundarbans',
      district: 'Khulna',
      date: DateTime(2025, 12, 20),
      totalSpent: 9000,
    ),
  ];

  testWidgets('shows each trip once, grouped by year', (tester) async {
    await tester.pumpWidget(wrap(JourneyTimelineWidget(entries: entries)));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Sajek'), findsWidgets);
    expect(find.textContaining('Sundarbans'), findsWidgets);
    expect(find.textContaining('2026'), findsWidgets);
    expect(find.textContaining('2025'), findsWidgets);
  });

  testWidgets('a single trip still lays out', (tester) async {
    await tester
        .pumpWidget(wrap(JourneyTimelineWidget(entries: [entries.first])));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Sajek'), findsWidgets);
    expect(find.textContaining('Sundarbans'), findsNothing);
  });

  testWidgets('an empty journey renders without error', (tester) async {
    await tester.pumpWidget(wrap(const JourneyTimelineWidget(entries: [])));

    expect(tester.takeException(), isNull);
  });
}
