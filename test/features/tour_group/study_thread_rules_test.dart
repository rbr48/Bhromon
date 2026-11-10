import 'package:bhromon/features/tour_group/domain/models/study_thread_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_thread_rules.dart';
import 'package:flutter_test/flutter_test.dart';

// The discussions of a study book: their order, search, the fence behind a member's place,
// the daily limit and the pin limit, which replies a viewer sees, and who may accept an answer.
// The rules here mirror the ones in firestore.rules, so a change to one needs the other.

StudyThread _thread(
  String id, {
  DateTime? at,
  String by = 'a@x.com',
  bool pinned = false,
  bool locked = false,
  String? chapterId,
  String title = 'A question',
  String body = 'Why is the first line so short?',
}) =>
    StudyThread(
      id: id,
      title: title,
      body: body,
      createdByEmail: by,
      createdAt: at,
      pinned: pinned,
      locked: locked,
      chapterId: chapterId,
    );

StudyReply _reply(
  String id, {
  DateTime? at,
  String by = 'b@x.com',
  int reported = 0,
}) =>
    StudyReply(
      id: id,
      text: 'An answer',
      createdByEmail: by,
      createdAt: at,
      reportCount: reported,
    );

void main() {
  group('the order of threads', () {
    test('pinned first, then the newest', () {
      final sorted = sortStudyThreads([
        _thread('old', at: DateTime(2026, 11, 1)),
        _thread('new', at: DateTime(2026, 11, 5)),
        _thread('pinned', at: DateTime(2026, 9, 1), pinned: true),
      ]);
      expect(sorted.map((t) => t.id), ['pinned', 'new', 'old']);
    });

    test('a thread whose time is not yet known comes first', () {
      final sorted = sortStudyThreads(
          [_thread('written', at: DateTime(2026, 11, 5)), _thread('pending')]);
      expect(sorted.map((t) => t.id), ['pending', 'written']);
    });
  });

  group('search within a book', () {
    final threads = [
      _thread('a', title: 'Symbolism of the train'),
      _thread('b', title: 'Chapter two', body: 'Who is the narrator?'),
    ];

    test('matches the title or the body, ignoring case and spaces at the ends',
        () {
      expect(searchStudyThreads(threads, '  TRAIN ').map((t) => t.id), ['a']);
      expect(searchStudyThreads(threads, 'narrator').map((t) => t.id), ['b']);
    });

    test('an empty query keeps every thread', () {
      expect(searchStudyThreads(threads, '  ').length, 2);
    });

    test('a query that matches nothing returns nothing', () {
      expect(searchStudyThreads(threads, 'dragon'), isEmpty);
    });
  });

  group('the fence behind a member\'s place', () {
    final chapterNumbers = {'c1': 1, 'c2': 2, 'c3': 3};

    test('a thread on a chapter later than the place is behind the fence', () {
      final later = _thread('x', chapterId: 'c3');
      expect(isBehindFence(later, chapterNumberById: chapterNumbers, place: 2),
          isTrue);
    });

    test('a thread on the place or an earlier chapter is not behind it', () {
      expect(
          isBehindFence(_thread('x', chapterId: 'c2'),
              chapterNumberById: chapterNumbers, place: 2),
          isFalse);
      expect(
          isBehindFence(_thread('x', chapterId: 'c1'),
              chapterNumberById: chapterNumbers, place: 2),
          isFalse);
    });

    test(
        'without a place, or for a thread about the whole book, nothing is behind the fence',
        () {
      expect(
          isBehindFence(_thread('x', chapterId: 'c3'),
              chapterNumberById: chapterNumbers, place: null),
          isFalse);
      expect(
          isBehindFence(_thread('x'),
              chapterNumberById: chapterNumbers, place: 1),
          isFalse);
    });
  });

  group('limits', () {
    // The day is the Dhaka day (UTC+6), so these instants are written in UTC.
    final now = DateTime.utc(2026, 11, 9, 8); // 14:00 on 9 November in Dhaka

    test('the Dhaka day key is the date six hours on, as a number', () {
      expect(threadDayKey(DateTime.utc(2026, 11, 9, 8)), 20261109);
      expect(threadDayKey(DateTime.utc(2026, 11, 9, 17, 59)),
          20261109); // 23:59 in Dhaka
      expect(threadDayKey(DateTime.utc(2026, 11, 9, 18)),
          20261110); // midnight in Dhaka
    });

    test('a member has started a thread today when its Dhaka day is today', () {
      final threads = [
        _thread('today', at: DateTime.utc(2026, 11, 9, 2), by: 'me@x.com'),
        _thread('yesterday', at: DateTime.utc(2026, 11, 8, 17), by: 'me@x.com'),
        _thread('others', at: DateTime.utc(2026, 11, 9, 3), by: 'other@x.com'),
      ];
      expect(threadsStartedToday(threads, email: 'me@x.com', now: now), 1);
    });

    test('the count turns over at Dhaka midnight, not at the local midnight',
        () {
      final threads = [
        _thread('before-midnight',
            at: DateTime.utc(2026, 11, 9, 17, 59), by: 'me@x.com'),
        _thread('after-midnight',
            at: DateTime.utc(2026, 11, 9, 18, 1), by: 'me@x.com'),
      ];
      expect(
          threadsStartedToday(threads,
              email: 'me@x.com', now: DateTime.utc(2026, 11, 9, 17, 30)),
          1);
      expect(
          threadsStartedToday(threads,
              email: 'me@x.com', now: DateTime.utc(2026, 11, 9, 18, 30)),
          1);
    });

    test('a member may start a thread until the daily limit is reached', () {
      final under = [
        for (var i = 0; i < kThreadsPerDayMax - 1; i++)
          _thread('t$i', at: now, by: 'me@x.com')
      ];
      final full = [
        for (var i = 0; i < kThreadsPerDayMax; i++)
          _thread('t$i', at: now, by: 'me@x.com')
      ];
      expect(canStartThreadToday(under, email: 'me@x.com', now: now), isTrue);
      expect(canStartThreadToday(full, email: 'me@x.com', now: now), isFalse);
    });

    test('an admin may pin up to the limit of threads', () {
      final two = [_thread('a', pinned: true), _thread('b', pinned: true)];
      final three = [...two, _thread('c', pinned: true)];
      expect(canPinMoreThreads(two), isTrue);
      expect(canPinMoreThreads(three), isFalse);
    });
  });

  group('replies', () {
    test(
        'replies are in the order they were written, and a reply with no time comes last',
        () {
      final sorted = sortStudyReplies([
        _reply('late', at: DateTime(2026, 11, 5)),
        _reply('pending'),
        _reply('early', at: DateTime(2026, 11, 1)),
      ]);
      expect(sorted.map((r) => r.id), ['early', 'late', 'pending']);
    });

    test(
        'a reported reply is hidden from other members, but its author and an admin see it',
        () {
      final reported = _reply('r', by: 'author@x.com', reported: 1);
      expect(
          isReplyVisibleTo(reported,
              viewerEmail: 'other@x.com', isAdmin: false),
          isFalse);
      expect(
          isReplyVisibleTo(reported,
              viewerEmail: 'author@x.com', isAdmin: false),
          isTrue);
      expect(
          isReplyVisibleTo(reported, viewerEmail: 'other@x.com', isAdmin: true),
          isTrue);
      expect(
          isReplyVisibleTo(_reply('ok'),
              viewerEmail: 'other@x.com', isAdmin: false),
          isTrue);
    });

    test('the asker or an admin may accept an answer; nobody else may', () {
      final thread = _thread('t', by: 'asker@x.com');
      expect(
          canAcceptAnswer(thread, viewerEmail: 'asker@x.com', isAdmin: false),
          isTrue);
      expect(canAcceptAnswer(thread, viewerEmail: 'other@x.com', isAdmin: true),
          isTrue);
      expect(
          canAcceptAnswer(thread, viewerEmail: 'other@x.com', isAdmin: false),
          isFalse);
    });

    test('a locked thread takes no replies', () {
      expect(canReplyTo(_thread('t')), isTrue);
      expect(canReplyTo(_thread('t', locked: true)), isFalse);
    });

    test('nobody votes on or reports their own reply', () {
      final mine = _reply('r', by: 'me@x.com');
      expect(canVoteOnReply(mine, viewerEmail: 'me@x.com'), isFalse);
      expect(canVoteOnReply(mine, viewerEmail: 'other@x.com'), isTrue);
    });
  });

  group('reading the stored thread and reply', () {
    test('a thread with no title or body is not read', () {
      expect(StudyThread.fromMap('x', {'title': 'Q', 'body': ' '}), isNull);
      expect(StudyThread.fromMap('x', {'body': 'Text'}), isNull);
    });

    test(
        'a thread reads its page, chapter, pins and accepted answer, and empty values as none',
        () {
      final read = StudyThread.fromMap('x', {
        'title': 'Q',
        'body': 'Text',
        'pageRef': 'p. 34',
        'chapterId': 'c2',
        'pinned': true,
        'acceptedReplyId': 'r1',
      });
      expect(read?.pageRef, 'p. 34');
      expect(read?.chapterId, 'c2');
      expect(read?.pinned, isTrue);
      expect(read?.isAnswered, isTrue);
      final bare = StudyThread.fromMap('y', {
        'title': 'Q',
        'body': 'Text',
        'chapterId': '',
        'acceptedReplyId': ''
      });
      expect(bare?.chapterId, isNull);
      expect(bare?.isAnswered, isFalse);
    });

    test('a thread writes an empty page reference as null', () {
      final fields =
          const StudyThread(id: '', title: 'Q', body: 'Text').toFields();
      expect(fields['pageRef'], isNull);
      expect(fields['acceptedReplyId'], isNull);
      expect(fields['locked'], isFalse);
    });

    test(
        'a reply with no text is not read, and its counts read as zero when missing',
        () {
      expect(StudyReply.fromMap('x', {'text': ' '}), isNull);
      final read = StudyReply.fromMap('y', {'text': 'Answer'});
      expect(read?.helpfulCount, 0);
      expect(read?.reportCount, 0);
      expect(read?.isReported, isFalse);
    });

    test('a report reason is read by name, and an unknown one reads as other',
        () {
      expect(StudyReportReason.fromName('spam'), StudyReportReason.spam);
      expect(StudyReportReason.fromName('bogus'), StudyReportReason.other);
    });
  });
}
