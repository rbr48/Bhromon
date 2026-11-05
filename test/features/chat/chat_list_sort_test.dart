import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/chat/domain/chat_list_sort.dart';

ChatListRow _row(String id, {DateTime? at, String? name}) => ChatListRow(
      chatId: id,
      lastMessageAt: at,
      otherName: name,
    );

List<String> _ids(List<ChatListRow> rows) =>
    [for (final row in rows) row.chatId];

void main() {
  final now = DateTime(2026, 11, 5, 12);

  group('recent (the default order)', () {
    test('puts the newest message first', () {
      final rows = [
        _row('a', at: now.subtract(const Duration(hours: 2))),
        _row('b', at: now),
        _row('c', at: now.subtract(const Duration(days: 1))),
      ];
      final sorted = sortChatRows(rows, ChatListSort.recent, (r) => r);
      expect(_ids(sorted), ['b', 'a', 'c']);
    });

    test('puts a chat with no message time after every dated chat', () {
      final rows = [
        _row('none-1'),
        _row('old', at: now.subtract(const Duration(days: 9))),
        _row('none-2'),
        _row('new', at: now),
      ];
      final sorted = sortChatRows(rows, ChatListSort.recent, (r) => r);
      expect(_ids(sorted), ['new', 'old', 'none-1', 'none-2']);
    });

    test('breaks equal times by chat id, so the order is stable', () {
      final rows = [
        _row('chat-c', at: now),
        _row('chat-a', at: now),
        _row('chat-b', at: now),
      ];
      final sorted = sortChatRows(rows, ChatListSort.recent, (r) => r);
      expect(_ids(sorted), ['chat-a', 'chat-b', 'chat-c']);
    });

    test('ignores the stored name', () {
      final rows = [
        _row('a', at: now.subtract(const Duration(hours: 1)), name: 'Aaron'),
        _row('b', at: now, name: 'Zed'),
      ];
      final sorted = sortChatRows(rows, ChatListSort.recent, (r) => r);
      expect(_ids(sorted), ['b', 'a']);
    });
  });

  group('name', () {
    test('sorts A to Z, ignoring case and surrounding spaces', () {
      final rows = [
        _row('1', name: 'carol'),
        _row('2', name: '  Alice '),
        _row('3', name: 'bob'),
      ];
      final sorted = sortChatRows(rows, ChatListSort.name, (r) => r);
      expect(_ids(sorted), ['2', '3', '1']);
    });

    test('puts a chat with no stored name after the named ones', () {
      final rows = [
        _row('no-name', at: now),
        _row('blank', name: '   ', at: now),
        _row('zed', name: 'Zed'),
        _row('amy', name: 'Amy'),
      ];
      final sorted = sortChatRows(rows, ChatListSort.name, (r) => r);
      expect(_ids(sorted), ['amy', 'zed', 'blank', 'no-name']);
    });

    test('breaks equal names by the newest message', () {
      final rows = [
        _row('older', name: 'Sam', at: now.subtract(const Duration(days: 2))),
        _row('newer', name: 'Sam', at: now),
      ];
      final sorted = sortChatRows(rows, ChatListSort.name, (r) => r);
      expect(_ids(sorted), ['newer', 'older']);
    });
  });

  test('returns a new list and leaves the input unchanged', () {
    final input = [
      _row('a', at: now.subtract(const Duration(hours: 1))),
      _row('b', at: now),
    ];
    final sorted = sortChatRows(input, ChatListSort.recent, (r) => r);
    expect(identical(sorted, input), isFalse);
    expect(_ids(input), ['a', 'b']);
    expect(_ids(sorted), ['b', 'a']);
  });

  test('sorts any item type through rowOf, as the chats list does', () {
    final chats = <Map<String, Object?>>[
      {'id': 'x', 'time': now.subtract(const Duration(hours: 3))},
      {'id': 'y', 'time': now},
    ];
    final sorted = sortChatRows(
      chats,
      ChatListSort.recent,
      (chat) => _row(chat['id']! as String, at: chat['time'] as DateTime?),
    );
    expect([for (final chat in sorted) chat['id']], ['y', 'x']);
  });

  test('the chats list opens on recent and sorts both of its lists', () {
    // Source check, like the navigation test: the screen must start on recent and
    // sort the server list and the offline list, so a change cannot drop either.
    final screen =
        File('lib/features/chat/presentation/pages/chats_list_screen.dart')
            .readAsStringSync();
    expect(screen, contains('ChatListSort _sort = ChatListSort.recent;'));
    expect('sortChatRows('.allMatches(screen).length, 2);
  });
}
