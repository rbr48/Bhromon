import 'dart:io';

import 'package:bhromon/features/official_feed/domain/official_feed_choice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  group('the stored answer', () {
    test('reads back as the choice it was written from', () {
      for (final choice in OfficialFeedChoice.values) {
        expect(parseOfficialFeedChoice(officialFeedChoiceName(choice)), choice);
      }
    });

    test('anything unknown counts as not answered, so the question returns',
        () {
      expect(parseOfficialFeedChoice(null), OfficialFeedChoice.unanswered);
      expect(parseOfficialFeedChoice(7), OfficialFeedChoice.unanswered);
      expect(parseOfficialFeedChoice('maybe'), OfficialFeedChoice.unanswered);
    });
  });

  group('OfficialFeedPreference', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('bhromon_official_feed_');
      Hive.init(dir.path);
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('a new device has not answered yet', () async {
      expect(
        await OfficialFeedPreference.load(),
        OfficialFeedChoice.unanswered,
      );
    });

    test('an answer survives a restart of the app', () async {
      await OfficialFeedPreference.save(OfficialFeedChoice.follow);
      await Hive.close();
      Hive.init(dir.path);

      expect(await OfficialFeedPreference.load(), OfficialFeedChoice.follow);
    });
  });
}
