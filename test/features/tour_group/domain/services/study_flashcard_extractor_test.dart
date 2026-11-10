import 'package:bhromon/features/tour_group/domain/services/study_flashcard_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StudyFlashcardExtractor', () {
    const sampleExamMarkdown = '''
### প্রশ্ন ১ [মান: ১০ + ১০ = ২০]
১(ক) উত্তরাধিকার পরিকল্পনা (Succession Planning) বলতে কী বুঝায়? [৪ নম্বর]
প্রতিষ্ঠানের প্রধান নির্বাহী (CEO) ও গুরুত্বপূর্ণ পদসমূহ শূন্য হলে যাতে নেতৃত্বের সংকট না হয়, সেজন্য আগেভাগেই যোগ্য কর্মকর্তাদের প্রস্তুত রাখা।

১(খ) উত্তরাধিকার পরিকল্পনার সুবিধাসমূহ আলোচনা করুন। [৬ নম্বর]
১. নেতৃত্বের ধারাবাহিকতা রক্ষা।
২. প্রতিষ্ঠানের মেধাবী কর্মকর্তাদের ধরে রাখা।
৩. জরুরি সংকট হ্রাস।

### Question 2 [Marks: 5 + 5 = 10]
2(a) What are the key objectives of Bank Company Act 1991?
The Bank Company Act 1991 regulates banking companies in Bangladesh to ensure depositor protection and financial stability.

2(b) Describe the powers of Bangladesh Bank under Section 45.
Under Section 45, Bangladesh Bank can issue directions to banking companies for public interest and proper banking administration.
''';

    test(
        'extracts structured question/answer flashcards with module association',
        () {
      final cards = StudyFlashcardExtractor.extractFromMarkdown(
        deckId: 'deck_lpgb',
        subjectTitle: 'Laws & Practice of General Banking (LPGB)',
        markdownContent: sampleExamMarkdown,
        today: DateTime(2026, 11, 10),
      );

      expect(cards.length, 4);

      // Card 1
      expect(cards[0].front, contains('প্রশ্ন ১ [মান: ১০ + ১০ = ২০] - ১(ক)'));
      expect(cards[0].back, contains('প্রতিষ্ঠানের প্রধান নির্বাহী'));
      expect(cards[0].deckId, 'deck_lpgb');
      expect(cards[0].box, 1);
      expect(cards[0].dueOn, '2026-11-10');

      // Card 2
      expect(cards[1].front, contains('১(খ)'));
      expect(cards[1].back, contains('নেতৃত্বের ধারাবাহিকতা রক্ষা'));

      // Card 3: Bank Company Act -> Module A
      expect(cards[2].front, contains('Question 2'));
      expect(cards[2].front, contains('2(a)'));
      expect(cards[2].back, contains('Bank Company Act 1991 regulates'));
      expect(cards[2].moduleCode, 'A');

      // Card 4: Bangladesh Bank powers -> Module A
      expect(cards[3].front, contains('2(b)'));
      expect(cards[3].moduleCode, 'A');
    });

    test('generates deterministic card IDs preventing duplicate generation',
        () {
      final run1 = StudyFlashcardExtractor.extractFromMarkdown(
        deckId: 'deck_lpgb',
        subjectTitle: 'LPGB',
        markdownContent: sampleExamMarkdown,
        today: DateTime(2026, 11, 10),
      );

      final run2 = StudyFlashcardExtractor.extractFromMarkdown(
        deckId: 'deck_lpgb',
        subjectTitle: 'LPGB',
        markdownContent: sampleExamMarkdown,
        today: DateTime(2026, 11, 10),
      );

      expect(run1.length, run2.length);
      for (var i = 0; i < run1.length; i++) {
        expect(run1[i].id, equals(run2[i].id));
      }
    });

    test('returns empty list for blank or invalid content', () {
      final cards = StudyFlashcardExtractor.extractFromMarkdown(
        deckId: 'deck_empty',
        subjectTitle: 'LPGB',
        markdownContent: '   \n\n  ',
        today: DateTime(2026, 11, 10),
      );
      expect(cards, isEmpty);
    });
  });
}
