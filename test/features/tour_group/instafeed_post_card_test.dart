import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/instafeed/instafeed_post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTourGroupRepo extends TourGroupRepository {
  int viewWrites = 0;

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
  }) async {
    viewWrites++;
  }
}

Widget _wrap(Widget child,
    {Locale locale = const Locale('bn'),
    Brightness brightness = Brightness.light}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Theme(
      data: ThemeData(brightness: brightness),
      child: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    ),
  );
}

void main() {
  final repo = _FakeTourGroupRepo();
  final now = DateTime(2026, 10, 27, 10, 30);

  testWidgets('building a card does not record a view by itself',
      (tester) async {
    final counting = _FakeTourGroupRepo();
    final post = TourPostItem(
      id: 'post_202',
      tourId: 'tour_cox',
      authorEmail: 'author@bhromon.fun',
      authorName: 'Author',
      authorPhoto: null,
      caption: 'Built, not viewed',
      images: const ['https://example.com/unseen.jpg'],
      createdAt: now,
      viewCount: 0,
      viewers: const [],
    );

    await tester.pumpWidget(
      _wrap(
        InstafeedPostCard(
          repository: counting,
          tourId: 'tour_cox',
          post: post,
          isBookmarked: false,
          onBookmarkToggle: () {},
        ),
      ),
    );
    await tester.pump();

    expect(counting.viewWrites, 0);
  });

  testWidgets(
      'InstafeedPostCard renders clean metric row and does NOT show duplicate view count on timestamp row',
      (tester) async {
    final post = TourPostItem(
      id: 'post_101',
      tourId: 'tour_cox',
      authorEmail: 'author@bhromon.fun',
      authorName: 'Shakib Traveler',
      authorPhoto: null,
      caption: 'Sunset at Inani Beach #sunset #coxsbazar',
      images: const ['https://example.com/sunset.jpg'],
      createdAt: now,
      viewCount: 42,
      viewers: const ['user1@test.com', 'user2@test.com'],
      likes: const ['user1@test.com', 'traveler@bhromon.fun'],
    );

    await tester.pumpWidget(
      _wrap(
        InstafeedPostCard(
          repository: repo,
          tourId: 'tour_cox',
          post: post,
          isBookmarked: false,
          onBookmarkToggle: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 1. Author and Caption are displayed
    expect(find.text('Shakib Traveler'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) =>
          w is RichText &&
          w.text.toPlainText().contains('Sunset at Inani Beach')),
      findsOneWidget,
    );

    // 2. Primary metric row displays like and view counts
    expect(find.textContaining('বার দেখা হয়েছে'), findsOneWidget);

    // 3. Duplicate view badge (👁️) MUST NOT be present anywhere in the card
    expect(find.textContaining('👁️'), findsNothing);
  });

  testWidgets('InstafeedPostCard handles English locale metric row correctly',
      (tester) async {
    final post = TourPostItem(
      id: 'post_102',
      tourId: 'tour_cox',
      authorEmail: 'author@bhromon.fun',
      authorName: 'Sarah Explorer',
      authorPhoto: null,
      caption: 'Morning Tea in Sreemangal #tea #nature',
      images: const ['https://example.com/tea.jpg'],
      createdAt: now,
      viewCount: 15,
      likes: const ['sarah@test.com'],
    );

    await tester.pumpWidget(
      _wrap(
        InstafeedPostCard(
          repository: repo,
          tourId: 'tour_cox',
          post: post,
          isBookmarked: true,
          onBookmarkToggle: () {},
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Sarah Explorer'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) =>
          w is RichText &&
          w.text.toPlainText().contains('Morning Tea in Sreemangal')),
      findsOneWidget,
    );
    expect(find.textContaining('👁️'), findsNothing);
  });

  testWidgets(
      'InstafeedPostCard adapts card background to feedSurface in Light and Dark themes',
      (tester) async {
    final post = TourPostItem(
      id: 'post_theme_test',
      tourId: 'tour_cox',
      authorEmail: 'traveler@bhromon.fun',
      authorName: 'Traveler Test',
      authorPhoto: null,
      caption: 'Testing adaptive surface colors',
      images: const ['https://example.com/photo.jpg'],
      createdAt: now,
      viewCount: 5,
    );

    // 1. Test Light Theme (feedSurface should be Colors.white, not 0xFF161616)
    await tester.pumpWidget(
      _wrap(
        InstafeedPostCard(
          repository: repo,
          tourId: 'tour_cox',
          post: post,
          isBookmarked: false,
          onBookmarkToggle: () {},
        ),
        brightness: Brightness.light,
      ),
    );
    await tester.pump();

    final lightContainer = tester.widget<Container>(
      find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color == Colors.white),
    );
    expect((lightContainer.decoration as BoxDecoration).color, Colors.white);

    // 2. Test Dark Theme (feedSurface should be Color(0xFF1E1E1E))
    await tester.pumpWidget(
      _wrap(
        InstafeedPostCard(
          key: const ValueKey('dark_card'),
          repository: repo,
          tourId: 'tour_cox',
          post: post,
          isBookmarked: false,
          onBookmarkToggle: () {},
        ),
        brightness: Brightness.dark,
      ),
    );
    await tester.pump();

    final darkContainer = tester.widget<Container>(
      find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color == const Color(0xFF1E1E1E)),
    );
    expect((darkContainer.decoration as BoxDecoration).color,
        const Color(0xFF1E1E1E));
  });
}
