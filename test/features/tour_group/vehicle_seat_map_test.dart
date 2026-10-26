import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/tour_group/domain/models/logistics_models.dart';
import 'package:bhromon/features/tour_group/domain/models/vehicle_models.dart';
import 'package:bhromon/features/tour_group/domain/services/seat_layout_engine.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/transport/vehicle_seat_map.dart';

Future<void> _pump(
  WidgetTester tester,
  VehicleLayout layout, {
  Map<String, BusSeat> seats = const {},
  String me = '',
  ValueChanged<String>? onTap,
  VehicleKind? kind,
  double width = 360,
}) {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: VehicleSeatMap(
          layout: layout,
          seats: seats,
          myEmail: me,
          kind: kind,
          onSeatTap: onTap ?? (_) {},
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('every vehicle kind draws on a phone without overflowing',
      (tester) async {
    for (final kind in VehicleKind.values) {
      final v = TourVehicle.create(
          id: 'v', kind: kind, name: kind.name, now: DateTime(2026));
      await _pump(tester, buildLayout(v), kind: kind);
      expect(tester.takeException(), isNull, reason: kind.name);
    }
    await _pump(tester, legacyCoachLayout());
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a seat reports its id', (tester) async {
    String? tapped;
    await _pump(tester, legacyCoachLayout(), onTap: (id) => tapped = id);
    await tester.tap(find.text('B3'));
    expect(tapped, 'B3');
  });

  testWidgets('taken seats show the member, and family seats show +n',
      (tester) async {
    await _pump(
      tester,
      legacyCoachLayout(),
      me: 'Rina@x.com',
      seats: {
        'A1': const BusSeat(
            seatNumber: 'A1',
            assignedMemberEmail: 'rina@x.com',
            assignedMemberName: 'Rina'),
        'A2': const BusSeat(
            seatNumber: 'A2',
            assignedMemberEmail: 'rina@x.com',
            assignedMemberName: 'Rina',
            familySlot: 1),
      },
    );
    expect(find.text('Rina'), findsOneWidget);
    expect(find.text('Rina +1'), findsOneWidget);
    expect(find.text('Free'), findsNWidgets(34));
  });

  testWidgets('a wide coach fits a tablet without a sideways scroll',
      (tester) async {
    final v = TourVehicle.create(
        id: 'v', kind: VehicleKind.bus, name: 'Bus', now: DateTime(2026));
    await _pump(tester, buildLayout(v), width: 800);
    expect(
        find.byWidgetPredicate((w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal),
        findsNothing);
  });
}
