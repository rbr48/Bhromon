import 'dart:io';

import 'package:bhromon/features/tour_group/data/tour_hub_preference.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory dir;
  late TourHubPreference preference;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('bhromon_hub_preference');
    Hive.init(dir.path);
  });

  setUp(() async {
    preference = TourHubPreference();
    if (Hive.isBoxOpen('tour_groups_box')) {
      await Hive.box<dynamic>('tour_groups_box').clear();
    }
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  test('reads nothing while the tour box is not open', () {
    expect(preference.read(), isNull);
  });

  test('remembers a pick and reads it back', () async {
    await preference.remember('tour_b');
    expect(preference.read(), 'tour_b');
  });

  test('a new pick replaces the old one', () async {
    await preference.remember('tour_a');
    await preference.remember('tour_b');
    expect(preference.read(), 'tour_b');
  });

  test('forget clears only the pick it is given', () async {
    await preference.remember('tour_b');
    await preference.forget('tour_a');
    expect(preference.read(), 'tour_b');

    await preference.forget('tour_b');
    expect(preference.read(), isNull);
  });

  test('an empty id is never saved', () async {
    await preference.remember('');
    expect(preference.read(), isNull);
  });

  test('the pick is on disk, so it survives a restart', () async {
    await preference.remember('tour_b');
    await Hive.close();
    expect(preference.read(), isNull);

    await Hive.openBox<dynamic>('tour_groups_box');
    expect(preference.read(), 'tour_b');
  });
}
