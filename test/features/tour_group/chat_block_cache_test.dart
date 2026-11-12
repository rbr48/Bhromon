import 'package:bhromon/features/tour_group/domain/services/chat_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

// A message's blocks are parsed once and reused, so a bubble that rebuilds or scrolls back
// into view does not parse its text again.

/// The same characters as [text] in a string of its own, as a message read again from the
/// server arrives.
String _copyOf(String text) => String.fromCharCodes(text.codeUnits);

void main() {
  group('ChatBlockCache', () {
    test('a text is parsed once, and asked for again it gives the same blocks',
        () {
      final cache = ChatBlockCache();

      final first = cache.blocksOf('# Title\nsome **bold** text');
      final second = cache.blocksOf('# Title\nsome **bold** text');

      expect(identical(first, second), isTrue);
      expect(cache.length, 1);
    });

    test('the same text in another string is not parsed again', () {
      final cache = ChatBlockCache();
      const text = 'a line with a [link](https://bhromon.fun)';

      final first = cache.blocksOf(text);
      final second = cache.blocksOf(_copyOf(text));

      expect(identical(first, second), isTrue);
    });

    test('the blocks are what the parser gives', () {
      final cache = ChatBlockCache();

      final blocks = cache.blocksOf('## Plan\n- one\n- two');

      expect(blocks, hasLength(2));
      final heading = blocks[0] as ChatHeadingBlock;
      expect(heading.level, 2);
      expect(heading.spans.single.text, 'Plan');
      final list = blocks[1] as ChatListBlock;
      expect(list.items.map((item) => item.spans.single.text), ['one', 'two']);
    });

    test('the shared blocks cannot be changed', () {
      final cache = ChatBlockCache();

      final blocks = cache.blocksOf('hello');

      expect(
          () => blocks.add(const ChatDividerBlock()), throwsUnsupportedError);
    });

    test('over the limit, the text used least recently goes first', () {
      final cache = ChatBlockCache(maxEntries: 2);
      final a = cache.blocksOf('a');
      cache.blocksOf('b');
      // 'a' is used again, so 'b' is now the one used least recently.
      cache.blocksOf('a');

      cache.blocksOf('c');

      expect(cache.length, 2);
      expect(identical(cache.blocksOf('a'), a), isTrue,
          reason: 'a was used after b, so it is kept');
    });

    test('a text dropped from the cache is parsed again when it is needed', () {
      final cache = ChatBlockCache(maxEntries: 1);
      final first = cache.blocksOf('one');
      cache.blocksOf('two');

      final again = cache.blocksOf('one');

      expect(identical(first, again), isFalse);
      expect(
          (again.single as ChatParagraphBlock).lines.single.spans.single.text,
          'one');
    });

    test('the texts held stay within the character budget', () {
      final cache = ChatBlockCache(maxChars: 10);
      cache.blocksOf('12345');
      cache.blocksOf('67890');
      expect(cache.length, 2);

      cache.blocksOf('abc');

      expect(cache.length, 2, reason: 'the oldest text made room');
    });

    test('a text larger than the whole budget is parsed but not held', () {
      final cache = ChatBlockCache(maxChars: 4);

      final blocks = cache.blocksOf('longer than four');

      expect(blocks, hasLength(1));
      expect(cache.length, 0);
    });

    test('clear forgets every text', () {
      final cache = ChatBlockCache();
      final first = cache.blocksOf('hello');

      cache.clear();

      expect(cache.length, 0);
      expect(identical(cache.blocksOf('hello'), first), isFalse);
    });
  });

  test('chatBlocksOf shares one cache between its callers', () {
    const text = 'a message shown in two places';

    expect(identical(chatBlocksOf(text), chatBlocksOf(_copyOf(text))), isTrue);
  });
}
