import 'package:bhromon/features/tour_group/domain/models/study_flashcard_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_flashcard_extractor.dart';
import 'package:bhromon/features/tour_group/domain/services/study_flashcard_rules.dart';
import 'package:bhromon/features/tour_group/domain/services/study_plain_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('plainTextFromMarkdown', () {
    test('takes bold and italic marks out and keeps the words', () {
      expect(
        plainTextFromMarkdown('**[মান: ২০ × ২ = ৪০]**'),
        '[মান: ২০ × ২ = ৪০]',
      );
      expect(
        plainTextFromMarkdown('*Note* and _this_ and __that__'),
        'Note and this and that',
      );
    });

    test('leaves a lone star, or an underscore inside a word, as it is', () {
      expect(plainTextFromMarkdown('2 * 3 * 4 = 24'), '2 * 3 * 4 = 24');
      expect(plainTextFromMarkdown('snake_case_name'), 'snake_case_name');
    });

    test('takes heading and quote marks out of a past-year question', () {
      expect(
        plainTextFromMarkdown(
          '> **Question 5 — Full Verbatim Problem Statement:**\n'
          '> **At a point of time, a bank has**',
        ),
        'Question 5 — Full Verbatim Problem Statement:\n'
        'At a point of time, a bank has',
      );
      expect(
        plainTextFromMarkdown('### Question 1 [Marks: 10]'),
        'Question 1 [Marks: 10]',
      );
    });

    test(
        'keeps square brackets that are not links, and unescapes the ones that are',
        () {
      expect(plainTextFromMarkdown(r'\[Marks: 10\]'), '[Marks: 10]');
      expect(plainTextFromMarkdown(r'\*literal\* stars'), '*literal* stars');
      expect(plainTextFromMarkdown('[Marks: 10] stays'), '[Marks: 10] stays');
    });

    test('a link keeps its words and an image keeps its alt text', () {
      expect(
        plainTextFromMarkdown('see [the table](https://example.com/x) now'),
        'see the table now',
      );
      expect(
          plainTextFromMarkdown('![Balance sheet](img.png)'), 'Balance sheet');
    });

    test('code keeps its words and loses its marks', () {
      expect(plainTextFromMarkdown('Use `CRR` here'), 'Use CRR here');
      expect(
        plainTextFromMarkdown('```\nline one\nline two\n```'),
        'line one\nline two',
      );
    });

    test('a figure has no words for a card, so it is dropped', () {
      expect(
        plainTextFromMarkdown(
          'before\n```chart:ppc\ntitle: X\nx: Goods\n```\nafter',
        ),
        'before\n\nafter',
      );
      expect(plainTextFromMarkdown('<svg width="10"><rect/></svg>'), '');
    });

    test('a list item gets a bullet, and a table reads as its cells', () {
      expect(plainTextFromMarkdown('- one\n- two'), '• one\n• two');
      expect(
        plainTextFromMarkdown('| Head | Value |\n|---|---|\n| a | 10 |'),
        'Head · Value\na · 10',
      );
    });

    test('a rule leaves a gap between the lines around it', () {
      expect(plainTextFromMarkdown('one\n---\ntwo'), 'one\n\ntwo');
    });

    test('text without markup comes back as it went in', () {
      const bengali =
          'ব্যাংক কোম্পানি আইন ১৯৯১ এবং বাংলাদেশ ব্যাংকের নির্দেশনাবলী।';
      expect(plainTextFromMarkdown(bengali), bengali);
    });

    test('converting twice gives the same text as converting once', () {
      const samples = [
        '**[মান: ২০]**\n> *quote* and `code`',
        '### Heading\n- item\n| a | b |\n|---|---|\n| 1 | 2 |',
      ];
      for (final sample in samples) {
        final once = plainTextFromMarkdown(sample);
        expect(plainTextFromMarkdown(once), once);
      }
    });
  });

  group('flashcards from a markdown solution', () {
    test('the front and the back of a card are plain text', () {
      const markdown = '''
### Question 5 — Calculation of TDTL and CRR [Marks: 20]
> **Question 5 — Full Verbatim Problem Statement:**
> **At a point of time, a scheduled bank has the following liabilities:**

**Solution:** The total demand and time liabilities are worked out first, then the reserve.
''';
      final cards = StudyFlashcardExtractor.extractFromMarkdown(
        deckId: 'deck1',
        subjectTitle: 'Banking',
        markdownContent: markdown,
        today: DateTime(2026, 11, 11),
      );

      expect(cards, isNotEmpty);
      for (final card in cards) {
        expect(card.front, isNot(contains('**')));
        expect(card.back, isNot(contains('**')));
        expect(card.back, isNot(startsWith('>')));
      }
      expect(cards.first.back, contains('Full Verbatim Problem Statement'));
    });

    test('the Anki file carries plain text for a card saved with markup', () {
      final csv = toAnkiCsv([
        const StudyFlashcard(
          id: 'c1',
          deckId: 'deck1',
          front: '**Q1**',
          back: '> *answer*',
          dueOn: '2026-11-11',
        ),
      ]);

      expect(csv, '"Q1","answer"');
    });
  });
}
