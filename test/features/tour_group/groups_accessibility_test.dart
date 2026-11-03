import 'dart:ui' show Tristate;

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/groups/group_card.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/groups/member_avatar.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/groups/sos_row.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/groups/switcher_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

// What a screen reader gets from the groups widgets, and how large their tap targets
// are (plan sections 6.1, 9.5 and the 48 dp rule).

TourGroup _trip(String id, String name) => TourGroup(
      id: id,
      name: name,
      ownerEmail: 'me@bhromon.fun',
      inviteCode: 'ABCDEFGH',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 4),
      createdAt: DateTime(2026, 10, 1),
      tourType: TourType.hill,
    );

Widget _host(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      DefaultMaterialLocalizations.delegate,
      DefaultWidgetsLocalizations.delegate,
    ],
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(width: 360, child: child),
      ),
    ),
  );
}

/// The semantics the node labelled [label] exposes.
SemanticsData _semanticsOf(WidgetTester tester, String label) {
  return tester.getSemantics(find.bySemanticsLabel(label)).getSemanticsData();
}

void main() {
  testWidgets(
      'a group card is a button labelled with the group name, and acts on tap',
      (tester) async {
    await tester.pumpWidget(_host(GroupCard(
      group: _trip('a', 'Sajek'),
      selected: false,
      onTap: () {},
    )));
    await tester.pumpAndSettle();

    final data = _semanticsOf(tester, 'Sajek');
    expect(data.label, 'Sajek');
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.flagsCollection.isSelected, isNot(Tristate.isTrue));
  });

  testWidgets('the selected group card says it is selected', (tester) async {
    await tester.pumpWidget(_host(GroupCard(
      group: _trip('a', 'Sajek'),
      selected: true,
      onTap: () {},
    )));
    await tester.pumpAndSettle();

    expect(
      _semanticsOf(tester, 'Sajek').flagsCollection.isSelected,
      Tristate.isTrue,
    );
  });

  testWidgets('a member face is labelled with the member name only',
      (tester) async {
    await tester.pumpWidget(_host(const MemberAvatar(name: 'Rahim')));
    await tester.pumpAndSettle();

    // The initial inside the face is decoration; the label is the name, read once.
    expect(find.bySemanticsLabel('Rahim'), findsOneWidget);
    expect(_semanticsOf(tester, 'Rahim').label, 'Rahim');
  });

  testWidgets('the switcher chips say which group is selected', (tester) async {
    await tester.pumpWidget(_host(SwitcherChips(
      groups: [_trip('a', 'Sajek'), _trip('b', 'Bandarban')],
      selectedId: 'a',
      onSelected: (_) {},
    )));
    await tester.pumpAndSettle();

    final selected = _semanticsOf(tester, 'Sajek');
    expect(selected.flagsCollection.isSelected, Tristate.isTrue);
    expect(selected.hasAction(SemanticsAction.tap), isTrue);

    final other = _semanticsOf(tester, 'Bandarban');
    expect(other.flagsCollection.isSelected, isNot(Tristate.isTrue));
    expect(other.hasAction(SemanticsAction.tap), isTrue);
  });

  testWidgets('tappable groups widgets are at least 48 dp tall',
      (tester) async {
    await tester.pumpWidget(_host(Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GroupCard(group: _trip('a', 'Sajek'), selected: false, onTap: () {}),
        SosRow(title: 'SOS', subtitle: 'Alert the group', onTap: () {}),
        SwitcherChips(
          groups: [_trip('a', 'Sajek'), _trip('b', 'Bandarban')],
          selectedId: 'a',
          onSelected: (_) {},
        ),
      ],
    )));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(GroupCard)).height,
        greaterThanOrEqualTo(48));
    expect(
        tester.getSize(find.byType(SosRow)).height, greaterThanOrEqualTo(48));
    for (final chip in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))) {
      expect(
        tester.getSize(find.byWidget(chip)).height,
        greaterThanOrEqualTo(48),
        reason: 'the chip ${(chip.label as Text).data} is smaller than 48 dp',
      );
    }
  });
}
