import 'dart:async';
import 'dart:io';

import 'package:bhromon/features/tour_group/data/active_group.dart';
import 'package:bhromon/features/tour_group/data/tour_hub_preference.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('bhromon_active').path);
  });

  setUp(() async {
    final box = await Hive.openBox<dynamic>('tour_groups_box');
    await box.clear();
  });

  test('select makes the group active, saves it, and announces it', () async {
    final active = ActiveGroup(preference: TourHubPreference());
    final seen = <String?>[];
    final sub = active.changes.listen(seen.add);

    await active.select('tour-a');
    await Future<void>.delayed(Duration.zero);

    expect(active.current, 'tour-a');
    expect(seen, ['tour-a']);
    expect(TourHubPreference().read(), 'tour-a');
    await sub.cancel();
  });

  test('the active group survives a restart', () async {
    await ActiveGroup(preference: TourHubPreference()).select('tour-a');

    final afterRestart = ActiveGroup(preference: TourHubPreference());
    expect(afterRestart.current, 'tour-a');
  });

  test('an empty id is ignored', () async {
    final active = ActiveGroup(preference: TourHubPreference());
    await active.select('');
    expect(active.current, isNull);
  });

  test('clearIf clears only the group it names', () async {
    final active = ActiveGroup(preference: TourHubPreference());
    await active.select('tour-a');

    await active.clearIf('tour-b');
    expect(active.current, 'tour-a', reason: 'another group leaves it alone');

    await active.clearIf('tour-a');
    expect(active.current, isNull);
    expect(TourHubPreference().read(), isNull,
        reason: 'the saved pick goes too');
  });

  test('clear empties the active group and tells the listeners', () async {
    final active = ActiveGroup(preference: TourHubPreference());
    await active.select('tour-a');
    final seen = <String?>[];
    final Completer<void> done = Completer<void>();
    final sub = active.changes.listen((value) {
      seen.add(value);
      if (value == null) done.complete();
    });

    await active.clear();
    await done.future;

    expect(active.current, isNull);
    expect(seen, [null]);
    expect(TourHubPreference().read(), isNull);
    await sub.cancel();
  });
}
