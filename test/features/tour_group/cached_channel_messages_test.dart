import 'dart:io';

import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:bhromon/features/tour_group/data/channel_message_cache.dart';
import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/cached_channel_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../../helpers/perf_fixtures.dart';

/// Lets the cache read finish. The read is real file I/O, so the test waits in
/// real time and pumps frames until the page has a result.
Future<void> _untilRead(
    WidgetTester tester, List<List<ChannelMessage>?> seen) async {
  for (var i = 0; i < 200 && seen.last == null; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

void main() {
  late Directory dir;
  late ChannelMessageCache cache;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bhromon_cached_view_');
    Hive.init(dir.path);
    cache = ChannelMessageCache(
      encryption: HiveEncryptionService.withStorage(CountingSecureStorage()),
    );
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('the page gets the cached messages once they are read',
      (tester) async {
    await tester.runAsync(() => cache.write(
          't1',
          'general',
          [
            ChannelMessage(
              id: 'm1',
              senderEmail: 'asha@example.com',
              senderName: 'Asha',
              text: 'from the cache',
              timestamp: DateTime(2026, 11, 2, 9),
            ),
          ],
        ));

    final seen = <List<ChannelMessage>?>[];
    await tester.pumpWidget(MaterialApp(
      home: CachedChannelMessages(
        tourId: 't1',
        channelId: 'general',
        cache: cache,
        builder: (context, cached) {
          seen.add(cached);
          return const SizedBox();
        },
      ),
    ));

    expect(seen.first, isNull, reason: 'the first frame waits for the read');
    await _untilRead(tester, seen);

    expect(seen.last?.map((m) => m.text).toList(), ['from the cache']);
  });

  testWidgets(
      'a channel with nothing cached gives an empty list, not a pending read',
      (tester) async {
    // The box is made in real time first, as the app's own writes make it, so
    // the page's read is a quick lookup inside the test.
    await tester.runAsync(() => cache.write('t9', 'food', const []));

    final seen = <List<ChannelMessage>?>[];
    await tester.pumpWidget(MaterialApp(
      home: CachedChannelMessages(
        tourId: 't9',
        channelId: 'food',
        cache: cache,
        builder: (context, cached) {
          seen.add(cached);
          return const SizedBox();
        },
      ),
    ));

    await _untilRead(tester, seen);

    expect(seen.last, isEmpty);
  });
}
