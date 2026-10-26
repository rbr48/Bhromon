import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/localization/tour_translation_keys.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import 'package:bhromon/features/tour_group/domain/services/scrapbook_engine.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/scrapbook/scrapbook_magazine.dart';

// Reels without covers and text-only posts, so no network images load.
TourPostItem _reel(String id, {String author = 'rina@x.com', int likes = 0}) =>
    TourPostItem(
      id: id,
      tourId: 't1',
      authorEmail: author,
      authorName: author == 'rina@x.com' ? 'Rina' : 'Babu',
      caption: 'Watching the waves roll in at Inani beach',
      images: const [],
      videoUrl: 'https://bhromon.fun/media/t1/posts/$id.mp4',
      isReel: true,
      location: 'Inani',
      likes: [for (var i = 0; i < likes; i++) 'fan$i@x.com'],
      createdAt: DateTime(2026, 10, 25, 9, id.length),
    );

Future<void> _pump(WidgetTester tester, List<TourPostItem> posts,
    {String me = ''}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ScrapbookMagazine(
        issue: ScrapbookIssue.build(posts: posts),
        posts: posts,
        group: null,
        travellers: 3,
        myEmail: me,
        onShareText: () {},
      ),
    ),
  ));
}

void main() {
  testWidgets('an empty tour shows the cover and the back cover only',
      (tester) async {
    await _pump(tester, const []);
    expect(find.text('BHROMON'), findsOneWidget);
    expect(find.textContaining('This magazine writes itself'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('a tour with posts gets its pages, and next turns the page',
      (tester) async {
    await _pump(tester, [
      _reel('a', likes: 3),
      _reel('bb', author: 'babu@x.com', likes: 1),
    ]);
    // Cover, numbers, one chapter, moments, quotes, awards, places, back.
    expect(find.text('1 / 8'), findsOneWidget);

    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('The trip in numbers'), findsOneWidget);
    expect(find.text('2 / 8'), findsOneWidget);
  });

  testWidgets("the reader's own page appears when they posted", (tester) async {
    await _pump(tester, [_reel('a', likes: 2)], me: 'rina@x.com');
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Your page'), findsOneWidget);
  });

  testWidgets('play turns into pause and back', (tester) async {
    await _pump(tester, [_reel('a', likes: 1)]);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(find.byTooltip('Play'), findsOneWidget);
  });

  testWidgets('every page fits a small phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(
      tester,
      [_reel('a', likes: 3), _reel('bb', author: 'babu@x.com', likes: 1)],
      me: 'rina@x.com',
    );
    for (var i = 0; i < 8; i++) {
      expect(tester.takeException(), isNull, reason: 'page ${i + 1}');
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  test('every award has a title and a detail in both languages', () {
    final en = TourTranslationKeys.localizedValues['en']!;
    final bn = TourTranslationKeys.localizedValues['bn']!;
    for (final key in scrapbookAwardKeys()) {
      expect(en.containsKey(key), isTrue, reason: 'no English for $key');
      expect(bn.containsKey(key), isTrue, reason: 'no Bengali for $key');
    }
  });
}
