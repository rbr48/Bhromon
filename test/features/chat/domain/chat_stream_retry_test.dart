import 'package:bhromon/features/chat/domain/chat_stream_retry.dart';
import 'package:flutter_test/flutter_test.dart';

// A failed messages listener is opened again after a growing wait, and only for a chat that
// exists.

void main() {
  test('the wait doubles from one second and stops at the cap', () {
    expect(
      [for (var i = 0; i < 8; i++) chatStreamRetryDelay(i).inSeconds],
      [1, 2, 4, 8, 16, 30, 30, 30],
    );
    expect(chatStreamRetryDelay(-3), const Duration(seconds: 1));
    expect(chatStreamRetryDelay(1000), kChatStreamRetryCap);
  });

  test('a failed listener of an existing chat is retried once at a time', () {
    expect(
      shouldRetryChatStream(
          failed: true, chatExists: true, retryPending: false),
      isTrue,
    );
    expect(
      shouldRetryChatStream(failed: true, chatExists: true, retryPending: true),
      isFalse,
    );
  });

  test('a chat that does not exist yet is not retried', () {
    expect(
      shouldRetryChatStream(
          failed: true, chatExists: false, retryPending: false),
      isFalse,
    );
  });

  test('a listener that is delivering is left alone', () {
    expect(
      shouldRetryChatStream(
          failed: false, chatExists: true, retryPending: false),
      isFalse,
    );
  });
}
