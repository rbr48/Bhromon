import 'dart:async';
import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/data/tour_hub_preference.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/tour_group_hub_screen.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/groups/group_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePreference implements TourHubPreference {
  String? _id;
  @override
  String? read() => _id;
  @override
  Future<void> remember(String tourId) async {
    _id = tourId;
  }

  @override
  Future<void> forget(String tourId) async {
    if (_id == tourId) _id = null;
  }
}

class _MockTourGroupRepo extends TourGroupRepository {
  final StreamController<List<TourGroup>> _groupsController =
      StreamController<List<TourGroup>>.broadcast();

  List<TourGroup> groups = [];

  void emitGroups(List<TourGroup> list) {
    groups = list;
    _groupsController.add(list);
  }

  @override
  Stream<List<TourGroup>> watchMyGroups() async* {
    yield groups;
    yield* _groupsController.stream;
  }

  @override
  Stream<List<TourMember>> watchMembers(String tourId) async* {
    yield [];
  }

  @override
  String get currentEmail => 'traveler@bhromon.fun';

  @override
  String get currentDisplayName => 'Traveler';

  void dispose() {
    _groupsController.close();
  }
}

Widget _testApp(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  );
}

void main() {
  late _MockTourGroupRepo repo;
  final now = DateTime(2026, 11, 7, 12, 0);

  final g1 = TourGroup(
    id: 'grp_1',
    name: 'Brothers Mess',
    destination: '',
    preset: TourGroup.messPreset,
    kind: GroupKind.family,
    ownerEmail: 'traveler@bhromon.fun',
    inviteCode: 'BMESS123',
    startDate: now,
    endDate: now,
    createdAt: now,
  );

  final g2 = TourGroup(
    id: 'grp_2',
    name: 'Cox Trip 2026',
    destination: "Cox's Bazar",
    kind: GroupKind.tour,
    ownerEmail: 'traveler@bhromon.fun',
    inviteCode: 'COX2026X',
    startDate: now,
    endDate: now,
    createdAt: now,
  );

  final g3 = TourGroup(
    id: 'grp_3',
    name: 'Family Circle',
    destination: '',
    kind: GroupKind.family,
    ownerEmail: 'traveler@bhromon.fun',
    inviteCode: 'FAM99999',
    startDate: now,
    endDate: now,
    createdAt: now,
  );

  setUp(() {
    repo = _MockTourGroupRepo();
    repo.groups = [g1, g2, g3];
  });

  tearDown(() {
    repo.dispose();
  });

  testWidgets('renders search field on group hub when groups are present',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        TourGroupHubScreen(
          repository: repo,
          preference: _FakePreference(),
          groupsV2: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(GroupCard), findsNWidgets(3));
  });

  testWidgets('filters groups in real-time when query is typed',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        TourGroupHubScreen(
          repository: repo,
          preference: _FakePreference(),
          groupsV2: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Type "mess" into the search bar
    await tester.enterText(find.byType(TextField), 'mess');
    await tester.pumpAndSettle();

    // Should only show Brothers Mess
    expect(find.byType(GroupCard), findsOneWidget);
    expect(find.text('Brothers Mess'), findsOneWidget);
    expect(find.text('Cox Trip 2026'), findsNothing);

    // Clear with suffix icon button
    final clearButton = find.byTooltip('Clear search');
    expect(clearButton, findsOneWidget);
    await tester.tap(clearButton);
    await tester.pumpAndSettle();

    // All groups restored
    expect(find.byType(GroupCard), findsNWidgets(3));
  });

  testWidgets('displays no groups found state when search query does not match',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        TourGroupHubScreen(
          repository: repo,
          preference: _FakePreference(),
          groupsV2: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'unknown-xyz');
    await tester.pumpAndSettle();

    expect(find.byType(GroupCard), findsNothing);
    expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
    expect(find.text('No groups matching "unknown-xyz"'), findsOneWidget);

    // Tap clear button in empty state
    await tester.tap(find.text('Clear search'));
    await tester.pumpAndSettle();

    expect(find.byType(GroupCard), findsNWidgets(3));
  });
}
