import 'package:bhromon/features/chat/domain/chat_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chatTextMatchesQuery', () {
    test('matches exact substring', () {
      expect(chatTextMatchesQuery('Hello world', 'world'), isTrue);
      expect(chatTextMatchesQuery('Hello world', 'Hello'), isTrue);
    });

    test('case-insensitive match', () {
      expect(chatTextMatchesQuery('Dhaka to Cox\'s Bazar', 'cox'), isTrue);
      expect(chatTextMatchesQuery('MEETING AT 3PM', 'meeting'), isTrue);
      expect(chatTextMatchesQuery('sajek valley tour', 'SAJEK'), isTrue);
    });

    test('ignores leading and trailing whitespace in query', () {
      expect(chatTextMatchesQuery('Hotel Sea Crown', '  Sea Crown  '), isTrue);
    });

    test('returns false when query is empty or whitespace only', () {
      expect(chatTextMatchesQuery('Hotel Sea Crown', ''), isFalse);
      expect(chatTextMatchesQuery('Hotel Sea Crown', '   '), isFalse);
    });

    test('returns false when query does not match', () {
      expect(chatTextMatchesQuery('Hotel Sea Crown', 'Sylhet'), isFalse);
    });

    test('handles Bengali text correctly', () {
      expect(
          chatTextMatchesQuery('কক্সবাজার ভ্রমণ পরিকল্পনা', 'ভ্রমণ'), isTrue);
      expect(chatTextMatchesQuery('সাজেক ভ্যালি চাঁদের গাড়ি', 'চাঁদের গাড়ি'),
          isTrue);
      expect(chatTextMatchesQuery('সিলেট ট্যুর', 'বান্দরবান'), isFalse);
    });
  });
}
