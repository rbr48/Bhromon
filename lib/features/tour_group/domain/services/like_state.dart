/// What a like control shows, and what its next tap asks for.
///
/// While a like is being saved, the control shows the state the user last asked for (the
/// optimistic state). Otherwise it shows the server's state. A tap asks for the opposite of
/// what is shown, computed from what is shown and never from a stale copy of the item. So two
/// quick taps send two opposite writes in order, and the saved state is the last one asked for.
/// The optimistic state is dropped once the server holds the same state.
class LikeState {
  const LikeState._();

  /// Whether the control shows the item as liked.
  static bool shown({required bool? optimistic, required bool onServer}) =>
      optimistic ?? onServer;

  /// The state the next tap asks for: the opposite of what is shown.
  static bool tapTarget({required bool? optimistic, required bool onServer}) =>
      !shown(optimistic: optimistic, onServer: onServer);

  /// Whether the server holds the state the optimistic state asks for, so that state can go.
  static bool serverCaughtUp({
    required bool? optimistic,
    required bool onServer,
  }) =>
      optimistic != null && optimistic == onServer;

  /// The like count to show: the server's count, moved by the difference between what is shown
  /// and what the server holds. It never goes below zero.
  static int shownCount({
    required int onServerCount,
    required bool shownLiked,
    required bool onServerLiked,
  }) {
    final count =
        onServerCount + (shownLiked ? 1 : 0) - (onServerLiked ? 1 : 0);
    return count < 0 ? 0 : count;
  }
}
