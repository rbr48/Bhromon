import 'package:bhromon/features/tour_group/domain/services/chat_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

List<ChatSpan> _spans(String text) => parseChatMarkdown(text).single.spans;

String _visible(String text) =>
    parseChatMarkdown(text).expand((l) => l.spans).map((s) => s.text).join();

void main() {
  group('chat markdown', () {
    test('plain text is one unstyled span', () {
      final spans = _spans('hello there');
      expect(spans, hasLength(1));
      expect(spans.single.text, 'hello there');
      expect(spans.single.bold || spans.single.italic || spans.single.strike,
          isFalse);
    });

    test('bold, italic and strike-through', () {
      final spans = _spans('a **b** *c* ~~d~~');
      expect(spans.firstWhere((s) => s.text == 'b').bold, isTrue);
      expect(spans.firstWhere((s) => s.text == 'c').italic, isTrue);
      expect(spans.firstWhere((s) => s.text == 'd').strike, isTrue);
    });

    test('underscores italicise a word but not a name with underscores', () {
      expect(_spans('_hi_').single.italic, isTrue);
      final snake = _spans('snake_case_name');
      expect(snake.single.italic, isFalse);
      expect(snake.single.text, 'snake_case_name');
    });

    test('an asterisk followed by a space is ordinary text', () {
      expect(_visible('2 * 3 * 4'), '2 * 3 * 4');
      expect(_spans('2 * 3 * 4').any((s) => s.italic), isFalse);
    });

    test('code is not formatted inside', () {
      final code = _spans('run `**not bold**` now').firstWhere((s) => s.code);
      expect(code.text, '**not bold**');
      expect(code.bold, isFalse);
    });

    test('a spoiler is hidden, and its spans share one id', () {
      final spans = _spans('x ||secret **bold**|| y ||again||');
      final first =
          spans.where((s) => s.spoilerId == 0).map((s) => s.text).join();
      expect(first, 'secret bold');
      expect(spans.any((s) => s.spoilerId == 1 && s.text == 'again'), isTrue);
    });

    test('unmatched markers stay as typed', () {
      expect(_visible('**oops'), '**oops');
      expect(_visible('a || b'), 'a || b');
    });

    test('a link is found, and punctuation after it is left out', () {
      final spans = _spans('see https://maps.example/x. then');
      expect(spans.firstWhere((s) => s.link != null).link,
          'https://maps.example/x');
      expect(_visible('see https://maps.example/x. then'),
          'see https://maps.example/x. then');
    });

    test('a bare scheme is not a link', () {
      expect(_spans('https://.').any((s) => s.link != null), isFalse);
    });

    test('a line starting with "> " is a quote', () {
      final lines = parseChatMarkdown('> quoted\nnormal');
      expect(lines[0].quote, isTrue);
      expect(lines[0].spans.single.text, 'quoted');
      expect(lines[1].quote, isFalse);
    });

    test('no text is lost when markers are removed', () {
      const text = 'mix **a** _b_ ~~c~~ `d` ||e|| https://f.g ok';
      expect(_visible(text), 'mix a b c d e https://f.g ok');
    });

    test('underline with double underscore', () {
      final spans = _spans('this is __underlined__ text');
      final underlined = spans.firstWhere((s) => s.text == 'underlined');
      expect(underlined.underline, isTrue);
      expect(underlined.italic, isFalse);
    });

    test('highlight with double equals', () {
      final spans = _spans('important ==urgent notice== here');
      final highlighted = spans.firstWhere((s) => s.text == 'urgent notice');
      expect(highlighted.highlight, isTrue);
    });

    test('named markdown link [label](url)', () {
      final spans = _spans('Check out [Bhromon App](https://bhromon.fun) now');
      final linkSpan = spans.firstWhere((s) => s.link != null);
      expect(linkSpan.text, 'Bhromon App');
      expect(linkSpan.link, 'https://bhromon.fun');
      expect(linkSpan.underline, isTrue);
    });

    test('parseChatBlocks parses headings', () {
      final blocks = parseChatBlocks('# Main Title\n## Subtitle\n### Section');
      expect(blocks, hasLength(3));
      expect(blocks[0], isA<ChatHeadingBlock>());
      expect((blocks[0] as ChatHeadingBlock).level, 1);
      expect((blocks[0] as ChatHeadingBlock).spans.single.text, 'Main Title');
      expect((blocks[1] as ChatHeadingBlock).level, 2);
      expect((blocks[2] as ChatHeadingBlock).level, 3);
    });

    test('parseChatBlocks parses fenced code block with language', () {
      const input = '```dart\nvoid main() {\n  print("hello");\n}\n```';
      final blocks = parseChatBlocks(input);
      expect(blocks, hasLength(1));
      expect(blocks.single, isA<ChatCodeBlock>());
      final codeBlock = blocks.single as ChatCodeBlock;
      expect(codeBlock.language, 'dart');
      expect(codeBlock.code, 'void main() {\n  print("hello");\n}');
    });

    test('parseChatBlocks parses markdown table with alignments', () {
      const input = '''
| Destination | Budget | Status |
| :--- | :---: | ---: |
| Cox's Bazar | ৳ 5,500 | Confirmed |
| Sajek Valley | ৳ 7,200 | Planning |
''';
      final blocks = parseChatBlocks(input.trim());
      expect(blocks, hasLength(1));
      expect(blocks.single, isA<ChatTableBlock>());
      final table = blocks.single as ChatTableBlock;
      expect(table.headers, hasLength(3));
      expect(table.headers[0].plainText, 'Destination');
      expect(table.headers[1].plainText, 'Budget');
      expect(table.headers[2].plainText, 'Status');

      expect(table.alignments[0], ChatTableAlign.left);
      expect(table.alignments[1], ChatTableAlign.center);
      expect(table.alignments[2], ChatTableAlign.right);

      expect(table.rows, hasLength(2));
      expect(table.rows[0].cells[0].plainText, "Cox's Bazar");
      expect(table.rows[0].cells[1].plainText, "৳ 5,500");
      expect(table.rows[0].cells[2].plainText, "Confirmed");
      expect(table.rows[1].cells[0].plainText, "Sajek Valley");
    });

    test('parseChatBlocks parses task checklists and lists', () {
      const input = '''
- [ ] Buy tickets
- [x] Book hotel
- Regular item
''';
      final blocks = parseChatBlocks(input.trim());
      expect(blocks, hasLength(1));
      expect(blocks.single, isA<ChatListBlock>());
      final list = blocks.single as ChatListBlock;
      expect(list.ordered, isFalse);
      expect(list.items, hasLength(3));
      expect(list.items[0].isChecked, isFalse);
      expect(list.items[0].spans.single.text, 'Buy tickets');
      expect(list.items[1].isChecked, isTrue);
      expect(list.items[1].spans.single.text, 'Book hotel');
      expect(list.items[2].isChecked, isNull);
      expect(list.items[2].spans.single.text, 'Regular item');
    });

    test('parseChatBlocks parses horizontal divider', () {
      final blocks = parseChatBlocks('first line\n---\nsecond line');
      expect(blocks, hasLength(3));
      expect(blocks[0], isA<ChatParagraphBlock>());
      expect(blocks[1], isA<ChatDividerBlock>());
      expect(blocks[2], isA<ChatParagraphBlock>());
    });

    test(
        'parseChatBlocks parses Bengali comparison table with leading paragraphs',
        () {
      const input = '''
হোয়াটসঅ্যাপের চ্যাটে নোটিশ আর হিসাব হারিয়ে যায়? বেছে নিন ‘ভ্রমণ (Bhromon)’! 🇧🇩✨
⚖️ হোয়াটসঅ্যাপ বনাম ভ্রমণ (Bhromon): পার্থক্য কোথায়?
| বিষয় / ফিচার | ❌ হোয়াটসঅ্যাপ (WhatsApp) | ✅ ভ্রমণ (Bhromon) |
|---|---|---|
| ১. খরচের হিসাব (Ledger) | কোনো বিল্ট-ইন হিসাব নেই; আলাদা লাগে। | স্মার্ট লেজার: অটোমেটিক সেটেলমেন্ট। |
| ২. মেস ও শেয়ার্ড ফ্ল্যাট | সুযোগ নেই। | ডেইলি মিল ট্র্যাকার। |
''';
      final blocks = parseChatBlocks(input.trim());
      expect(blocks.any((b) => b is ChatTableBlock), isTrue);
      final table =
          blocks.firstWhere((b) => b is ChatTableBlock) as ChatTableBlock;
      expect(table.headers, hasLength(3));
      expect(table.rows, hasLength(2));
    });

    test('parseChatBlocks parses LaTeX display math block', () {
      const text = r'''
Under the expanded accounting equation:
$$\text{Assets (A)} + \text{Expenses (E)} = \text{Liabilities (L)} + \text{Revenues (R)}$$
And the next paragraph follows.
''';
      final blocks = parseChatBlocks(text.trim());
      expect(blocks, hasLength(3));
      expect(blocks[0], isA<ChatParagraphBlock>());
      expect(blocks[1], isA<ChatMathBlock>());
      final math = blocks[1] as ChatMathBlock;
      expect(math.latex, contains(r'\text{Assets (A)}'));
      expect(blocks[2], isA<ChatParagraphBlock>());
    });

    test('parseChatBlocks parses inline LaTeX math and preserves plain prices',
        () {
      const text =
          r'Price is $100 and formula is $\text{Rate} = \frac{2}{\text{Useful Life}}$ for asset.';
      final blocks = parseChatBlocks(text);
      expect(blocks, hasLength(1));
      final para = blocks[0] as ChatParagraphBlock;
      final spans = para.lines[0].spans;
      // Should have math span for formula
      expect(spans.any((s) => s.math && s.text.contains(r'\frac')), isTrue);
      // Should have normal text containing $100
      expect(spans.any((s) => !s.math && s.text.contains(r'$100')), isTrue);
    });

    test('parseChatBlocks restores line breaks for dense collapsed pasted text',
        () {
      // 300+ chars with 0 newlines
      const denseText =
          'Source documents (invoices, receipts, bank memos).Step 2: Journalize transactions chronologically in the Journal.Step 3: Post journal entries to respective accounts.Phase II — Summarizing & Adjusting (At Period-End):Step 4: Prepare an Unadjusted Trial Balance.Step 5: Journalize and post Adjusting Entries.Step 6: Prepare an Adjusted Trial Balance.10(viii) Methods of Depreciation [4 Marks]Under IAS 16 rules.1. Straight-Line Method (SLM) is great.2. Declining-Balance Method (DBM) is also great.';
      final blocks = parseChatBlocks(denseText);
      // Because line breaks were restored, there should be multiple distinct blocks/paragraphs
      expect(blocks.length, greaterThanOrEqualTo(5));
    });
  });
}
