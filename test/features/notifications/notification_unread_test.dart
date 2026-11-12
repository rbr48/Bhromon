import 'package:bhromon/features/notifications/data/notification_center_repository.dart';
import 'package:flutter_test/flutter_test.dart';

AppNotification _notification({
  String id = 'n',
  required DateTime at,
  bool read = false,
}) =>
    AppNotification(
      id: id,
      title: 'Title',
      body: '',
      action: null,
      uid: null,
      itemId: null,
      tourId: null,
      imageUrl: null,
      timestamp: at,
      read: read,
    );

void main() {
  final seenAt = DateTime(2026, 10, 30, 12);

  test('a notification newer than the last visit is unread', () {
    final n = _notification(at: seenAt.add(const Duration(minutes: 5)));

    expect(notificationIsUnread(n, seenAt), isTrue);
  });

  test('a notification from before the last visit is read', () {
    final n = _notification(at: seenAt.subtract(const Duration(minutes: 5)));

    expect(notificationIsUnread(n, seenAt), isFalse);
  });

  test('a notification marked read is never unread', () {
    final n = _notification(
      at: seenAt.add(const Duration(minutes: 5)),
      read: true,
    );

    expect(notificationIsUnread(n, seenAt), isFalse);
  });

  group('the read flag', () {
    test('only an explicit false means unread', () {
      // An entry written before the flag existed has none, and it reads as read.
      expect(readFlagMeansRead(null), isTrue);
      expect(readFlagMeansRead(true), isTrue);
      expect(readFlagMeansRead(false), isFalse);
    });
  });

  group('the bell count', () {
    test('counts only unread entries newer than the last visit', () {
      final items = [
        _notification(id: 'new', at: seenAt.add(const Duration(minutes: 1))),
        _notification(
          id: 'newRead',
          at: seenAt.add(const Duration(minutes: 2)),
          read: true,
        ),
        _notification(id: 'old', at: seenAt.subtract(const Duration(days: 1))),
      ];

      expect(unseenCount(items, seenAt), 1);
    });

    test('before the first visit every unread entry counts', () {
      final items = [
        _notification(id: 'a', at: DateTime(2026, 1, 1)),
        _notification(id: 'b', at: DateTime(2026, 2, 1), read: true),
      ];

      expect(unseenCount(items, DateTime.fromMillisecondsSinceEpoch(0)), 1);
    });
  });

  group('the list actions', () {
    final items = [
      _notification(id: 'a', at: seenAt),
      _notification(id: 'b', at: seenAt, read: true),
      _notification(id: 'c', at: seenAt),
    ];

    test('mark all read touches only the unread entries', () {
      expect(unreadIds(items), ['a', 'c']);
    });

    test('clear read removes only the read entries', () {
      expect(readIds(items), ['b']);
    });
  });
}
