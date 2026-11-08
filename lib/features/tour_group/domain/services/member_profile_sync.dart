/// The fields a member's own row must hold, computed from the signed-in person.
///
/// Returns only the fields that differ, so a row that is already right gets no write.
/// Running it again on the rows it returns gives no further changes.
///
/// * `uid` is filled in when the row has none (an admin added the person by email).
/// * `displayName` follows the in-app name, unless the name is still the placeholder
///   `Explorer`.
/// * `photoUrl` follows the in-app photo when there is one.
Map<String, Object> memberRowUpdates({
  required Map<String, dynamic> row,
  required String uid,
  required String displayName,
  required String? photoUrl,
}) {
  final updates = <String, Object>{};
  final rowUid = row['uid'];
  if (uid.isNotEmpty && rowUid != uid) {
    updates['uid'] = uid;
  }
  if (displayName != 'Explorer' && row['displayName'] != displayName) {
    updates['displayName'] = displayName;
  }
  if (photoUrl != null && row['photoUrl'] != photoUrl) {
    updates['photoUrl'] = photoUrl;
  }
  return updates;
}

/// Writes the [updatesFor] of each row through [write], and returns how many rows were
/// written. A row that needs nothing is not written. A row whose write fails goes to
/// [onFailure] and is skipped, so the other rows are still written.
Future<int> applyMemberRowSync<R>(
  Iterable<R> rows, {
  required Map<String, Object> Function(R row) updatesFor,
  required Future<void> Function(R row, Map<String, Object> updates) write,
  required void Function(Object error, StackTrace stackTrace) onFailure,
}) async {
  var written = 0;
  for (final row in rows) {
    final updates = updatesFor(row);
    if (updates.isEmpty) continue;
    try {
      await write(row, updates);
      written++;
    } catch (error, stackTrace) {
      onFailure(error, stackTrace);
    }
  }
  return written;
}
