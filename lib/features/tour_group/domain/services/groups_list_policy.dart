// When the list of my groups may say "you have no groups", and when a failed read is tried
// again. Pure Dart, so the decisions are tested without Firebase.
//
// After the browser's data is cleared and the person signs in again, nothing is cached. The
// list used to show the empty cache as "no groups", and one refused read (the sign-in had
// not reached the database yet) dropped a group for the rest of the session.

/// How long the list waits for the server before it shows what the cache has, even when
/// that is nothing. A phone that is offline must not wait for ever.
const Duration kGroupsServerWait = Duration(seconds: 10);

/// How many times a failed read of the memberships, or of one group, is tried again.
const int kGroupsReadRetries = 6;

/// What the list is bound to: the account and the email its memberships are stored under.
/// The email can arrive after the account does, and the memberships are looked up by email,
/// so a change of either starts the list again.
String groupsBindKey(String uid, String email) => '$uid|$email';

/// Whether a memberships answer is shown. An empty answer from the cache, before the server
/// has spoken, is not: it says only that this device remembers nothing.
bool showsMembershipAnswer({
  required bool fromCache,
  required bool empty,
  required bool heardFromServer,
}) {
  if (!fromCache) return true;
  if (!empty) return true;
  return heardFromServer;
}

/// The wait before try number [attempt] (0 for the first retry): 1, 2, 4, 8 and 16 seconds,
/// and then 30.
Duration groupsRetryDelay(int attempt) {
  if (attempt < 0) return const Duration(seconds: 1);
  if (attempt >= 5) return const Duration(seconds: 30);
  return Duration(seconds: 1 << attempt);
}

/// Whether a failed read is tried again after [attempt] earlier retries.
bool retriesGroupsRead(int attempt) => attempt < kGroupsReadRetries;
