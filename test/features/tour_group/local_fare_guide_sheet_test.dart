import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/transport/local_fare_guide_sheet.dart';

void main() {
  Widget wrapSheet(Widget sheet) {
    return MaterialApp(
      home: Scaffold(
        body: sheet,
      ),
    );
  }

  testWidgets('LocalFareGuideSheet renders header, stepper and route list',
      (tester) async {
    await tester.pumpWidget(wrapSheet(
      const LocalFareGuideSheet(initialPassengers: 4),
    ));
    await tester.pumpAndSettle();

    expect(find.text('লোকাল পরিবহন ভাড়া গাইড'), findsOneWidget);
    expect(find.text('ভ্রমণকারী যাত্রী সংখ্যা'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('সব অঞ্চল'), findsOneWidget);
    expect(find.text('চট্টগ্রাম ও পাহাড়ি অঞ্চল'), findsOneWidget);
  });

  testWidgets('LocalFareGuideSheet increments and decrements passengers',
      (tester) async {
    await tester.pumpWidget(wrapSheet(
      const LocalFareGuideSheet(initialPassengers: 2),
    ));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);

    // Tap plus
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);

    // Tap minus
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('LocalFareGuideSheet filters by search query', (tester) async {
    await tester.pumpWidget(wrapSheet(
      const LocalFareGuideSheet(initialPassengers: 5),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'সাজেক');
    await tester.pumpAndSettle();

    expect(find.textContaining('সাজেক'), findsWidgets);
  });
}
