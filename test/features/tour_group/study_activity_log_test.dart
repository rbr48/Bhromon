import 'dart:io';

import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:bhromon/features/tour_group/data/study_activity_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../../helpers/perf_fixtures.dart';

// The study a member does on this device, counted per day. The counts feed the streak and the progress card, and they
// must survive a restart without leaving the device.

void main() {
  late Directory dir;
  late CountingSecureStorage storage;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bhromon_activity_');
    Hive.init(dir.path);
    storage = CountingSecureStorage();
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  StudyActivityLog log() => StudyActivityLog(
        encryption: HiveEncryptionService.withStorage(storage),
      );

  test('counts reviews and quizzes per day, and the counts survive a restart',
      () async {
    await log().recordReview(DateTime(2026, 11, 9, 8));
    await log().recordReview(DateTime(2026, 11, 9, 20));
    await log().recordQuiz(DateTime(2026, 11, 10, 9));

    await Hive.close();

    final afterRestart = log();
    expect(await afterRestart.cardsReviewed(), 2);
    expect(await afterRestart.activeDays(), [
      DateTime(2026, 11, 9),
      DateTime(2026, 11, 10),
    ]);
  });

  test(
      'a day with only quiz attempts is still an active day, but no card was reviewed',
      () async {
    await log().recordQuiz(DateTime(2026, 11, 3, 12));

    expect(await log().cardsReviewed(), 0);
    expect(await log().activeDays(), [DateTime(2026, 11, 3)]);
  });

  test(
      'a working or a finding check counts as an active day, and the cards reviewed in a week are counted from its Monday',
      () async {
    await log().recordReview(DateTime(2026, 11, 9, 8));
    await log().recordReview(DateTime(2026, 11, 15, 8));
    await log().recordReview(DateTime(2026, 11, 16, 8));
    await log().recordAction(DateTime(2026, 11, 12, 10));

    expect(
      await log().cardsReviewedBetween(
        DateTime(2026, 11, 9),
        DateTime(2026, 11, 16),
      ),
      2,
    );
    expect(await log().activeDays(), [
      DateTime(2026, 11, 9),
      DateTime(2026, 11, 12),
      DateTime(2026, 11, 15),
      DateTime(2026, 11, 16),
    ]);
  });
}
