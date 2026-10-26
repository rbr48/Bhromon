import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/widgets/skeleton.dart';

void main() {
  // The shimmer repeats forever, so the tests pump frames instead of settling.
  // The skeletons sit in scrolling lists in the app; the test does the same.
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  testWidgets('a feed skeleton shows the requested number of cards',
      (tester) async {
    await tester.pumpWidget(wrap(const FeedListSkeleton(count: 2)));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    expect(find.byType(FeedCardSkeleton), findsNWidgets(2));
  });

  testWidgets('the default feed skeleton shows three cards', (tester) async {
    await tester.pumpWidget(wrap(const FeedListSkeleton()));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(FeedCardSkeleton), findsNWidgets(3));
  });

  testWidgets('a single feed card builds', (tester) async {
    await tester.pumpWidget(wrap(const FeedCardSkeleton()));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    expect(find.byType(SkeletonBox), findsWidgets);
  });

  testWidgets('a row of cards, a panel and a box build with their sizes',
      (tester) async {
    await tester.pumpWidget(wrap(const Column(children: [
      HorizontalCardsSkeleton(cardWidth: 120, cardHeight: 80),
      PanelSkeleton(),
      SkeletonBox(height: 20, width: 60, circle: true),
    ])));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    expect(find.byType(PanelSkeleton), findsOneWidget);
    final box = tester.widget<SkeletonBox>(find.byType(SkeletonBox).last);
    expect(box.height, 20);
    expect(box.width, 60);
    expect(box.circle, isTrue);
  });

  testWidgets('a shimmer keeps its child visible while it animates',
      (tester) async {
    await tester.pumpWidget(wrap(const Shimmer(child: Text('Loading'))));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Loading'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
