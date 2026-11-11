import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/instafeed/instafeed_carousel.dart';

Widget _wrap(Widget child, {Locale locale = const Locale('bn')}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 500,
          height: 500,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  group('InstafeedCarousel desktop navigation', () {
    const singleImage = ['https://bhromon.fun/media/tour1/posts/image1.jpg'];
    const multiImages = [
      'https://bhromon.fun/media/tour1/posts/image1.jpg',
      'https://bhromon.fun/media/tour1/posts/image2.jpg',
      'https://bhromon.fun/media/tour1/posts/image3.jpg',
    ];

    testWidgets('single image does not show navigation buttons or index badge',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const InstafeedCarousel(imageUrls: singleImage)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('carousel_prev_button')), findsNothing);
      expect(find.byKey(const ValueKey('carousel_next_button')), findsNothing);
      expect(find.text('1/1'), findsNothing);
    });

    testWidgets(
        'multi-image starts on slide 1 showing next button only and 1/3 badge',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const InstafeedCarousel(imageUrls: multiImages)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // On first image:
      expect(find.text('1/3'), findsOneWidget);
      expect(find.byKey(const ValueKey('carousel_prev_button')), findsNothing);
      expect(
          find.byKey(const ValueKey('carousel_next_button')), findsOneWidget);
    });

    testWidgets('tapping next and prev buttons navigates through slides',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const InstafeedCarousel(imageUrls: multiImages)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // 1. Advance to slide 2
      await tester.tap(find.byKey(const ValueKey('carousel_next_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('2/3'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('carousel_prev_button')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('carousel_next_button')), findsOneWidget);

      // 2. Advance to slide 3 (last slide)
      await tester.tap(find.byKey(const ValueKey('carousel_next_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('3/3'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('carousel_prev_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('carousel_next_button')), findsNothing);

      // 3. Go back to slide 2
      await tester.tap(find.byKey(const ValueKey('carousel_prev_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('2/3'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('carousel_prev_button')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('carousel_next_button')), findsOneWidget);
    });

    testWidgets('tapping pagination dot jumps directly to that slide',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const InstafeedCarousel(imageUrls: multiImages)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('1/3'), findsOneWidget);

      // Tap on the 3rd dot indicator
      final dots = find.byType(AnimatedContainer);
      expect(dots, findsWidgets);

      // In the dot row, find the last dot
      final lastDot = dots.at(dots.evaluate().length - 1);
      await tester.tap(lastDot);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('3/3'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('carousel_prev_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('carousel_next_button')), findsNothing);
    });

    testWidgets('tapping fullscreen icon calls onImageTap callback with index',
        (tester) async {
      int? tappedIndex;

      await tester.pumpWidget(
        _wrap(InstafeedCarousel(
          imageUrls: multiImages,
          onImageTap: (idx) => tappedIndex = idx,
        )),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Advance to slide 2
      await tester.tap(find.byKey(const ValueKey('carousel_next_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Tap fullscreen button
      await tester.tap(find.byIcon(Icons.fullscreen_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tappedIndex, equals(1));
    });
  });
}
