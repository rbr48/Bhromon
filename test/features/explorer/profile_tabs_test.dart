import 'package:bhromon/features/explorer/domain/profile_tabs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the own profile tabs', () {
    test(
        'without kGroupsV2 the groups tab is first and the profile opens on it',
        () {
      expect(profileTabKeys(groupsV2: false), ['tours', 'games', 'settings']);
      expect(defaultProfileTab(groupsV2: false), 'tours');
    });

    test(
        'with kGroupsV2 there is no groups tab, and the profile opens on Games',
        () {
      expect(profileTabKeys(groupsV2: true), ['games', 'settings']);
      expect(defaultProfileTab(groupsV2: true), 'games');
    });
  });

  group('a swipe between tabs', () {
    final keys = profileTabKeys(groupsV2: true);

    test('moves one tab each way', () {
      expect(stepProfileTab(keys, 'games', 1), 'settings');
      expect(stepProfileTab(keys, 'settings', -1), 'games');
    });

    test('stops at the first and the last tab, without looping', () {
      expect(stepProfileTab(keys, 'games', -1), 'games');
      expect(stepProfileTab(keys, 'settings', 1), 'settings');
    });

    test('does not skip a tab', () {
      var tab = 'games';
      final seen = <String>[tab];
      for (var i = 0; i < keys.length; i++) {
        tab = stepProfileTab(keys, tab, 1);
        seen.add(tab);
      }
      expect(seen, ['games', 'settings', 'settings']);
    });

    test('an unknown tab stays where it is', () {
      expect(stepProfileTab(keys, 'tours', 1), 'tours');
    });
  });
}
