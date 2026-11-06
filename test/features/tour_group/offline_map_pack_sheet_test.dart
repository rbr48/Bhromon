import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/map/offline_map_pack_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('bhromon_map_sheet_test');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Widget buildTestWidget() {
    return const MaterialApp(
      locale: Locale('en'),
      supportedLocales: [Locale('en'), Locale('bn')],
      localizationsDelegates: [
        AppLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: Scaffold(
        body: OfflineMapPackSheet(),
      ),
    );
  }

  testWidgets(
      'renders OfflineMapPackSheet with curated regions and filter chips',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('Offline Map Packs'), findsOneWidget);
    expect(find.text('All Regions'), findsOneWidget);
    expect(find.text('Sajek Valley & Ruilui'), findsOneWidget);

    // Expand region details
    await tester.tap(find.text('Sajek Valley & Ruilui'));
    await tester.pumpAndSettle();

    expect(find.text('Emergency Helplines:'), findsOneWidget);
    expect(find.text('Offline Waypoints:'), findsOneWidget);
    expect(find.text('Open Interactive Offline Map'), findsOneWidget);
  });

  testWidgets('filters regions by division when chip is tapped',
      (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Tap Sylhet filter chip
    await tester.tap(find.text('Sylhet'));
    await tester.pumpAndSettle();

    expect(find.text('Tanguar Haor & Tekerghat'), findsOneWidget);
    expect(find.text('Sajek Valley & Ruilui'), findsNothing);
  });
}
