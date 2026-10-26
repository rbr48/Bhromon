import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/tour_group/presentation/widgets/instafeed/tour_safe_network_image.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: child),
      );

  group('TourSafeNetworkImage', () {
    testWidgets('shows invalid URL error UI on blank url', (tester) async {
      await tester.pumpWidget(
        wrap(const TourSafeNetworkImage(imageUrl: '')),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(find.text('Invalid image link'), findsOneWidget);
    });

    testWidgets('shows invalid URL error UI on non-http local path',
        (tester) async {
      await tester.pumpWidget(
        wrap(
            const TourSafeNetworkImage(imageUrl: '/data/user/0/app/cache.jpg')),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(find.text('Invalid image link'), findsOneWidget);
    });

    testWidgets('renders custom error widget when provided on invalid url',
        (tester) async {
      await tester.pumpWidget(
        wrap(const TourSafeNetworkImage(
          imageUrl: '',
          errorWidget: Text('Custom Error Widget'),
        )),
      );
      await tester.pumpAndSettle();

      expect(find.text('Custom Error Widget'), findsOneWidget);
    });

    testWidgets('renders placeholder for remote url', (tester) async {
      await tester.pumpWidget(
        wrap(const TourSafeNetworkImage(
          imageUrl: 'https://bhromon.fun/media/tour1/posts/image.jpg',
          placeholder: Text('Custom Loading...'),
        )),
      );

      expect(find.text('Custom Loading...'), findsOneWidget);
    });
  });
}
