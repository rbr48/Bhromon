import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/entities/explorer_profile.dart';
import 'package:bhromon/core/entities/pro_tip.dart';
import 'package:bhromon/core/entities/trip_log.dart';
import 'package:bhromon/core/errors/failures.dart';
import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:bhromon/features/explorer/domain/usecases/get_top_explorers_usecase.dart';
import 'package:bhromon/features/feed/data/repositories/feed_repository_impl.dart';
import 'package:bhromon/features/feed/domain/repositories/i_feed_repository.dart';
import 'package:bhromon/features/feed/domain/usecases/get_saved_trip_logs_usecase.dart';
import 'package:bhromon/features/feed/domain/usecases/get_smart_feed_usecase.dart';
import 'package:bhromon/features/feed/presentation/bloc/feed_cubit.dart';
import 'package:bhromon/features/feed/presentation/bloc/feed_state.dart';
import 'package:bhromon/features/pro_tip/domain/usecases/get_latest_tips_usecase.dart';

import '../helpers/fake_firestore.dart';
import '../helpers/perf_fixtures.dart';

void main() {
  late FakeFirestore fs;
  late FeedRepositoryImpl repo;
  late Future<void> Function() cleanupHive;
  final base = DateTime(2026, 9, 1);

  setUp(() async {
    cleanupHive = await setUpTempHive();
    fs = FakeFirestore();
    repo = FeedRepositoryImpl.withOnlineCheck(
      fs,
      HiveEncryptionService.withStorage(CountingSecureStorage()),
      () async => true,
    );
  });

  tearDown(() => cleanupHive());

  void seedLogs(int live, {int archived = 0}) {
    for (var i = 0; i < live; i++) {
      fs.seed(
          'trip_logs',
          'live_$i',
          tripLogDoc(
            authorId: 'author_${i % 40}',
            lastConfirmed: base.subtract(Duration(hours: i)),
          ));
    }
    for (var i = 0; i < archived; i++) {
      fs.seed(
          'archived_trip_logs',
          'old_$i',
          tripLogDoc(
            authorId: 'author_${i % 40}',
            lastConfirmed: DateTime(2023, 1, 1).subtract(Duration(hours: i)),
          ));
    }
  }

  group('FeedRepositoryImpl paging', () {
    test('first page reads one page of documents, not whole collections',
        () async {
      seedLogs(1000, archived: 500);
      final me = viewer('me');
      final ctx = await repo.loadViewerContext(me);
      fs.resetCounters();

      final page = (await repo.getFeedPage(me, ctx)).getOrElse(() => throw 'x');

      expect(page.logs, hasLength(kFeedPageSize));
      expect(page.hasMore, isTrue);
      expect(fs.documentsRead, kFeedPageSize,
          reason: 'old code read all 1,500 documents on every load');
      expect(fs.queriesByCollection.containsKey('archived_trip_logs'), isFalse);
      // Newest first.
      expect(page.logs.first.tripId, 'live_0');
    });

    test('paging walks every live log exactly once, newest first', () async {
      seedLogs(95);
      final me = viewer('me');
      final ctx = await repo.loadViewerContext(me);
      final seen = <String>[];
      FeedCursor? cursor;
      var pages = 0;
      do {
        final page = (await repo.getFeedPage(me, ctx, after: cursor))
            .getOrElse(() => throw 'x');
        seen.addAll(page.logs.map((l) => l.tripId));
        cursor = page.next;
        pages++;
      } while (cursor != null);

      expect(pages, 4); // 30 + 30 + 30 + 5
      expect(seen, [for (var i = 0; i < 95; i++) 'live_$i']);
    });

    test('archive pages come only from archived_trip_logs', () async {
      seedLogs(10, archived: 45);
      final me = viewer('me');
      fs.resetCounters();
      final page = (await repo.getArchivedPage(me, FeedViewerContext.empty))
          .getOrElse(() => throw 'x');
      expect(page.logs, hasLength(30));
      expect(page.logs.every((l) => l.tripId.startsWith('old_')), isTrue);
      expect(fs.queriesByCollection.keys, ['archived_trip_logs']);
    });

    test('viewer context loads blocked + follows once, in two small reads',
        () async {
      fs.seed('explorer_profiles/me/blocked_users', 'author_1', {});
      fs.seed('follows', 'me_author_2',
          {'followerId': 'me', 'followedId': 'author_2'});
      fs.seed('follows', 'x_y', {'followerId': 'x', 'followedId': 'y'});

      final ctx = await repo.loadViewerContext(viewer('me'));

      expect(ctx.blockedUids, {'author_1'});
      expect(ctx.followedUids, {'author_2'});
      expect(fs.queriesByCollection['follows'], 1);
      expect(fs.queriesByCollection['explorer_profiles/me/blocked_users'], 1);
    });

    test('guests skip the viewer-context reads entirely', () async {
      final ctx = await repo.loadViewerContext(viewer('explorer_user'));
      expect(ctx.blockedUids, isEmpty);
      expect(fs.documentsRead, 0);
    });

    test('filters blocked authors and enforces diary visibility', () async {
      fs.seed('trip_logs', 'public',
          tripLogDoc(authorId: 'a', lastConfirmed: base));
      fs.seed('trip_logs', 'blocked',
          tripLogDoc(authorId: 'troll', lastConfirmed: base));
      fs.seed(
          'trip_logs',
          'private_other',
          tripLogDoc(
              authorId: 'b', lastConfirmed: base, visibility: 'private'));
      fs.seed(
          'trip_logs',
          'private_mine',
          tripLogDoc(
              authorId: 'me', lastConfirmed: base, visibility: 'private'));
      fs.seed(
          'trip_logs',
          'friends_followed',
          tripLogDoc(
              authorId: 'friend', lastConfirmed: base, visibility: 'friends'));
      fs.seed(
          'trip_logs',
          'friends_stranger',
          tripLogDoc(
              authorId: 'stranger',
              lastConfirmed: base,
              visibility: 'friends'));

      const ctx =
          FeedViewerContext(blockedUids: {'troll'}, followedUids: {'friend'});
      final page = (await repo.getFeedPage(viewer('me'), ctx))
          .getOrElse(() => throw 'x');

      expect(page.logs.map((l) => l.tripId).toSet(),
          {'public', 'private_mine', 'friends_followed'});
    });

    test('saved logs are fetched by id in whereIn chunks, in saved order',
        () async {
      seedLogs(100, archived: 20);
      final ids = [
        for (var i = 64; i >= 0; i--) 'live_$i',
        'old_3',
        'missing',
      ];
      fs.resetCounters();

      final logs = (await repo.getTripLogsByIds(
              viewer('me'), FeedViewerContext.empty, ids))
          .getOrElse(() => throw 'x');

      expect(logs.map((l) => l.tripId).toList(),
          [for (var i = 64; i >= 0; i--) 'live_$i', 'old_3']);
      // 67 ids -> 3 whereIn queries on trip_logs, then the 2 misses on archive.
      expect(fs.queriesByCollection['trip_logs'], 3);
      expect(fs.queriesByCollection['archived_trip_logs'], 1);
    });
  });

  group('GetSmartFeedUseCase', () {
    test('rankLogs scores each log once (was twice per comparison)', () {
      final logs = [
        for (var i = 0; i < 500; i++)
          TripLog(
            tripId: 't$i',
            authorId: 'a',
            title: 'T',
            blocks: const [],
            routePoints: const [],
            costItems: const [],
            locationPinId: 'p',
            trustScore: 0,
            helpfulVotes: i,
            lastConfirmed: base,
            division: 'Dhaka',
            district: 'Dhaka',
          ),
      ];
      var calls = 0;
      final ranked = GetSmartFeedUseCase.rankLogs(logs, (log) {
        calls++;
        return log.helpfulVotes.toDouble();
      });

      expect(calls, 500,
          reason:
              'a comparator-based sort calls it ~2·n·log2(n) ≈ 9,000 times');
      expect(ranked.first.tripId, 't499');
      expect(ranked.last.tripId, 't0');
    });

    test('reuses the viewer context for later pages', () async {
      seedLogs(70);
      fs.seed('follows', 'f', {'followerId': 'me', 'followedId': 'author_3'});
      final usecase = GetSmartFeedUseCase(
          repo, HiveEncryptionService.withStorage(CountingSecureStorage()));

      final first = (await usecase(SmartFeedRequest(viewer: viewer('me'))))
          .getOrElse(() => throw 'x');
      final followsAfterFirst = fs.queriesByCollection['follows'];
      await usecase(SmartFeedRequest(
        viewer: viewer('me'),
        viewerContext: first.viewerContext,
        after: first.next,
      ));

      expect(followsAfterFirst, 1);
      expect(fs.queriesByCollection['follows'], 1,
          reason: 'the follows query used to run twice per load, every page');
    });
  });

  group('FeedCubit', () {
    test('a slow, superseded load cannot overwrite a newer one', () async {
      final smart = _ScriptedSmartFeed();
      final cubit = _cubit(smart);

      final guestDone = cubit.loadFeed(viewer('guest'));
      final signedInDone = cubit.loadFeed(viewer('me'));

      // The signed-in load finishes first, the guest load afterwards.
      smart.complete('me', [_log('mine')]);
      await signedInDone;
      smart.complete('guest', [_log('guest_view')]);
      await guestDone;

      final state = cubit.state as FeedLoaded;
      expect(state.logs.single.tripId, 'mine');
      await cubit.close();
    });

    test('loadMore appends the next page once, ignoring duplicate calls',
        () async {
      final smart = _ScriptedSmartFeed(autoComplete: true)
        ..pages = [
          [_log('a'), _log('b')],
          [_log('b'), _log('c')],
        ];
      final cubit = _cubit(smart);
      await cubit.loadFeed(viewer('me'));

      await Future.wait([cubit.loadMore(), cubit.loadMore(), cubit.loadMore()]);

      final state = cubit.state as FeedLoaded;
      expect(state.logs.map((l) => l.tripId), ['a', 'b', 'c']);
      expect(smart.calls, 2, reason: 'one initial page + one loadMore');
      expect(smart.requests.last.viewerContext, isNotNull);
      await cubit.close();
    });

    test('loadMore does nothing once the feed is exhausted', () async {
      final smart = _ScriptedSmartFeed(autoComplete: true, hasMore: false)
        ..pages = [
          [_log('a')],
        ];
      final cubit = _cubit(smart);
      await cubit.loadFeed(viewer('me'));
      await cubit.loadMore();
      expect(smart.calls, 1);
      await cubit.close();
    });
  });
}

TripLog _log(String id) => TripLog(
      tripId: id,
      authorId: 'a',
      title: id,
      blocks: const [],
      routePoints: const [],
      costItems: const [],
      locationPinId: 'p',
      trustScore: 0,
      helpfulVotes: 0,
      lastConfirmed: DateTime.now(),
      division: 'Dhaka',
      district: 'Dhaka',
    );

FeedCubit _cubit(_ScriptedSmartFeed smart) => FeedCubit(
      smart,
      _FixedTips(),
      _FixedExplorers(),
      _NoSaved(),
    );

/// Smart-feed use case whose results the test releases explicitly.
class _ScriptedSmartFeed implements GetSmartFeedUseCase {
  _ScriptedSmartFeed({this.autoComplete = false, this.hasMore = true});

  final bool autoComplete;
  final bool hasMore;
  List<List<TripLog>> pages = [];
  int calls = 0;
  final List<SmartFeedRequest> requests = [];
  final Map<String, Completer<Either<Failure, SmartFeedPage>>> _pending = {};

  void complete(String uid, List<TripLog> logs) =>
      _pending[uid]!.complete(Right(SmartFeedPage(
          logs: logs, next: null, viewerContext: FeedViewerContext.empty)));

  @override
  Future<Either<Failure, SmartFeedPage>> call(SmartFeedRequest request) {
    calls++;
    requests.add(request);
    if (autoComplete) {
      final index = calls - 1;
      final logs = index < pages.length ? pages[index] : <TripLog>[];
      final more = hasMore && index + 1 < pages.length;
      return Future.value(Right(SmartFeedPage(
        logs: logs,
        next: more ? FeedCursor(index) : null,
        viewerContext: FeedViewerContext.empty,
      )));
    }
    return (_pending[request.viewer.uid] = Completer()).future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixedTips implements GetLatestTipsUseCase {
  @override
  Future<Either<Failure, List<ProTip>>> call(int? params) async =>
      const Right([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixedExplorers implements GetTopExplorersUseCase {
  @override
  Future<Either<Failure, List<ExplorerProfile>>> call(int? params) async =>
      const Right([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoSaved implements GetSavedTripLogsUseCase {
  @override
  Future<Either<Failure, List<TripLog>>> call(
          SavedTripLogsRequest request) async =>
      const Right([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
