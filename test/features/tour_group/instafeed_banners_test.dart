import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/tour_group/domain/models/safety_alert_models.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/instafeed/instafeed_travel_banners.dart';

void main() {
  // The test app has no localization delegate, so the English labels show.
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  testWidgets('the tide banner reports taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrap(InstafeedTideBanner(onTap: () => taps++)));

    await tester.tap(find.byType(InstafeedTideBanner));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(taps, 1);
  });

  testWidgets('an SOS banner names the sender', (tester) async {
    await tester.pumpWidget(wrap(InstafeedSosBanner(
      tourId: 't1',
      alert: SafetyAlert(
        id: 'a1',
        senderEmail: 'rina@example.com',
        senderName: 'Rina',
        createdAt: DateTime(2026, 10, 25, 12),
        resolved: false,
      ),
    )));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Rina'), findsWidgets);
  });

  testWidgets('the member dialog shows seat, room and family size',
      (tester) async {
    await tester.pumpWidget(wrap(const InstafeedMemberLogisticsDialog(
      authorName: 'Rina',
      authorEmail: 'rina@example.com',
      seatNumber: '12C',
      roomNumber: '101',
      familyCount: 3,
    )));

    expect(tester.takeException(), isNull);
    expect(find.text('Seat 12C'), findsOneWidget);
    expect(find.text('Room 101'), findsOneWidget);
    expect(find.text('3 people'), findsOneWidget);
  });

  testWidgets('the member dialog says when nothing is assigned yet',
      (tester) async {
    await tester.pumpWidget(wrap(const InstafeedMemberLogisticsDialog(
      authorName: 'Babu',
      authorEmail: 'babu@example.com',
    )));

    expect(tester.takeException(), isNull);
    expect(find.text('Not assigned'), findsWidgets);
  });
}
