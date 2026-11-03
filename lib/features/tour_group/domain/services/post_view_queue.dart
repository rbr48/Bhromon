/// The posts a member has been shown, whose views are not recorded yet.
///
/// The feed notes each post as it builds it, and the waiting views are sent
/// together with [take]. A fast scroll then costs a few writes, not one write
/// per post. A post is handed over at most once per session, so its view is
/// sent once.
class PostViewQueue {
  final Set<String> _pending = <String>{};
  final Set<String> _sent = <String>{};

  /// Whether no view is waiting to be sent.
  bool get isEmpty => _pending.isEmpty;

  /// Notes that the member was shown [postId]. [alreadyViewed] says whether the
  /// member is already listed as a viewer of it, which needs no write.
  void note(String postId, {required bool alreadyViewed}) {
    if (alreadyViewed || _sent.contains(postId)) return;
    _pending.add(postId);
  }

  /// Hands over the waiting posts, in the order they were noted, and marks them
  /// as sent. Returns an empty list when nothing is waiting.
  List<String> take() {
    if (_pending.isEmpty) return const [];
    final ids = _pending.toList();
    _pending.clear();
    _sent.addAll(ids);
    return ids;
  }
}
