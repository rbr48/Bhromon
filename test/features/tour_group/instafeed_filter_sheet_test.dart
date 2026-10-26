import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/instafeed/instafeed_filter_sheet.dart';

final _days = [
  TourDayInfo(
    id: 'day1',
    dayNumber: 1,
    date: DateTime(2026, 10, 25),
    label: 'ডে ১',
  ),
  TourDayInfo(
    id: 'day2',
    dayNumber: 2,
    date: DateTime(2026, 10, 26),
    label: 'ডে ২',
  ),
];

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('the bar shows the active filters and opens on tap',
      (tester) async {
    var opened = 0;
    await tester.pumpWidget(_wrap(InstafeedFilterBar(
      summary: 'ছবি (Photos) · ডে ১',
      onTap: () => opened++,
    )));

    expect(find.text('ছবি (Photos) · ডে ১'), findsOneWidget);
    await tester.tap(find.text('ছবি (Photos) · ডে ১'));
    expect(opened, 1);
  });

  testWidgets('a media choice is reported with its id', (tester) async {
    String? picked;
    await tester.pumpWidget(_wrap(InstafeedFilterSheet(
      selectedMedia: 'all',
      onMediaSelected: (id) => picked = id,
      days: const [],
      selectedDay: 'all',
      onDaySelected: (_) {},
    )));

    for (final option in instafeedMediaFilters) {
      expect(find.text(option.label), findsOneWidget);
    }
    await tester.tap(find.text(instafeedMediaFilters[1].label));
    expect(picked, 'photos');
  });

  testWidgets(
      'the day choices show and report their ids when the tour has days',
      (tester) async {
    String? picked;
    await tester.pumpWidget(_wrap(InstafeedFilterSheet(
      selectedMedia: 'all',
      onMediaSelected: (_) {},
      days: _days,
      selectedDay: 'all',
      onDaySelected: (id) => picked = id,
    )));

    expect(find.text('সব দিন'), findsOneWidget);
    await tester.tap(find.text('ডে ২'));
    expect(picked, 'day2');
  });

  testWidgets('the day section is left out when the tour has no days',
      (tester) async {
    await tester.pumpWidget(_wrap(InstafeedFilterSheet(
      selectedMedia: 'all',
      onMediaSelected: (_) {},
      days: const [],
      selectedDay: 'all',
      onDaySelected: (_) {},
    )));

    expect(find.text('দিন'), findsNothing);
    expect(find.text('সব দিন'), findsNothing);
  });
}
