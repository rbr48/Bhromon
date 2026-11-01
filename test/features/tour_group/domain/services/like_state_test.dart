import 'package:bhromon/features/tour_group/domain/services/like_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LikeState', () {
    test('shows the server state when nothing is being saved', () {
      expect(LikeState.shown(optimistic: null, onServer: true), isTrue);
      expect(LikeState.shown(optimistic: null, onServer: false), isFalse);
    });

    test('shows the state the user asked for while a save is in flight', () {
      expect(LikeState.shown(optimistic: false, onServer: true), isFalse);
      expect(LikeState.shown(optimistic: true, onServer: false), isTrue);
    });

    test('a tap asks for the opposite of what is shown', () {
      expect(LikeState.tapTarget(optimistic: null, onServer: true), isFalse);
      expect(LikeState.tapTarget(optimistic: null, onServer: false), isTrue);
      expect(LikeState.tapTarget(optimistic: false, onServer: true), isTrue);
    });

    test('two quick taps on a liked item end liked, not unliked', () {
      // The server holds "liked". The first tap asks for "unliked" and shows it. The second
      // tap comes before the server has answered, so it must ask for "liked" again.
      final first = LikeState.tapTarget(optimistic: null, onServer: true);
      expect(first, isFalse);
      final second = LikeState.tapTarget(optimistic: first, onServer: true);
      expect(second, isTrue);
    });

    test('the optimistic state is dropped only once the server holds it', () {
      expect(
        LikeState.serverCaughtUp(optimistic: true, onServer: true),
        isTrue,
      );
      expect(
        LikeState.serverCaughtUp(optimistic: true, onServer: false),
        isFalse,
      );
      expect(
        LikeState.serverCaughtUp(optimistic: null, onServer: true),
        isFalse,
      );
    });

    test('the count moves by what is shown compared with the server', () {
      expect(
        LikeState.shownCount(
            onServerCount: 3, shownLiked: true, onServerLiked: false),
        4,
      );
      expect(
        LikeState.shownCount(
            onServerCount: 3, shownLiked: false, onServerLiked: true),
        2,
      );
      expect(
        LikeState.shownCount(
            onServerCount: 3, shownLiked: true, onServerLiked: true),
        3,
      );
      expect(
        LikeState.shownCount(
            onServerCount: 0, shownLiked: false, onServerLiked: true),
        0,
      );
    });
  });
}
