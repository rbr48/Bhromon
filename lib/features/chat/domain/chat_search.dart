/// Whether a message's [text] matches a chat search [query]. The match ignores case and
/// the spaces around the query. An empty query matches nothing, and so does a message
/// whose text is not known on this device yet.
bool chatTextMatchesQuery(String text, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return false;
  return text.toLowerCase().contains(q);
}
