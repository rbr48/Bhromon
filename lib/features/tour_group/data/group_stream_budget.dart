import 'package:flutter/foundation.dart';

/// Counts the shared upstream subscriptions the groups screens hold: one for the
/// groups list, and one per tour for its members and for its family list. In the style of
/// [ChannelListenerBudget]. A debug build asserts when one key holds more than
/// [maxPerKey] upstreams, which would mean a screen has opened its own listener
/// again instead of sharing the one it has.
class GroupStreamBudget {
  GroupStreamBudget._();

  /// The key of the one groups list for the whole app.
  static const String myGroups = 'myGroups';

  /// The key of one tour's members stream.
  static String membersKey(String tourId) => 'members:$tourId';

  /// The key of one circle's shared family list.
  static String familyTasksKey(String tourId) => 'family_tasks:$tourId';

  /// The most upstreams one key may hold at once.
  static const int maxPerKey = 1;

  static final Map<String, int> _live = <String, int>{};
  static int _opened = 0;

  /// Upstreams held right now under [key].
  static int liveOf(String key) => _live[key] ?? 0;

  /// Upstreams held right now, under every key.
  static int get live => _live.values.fold(0, (sum, n) => sum + n);

  /// Upstreams opened since the last [reset], under every key. It counts starts,
  /// not the upstreams held, so a stream that is opened and closed again adds one.
  static int get opened => _opened;

  /// Counts one upstream opened under [key]. Asserts in debug when [key] now holds more
  /// than [maxPerKey].
  static void open(String key) {
    final now = liveOf(key) + 1;
    _live[key] = now;
    _opened++;
    assert(
      now <= maxPerKey,
      '$key holds $now upstreams; the budget is $maxPerKey. A screen opened its own listener.',
    );
  }

  /// Counts one upstream closed under [key]. Closing a key with none open does nothing.
  static void close(String key) {
    final now = liveOf(key) - 1;
    if (now <= 0) {
      _live.remove(key);
    } else {
      _live[key] = now;
    }
  }

  /// Clears the counts between tests.
  @visibleForTesting
  static void reset() {
    _live.clear();
    _opened = 0;
  }
}
