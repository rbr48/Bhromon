/// How often an open group screen refreshes its presence document.
const Duration kPresenceHeartbeat = Duration(seconds: 60);

/// A member whose last refresh is older than this is shown as away. A phone
/// that loses signal, or is closed, stops refreshing and drops out by itself.
const Duration kPresenceStaleAfter = Duration(minutes: 3);

/// Whether a member last seen at [lastSeen] is online at [now].
bool isOnlineAt(DateTime? lastSeen, DateTime now) {
  if (lastSeen == null) return false;
  return now.difference(lastSeen) <= kPresenceStaleAfter;
}
