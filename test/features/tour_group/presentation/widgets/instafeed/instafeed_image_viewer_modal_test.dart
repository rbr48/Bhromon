import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/instafeed/instafeed_image_viewer_modal.dart';

class _FakeTourGroupRepo extends TourGroupRepository {
  @override
  String get currentEmail => 'traveler@bhromon.fun';

  @override
  String get currentDisplayName => 'Traveler';

  @override
  String? get currentPhotoUrl => null;

  @override
  Future<void> recordPostView({
    required String tourId,
    required String postId,
  }) async {}
}

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
    home: child,
  );
}

void main() {
  group('InstafeedImageViewerModal desktop navigation', () {
    final repo = _FakeTourGroupRepo();
    final now = DateTime(2026, 10, 27, 10, 30);

    final post = TourPostItem(
      id: 'post_modal_1',
      tourId: 'tour_cox',
      authorEmail: 'author@bhromon.fun',
      authorName: 'Author',
      authorPhoto: null,
      caption: 'Modal test caption',
      images: const [
        'https://bhromon.fun/media/tour1/posts/image1.jpg',
        'https://bhromon.fun/media/tour1/posts/image2.jpg',
        'https://bhromon.fun/media/tour1/posts/image3.jpg',
      ],
      createdAt: now,
      viewCount: 1,
      viewers: const ['traveler@bhromon.fun'],
    );

    testWidgets(
        'multi-image starts on slide 1 showing modal_next_button and 1 / 3 counter',
        (tester) async {
      await tester.pumpWidget(
        _wrap(InstafeedImageViewerModal(
          repository: repo,
          tourId: 'tour_cox',
          post: post,
        )),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.byKey(const ValueKey('modal_prev_button')), findsNothing);
      expect(find.byKey(const ValueKey('modal_next_button')), findsOneWidget);
    });

    testWidgets('clicking next button advances to next photo', (tester) async {
      await tester.pumpWidget(
        _wrap(InstafeedImageViewerModal(
          repository: repo,
          tourId: 'tour_cox',
          post: post,
        )),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('modal_next_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.byKey(const ValueKey('modal_prev_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('modal_next_button')), findsOneWidget);
    });

    testWidgets('keyboard arrow navigation moves between slides',
        (tester) async {
      await tester.pumpWidget(
        _wrap(InstafeedImageViewerModal(
          repository: repo,
          tourId: 'tour_cox',
          post: post,
        )),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Press Arrow Right key
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('2 / 3'), findsOneWidget);

      // Press Arrow Right key again
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('3 / 3'), findsOneWidget);
      expect(find.byKey(const ValueKey('modal_prev_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('modal_next_button')), findsNothing);

      // Press Arrow Left key to go back
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('2 / 3'), findsOneWidget);
    });
  });
}
