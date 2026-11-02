import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/chat/domain/chat_deletion.dart';

void main() {
  final sent = DateTime(2026, 11, 1, 10);
  const me = 'uid-me';
  const other = 'uid-other';

  group('canDeleteForEveryone', () {
    bool check({
      String? senderId = me,
      String currentUid = me,
      DateTime? sentAt,
      DateTime? now,
      bool alreadyDeleted = false,
    }) {
      return canDeleteForEveryone(
        senderId: senderId,
        currentUid: currentUid,
        sentAt: sentAt ?? sent,
        now: now ?? sent.add(const Duration(minutes: 5)),
        alreadyDeleted: alreadyDeleted,
      );
    }

    test('the sender can delete their own recent message', () {
      expect(check(), isTrue);
    });

    test('nobody else can delete it for everyone', () {
      expect(check(senderId: other), isFalse);
    });

    test('a signed-out viewer cannot delete anything for everyone', () {
      expect(check(currentUid: '', senderId: ''), isFalse);
    });

    test('the window is 60 hours from the time it was sent', () {
      expect(
        check(
            now: sent
                .add(kDeleteForEveryoneWindow - const Duration(minutes: 1))),
        isTrue,
      );
      expect(check(now: sent.add(kDeleteForEveryoneWindow)), isFalse);
      expect(
        check(
            now: sent.add(kDeleteForEveryoneWindow + const Duration(days: 3))),
        isFalse,
      );
    });

    test('a message with no time yet cannot be deleted for everyone', () {
      expect(
        canDeleteForEveryone(
          senderId: me,
          currentUid: me,
          sentAt: null,
          now: sent,
          alreadyDeleted: false,
        ),
        isFalse,
      );
    });

    test('a message that is already deleted is not deleted again', () {
      expect(check(alreadyDeleted: true), isFalse);
    });

    test('the window matches the messages rule', () {
      expect(kDeleteForEveryoneWindow, const Duration(hours: 60));
    });
  });

  group('isMessageHiddenByCutoff', () {
    test('no cut-off means nothing is hidden', () {
      expect(
        isMessageHiddenByCutoff(sentAt: sent, clearedAt: null),
        isFalse,
      );
    });

    test('messages up to the cut-off are hidden, including the same moment',
        () {
      expect(
        isMessageHiddenByCutoff(
          sentAt: sent.subtract(const Duration(seconds: 1)),
          clearedAt: sent,
        ),
        isTrue,
      );
      expect(
        isMessageHiddenByCutoff(sentAt: sent, clearedAt: sent),
        isTrue,
      );
    });

    test('messages after the cut-off stay visible', () {
      expect(
        isMessageHiddenByCutoff(
          sentAt: sent.add(const Duration(seconds: 1)),
          clearedAt: sent,
        ),
        isFalse,
      );
    });

    test('a message with no time yet stays visible', () {
      expect(
        isMessageHiddenByCutoff(sentAt: null, clearedAt: sent),
        isFalse,
      );
    });
  });

  group('isChatHiddenByCutoff', () {
    test('a chat that was never deleted is shown', () {
      expect(
        isChatHiddenByCutoff(clearedAt: null, lastMessageAt: sent),
        isFalse,
      );
    });

    test('a deleted chat with no new message stays hidden', () {
      expect(
        isChatHiddenByCutoff(clearedAt: sent, lastMessageAt: sent),
        isTrue,
      );
      expect(
        isChatHiddenByCutoff(
          clearedAt: sent,
          lastMessageAt: sent.subtract(const Duration(days: 2)),
        ),
        isTrue,
      );
    });

    test('a deleted chat comes back when a newer message arrives', () {
      expect(
        isChatHiddenByCutoff(
          clearedAt: sent,
          lastMessageAt: sent.add(const Duration(minutes: 1)),
        ),
        isFalse,
      );
    });

    test('a deleted chat with no known last message stays hidden', () {
      expect(
        isChatHiddenByCutoff(clearedAt: sent, lastMessageAt: null),
        isTrue,
      );
    });
  });
}
