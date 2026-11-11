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
}
