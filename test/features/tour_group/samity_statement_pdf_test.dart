import 'dart:convert';
import 'dart:typed_data';

import 'package:bhromon/features/tour_group/data/samity_statement_pdf.dart';
import 'package:bhromon/features/tour_group/data/tour_export_pdf.dart'
    show TourPdfLabels;
import 'package:bhromon/features/tour_group/domain/models/samity_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:flutter_test/flutter_test.dart';

TourPdfLabels _labels() => TourPdfLabels(
      text: (key, {args}) => key,
      number: (n) => '$n',
      date: (d) => '${d.year}-${d.month}-${d.day}',
      dateTime: (d) => '${d.year}-${d.month}-${d.day} ${d.hour}:${d.minute}',
    );

TourGroup _samityGroup() => TourGroup(
      id: 'samity-1',
      name: 'Mohalla Samity 2026',
      ownerEmail: 'admin@example.com',
      inviteCode: 'SAM2026',
      preset: TourGroup.samityPreset,
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 12, 31),
      samity: const SamityConfig(
        contributionTaka: 5000,
        startMonth: '2026-01',
        dueDay: 10,
        payoutOrder: [
          'alice@example.com',
          'bob@example.com',
          'carol@example.com',
        ],
      ),
      createdAt: DateTime(2026, 1, 1),
    );

List<TourMember> _members() => [
      TourMember(
        tourId: 'samity-1',
        email: 'alice@example.com',
        displayName: 'Alice Rahman',
        role: TourRole.owner,
        status: TourMemberStatus.active,
        joinedAt: DateTime(2026, 1, 1),
      ),
      TourMember(
        tourId: 'samity-1',
        email: 'bob@example.com',
        displayName: 'Bob Ahmed',
        role: TourRole.member,
        status: TourMemberStatus.active,
        joinedAt: DateTime(2026, 1, 1),
      ),
      TourMember(
        tourId: 'samity-1',
        email: 'carol@example.com',
        displayName: 'Carol Begum',
        role: TourRole.member,
        status: TourMemberStatus.active,
        joinedAt: DateTime(2026, 1, 1),
      ),
    ];

int _pageCount(Uint8List bytes) {
  return RegExp(r'/Type\s*/Page(?!s)').allMatches(latin1.decode(bytes)).length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buildSamityStatementPdf builds a valid PDF with header and tables',
      () async {
    final group = _samityGroup();
    final members = _members();
    final payments = [
      const SamityPayment(
        cycle: 0,
        email: 'alice@example.com',
        amountTaka: 5000,
        recordedByEmail: 'alice@example.com',
      ),
      const SamityPayment(
        cycle: 0,
        email: 'bob@example.com',
        amountTaka: 5000,
        recordedByEmail: 'bob@example.com',
      ),
      const SamityPayment(
        cycle: 0,
        email: 'carol@example.com',
        amountTaka: 5000,
        recordedByEmail: 'carol@example.com',
      ),
      const SamityPayment(
        cycle: 1,
        email: 'alice@example.com',
        amountTaka: 5000,
        recordedByEmail: 'alice@example.com',
      ),
    ];
    final payouts = [
      const SamityPayout(
        cycle: 0,
        recipientEmail: 'alice@example.com',
        amountTaka: 15000,
        recordedByEmail: 'admin@example.com',
      ),
    ];

    final data = SamityStatementData(
      group: group,
      members: members,
      payments: payments,
      payouts: payouts,
      generatedAt: DateTime(2026, 2, 15),
    );

    final bytes = await buildSamityStatementPdf(
      data: data,
      labels: _labels(),
    );

    expect(bytes, isNotEmpty);
    expect(ascii.decode(bytes.sublist(0, 5)), equals('%PDF-'));
    expect(_pageCount(bytes), greaterThanOrEqualTo(1));
  });

  test('buildSamityStatementPdf handles empty payments and payouts gracefully',
      () async {
    final group = _samityGroup();
    final members = _members();

    final data = SamityStatementData(
      group: group,
      members: members,
      payments: const [],
      payouts: const [],
      generatedAt: DateTime(2026, 1, 1),
    );

    final bytes = await buildSamityStatementPdf(
      data: data,
      labels: _labels(),
    );

    expect(bytes, isNotEmpty);
    expect(ascii.decode(bytes.sublist(0, 5)), equals('%PDF-'));
    expect(_pageCount(bytes), greaterThanOrEqualTo(1));
  });
}
