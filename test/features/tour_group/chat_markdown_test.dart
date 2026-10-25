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
  });
}
