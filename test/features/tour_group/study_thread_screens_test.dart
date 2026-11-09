import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/study_reading_position.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_thread_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_discussion_screen.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_thread_screen.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_thread_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// The discussion of a book and one thread, with a fake repository that records each change. The
// rules these screens follow are tested on the emulator in functions/tests/study_threads_rules.test.js.

class _FakeDiscussionRepo extends TourGroupRepository {
  _FakeDiscussionRepo({
    this.threads = const [],
    this.replies = const [],
    this.chapters = const [],
    this.role,
  });

  final List<StudyThread> threads;
  final List<StudyReply> replies;
  final List<StudyChapter> chapters;
  final TourRole? role;
  final List<String> calls = [];

  @override
  String get currentEmail => 'me@x.com';

  @override
  Future<TourRole?> myRole(String tourId) async => role;

  @override
  Stream<List<StudyThread>> watchStudyThreads(String tourId, String bookId) =>
      Stream.value(threads);

  @override
  Stream<List<StudyReply>> watchStudyReplies(
    String tourId,
    String bookId,
    String threadId,
  ) =>
      Stream.value(replies);

  @override
  Stream<List<StudyChapter>> watchStudyChapters(String tourId, String bookId) =>
      Stream.value(chapters);

  @override
  Future<bool> toggleStudyReplyHelpful(
    String tourId,
    String bookId,
    String threadId,
    String replyId,
  ) async {
    calls.add('helpful $replyId');
    return true;
  }

  @override
  Future<void> setStudyAcceptedAnswer(
    String tourId,
    String bookId,
    String threadId, {
    String? replyId,
  }) async {
    calls.add('accept ${replyId ?? 'none'}');
  }

  @override
  Future<void> setStudyThreadLocked(
    String tourId,
    String bookId,
    String threadId, {
    required bool locked,
  }) async {
    calls.add('locked $locked');
  }

  @override
  Future<void> setStudyThreadPinned(
    String tourId,
    String bookId,
    String threadId, {
    required bool pinned,
  }) async {
    calls.add('pinned $pinned');
  }

  @override
  Future<void> addStudyThread(
    String tourId,
    String bookId, {
    required String title,
    required String body,
    String? chapterId,
    String pageRef = '',
  }) async {
    calls.add('start $title');
  }
}

/// The reading position and fence kept in memory, so a test sees what the screen saved.
class _FakePosition extends StudyReadingPosition {
  _FakePosition({this.number, this.fence = true});

  int? number;
  bool fence;

  @override
  Future<int?> load({required String tourId, required String bookId}) async =>
      number;

  @override
  Future<bool> loadFence() async => fence;

  @override
  Future<void> saveFence(bool hide) async {
    fence = hide;
  }
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: page,
  ));
  await tester.pumpAndSettle();
}

const _book =
    StudyBook(id: 'b1', title: 'Anna Karenina', createdByEmail: 'admin@x.com');

final _chapterOne = StudyChapter(id: 'c1', number: 1, title: 'First');
final _chapterFive = StudyChapter(id: 'c5', number: 5, title: 'Fifth');

final _openThread = StudyThread(
  id: 't1',
  title: 'Why the train?',
  body: 'The train appears three times.',
  chapterId: 'c1',
  createdByEmail: 'me@x.com',
  createdAt: DateTime(2030, 1, 1),
);

final _laterThread = StudyThread(
  id: 't2',
  title: 'The ending',
  body: 'Spoiler: she is gone.',
  chapterId: 'c5',
  createdByEmail: 'other@x.com',
  createdAt: DateTime(2030, 1, 2),
);

final _othersReply = StudyReply(
  id: 'r1',
  text: 'It marks the turning point.',
  createdByEmail: 'other@x.com',
  createdAt: DateTime(2030, 1, 1, 10),
  helpfulCount: 2,
);

final _myReply = StudyReply(
  id: 'r2',
  text: 'My own answer.',
  createdByEmail: 'me@x.com',
  createdAt: DateTime(2030, 1, 1, 11),
);

void main() {
  group('the discussion of a book', () {
    testWidgets(
        'a thread from a later chapter shows only its label until it is opened',
        (tester) async {
      final repo = _FakeDiscussionRepo(
        threads: [_openThread, _laterThread],
        chapters: [_chapterOne, _chapterFive],
      );
      await _pump(
        tester,
        StudyDiscussionScreen(
          tourId: 'T',
          book: _book,
          repository: repo,
          position: _FakePosition(number: 1),
        ),
      );

      expect(find.text('Why the train?'), findsOneWidget);
      expect(find.text('The ending'), findsNothing);
      expect(find.text('Later chapter'), findsOneWidget);
      expect(find.text('Start a thread'), findsOneWidget);
    });

    testWidgets('turning the fence off shows the later thread by its title',
        (tester) async {
      final position = _FakePosition(number: 1, fence: true);
      final repo = _FakeDiscussionRepo(
        threads: [_openThread, _laterThread],
        chapters: [_chapterOne, _chapterFive],
      );
      await _pump(
        tester,
        StudyDiscussionScreen(
          tourId: 'T',
          book: _book,
          repository: repo,
          position: position,
        ),
      );

      // The fence menu is in the app bar; the list tiles have their own menus.
      await tester.tap(find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.more_vert_rounded),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show threads from later chapters'));
      await tester.pumpAndSettle();

      expect(position.fence, isFalse);
      expect(find.text('The ending'), findsOneWidget);
    });
  });

  group('one thread', () {
    testWidgets(
        'the asker accepts a reply, and another member can mark a reply helpful but not their own',
        (tester) async {
      final repo = _FakeDiscussionRepo(
        threads: [_openThread],
        replies: [_othersReply, _myReply],
        chapters: [_chapterOne],
        role: TourRole.member,
      );
      await _pump(
        tester,
        StudyThreadScreen(
          tourId: 'T',
          bookId: 'b1',
          bookTitle: 'Anna Karenina',
          threadId: 't1',
          repository: repo,
        ),
      );

      expect(find.text('It marks the turning point.'), findsOneWidget);
      expect(find.text('My own answer.'), findsOneWidget);
      // The asker sees accept on each reply; the first in time order is the other member's.
      expect(find.text('Accept this answer'), findsWidgets);

      await tester.tap(find.text('Accept this answer').first);
      await tester.pumpAndSettle();
      expect(repo.calls, ['accept r1']);

      // Helpful is offered on the other member's reply, with its count.
      await tester.tap(find.text('Helpful (2)'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['accept r1', 'helpful r1']);
    });

    testWidgets('a locked thread takes no reply', (tester) async {
      final locked = StudyThread(
        id: 't1',
        title: 'Closed',
        body: 'Done.',
        createdByEmail: 'other@x.com',
        locked: true,
      );
      final repo = _FakeDiscussionRepo(threads: [locked]);
      await _pump(
        tester,
        StudyThreadScreen(
          tourId: 'T',
          bookId: 'b1',
          bookTitle: 'Anna Karenina',
          threadId: 't1',
          repository: repo,
        ),
      );

      expect(
          find.text('This thread is locked. No more replies.'), findsOneWidget);
      // No reply box is offered on a locked thread.
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('an admin locks a thread', (tester) async {
      final repo = _FakeDiscussionRepo(
        threads: [_openThread],
        replies: const [],
        role: TourRole.admin,
      );
      await _pump(
        tester,
        StudyThreadScreen(
          tourId: 'T',
          bookId: 'b1',
          bookTitle: 'Anna Karenina',
          threadId: 't1',
          repository: repo,
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lock thread'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['locked true']);
    });
  });

  group('the thread composer', () {
    testWidgets(
        'it refuses a blank title and a blank question, then returns the draft',
        (tester) async {
      StudyThreadDraft? saved;
      await _pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showStudyThreadComposer(
                  context,
                  chapters: [_chapterOne],
                  initialTitle: '',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Post thread'));
      await tester.pumpAndSettle();
      expect(find.text('Give the thread a title'), findsOneWidget);
      expect(saved, isNull);

      await tester.enterText(find.byType(TextField).at(0), 'Why the train?');
      await tester.tap(find.text('Post thread'));
      await tester.pumpAndSettle();
      expect(find.text('Write the question or point'), findsOneWidget);
      expect(saved, isNull);

      await tester.enterText(
          find.byType(TextField).at(1), 'It appears three times.');
      await tester.tap(find.text('Post thread'));
      await tester.pumpAndSettle();
      expect(saved?.title, 'Why the train?');
      expect(saved?.body, 'It appears three times.');
      expect(saved?.chapterId, isNull);
    });
  });
}
