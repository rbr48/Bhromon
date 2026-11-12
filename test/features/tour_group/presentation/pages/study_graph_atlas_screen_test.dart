import 'dart:convert';

import 'package:bhromon/features/tour_group/presentation/pages/study_graph_atlas_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mockAtlasJson = '''[
    {
      "id": "poe_96th_English_1",
      "index": 1,
      "exam": "96th",
      "examLabel": "96th BPE (May 2023)",
      "language": "English",
      "title": "Production Possibility Curve (PPC)",
      "subtitle": "Scarcity & Opportunity Cost",
      "headerText": "PPC Header",
      "svg": "<svg xmlns=\\"http://www.w3.org/2000/svg\\" viewBox=\\"0 0 100 100\\"><circle cx=\\"50\\" cy=\\"50\\" r=\\"40\\"/></svg>"
    },
    {
      "id": "poe_5th_Bangla_2",
      "index": 2,
      "exam": "5th",
      "examLabel": "5th New BPE (Apr 2025)",
      "language": "Bangla",
      "title": "নিরপেক্ষ রেখা (Indifference Curve)",
      "subtitle": "ভোক্তার পছন্দের ধারাবাহিকতা",
      "headerText": "IC Header",
      "svg": "<svg xmlns=\\"http://www.w3.org/2000/svg\\" viewBox=\\"0 0 100 100\\"><rect width=\\"100\\" height=\\"100\\"/></svg>"
    }
  ]''';

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        if (key == 'assets/study/poe_graph_atlas.json') {
          final bytes = utf8.encode(mockAtlasJson);
          return ByteData.view(Uint8List.fromList(bytes).buffer);
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  testWidgets('StudyGraphAtlasScreen renders items and filter chips',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StudyGraphAtlasScreen(tourId: 'test_tour'),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Dynamic SVG Graph Atlas'), findsOneWidget);
    expect(find.text('All Exams (সব পরীক্ষা)'), findsOneWidget);
    expect(find.text('96th BPE (May 2023)'), findsWidgets);
    expect(find.text('Production Possibility Curve (PPC)'), findsOneWidget);

    // Drag down to reveal second card
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('নিরপেক্ষ রেখা (Indifference Curve)'), findsOneWidget);

    // Search filtering
    await tester.enterText(find.byType(TextField), 'PPC');
    await tester.pumpAndSettle();

    expect(find.text('Production Possibility Curve (PPC)'), findsOneWidget);
    expect(find.text('নিরপেক্ষ রেখা (Indifference Curve)'), findsNothing);
  });
}
