import 'package:bhromon/features/tour_group/domain/services/chat_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a chart:ppc fence becomes a chart block', () {
    final blocks = parseChatBlocks(
      '```chart:ppc\nxmax: 100\nymax: 80\npoint A: 20 70\n```',
    );

    expect(blocks, hasLength(1));
    final chart = blocks.single as ChatChartBlock;
    expect(chart.spec.xMax, 100);
    expect(chart.spec.yMax, 80);
    expect(chart.spec.points.single.label, 'A');
  });

  test('a chart between paragraphs keeps the order of the note', () {
    final blocks = parseChatBlocks(
      'প্রথম অংশ।\n\n```chart:ppc\nxmax: 100\nymax: 80\n```\n\nশেষ অংশ।',
    );

    expect(blocks.map((b) => b.runtimeType), [
      ChatParagraphBlock,
      ChatChartBlock,
      ChatParagraphBlock,
    ]);
  });

  test('a chart fence that does not parse stays a code block', () {
    final blocks = parseChatBlocks('```chart:ppc\nxmax: 100\n```');

    final code = blocks.single as ChatCodeBlock;
    expect(code.language, 'chart:ppc');
    expect(code.code, 'xmax: 100');
  });

  test('other code fences are unchanged', () {
    final blocks = parseChatBlocks('```dart\nvoid main() {}\n```');

    final code = blocks.single as ChatCodeBlock;
    expect(code.language, 'dart');
    expect(blocks.whereType<ChatChartBlock>(), isEmpty);
  });

  test('a fenced svg block becomes a ChatSvgBlock', () {
    const rawSvg =
        '<svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="40"/></svg>';
    final blocks = parseChatBlocks('```svg\n$rawSvg\n```');

    expect(blocks, hasLength(1));
    final svgBlock = blocks.single as ChatSvgBlock;
    expect(svgBlock.svg, rawSvg);
  });

  test('a raw svg element in markdown prose becomes a ChatSvgBlock', () {
    const rawSvg =
        '<svg viewBox="0 0 100 100">\n  <rect width="100" height="100"/>\n</svg>';
    final blocks =
        parseChatBlocks('পূর্ববর্তী আলোচনা।\n\n$rawSvg\n\nপরবর্তী বিশ্লেষণ।');

    expect(blocks.map((b) => b.runtimeType), [
      ChatParagraphBlock,
      ChatSvgBlock,
      ChatParagraphBlock,
    ]);
    final svgBlock = blocks[1] as ChatSvgBlock;
    expect(svgBlock.svg, rawSvg);
  });
}
