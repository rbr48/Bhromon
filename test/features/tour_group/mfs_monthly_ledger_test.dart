// test/features/tour_group/mfs_monthly_ledger_test.dart
//
// Unit tests for Bhromon's MFS SMS parser, duplicate TrxID guard,
// monthly carry-forward ledger engine, and Bangla numeral/currency formatter.

import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/tour_group/domain/models/expense_models.dart';
import 'package:bhromon/features/tour_group/domain/services/mfs_sms_parser.dart';
import 'package:bhromon/features/tour_group/data/monthly_ledger_pdf.dart';
import 'package:bhromon/features/tour_group/domain/services/trip_ledger_engine.dart';

void main() {
  group('MfsSmsParser & MfsTrxIdValidator', () {
    test('parses standard bKash Send Money SMS with fee and timestamp', () {
      const sms =
          'You have sent Tk 1,500.00 to 01712344821. Fee Tk 5.00. Balance Tk 4,210.50. TrxID BKL890XYZ1 at 05/11/2026 14:32';
      final parsed = MfsSmsParser.parse(sms);

      expect(parsed, isNotNull);
      expect(parsed!.provider, MfsProvider.bkash);
      expect(parsed.trxId, 'BKL890XYZ1');
      expect(parsed.amountPaisa, 150000);
      expect(parsed.feePaisa, 500);
      expect(parsed.counterpartyMaskedPhone, '017****4821');
      expect(parsed.transactionTime, DateTime(2026, 11, 5, 14, 32));
    });

    test('parses Nagad Cash Out SMS with Bengali numerals normalized', () {
      const sms =
          'Cash Out Tk ২,৫০০.০০ successful to 01899887766. Charge: Tk ২৮.৭৫. TxnID: 73N89A1B2C at ০৪/১১/২০২৬ ১৯:১৫';
      final parsed = MfsSmsParser.parse(sms);

      expect(parsed, isNotNull);
      expect(parsed!.provider, MfsProvider.nagad);
      expect(parsed.trxId, '73N89A1B2C');
      expect(parsed.amountPaisa, 250000);
      expect(parsed.feePaisa, 2875);
      expect(parsed.counterpartyMaskedPhone, '018****7766');
    });

    test('detects duplicate TrxID within the same group', () {
      final existingSettlements = [
        SettlementRecord(
          id: 'set_1',
          tourId: 'mess_dhaka_1',
          fromMemberId: 'm1',
          fromMemberName: 'রাফি',
          toMemberId: 'm2',
          toMemberName: 'শোহাগ',
          amountPaisa: 100000,
          date: DateTime(2026, 11, 2),
          mfsInfo: const MfsPaymentInfo(
            provider: MfsProvider.bkash,
            trxId: 'BKL890XYZ1',
            status: MfsVerificationStatus.verified,
          ),
          addedByEmail: 'rafi@example.com',
        ),
      ];

      expect(
        MfsTrxIdValidator.isDuplicateTrxId(
          tourId: 'mess_dhaka_1',
          trxId: 'bkl890xyz1',
          expenses: const [],
          settlements: existingSettlements,
        ),
        isTrue,
      );

      expect(
        MfsTrxIdValidator.isDuplicateTrxId(
          tourId: 'other_group_2',
          trxId: 'BKL890XYZ1',
          expenses: const [],
          settlements: existingSettlements,
        ),
        isFalse,
      );
    });
  });

  group('TripLedgerEngine Monthly Statement & MFS Verification', () {
    const engine = TripLedgerEngine();
    const members = [
      LedgerMember(id: 'u1', name: 'শোহাগ রানা'),
      LedgerMember(id: 'u2', name: 'তানভীর আহমেদ'),
      LedgerMember(id: 'u3', name: 'মাহমুদ হাসান'),
    ];

    test(
        'carries forward October balances into November and separates verified vs pending MFS',
        () {
      final expenses = [
        // October expense: 3,000 BDT paid by u1 (1,000 BDT share each -> u1 +2000, u2 -1000, u3 -1000)
        ExpenseItem(
          id: 'exp_oct_1',
          tourId: 'samity_01',
          title: 'অক্টোবর বাজার খরচ',
          amountPaisa: 300000,
          paidById: 'u1',
          paidByName: 'শোহাগ রানা',
          category: 'Food',
          date: DateTime(2026, 10, 15),
          addedByEmail: 'shohag@example.com',
        ),
        // November expense: 6,000 BDT paid by u1 via bKash with 60 BDT fee absorbed by group (6,060 BDT -> 2,020 BDT share each)
        ExpenseItem(
          id: 'exp_nov_1',
          tourId: 'samity_01',
          title: 'নভেম্বর মাসের চাল ও তেল ক্রয়',
          amountPaisa: 600000,
          paidById: 'u1',
          paidByName: 'শোহাগ রানা',
          category: 'Food',
          date: DateTime(2026, 11, 3),
          addedByEmail: 'shohag@example.com',
          mfsInfo: const MfsPaymentInfo(
            provider: MfsProvider.bkash,
            trxId: 'BKNOV11223',
            feePaisa: 6000,
            feeAbsorbedByGroup: true,
            status: MfsVerificationStatus.verified,
          ),
        ),
      ];

      final settlements = [
        // u2 pays 2,000 BDT + 37 BDT fee via verified bKash to u1
        SettlementRecord(
          id: 'set_nov_1',
          tourId: 'samity_01',
          fromMemberId: 'u2',
          fromMemberName: 'তানভীর আহমেদ',
          toMemberId: 'u1',
          toMemberName: 'শোহাগ রানা',
          amountPaisa: 200000,
          date: DateTime(2026, 11, 4),
          mfsInfo: const MfsPaymentInfo(
            provider: MfsProvider.bkash,
            trxId: 'BKSET99887',
            feePaisa: 3700,
            feeAbsorbedByGroup: true,
            status: MfsVerificationStatus.verified,
          ),
          addedByEmail: 'tanvir@example.com',
        ),
        // u3 submits an UNVERIFIED Nagad payment of 1,500 BDT to u1
        SettlementRecord(
          id: 'set_nov_2',
          tourId: 'samity_01',
          fromMemberId: 'u3',
          fromMemberName: 'মাহমুদ হাসান',
          toMemberId: 'u1',
          toMemberName: 'শোহাগ রানা',
          amountPaisa: 150000,
          date: DateTime(2026, 11, 5),
          mfsInfo: const MfsPaymentInfo(
            provider: MfsProvider.nagad,
            trxId: 'NGDPEND123',
            status: MfsVerificationStatus.unverified,
          ),
          addedByEmail: 'mahmud@example.com',
        ),
      ];

      final statement = engine.computeMonthlyStatement(
        tourId: 'samity_01',
        groupTitle: 'ডাগনভূঞা মেস ও সমিতি তহবিল',
        groupArchetype: 'mess',
        year: 2026,
        month: 11,
        members: members,
        allExpenses: expenses,
        allSettlements: settlements,
      );

      expect(statement.totalMonthExpensesPaisa, 606000);
      expect(statement.totalVerifiedMfsCollectionsPaisa, 200000);
      expect(statement.totalPendingMfsCollectionsPaisa, 150000);

      final u1 =
          statement.memberStandings.firstWhere((s) => s.memberId == 'u1');
      final u2 =
          statement.memberStandings.firstWhere((s) => s.memberId == 'u2');
      final u3 =
          statement.memberStandings.firstWhere((s) => s.memberId == 'u3');

      // October opening balances: u1 = +2000 BDT, u2 = -1000 BDT, u3 = -1000 BDT
      expect(u1.openingBalancePaisa, 200000);
      expect(u2.openingBalancePaisa, -100000);
      expect(u3.openingBalancePaisa, -100000);

      // u3's 1,500 BDT Nagad payment is still unverified, so it sits in pendingMfsSubmittedPaisa
      expect(u3.pendingMfsSubmittedPaisa, 150000);
      expect(u3.closingNetBalancePaisa,
          -302000); // -1000 Oct - 2020 Nov = -3020 BDT
      expect(u3.projectedBalanceAfterPendingPaisa, -152000);
    });
  });

  group('BanglaLedgerFormatter', () {
    test('formats paisa into South Asian grouped Bangla Taka strings', () {
      expect(
        BanglaLedgerFormatter.formatTakaBangla(125050),
        '৳ ১,২৫০.৫০',
      );
      expect(
        BanglaLedgerFormatter.formatTakaBangla(-302000),
        '-৳ ৩,০২০',
      );
      expect(
        BanglaLedgerFormatter.formatMonthYearBangla(2026, 11),
        'নভেম্বর ২০২৬',
      );
    });

    test('MonthlyLedgerPdfGenerator generates valid non-empty PDF bytes', () async {
      const engine = TripLedgerEngine();
      final statement = engine.computeMonthlyStatement(
        tourId: 'samity_01',
        groupTitle: 'ডাগনভূঞা মেস ও সমিতি তহবিল',
        groupArchetype: 'mess',
        year: 2026,
        month: 11,
        members: const [
          LedgerMember(id: 'u1', name: 'শোহাগ রানা'),
          LedgerMember(id: 'u2', name: 'তানভীর আহমেদ'),
        ],
        allExpenses: const [],
        allSettlements: const [],
      );

      final pdfGenerator = MonthlyLedgerPdfGenerator();
      final bytes =
          await pdfGenerator.generate(statement, preparedByName: 'শোহাগ');
      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
    });
  });
}
