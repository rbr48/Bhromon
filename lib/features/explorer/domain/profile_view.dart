/// Pure rules for what a profile page shows, so that someone else's profile
/// never shows the signed-in person's own details.
library;

/// The @handle on a profile: the part of the person's email before the @, or
/// their name in lower case with underscores when the email is not known.
/// Characters other than letters, digits, `_` and `.` are dropped.
String profileHandle({required String email, required String displayName}) {
  final source = email.contains('@')
      ? email.split('@').first
      : displayName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
  final handle = source.replaceAll(RegExp(r'[^a-zA-Z0-9_.]'), '');
  return handle.isEmpty ? 'member' : handle;
}

/// The groups a profile lists. Your own profile lists all your groups.
/// Someone else's lists only the groups you both belong to, and none while
/// that is still being worked out ([sharedIds] is null).
List<T> profileGroups<T>({
  required bool isOwnProfile,
  required List<T> myGroups,
  required Set<String>? sharedIds,
  required String Function(T group) idOf,
}) {
  if (isOwnProfile) return myGroups;
  if (sharedIds == null) return const [];
  return [
    for (final group in myGroups)
      if (sharedIds.contains(idOf(group))) group,
  ];
}
