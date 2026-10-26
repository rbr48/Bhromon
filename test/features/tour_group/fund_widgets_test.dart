import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/domain/models/expense_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/trip_ledger_engine.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/fund/expense_editor.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/fund/fund_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _members = [
  for (final (email, name, family) in [
    ('a@x.com', 'Asha', 3),
    ('b@x.com', 'Babu', 1),
  ])
    TourMember(
      tourId: 't',
      email: email,
      displayName: name,
      role: TourRole.member,
      status: TourMemberStatus.active,
      joinedAt: DateTime(2026),
      familyCount: family,
    ),
];

/// Opens a sheet from a button and hands back what it returned.
Future<T?> _open<T>(
    WidgetTester tester, Future<T?> Function(BuildContext) open) async {
  T? result;
  tester.view.physicalSize = const Size(411, 891) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      DefaultMaterialLocalizations.delegate,
      DefaultWidgetsLocalizations.delegate,
    ],
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await open(context),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('an exact split must add up before it saves', (tester) async {
    ExpenseDraft? draft;
    await _open(tester, (c) async {
      draft = await showExpenseEditor(c,
          members: _members, group: null, me: 'a@x.com');
      return draft;
    });

    await tester.enterText(find.widgetWithText(TextField, 'What was it for'),
        'Boat to Saint Martin');
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '1000');
    await tester.tap(find.text('Exact'));
    await tester.pumpAndSettle();

    final shareFields = find.widgetWithText(TextField, 'Amount');
    Finder shareOf(String name) => find.descendant(
        of: find
            .ancestor(of: find.text(name), matching: find.byType(Row))
            .first,
        matching: find.byType(TextField));
    // The total field plus one per member.
    expect(shareFields, findsNWidgets(3));
    await tester.enterText(shareOf('Asha'), '700');
    await tester.enterText(shareOf('Babu'), '200');
    await tester.pumpAndSettle();
    expect(find.textContaining('Left to assign'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Save'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('The split adds up to'), findsOneWidget);
    expect(draft, isNull);

    await tester.scrollUntilVisible(find.text('Babu'), -300,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(shareOf('Babu'), '300');
    await tester.scrollUntilVisible(find.text('Save'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(draft, isNotNull);
    expect(draft!.amountPaisa, 100000);
    expect(draft!.splitMode, SplitMode.exact);
    expect(draft!.splitShares, {'a@x.com': 70000, 'b@x.com': 30000});
    expect(draft!.participantIds, isNull);
    expect(draft!.paidById, isNull, reason: 'paid from the fund by default');
  });

  testWidgets('a settle-up suggestion fills the payment form', (tester) async {
    TransferDraft? draft;
    await _open(tester, (c) async {
      draft = await showTransferSheet(c,
          members: _members,
          me: 'b@x.com',
          isAdmin: false,
          suggestion: const SettlementTransaction(
              from: 'Babu',
              fromId: 'b@x.com',
              to: 'Asha',
              toId: 'a@x.com',
              amountPaisa: 45050));
      return draft;
    });
    expect(find.text('450.50'), findsOneWidget);
    await tester.tap(find.text('bKash'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Mark paid'));
    await tester.tap(find.text('Mark paid'));
    await tester.pumpAndSettle();

    expect(draft, isNotNull);
    expect(draft!.fromId, 'b@x.com');
    expect(draft!.toId, 'a@x.com');
    expect(draft!.toName, 'Asha');
    expect(draft!.amountPaisa, 45050);
    expect(draft!.notes, 'bKash');
  });

  testWidgets('a member may not record a payment between two others',
      (tester) async {
    TransferDraft? draft;
    await _open(tester, (c) async {
      draft = await showTransferSheet(c,
          members: _members,
          me: 'c@x.com',
          isAdmin: false,
          suggestion: const SettlementTransaction(
              from: 'Babu',
              fromId: 'b@x.com',
              to: 'Asha',
              toId: 'a@x.com',
              amountPaisa: 100));
      return draft;
    });
    await tester.ensureVisible(find.text('Mark paid'));
    await tester.tap(find.text('Mark paid'));
    await tester.pumpAndSettle();
    expect(draft, isNull);
    expect(find.textContaining('only payments you made or received'),
        findsOneWidget);
  });

  testWidgets('the budget sheet works out the per-person collection',
      (tester) async {
    FundBudget? budget;
    await _open(tester, (c) async {
      budget = await showBudgetSheet(c,
          budget: const FundBudget(), headcount: 4, totalDays: 3);
      return budget;
    });
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '3000'); // Food
    await tester.enterText(fields.at(2), '5005'); // Hotel
    await tester.pumpAndSettle();
    expect(find.text(TripLedgerEngine.formatTaka(800500)), findsOneWidget);

    await tester.tap(find.byIcon(Icons.auto_fix_high_rounded));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(budget!.categoryPaisa, {'Food': 300000, 'Hotel': 500500});
    // 8,005 / 4 people = 2,001.25, rounded up to the next 10 taka.
    expect(budget!.perHeadTargetPaisa, 201000);
  });
}
