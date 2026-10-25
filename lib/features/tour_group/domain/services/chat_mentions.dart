// @mentions in channel messages: resolving them to members, and the
// autocomplete list shown while someone is typing one.

import '../models/tour_group.dart';

/// Mentions the whole tour. "@all" is accepted as well.
const String kMentionEveryone = 'everyone';

/// Mentions the organisers: the owner and the admins.
const String kMentionAdmins = 'admin';

final RegExp _nameChar = RegExp(r'[\p{L}\p{N}_]', unicode: true);

bool _isWordChar(String ch) => _nameChar.hasMatch(ch);

/// Emails of everyone [text] mentions. Matches "@everyone", "@all", "@admin"
/// and "@" followed by a member's name, ignoring case. Only active members
/// are mentioned. A name must end at a word boundary, so "@Tan" does not
/// match "Tanvir".
List<String> resolveMentions(String text, List<TourMember> members) {
  final active =
      members.where((m) => m.status == TourMemberStatus.active).toList();
  final byLength = [...active]
    ..sort((a, b) => b.displayName.length.compareTo(a.displayName.length));
  final lower = text.toLowerCase();
  final found = <String>[];

  void add(Iterable<String> emails) {
    for (final e in emails) {
      if (!found.contains(e)) found.add(e);
    }
  }

  for (var i = 0; i < lower.length; i++) {
    if (lower[i] != '@') continue;
    if (i > 0 && _isWordChar(lower[i - 1])) continue;
    final rest = lower.substring(i + 1);

    final group = _groupAt(rest);
    if (group == kMentionEveryone) {
      add(active.map((m) => m.email));
      continue;
    }
    if (group == kMentionAdmins) {
      add(active.where((m) => m.role != TourRole.member).map((m) => m.email));
      continue;
    }

    for (final m in byLength) {
      final name = m.displayName.trim().toLowerCase();
      if (name.isEmpty || !rest.startsWith(name)) continue;
      if (rest.length > name.length && _isWordChar(rest[name.length])) continue;
      add([m.email]);
      break;
    }
  }
  return found;
}

String? _groupAt(String rest) {
  for (final group in [kMentionEveryone, 'all', kMentionAdmins]) {
    if (!rest.startsWith(group)) continue;
    if (rest.length > group.length && _isWordChar(rest[group.length])) continue;
    return group == 'all' ? kMentionEveryone : group;
  }
  return null;
}

/// The "@" being typed at the cursor, and what has been typed after it.
class MentionQuery {
  /// Index of the "@" in the text.
  final int start;

  /// What follows the "@" up to the cursor, lower-cased.
  final String query;

  const MentionQuery(this.start, this.query);
}

/// The mention being typed when the cursor sits at [cursor], or null. A
/// mention ends at the first space.
MentionQuery? activeMentionQuery(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  final before = text.substring(0, cursor);
  final at = before.lastIndexOf('@');
  if (at < 0) return null;
  if (at > 0 && _isWordChar(before[at - 1])) return null;
  final query = before.substring(at + 1);
  if (query.contains(RegExp(r'\s'))) return null;
  return MentionQuery(at, query.toLowerCase());
}

/// Labels to offer for [query]: the two groups first, then members whose name
/// or a word of their name starts with what was typed.
List<String> mentionSuggestions(
  MentionQuery query,
  List<TourMember> members, {
  int limit = 6,
}) {
  final labels = <String>[];
  if (kMentionEveryone.startsWith(query.query)) labels.add(kMentionEveryone);
  if (kMentionAdmins.startsWith(query.query)) labels.add(kMentionAdmins);
  for (final m in members) {
    if (m.status != TourMemberStatus.active) continue;
    final name = m.displayName.trim();
    if (name.isEmpty) continue;
    final lower = name.toLowerCase();
    final words = lower.split(RegExp(r'\s+'));
    if (lower.startsWith(query.query) ||
        words.any((w) => w.startsWith(query.query))) {
      labels.add(name);
    }
  }
  return labels.take(limit).toList();
}

/// [text] with the mention being typed replaced by "@label ".
String applyMention(String text, MentionQuery query, int cursor, String label) {
  final before = text.substring(0, query.start);
  final after = text.substring(cursor).trimLeft();
  return '$before@$label $after';
}
