import 'package:bhromon/features/chat/domain/chat_search.dart';
import 'package:flutter_test/flutter_test.dart';

// Chat search matches the text of a message (E2EE_DESIGN.md, section 11, M4 item 7).
// An encrypted message has text only once this device has read it.

void main() {
  test('matches regardless of case', () {
    expect(chatTextMatchesQuery('Meet at the Hotel', 'hotel'), isTrue);
    expect(chatTextMatchesQuery('meet at the hotel', 'HOTEL'), isTrue);
  });

  test('ignores the spaces around the query', () {
    expect(chatTextMatchesQuery('meet at 5', '  at  '), isTrue);
  });

  test('an empty or blank query matches nothing', () {
    expect(chatTextMatchesQuery('anything', ''), isFalse);
    expect(chatTextMatchesQuery('anything', '   '), isFalse);
  });

  test('a message without text on this device does not match', () {
    expect(chatTextMatchesQuery('', 'hotel'), isFalse);
  });

  test('a message that does not contain the query does not match', () {
    expect(chatTextMatchesQuery('meet at 5', 'dinner'), isFalse);
  });

  test('matches Bengali text', () {
    expect(chatTextMatchesQuery('আজ ঢাকায় দেখা হবে', 'ঢাকা'), isTrue);
  });
}
