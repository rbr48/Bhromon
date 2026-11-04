import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/mess/mess_balance_sheet.dart';

void main() {
  testWidgets('MessBalanceSheet renders header and month selector',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MessBalanceSheet(tourId: 'mock_mess_id'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('মেস মিল ও বাজার হিসাব বিবরণী'), findsOneWidget);
    expect(find.text('স্বয়ংক্রিয় মিল রেট ও ব্যালেন্স শিট'), findsOneWidget);
  });
}
