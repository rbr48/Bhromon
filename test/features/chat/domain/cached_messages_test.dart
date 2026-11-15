import 'package:bhromon/features/chat/domain/cached_messages.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// The messages kept on the phone are restored and ordered before a chat shows them, and a
// message is compared through its nested values.

Map<String, dynamic> _cached(String id, String iso,
        [Map<String, dynamic> more = const {}]) =>
    {'id': id, 'timestamp': iso, 'text': 'message $id', ...more};

void main() {
  group('newestCachedMessages', () {
    test('gives the newest first, whatever order the cache holds them in', () {
      final shown = newestCachedMessages([
        _cached('b', '2026-11-10T10:00:00.000'),
        _cached('c', '2026-11-12T10:00:00.000'),
        _cached('a', '2026-11-09T10:00:00.000'),
      ], limit: 30);

      expect([for (final m in shown) m['id']], ['c', 'b', 'a']);
    });

    test('keeps only the newest up to the limit', () {
      final shown = newestCachedMessages([
        for (var day = 1; day <= 5; day++)
          _cached('m$day', '2026-11-0${day}T10:00:00.000'),
      ], limit: 2);

      expect([for (final m in shown) m['id']], ['m5', 'm4']);
    });

    test('turns the stored times back into timestamps', () {
      final shown = newestCachedMessages([
        _cached('a', '2026-11-09T10:00:00.000',
            {'editedAt': '2026-11-09T11:00:00.000'}),
      ], limit: 30);

      expect(shown.single['timestamp'], isA<Timestamp>());
      expect(
        (shown.single['timestamp'] as Timestamp).toDate(),
        DateTime(2026, 11, 9, 10),
      );
      expect(shown.single['editedAt'], isA<Timestamp>());
      expect(shown.single['text'], 'message a');
    });

    test('leaves out a message with no id or no usable time', () {
      final shown = newestCachedMessages([
        {'timestamp': '2026-11-09T10:00:00.000', 'text': 'no id'},
        {'id': 'x', 'text': 'no time'},
        {'id': 'y', 'timestamp': 'not a time'},
        _cached('ok', '2026-11-09T10:00:00.000'),
      ], limit: 30);

      expect([for (final m in shown) m['id']], ['ok']);
    });

    test('keeps a nested map usable, such as the reactions', () {
      final shown = newestCachedMessages([
        _cached('a', '2026-11-09T10:00:00.000', {
          'reactions': <dynamic, dynamic>{'u1': '❤️'},
        }),
      ], limit: 30);

      expect(shown.single['reactions'], isA<Map<String, dynamic>>());
    });

    test('a text that looks like a time is not touched', () {
      final restored =
          restoreCachedMessage({'id': 'a', 'text': '2026-11-09T10:00:00.000'});
      expect(restored['text'], '2026-11-09T10:00:00.000');
    });
  });

  group('messageDataEquals', () {
    test('two copies of the same message are equal', () {
      Map<String, dynamic> message() => {
            'text': 'hello',
            'timestamp': Timestamp.fromMillisecondsSinceEpoch(1000),
            'reactions': {'u1': '👍'},
            'mediaUrls': ['a', 'b'],
          };
      expect(messageDataEquals(message(), message()), isTrue);
    });

    test('a changed tick, reaction or list entry is seen', () {
      final base = {
        'status': 'sent',
        'reactions': {'u1': '👍'},
        'mediaUrls': ['a', 'b'],
      };
      expect(messageDataEquals(base, {...base, 'status': 'read'}), isFalse);
      expect(
        messageDataEquals(base, {
          ...base,
          'reactions': {'u1': '❤️'},
        }),
        isFalse,
      );
      expect(
        messageDataEquals(base, {
          ...base,
          'mediaUrls': ['a'],
        }),
        isFalse,
      );
      expect(messageDataEquals(base, {...base, 'seen': true}), isFalse);
    });
  });
}
