import 'package:bhromon/features/tour_group/domain/services/post_view_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PostViewQueue', () {
    test('a post noted twice is handed over once', () {
      final queue = PostViewQueue()
        ..note('a', alreadyViewed: false)
        ..note('a', alreadyViewed: false);

      expect(queue.take(), ['a']);
    });

    test('a post the member has already viewed is never handed over', () {
      final queue = PostViewQueue()..note('a', alreadyViewed: true);

      expect(queue.isEmpty, isTrue);
      expect(queue.take(), isEmpty);
    });

    test('hands over the waiting posts in the order noted, then clears', () {
      final queue = PostViewQueue()
        ..note('c', alreadyViewed: false)
        ..note('a', alreadyViewed: false)
        ..note('b', alreadyViewed: false);

      expect(queue.take(), ['c', 'a', 'b']);
      expect(queue.isEmpty, isTrue);
      expect(queue.take(), isEmpty);
    });

    test('a post handed over is not queued again in the session', () {
      final queue = PostViewQueue()..note('a', alreadyViewed: false);
      queue.take();

      queue.note('a', alreadyViewed: false);

      expect(queue.isEmpty, isTrue);
    });

    test('a different post noted after a hand-over is queued', () {
      final queue = PostViewQueue()..note('a', alreadyViewed: false);
      queue.take();

      queue.note('b', alreadyViewed: false);

      expect(queue.take(), ['b']);
    });
  });
}
