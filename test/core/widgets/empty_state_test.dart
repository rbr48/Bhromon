import 'package:bhromon/core/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the message and fits a short space', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 80,
          child: EmptyState(icon: Icons.inbox_outlined, message: 'No books'),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.text('No books'), findsOneWidget);
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
  });
}
