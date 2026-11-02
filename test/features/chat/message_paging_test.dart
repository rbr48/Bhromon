import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/chat/domain/message_paging.dart';

/// A message with an id and a version, so an update is visible.
typedef _Msg = ({String id, int version});

String _id(_Msg m) => m.id;

_Msg _m(String id, [int version = 1]) => (id: id, version: version);

List<String> _ids(List<_Msg> list) => [for (final m in list) m.id];

void main() {
  group('applyNewestPage', () {
    test('adds a brand new message at the top', () {
      final result = applyNewestPage<_Msg>(
        loaded: [_m('b'), _m('a')],
        newest: [_m('c'), _m('b')],
        idOf: _id,
      );
      expect(_ids(result), ['c', 'b', 'a']);
    });

    test('updates a loaded message in place without moving it', () {
      final result = applyNewestPage<_Msg>(
        loaded: [_m('b'), _m('a')],
        newest: [_m('b', 2), _m('a')],
        idOf: _id,
      );
      expect(_ids(result), ['b', 'a']);
      expect(result.first.version, 2);
    });

    test('never duplicates a message that is already on screen', () {
      final result = applyNewestPage<_Msg>(
        loaded: [_m('c'), _m('b'), _m('a')],
        newest: [_m('c'), _m('b')],
        idOf: _id,
      );
      expect(_ids(result), ['c', 'b', 'a']);
    });
  });

  group('appendOlderPage', () {
    test('adds older messages at the end', () {
      final result = appendOlderPage<_Msg>(
        loaded: [_m('c'), _m('b')],
        older: [_m('a'), _m('0')],
        idOf: _id,
      );
      expect(_ids(result), ['c', 'b', 'a', '0']);
    });

    test('skips messages that are already loaded', () {
      final result = appendOlderPage<_Msg>(
        loaded: [_m('c'), _m('b')],
        older: [_m('b'), _m('a')],
        idOf: _id,
      );
      expect(_ids(result), ['c', 'b', 'a']);
    });
  });

  test('scrolling back after a new message keeps every message once', () {
    // Newest page of three, then one older page of two.
    var list = applyNewestPage<_Msg>(
      loaded: const [],
      newest: [_m('9'), _m('8'), _m('7')],
      idOf: _id,
    );
    list = appendOlderPage<_Msg>(
      loaded: list,
      older: [_m('6'), _m('5')],
      idOf: _id,
    );

    // A new message arrives while the user is scrolled back. The live page is
    // the newest three again, now with 10 on top.
    list = applyNewestPage<_Msg>(
      loaded: list,
      newest: [_m('10'), _m('9'), _m('8')],
      idOf: _id,
    );

    // The next page starts after the oldest message loaded so far, which is
    // '5'. Older messages '4' and '3' are added once.
    list = appendOlderPage<_Msg>(
      loaded: list,
      older: [_m('4'), _m('3')],
      idOf: _id,
    );

    expect(_ids(list), ['10', '9', '8', '7', '6', '5', '4', '3']);
  });
}
