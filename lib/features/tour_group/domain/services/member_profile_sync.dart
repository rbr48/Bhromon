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
  if (uid.isNotEmpty && (rowUid is! String || rowUid.isEmpty)) {
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
