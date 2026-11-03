import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/groups/group_card.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/groups/switcher_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TourGroup _group(
  String id,
  String name, {
  bool family = false,
  String? preset,
}) =>
    TourGroup(
      id: id,
      name: name,
      ownerEmail: 'tester@bhromon.fun',
      inviteCode: 'ABCDEFGH',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 4),
      createdAt: DateTime(2026, 10, 1),
      kind: family ? GroupKind.family : GroupKind.tour,
      preset: preset,
    );

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('a housing society card says Society, not Family circles',
      (tester) async {
    final society = _group('s', 'Sunrise Tower',
        family: true, preset: TourGroup.societyPreset);
    await tester.pumpWidget(_app(GroupCard(
      group: society,
      selected: false,
      onTap: () {},
    )));
    await tester.pumpAndSettle();

    expect(find.text('Society'), findsOneWidget);
    expect(find.text('Family circles'), findsNothing);
    expect(find.byIcon(Icons.apartment_rounded), findsOneWidget);
    expect(find.byIcon(Icons.family_restroom_rounded), findsNothing);
  });

  testWidgets('a plain family circle card still says Family circles',
      (tester) async {
    final family = _group('f', 'Rahman Family', family: true);
    await tester.pumpWidget(_app(GroupCard(
      group: family,
      selected: false,
      onTap: () {},
    )));
    await tester.pumpAndSettle();

    expect(find.text('Family circles'), findsOneWidget);
    expect(find.byIcon(Icons.family_restroom_rounded), findsOneWidget);
  });

  testWidgets('the switcher lists a housing society under Groups, not Family',
      (tester) async {
    await tester.pumpWidget(_app(SwitcherChips(
      groups: [
        _group('f', 'Rahman Family', family: true),
        _group('s', 'Sunrise Tower',
            family: true, preset: TourGroup.societyPreset),
        _group('t', 'Cox Trip'),
      ],
      selectedId: null,
      onSelected: (_) {},
    )));
    await tester.pumpAndSettle();

    expect(find.text('Family circles'), findsOneWidget);
    expect(find.text('Groups'), findsOneWidget);
    expect(find.text('Trips'), findsOneWidget);
    expect(find.text('Sunrise Tower'), findsOneWidget);
  });
}
