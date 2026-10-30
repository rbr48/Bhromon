import 'package:bhromon/features/notifications/data/notification_center_repository.dart';
import 'package:flutter_test/flutter_test.dart';

AppNotification _notification({required DateTime at, bool read = false}) =>
    AppNotification(
      id: 'n',
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
}
