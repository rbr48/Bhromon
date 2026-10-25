import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/domain/models/expense_models.dart';
import 'package:bhromon/features/tour_group/domain/models/logistics_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import 'package:bhromon/features/tour_group/domain/services/invite_code.dart';
import 'package:bhromon/features/tour_group/domain/services/media_rules.dart';
import 'package:bhromon/features/tour_group/domain/services/trip_ledger_engine.dart';

ExpenseItem _expense(String id, int paisa,
        {String? payer,
        List<String>? participants,
        String category = 'Food'}) =>
    ExpenseItem(
      id: id,
      tourId: 't',
      title: id,
      amountPaisa: paisa,
      paidById: payer,
      category: category,
      date: DateTime(2026, 10, 25),
      participantIds: participants,
    );

DepositItem _deposit(String id, String email, int paisa, {String name = 'M'}) =>
    DepositItem(
      id: id,
      tourId: 't',
      memberId: email,
      memberName: name,
      amountPaisa: paisa,
      date: DateTime(2026, 10, 25),
    );

void main() {
  group('Ledger: nobody disappears from the books', () {
    test('a former member who paid keeps their credit and owes no share', () {
      final members = [
        const LedgerMemberInput(id: 'a@x.com', name: 'A', depositPaisa: 100000),
        const LedgerMemberInput(id: 'b@x.com', name: 'B', depositPaisa: 100000),
      ];
      final summary = TripLedgerEngine.computeLedger(
        members: members,
        expenses: [_expense('e1', 60000, payer: 'gone@x.com')],
      );
      final former = summary.rows.singleWhere((r) => r.id == 'gone@x.com');
      expect(former.isFormerMember, isTrue);
      expect(former.sharePaisa, 0);
      expect(former.netPaisa, 60000);
      // Members still split the 600 expense between them.
      expect(
          summary.rows
              .where((r) => !r.isFormerMember)
              .fold<int>(0, (s, r) => s + r.sharePaisa),
          60000);
    });

    test('a removed member deposit still counts toward the fund', () {
      final summary = TripLedgerEngine.computeLedger(
        members: const [LedgerMemberInput(id: 'a@x.com', name: 'A')],
        expenses: const [],
        deposits: [_deposit('d1', 'gone@x.com', 50000, name: 'Gone')],
      );
      expect(summary.totalDepositsPaisa, 50000);
      expect(summary.fundBalancePaisa, 50000);
      expect(summary.rows.any((r) => r.id == 'gone@x.com' && r.isFormerMember),
          isTrue);
    });

    test('deposit and payer ids match regardless of letter case', () {
      final summary = TripLedgerEngine.computeLedger(
        members: const [LedgerMemberInput(id: 'Asha@X.com', name: 'Asha')],
        expenses: [_expense('e1', 30000, payer: 'asha@x.com')],
        deposits: [_deposit('d1', 'ASHA@x.com', 70000)],
      );
      final row = summary.rows.single;
      expect(row.isFormerMember, isFalse);
      expect(row.depositPaisa, 70000);
      expect(row.directPaidPaisa, 30000);
      expect(row.contributedPaisa, 100000);
    });
  });

  group('Ledger: shares follow participants and family size', () {
    test('an expense shared by two people is not split among everyone', () {
      final members = [
        const LedgerMemberInput(id: 'a@x.com', name: 'A'),
        const LedgerMemberInput(id: 'b@x.com', name: 'B'),
        const LedgerMemberInput(id: 'c@x.com', name: 'C'),
      ];
      final summary = TripLedgerEngine.computeLedger(
        members: members,
        expenses: [
          _expense('e1', 9000, participants: ['a@x.com', 'b@x.com'])
        ],
      );
      final shares = {for (final r in summary.rows) r.id: r.sharePaisa};
      expect(shares['a@x.com'], 4500);
      expect(shares['b@x.com'], 4500);
      expect(shares['c@x.com'], 0);
    });

    test('family sizes weight the split and no paisa is lost', () {
      final members = [
        const LedgerMemberInput(id: 'a@x.com', name: 'A', familyCount: 2),
        const LedgerMemberInput(id: 'b@x.com', name: 'B', familyCount: 3),
      ];
      final summary = TripLedgerEngine.computeLedger(
        members: members,
        expenses: [_expense('e1', 1000)],
      );
      expect(summary.rows.map((r) => r.sharePaisa).toList(), [400, 600]);
      expect(summary.rows.fold<int>(0, (s, r) => s + r.sharePaisa), 1000);
    });

    test('unknown participants are ignored, falling back to all members', () {
      final summary = TripLedgerEngine.computeLedger(
        members: const [
          LedgerMemberInput(id: 'a@x.com', name: 'A'),
          LedgerMemberInput(id: 'b@x.com', name: 'B'),
        ],
        expenses: [
          _expense('e1', 1000, participants: ['gone@x.com'])
        ],
      );
      expect(summary.rows.map((r) => r.sharePaisa).toList(), [500, 500]);
    });

    test('balances always sum to zero, including the fund', () {
      final random = Random(7);
      for (var round = 0; round < 200; round++) {
        final ids = List.generate(1 + random.nextInt(5), (i) => 'm$i@x.com');
        final members = [
          for (final id in ids)
            LedgerMemberInput(
                id: id,
                name: id,
                familyCount: 1 + random.nextInt(3),
                depositPaisa: random.nextInt(50000)),
        ];
        final expenses = [
          for (var e = 0; e < random.nextInt(6); e++)
            _expense(
              'e$e',
              1 + random.nextInt(99999),
              payer: random.nextBool() ? ids[random.nextInt(ids.length)] : null,
              participants:
                  random.nextBool() ? [ids[random.nextInt(ids.length)]] : null,
            ),
        ];
        final summary = TripLedgerEngine.computeLedger(
            members: members, expenses: expenses);
        final shareSum = summary.rows.fold<int>(0, (s, r) => s + r.sharePaisa);
        expect(shareSum, summary.totalExpensePaisa, reason: 'round $round');

        // Every party's settlements add up to its own balance; the fund row
        // holds the opposite balance of the members combined.
        final parties = [
          ...summary.rows.map((r) => (name: r.name, net: r.netPaisa)),
          (
            name: TripLedgerEngine.fundLabel,
            net: -summary.rows.fold<int>(0, (s, r) => s + r.netPaisa)
          ),
        ];
        for (final party in parties) {
          final out = summary.settlements
              .where((t) => t.from == party.name)
              .fold<int>(0, (s, t) => s + t.amountPaisa);
          final into = summary.settlements
              .where((t) => t.to == party.name)
              .fold<int>(0, (s, t) => s + t.amountPaisa);
          expect(into - out, party.net, reason: 'round $round, ${party.name}');
        }
      }
    });
  });

  group('Amount input', () {
    test('accepts Bengali digits, commas and the taka sign', () {
      expect(TripLedgerEngine.parseTakaInput('১,২৫০.৫'), 125050);
      expect(TripLedgerEngine.parseTakaInput('৳ 1,000'), 100000);
      expect(TripLedgerEngine.parseTakaInput('12.5'), 1250);
      expect(TripLedgerEngine.parseTakaInput('0.05'), 5);
    });

    test(
        'rejects zero, negatives, junk, too many decimals and amounts over the cap',
        () {
      expect(TripLedgerEngine.parseTakaInput('0'), isNull);
      expect(TripLedgerEngine.parseTakaInput('-5'), isNull);
      expect(TripLedgerEngine.parseTakaInput('abc'), isNull);
      expect(TripLedgerEngine.parseTakaInput('1e3'), isNull);
      expect(TripLedgerEngine.parseTakaInput('1.234'), isNull);
      expect(TripLedgerEngine.parseTakaInput('10000001'), isNull);
      expect(TripLedgerEngine.parseTakaInput(''), isNull);
    });

    test('toPaisa throws instead of silently clamping', () {
      expect(() => TripLedgerEngine.toPaisa(-1), throwsArgumentError);
      expect(() => TripLedgerEngine.toPaisa(10000001), throwsArgumentError);
      expect(() => TripLedgerEngine.toPaisa(double.nan), throwsArgumentError);
    });

    test('formats paisa with grouping and decimals only when needed', () {
      expect(TripLedgerEngine.formatTaka(100000), '৳1,000');
      expect(TripLedgerEngine.formatTaka(125050), '৳1,250.50');
      expect(TripLedgerEngine.formatTaka(5), '৳0.05');
      expect(TripLedgerEngine.formatTaka(-250), '-৳2.50');
    });
  });

  group('Invite codes', () {
    test('new codes are 8 characters from the unambiguous alphabet', () {
      for (var i = 0; i < 200; i++) {
        final code = generateInviteCode();
        expect(code.length, inviteCodeLength);
        expect(isValidInviteCode(code), isTrue, reason: code);
        expect(RegExp('^[$inviteCodeAlphabet]+\$').hasMatch(code), isTrue);
        expect(code.contains(RegExp('[01IO]')), isFalse);
      }
    });

    test('codes from the seeded generator are reproducible', () {
      expect(generateInviteCode(random: Random(1)),
          generateInviteCode(random: Random(1)));
    });

    test('legacy 6-character codes are still accepted, others are not', () {
      expect(isValidInviteCode('A1B2C3'), isTrue);
      expect(isValidInviteCode('ABC'), isFalse);
      expect(isValidInviteCode('ABC DEF'), isFalse);
    });
  });

  group('Tour dates', () {
    test('totalDays counts calendar days whatever the time of day', () {
      final group = TourGroup(
        id: 'g',
        name: 'n',
        ownerEmail: 'o@x.com',
        inviteCode: 'ABCDEFGH',
        startDate: DateTime(2026, 10, 25, 22, 0),
        endDate: DateTime(2026, 10, 27, 6, 0),
        createdAt: DateTime(2026, 10, 1),
      );
      expect(group.totalDays, 3);
      expect(group.totalNights, 2);
    });

    test('isLiveAt covers the whole first and last day', () {
      final group = TourGroup(
        id: 'g',
        name: 'n',
        ownerEmail: 'o@x.com',
        inviteCode: 'ABCDEFGH',
        startDate: DateTime(2026, 10, 25, 15),
        endDate: DateTime(2026, 10, 26, 9),
        createdAt: DateTime(2026, 10, 1),
      );
      expect(group.isLiveAt(DateTime(2026, 10, 25, 0, 30)), isTrue);
      expect(group.isLiveAt(DateTime(2026, 10, 26, 23, 59)), isTrue);
      expect(group.isLiveAt(DateTime(2026, 10, 27, 0, 0)), isFalse);
      expect(group.isLiveAt(DateTime(2026, 10, 24, 23, 59)), isFalse);
    });

    test('copyWith can clear the meeting point, and leaves it alone otherwise',
        () {
      final base = TourGroup(
        id: 'g',
        name: 'n',
        ownerEmail: 'o@x.com',
        inviteCode: 'ABCDEFGH',
        startDate: DateTime(2026, 10, 25),
        endDate: DateTime(2026, 10, 26),
        createdAt: DateTime(2026, 10, 1),
        meetingPointTitle: 'Hotel lobby',
        meetingPointNote: 'Bring ID',
      );
      expect(base.copyWith(name: 'x').meetingPointTitle, 'Hotel lobby');
      final cleared =
          base.copyWith(meetingPointTitle: null, meetingPointNote: null);
      expect(cleared.meetingPointTitle, isNull);
      expect(cleared.meetingPointNote, isNull);
    });

    test('reads dates stored as strings (older documents) and as timestamps',
        () {
      final fromString = TourGroup.fromMap('g', {
        'ownerEmail': 'O@x.com',
        'startDate': '2026-10-25T00:00:00.000',
        'endDate': '2026-10-27T00:00:00.000',
      });
      expect(fromString.totalDays, 3);
      expect(fromString.ownerEmail, 'o@x.com');
    });
  });

  group('Logistics', () {
    test('bus seat copyWith keeps unspecified fields and can clear them', () {
      const seat = BusSeat(
          seatNumber: 'A1',
          assignedMemberEmail: 'a@x.com',
          assignedMemberName: 'A',
          isWindow: true);
      expect(seat.copyWith().assignedMemberEmail, 'a@x.com');
      final vacant =
          seat.copyWith(assignedMemberEmail: null, assignedMemberName: null);
      expect(vacant.isOccupied, isFalse);
      expect(vacant.isWindow, isTrue);
    });

    test('hotel room guest lists stay aligned and respect capacity', () {
      var room = const HotelRoom(
          id: 'r', roomNumber: '301', title: 'Deluxe', capacity: 2);
      room = room.addGuest('A@x.com', 'Asha');
      room = room.addGuest('b@x.com', 'Bilal');
      expect(room.assignedMemberEmails, ['a@x.com', 'b@x.com']);
      expect(room.assignedMemberNames, ['Asha', 'Bilal']);
      expect(() => room.addGuest('c@x.com', 'C'), throwsStateError);
      expect(() => room.addGuest('a@x.com', 'Asha'), throwsStateError);

      room = room.removeGuest('a@x.com');
      expect(room.assignedMemberEmails, ['b@x.com']);
      expect(room.assignedMemberNames, ['Bilal']);
      expect(
          room.removeGuest('nobody@x.com').assignedMemberEmails, ['b@x.com']);
    });

    test('a room saved with mismatched lists is repaired when read', () {
      final room = HotelRoom.fromMap('r', {
        'roomNumber': '301',
        'capacity': 3,
        'assignedMemberEmails': ['a@x.com', 'b@x.com'],
        'assignedMemberNames': ['Asha'],
      });
      expect(room.assignedMemberNames, ['Asha', '']);
    });
  });

  group('Posts & media', () {
    test('only https media counts as remote; device paths do not', () {
      expect(isRemoteMediaUrl('https://firebasestorage.googleapis.com/x.jpg'),
          isTrue);
      expect(isRemoteMediaUrl('/data/user/0/app/cache/x.jpg'), isFalse);
      expect(isRemoteMediaUrl('blob:https://app.bhromon.fun/abc'), isFalse);
      expect(isRemoteMediaUrl(null), isFalse);
    });

    test('a post with a device path is not shown as remote media', () {
      final post = TourPostItem.fromMap('p', {
        'images': ['/data/user/0/app/cache/x.jpg'],
        'createdAt': '2026-10-25T10:00:00.000',
      });
      expect(post.hasRemoteMedia, isFalse);
    });

    test('content types and extensions follow the storage rules', () {
      expect(imageContentType('IMG_1.JPG'), 'image/jpeg');
      expect(imageContentType('scan.pdf'), isNull);
      expect(videoContentType('clip.mov'), 'video/quicktime');
      expect(videoContentType('clip.avi'), isNull);
      expect(storedExtension('clip.MOV', 'mp4'), 'mov');
      expect(storedExtension('noext', 'jpg'), 'jpg');
      expect(kMaxImageBytes, 10 * 1024 * 1024);
      expect(kMaxVideoBytes, 100 * 1024 * 1024);
    });

    test('stories are grouped per author, each in posting order', () {
      final base = DateTime(2026, 10, 25, 10);
      TourStoryItem story(String id, String author, int minutes) =>
          TourStoryItem(
            id: id,
            authorEmail: author,
            authorName: author,
            mediaUrl: 'https://x/$id.jpg',
            createdAt: base.add(Duration(minutes: minutes)),
          );
      final groups = groupStoriesByAuthor([
        story('1', 'a@x.com', 0),
        story('2', 'b@x.com', 5),
        story('3', 'a@x.com', 10),
      ]);
      expect(groups.map((g) => g.first.authorEmail).toList(),
          ['a@x.com', 'b@x.com']);
      expect(groups.first.map((s) => s.id).toList(), ['1', '3']);
    });

    test('a story is active for 24 hours after posting', () {
      final story = TourStoryItem(
        id: 's',
        authorEmail: 'a@x.com',
        authorName: 'A',
        mediaUrl: 'https://x/s.jpg',
        createdAt: DateTime(2026, 10, 25, 10),
      );
      expect(story.isActiveAt(DateTime(2026, 10, 26, 9, 59)), isTrue);
      expect(story.isActiveAt(DateTime(2026, 10, 26, 10, 0)), isFalse);
    });
  });
}
