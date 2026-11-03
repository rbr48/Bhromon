/// The tabs of the person's own profile, and how a swipe moves between them.
///
/// With kGroupsV2 the groups list is on the Groups tab, so the profile has no groups
/// tab, and it opens on Games (P4.1).
List<String> profileTabKeys({required bool groupsV2}) {
  return groupsV2
      ? const ['games', 'vault', 'settings']
      : const ['tours', 'games', 'vault', 'settings'];
}

/// The tab a profile opens on.
String defaultProfileTab({required bool groupsV2}) =>
    groupsV2 ? 'games' : 'tours';

/// The tab a swipe moves to: [by] steps from [current] within [keys]. A swipe stops at
/// the first and the last tab, and does not wrap round. An unknown [current] stays put.
String stepProfileTab(List<String> keys, String current, int by) {
  final index = keys.indexOf(current);
  if (index < 0) return current;
  final next = (index + by).clamp(0, keys.length - 1);
  return keys[next];
}
