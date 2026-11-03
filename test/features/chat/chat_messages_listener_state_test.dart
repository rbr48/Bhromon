import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/chat/domain/chat_messages_listener_state.dart';

void main() {
  group('ChatMessagesListenerState', () {
    test('a listener is not delivering until its first snapshot', () {
      final state = ChatMessagesListenerState()..opened();
      expect(state.isDelivering, isFalse);
      state.delivered();
      expect(state.isDelivering, isTrue);
    });

    test('a failed listener is not delivering', () {
      final state = ChatMessagesListenerState()
        ..opened()
        ..delivered()
        ..failed();
      expect(state.isDelivering, isFalse);
    });

    test('a chat that already exists never asks for a restart', () {
      final state = ChatMessagesListenerState()..opened();
      expect(
        state.documentSnapshot(exists: true, hasPendingWrites: false),
        isFalse,
      );
      expect(
        state.documentSnapshot(exists: true, hasPendingWrites: false),
        isFalse,
      );
    });

    test('the chat appearing restarts a refused listener once', () {
      // Opened before the chat existed: the rules refused it and it failed.
      final state = ChatMessagesListenerState()
        ..opened()
        ..failed();
      expect(
        state.documentSnapshot(exists: false, hasPendingWrites: false),
        isFalse,
      );
      expect(
        state.documentSnapshot(exists: true, hasPendingWrites: false),
        isTrue,
      );

      // The restarted listener delivers; later snapshots ask for nothing.
      state
        ..opened()
        ..delivered();
      expect(
        state.documentSnapshot(exists: true, hasPendingWrites: false),
        isFalse,
      );
    });

    test(
        'this device\'s own pending write does not count as the chat appearing',
        () {
      final state = ChatMessagesListenerState()
        ..opened()
        ..failed();
      state.documentSnapshot(exists: false, hasPendingWrites: false);

      // The sender's local copy of the new chat, before the server has it.
      expect(
        state.documentSnapshot(exists: true, hasPendingWrites: true),
        isFalse,
      );
      // The server confirms the chat: now it asks for the restart.
      expect(
        state.documentSnapshot(exists: true, hasPendingWrites: false),
        isTrue,
      );
    });

    test('a listener that is delivering is not restarted when the chat appears',
        () {
      final state = ChatMessagesListenerState()
        ..opened()
        ..delivered();
      state.documentSnapshot(exists: false, hasPendingWrites: false);
      expect(
        state.documentSnapshot(exists: true, hasPendingWrites: false),
        isFalse,
      );
    });

    test('a chat that disappears asks for nothing', () {
      final state = ChatMessagesListenerState()..opened();
      state.documentSnapshot(exists: true, hasPendingWrites: false);
      expect(
        state.documentSnapshot(exists: false, hasPendingWrites: false),
        isFalse,
      );
    });

    test('a confirmed write restarts only a listener that is not delivering',
        () {
      final pending = ChatMessagesListenerState()..opened();
      expect(pending.documentWriteConfirmed(), isTrue);

      final refused = ChatMessagesListenerState()
        ..opened()
        ..failed();
      expect(refused.documentWriteConfirmed(), isTrue);

      final delivering = ChatMessagesListenerState()
        ..opened()
        ..delivered();
      expect(delivering.documentWriteConfirmed(), isFalse);
    });
  });
}
