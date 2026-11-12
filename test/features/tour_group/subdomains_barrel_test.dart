import 'package:bhromon/features/tour_group/ledger/ledger.dart';
import 'package:bhromon/features/tour_group/study_circle/study_circle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tour_group sub-domain barrel exports', () {
    test('study_circle barrel exposes study models and rule engines', () {
      expect(StudyModuleKey.values, isNotEmpty);
      expect(StudyModuleKey.flashcards.isBookModule, isTrue);
      const streak = StudyDailyStreak.empty;
      expect(streak.currentStreak, 0);
      expect(streak.tier, StudyStreakTier.none);
    });

    test('ledger barrel exposes expense models, MFS parser, and ledger engine',
        () {
      expect(TripLedgerEngine.parseTakaInput('250'), 25000);
      expect(SplitMode.family.name, 'family');
      final parsedMfs = MfsSmsParser.parse(
        'You have received Tk 500.00 from 01712345678. TrxID 9A8B7C6D5E at 12/11/2026 10:15',
      );
      expect(parsedMfs, isNotNull);
      expect(parsedMfs!.trxId, '9A8B7C6D5E');
    });
  });
}
