import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/core/widgets/privacy_toggle.dart';
import 'package:bhromon/core/widgets/weather_stamp_widget.dart';
import 'package:bhromon/core/widgets/diary_quality_ring.dart';
import 'package:bhromon/core/value_objects/diary_visibility.dart';
import 'package:bhromon/core/value_objects/weather_snapshot.dart';
import 'package:bhromon/core/services/trip_log_quality_scorer.dart';

void main() {
  group('PrivacyToggleWidget Smoke Tests', () {
    testWidgets('renders and handles taps correctly', (tester) async {
      DiaryVisibility selected = DiaryVisibility.private;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrivacyToggleWidget(
              current: selected,
              onChanged: (v) {
                selected = v;
              },
            ),
          ),
        ),
      );

      // Verify segments exist by checking display icons/labels
      expect(find.text('🔒'), findsOneWidget);
      expect(find.text('👥'), findsOneWidget);
      expect(find.text('🌍'), findsOneWidget);

      // Tap on community segment
      await tester.tap(find.text('🌍'));
      await tester.pumpAndSettle();

      expect(selected, DiaryVisibility.community);
    });
  });

  group('WeatherStampWidget Smoke Tests', () {
    testWidgets('renders weather info correctly', (tester) async {
      const weather = WeatherSnapshot(
        tempC: 28.4,
        emoji: '☀️',
        description: 'Clear sky',
        precipMm: 0.0,
        windKph: 12.0,
        weatherCode: 1000,
        isSafeToVisit: true,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WeatherStampWidget(
              weather: weather,
              compact: true,
            ),
          ),
        ),
      );

      expect(find.text('☀️'), findsOneWidget);
      expect(find.text('☀️ 28°C'), findsOneWidget);
    });
  });

  group('DiaryQualityRingWidget Smoke Tests', () {
    testWidgets('renders quality score grade correctly', (tester) async {
      const result = QualityResult(
        score: 85,
        tips: [],
        strengths: [],
        trustBonus: 0,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DiaryQualityRingWidget(
              result: result,
              size: 50,
            ),
          ),
        ),
      );

      // Check that grade label A is rendered
      expect(find.text('A'), findsOneWidget);
    });
  });
}
