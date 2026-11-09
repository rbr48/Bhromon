import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/domain/models/itinerary_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_activity_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/offline_map_regions.dart';
import 'package:bhromon/features/tour_group/domain/services/route_engine.dart';
import 'package:bhromon/features/tour_group/presentation/pages/offline_map_viewer_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sajek =
      kCuratedOfflineRegions.firstWhere((r) => r.id == 'sajek_valley');

  Widget buildTestWidget({Locale locale = const Locale('en')}) {
    return MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: OfflineMapViewerScreen(
        region: sajek,
        initialPosition: Position(
          latitude: 23.3833,
          longitude: 92.2833,
          timestamp: DateTime.now(),
          accuracy: 5.0,
          altitude: 800.0,
          altitudeAccuracy: 5.0,
          heading: 0.0,
          headingAccuracy: 5.0,
          speed: 0.0,
          speedAccuracy: 0.0,
        ),
      ),
    );
  }

  testWidgets(
      'renders OfflineMapViewerScreen with header, offline badge, and waypoints',
      (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('Sajek Valley & Ruilui'), findsOneWidget);
    expect(find.textContaining('Chattogram · ~18 MB'), findsOneWidget);
    expect(find.text('Offline Pack Active'), findsOneWidget);

    // Waypoint chips in horizontal carousel
    expect(find.text('Ruilui Para (Main Center)'), findsOneWidget);
    expect(find.text('Konglak Peak Viewpoint'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('focuses waypoint and shows details card when chip is tapped',
      (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Tap Konglak Peak chip
    await tester.tap(find.text('Konglak Peak Viewpoint'));
    await tester.pumpAndSettle();

    expect(find.text('Directions'), findsOneWidget);
    expect(find.textContaining('23.4110° N, 92.2980° E'), findsOneWidget);

    // Close waypoint card
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Directions'), findsNothing);
  });

  testWidgets('opens emergency helplines sheet when helpline icon is tapped',
      (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Tap emergency phone icon in app bar
    await tester.tap(find.byIcon(Icons.phone_in_talk_rounded));
    await tester.pumpAndSettle();

    expect(find.textContaining('Emergency Helplines'), findsOneWidget);
    expect(find.text('Sajek Tourist Police'), findsOneWidget);
    expect(find.text('01320183277'), findsOneWidget);
    expect(find.text('Call'), findsWidgets);
  });

  testWidgets('switches to Radar View when radar toggle button is tapped',
      (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Tap Radar mode icon
    await tester.tap(find.byIcon(Icons.radar_rounded));
    await tester.pumpAndSettle();

    // Verify CustomPaint with radar canvas is rendered
    expect(find.byType(CustomPaint), findsWidgets);

    // Toggle back to map mode
    await tester.tap(find.byIcon(Icons.map_rounded));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'renders checkpoints and shows checkpoint details card when selected',
      (tester) async {
    const checkpoints = [
      RouteCheckpoint(
        id: 'cp1',
        name: 'Dighinala Army Camp',
        highlight: 'Army escort registration point',
        kmFromStart: 45,
        lat: 23.2500,
        lng: 92.0500,
        kind: CheckpointKind.checkpost,
      ),
      RouteCheckpoint(
        id: 'cp2',
        name: 'Bagaihat Bazar',
        highlight: 'Lunch and fresh fruits',
        kmFromStart: 62,
        lat: 23.3200,
        lng: 92.1800,
        kind: CheckpointKind.food,
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: OfflineMapViewerScreen(
        region: sajek,
        initialPosition: Position(
          latitude: 23.3833,
          longitude: 92.2833,
          timestamp: DateTime.now(),
          accuracy: 5.0,
          altitude: 800.0,
          altitudeAccuracy: 5.0,
          heading: 0.0,
          headingAccuracy: 5.0,
          speed: 0.0,
          speedAccuracy: 0.0,
        ),
        checkpoints: checkpoints,
      ),
    ));
    await tester.pumpAndSettle();

    // Verify toggle chips exist
    expect(find.textContaining('Waypoints'), findsOneWidget);
    expect(find.textContaining('Checkpoints (2)'), findsOneWidget);

    // Switch to Checkpoints
    await tester.tap(find.textContaining('Checkpoints (2)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('#1 Dighinala Army Camp'), findsOneWidget);
    expect(find.textContaining('#2 Bagaihat Bazar'), findsOneWidget);

    // Tap Checkpoint 1
    await tester.tap(find.textContaining('#1 Dighinala Army Camp'));
    await tester.pumpAndSettle();

    expect(find.textContaining('CHECKPOST · 45 km'), findsOneWidget);
    expect(find.text('Army escort registration point'), findsOneWidget);
    expect(find.text('Directions'), findsOneWidget);

    // Close card
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Army escort registration point'), findsNothing);
  });

  test('RoutePlan and RouteLeg export valid GeoJSON FeatureCollection', () {
    final group = TourGroup(
      id: 'tour_1',
      name: 'Bandarban Hill Trek',
      destination: 'Bandarban',
      originCity: 'Dhaka',
      ownerEmail: 'user@example.com',
      inviteCode: 'ABCDEFGH',
      startDate: DateTime(2026, 12, 1),
      endDate: DateTime(2026, 12, 5),
      createdAt: DateTime(2026, 11, 1),
      stops: [
        TourStop(
          id: 's1',
          name: 'Bandarban',
          arrive: DateTime(2026, 12, 1),
          leave: DateTime(2026, 12, 3),
        ),
        TourStop(
          id: 's2',
          name: 'Chittagong',
          arrive: DateTime(2026, 12, 3),
          leave: DateTime(2026, 12, 5),
        ),
      ],
      returnHome: true,
    );

    final plan = RoutePlan.of(group);
    final geoJson = plan.toGeoJson();

    expect(geoJson['type'], 'FeatureCollection');
    final features = geoJson['features'] as List;
    expect(features.length, greaterThanOrEqualTo(2));

    final first = features.first as Map<String, dynamic>;
    expect(first['type'], 'Feature');
    expect(first['geometry']['type'], 'LineString');
    expect(first['properties']['fromName'], isNotEmpty);
    expect(first['properties']['toName'], isNotEmpty);
    expect(first['properties']['color'], isNotEmpty);

    final jsonStr = plan.toGeoJsonString();
    expect(jsonStr, contains('"FeatureCollection"'));
  });

  test('RouteCheckpoint exports valid GeoJSON Point Feature', () {
    const cp = RouteCheckpoint(
      id: 'cp_test',
      name: 'Escort Gate',
      lat: 23.1234,
      lng: 92.5678,
      kind: CheckpointKind.checkpost,
      highlight: 'Mandatory army escort',
      kmFromStart: 50,
    );

    final feature = cp.toGeoJsonFeature(1);
    expect(feature, isNotNull);
    expect(feature!['type'], 'Feature');
    expect(feature['geometry']['type'], 'Point');
    expect(feature['geometry']['coordinates'], [92.5678, 23.1234]);
    expect(feature['properties']['name'], 'Escort Gate');
    expect(feature['properties']['sequence'], 1);
    expect(feature['properties']['kind'], 'checkpost');
    expect(feature['properties']['emoji'], '🛡️');
  });
}
