import 'dart:io';

import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/data/tour_media_journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// Signed in as a fixed account, so the per-user keys can be checked.
class _SignedInRepository extends TourGroupRepository {
  @override
  String get currentUid => 'uid_1';

  @override
  String get currentEmail => 'lead@bhromon.fun';

  // The image cache needs platform plugins, which plain tests do not have.
  @override
  Future<void> emptyImageCache() async {}
}

/// Counts how often the image cache is emptied.
class _ImageCacheRepository extends _SignedInRepository {
  int emptied = 0;

  @override
  Future<void> emptyImageCache() async {
    emptied++;
  }
}

void main() {
  late Directory dir;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('bhromon_local_tour');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  test('leaving a tour clears that tour from this device and keeps the rest',
      () async {
    final groups = await Hive.openBox<dynamic>('tour_groups_box');
    final prefs = await Hive.openBox<dynamic>('channel_prefs');
    await groups.putAll({
      'tour_tour_a': {'name': 'Tour A'},
      'tour_tour_b': {'name': 'Tour B'},
      'my_tour_ids': ['tour_a', 'tour_b'],
      'feed_prefs_uid_1_tour_a': {
        'bookmarks': ['post_1']
      },
      'feed_prefs_uid_1_tour_b': {
        'bookmarks': ['post_2']
      },
      'post_draft_uid_1_tour_a': {'caption': 'draft'},
      'last_active_tour_id': 'tour_a',
    });
    await prefs.putAll({
      'read|tour_a|general': 1,
      'mute|tour_a|general': true,
      'read|tour_b|general': 2,
      // Starts with 'tour_a' but is a different tour, so it must survive.
      'read|tour_ab|general': 3,
    });

    await _SignedInRepository().clearLocalTourData('tour_a');

    expect(groups.containsKey('tour_tour_a'), isFalse);
    expect(groups.get('my_tour_ids'), ['tour_b']);
    expect(groups.containsKey('feed_prefs_uid_1_tour_a'), isFalse);
    expect(groups.containsKey('post_draft_uid_1_tour_a'), isFalse);
    expect(groups.containsKey('last_active_tour_id'), isFalse);
    expect(prefs.keys,
        unorderedEquals(['read|tour_b|general', 'read|tour_ab|general']));

    expect(groups.containsKey('tour_tour_b'), isTrue);
    expect(groups.containsKey('feed_prefs_uid_1_tour_b'), isTrue);
  });

  test('leaving a tour forgets its pending media uploads and no others',
      () async {
    final journal = TourMediaJournal.instance;
    await journal.recordPending(
      const TourMediaRef(tourId: 'tour_a', folder: 'posts', filename: 'a.jpg'),
    );
    await journal.recordPending(
      const TourMediaRef(tourId: 'tour_b', folder: 'posts', filename: 'b.jpg'),
    );
    expect(journal.pendingCount, 2);

    await _SignedInRepository().clearLocalTourData('tour_a');

    expect(journal.pendingCount, 1);
  });

  test('leaving a tour empties the image cache', () async {
    final repo = _ImageCacheRepository();

    await repo.clearLocalTourData('tour_a');

    expect(repo.emptied, 1);
  });
}
