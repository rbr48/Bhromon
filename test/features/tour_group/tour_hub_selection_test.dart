import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/data/tour_hub_preference.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/tour_group_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTourGroupRepository extends TourGroupRepository {
  _FakeTourGroupRepository({required this.groups});
  final List<TourGroup> groups;

  @override
  String get currentEmail => 'lead@bhromon.fun';

  @override
  Stream<List<TourGroup>> watchMyGroups() => Stream.value(groups);

  @override
  Stream<List<TourMember>> watchMembers(String tourId) =>
      Stream.value(const <TourMember>[]);
}

/// Keeps the hub's pick in memory, so these tests never touch Hive.
class _MemoryPreference extends TourHubPreference {
  _MemoryPreference({this.saved});

  String? saved;

  @override
  String? read() => saved;

  @override
  Future<void> remember(String tourId) async {
    saved = tourId;
  }

  @override
  Future<void> forget(String tourId) async {
    if (saved == tourId) saved = null;
  }
}

TourGroup _tour(String id, String name) => TourGroup(
      id: id,
      name: name,
      ownerEmail: 'lead@bhromon.fun',
      inviteCode: 'CODE$id',
      destination: 'Sajek',
      originCity: 'Dhaka',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 4),
      tourType: TourType.hill,
      modules: const TourModules(),
      createdAt: DateTime(2026, 10, 1),
    );

Future<void> _pumpHub(
  WidgetTester tester, {
  required List<TourGroup> groups,
  required TourHubPreference preference,
  String? initialTourId,
}) async {
  tester.view.physicalSize = const Size(1000, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: TourGroupHubScreen(
        repository: _FakeTourGroupRepository(groups: groups),
        preference: preference,
        initialTourId: initialTourId,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final dhaka = _tour('tour_dhaka', 'Dhaka Beach Weekend');
  final sajek = _tour('tour_sajek', "Sajek Cloud Trek '26");
  final groups = [dhaka, sajek];

  testWidgets('opens on the tour in the address, not the first one',
      (tester) async {
    await _pumpHub(
      tester,
      groups: groups,
      preference: _MemoryPreference(saved: dhaka.id),
      initialTourId: sajek.id,
    );

    expect(find.text(sajek.name), findsWidgets);
    expect(find.text(dhaka.name), findsNothing);
  });

  testWidgets('opens on the tour it remembers when the address names none',
      (tester) async {
    await _pumpHub(
      tester,
      groups: groups,
      preference: _MemoryPreference(saved: sajek.id),
    );

    expect(find.text(sajek.name), findsWidgets);
    expect(find.text(dhaka.name), findsNothing);
  });

  testWidgets('a remembered tour the user is not in is ignored',
      (tester) async {
    await _pumpHub(
      tester,
      groups: groups,
      preference: _MemoryPreference(saved: 'tour_gone'),
    );

    expect(find.text(dhaka.name), findsWidgets);
    expect(find.text(sajek.name), findsNothing);
  });

  testWidgets('opening a tour from its address remembers it', (tester) async {
    final preference = _MemoryPreference();

    await _pumpHub(
      tester,
      groups: groups,
      preference: preference,
      initialTourId: sajek.id,
    );

    expect(preference.saved, sajek.id);
  });
}
