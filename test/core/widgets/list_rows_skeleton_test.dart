import 'package:bhromon/core/widgets/skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fits a short space without overflowing', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(height: 120, child: ListRowsSkeleton()),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.byType(SkeletonBox), findsWidgets);
  });

  testWidgets('is announced as loading, not as its shapes', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ListRowsSkeleton(count: 2)),
    ));

    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    handle.dispose();
  });
}
