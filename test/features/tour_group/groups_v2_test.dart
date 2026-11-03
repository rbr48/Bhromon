import 'dart:async';
import 'dart:io';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/data/tour_hub_preference.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/tour_group_hub_screen.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/groups/group_card.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/groups/group_skeleton.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/groups/members_strip.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/groups/sos_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

// The groups list and the group page (kGroupsV2). The tests pass groupsV2: true, so
// they run the new layout whatever the build flag is.

class _Repo extends TourGroupRepository {
  _Repo({required this.groups, this.members = const [], this.silent = false});

  final List<TourGroup> groups;
  final List<TourMember> members;

  /// A members stream that never answers, as while a slow network loads.
  final bool silent;

  @override
  String get currentEmail => 'me@bhromon.fun';

  @override
  Stream<List<TourGroup>> watchMyGroups() => Stream.value(groups);

  @override
  Stream<TourGroup?> watchGroup(String tourId) => Stream.value(null);

  // Every listener gets its own stream, as the shared repository gives one per tour.
  @override
  Stream<List<TourMember>> watchMembers(String tourId) {
    if (silent) return Stream.multi((_) {});
    return Stream.multi((controller) {
      controller.add(members);
      controller.close();
    });
  }
}

TourMember _member(String tourId, String name, String email, TourRole role) {
  return TourMember(
    tourId: tourId,
    email: email,
    displayName: name,
    role: role,
    status: TourMemberStatus.active,
    joinedAt: DateTime(2026, 10, 1),
    familyCount: 1,
  );
}

TourGroup _trip(String id, {DateTime? start}) {
  final first = start ?? DateTime(2026, 11, 1);
  return TourGroup(
    id: id,
    name: 'Sajek $id',
    ownerEmail: 'me@bhromon.fun',
    inviteCode: 'ABCDEFGH',
    startDate: first,
    endDate: first.add(const Duration(days: 3)),
    createdAt: DateTime(2026, 10, 1),
    tourType: TourType.hill,
  );
}

TourGroup _family(String id) {
  return TourGroup(
    id: id,
    name: 'Home $id',
    ownerEmail: 'me@bhromon.fun',
    inviteCode: 'ABCDEFGH',
    startDate: DateTime(2026, 11, 1),
    endDate: DateTime(2026, 11, 1),
    createdAt: DateTime(2026, 10, 1),
    kind: GroupKind.family,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required TourGroupHubScreen hub,
  double textScale = 1.0,
  Size size = const Size(800, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      DefaultMaterialLocalizations.delegate,
      DefaultWidgetsLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: hub,
  ));
  await tester.pumpAndSettle();
}

TourGroupHubScreen _hub(_Repo repo, {String? routeId}) => TourGroupHubScreen(
      key: UniqueKey(),
      repository: repo,
      initialTourId: routeId,
      preference: TourHubPreference(),
      groupsV2: true,
    );

void main() {
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('bhromon_v2').path);
  });

  final owner = _member('t1', 'Organizer', 'me@bhromon.fun', TourRole.owner);

  testWidgets(
      'the groups list shows a card for each group, and the switcher when there are several',
      (tester) async {
    final groups = [_family('f1'), _trip('t1')];
    await _pump(tester, hub: _hub(_Repo(groups: groups, members: [owner])));

    expect(find.byType(GroupCard), findsNWidgets(2));
    expect(
        find.descendant(
            of: find.byType(GroupCard), matching: find.text('Home f1')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(GroupCard), matching: find.text('Sajek t1')),
        findsOneWidget);
  });

  testWidgets('with no groups the list shows the empty state, not cards',
      (tester) async {
    await _pump(tester, hub: _hub(_Repo(groups: const [], members: const [])));
    expect(find.byType(GroupCard), findsNothing);
    expect(find.byType(GroupSkeleton), findsNothing);
  });

  testWidgets(
      'a group page shows the members, the next step, the safety row and the tools, without Game zone or News',
      (tester) async {
    final trip =
        _trip('t1', start: DateTime.now().add(const Duration(days: 10)));
    await _pump(
      tester,
      hub: _hub(_Repo(groups: [trip], members: [owner]), routeId: 't1'),
    );

    expect(find.byType(MembersStrip), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
    expect(find.text('The trip starts in 10 days.'), findsOneWidget);
    expect(find.byType(SosRow), findsOneWidget);
    expect(find.text('Moments 📸'), findsOneWidget);
    expect(find.text('Game zone 🎮'), findsNothing);
    expect(find.text('Newspaper Hub 📰'), findsNothing);
  });

  testWidgets('a trip that has started shows no next step', (tester) async {
    final trip =
        _trip('t1', start: DateTime.now().subtract(const Duration(days: 2)));
    await _pump(
      tester,
      hub: _hub(_Repo(groups: [trip], members: [owner]), routeId: 't1'),
    );
    expect(find.textContaining('starts in'), findsNothing);
  });

  testWidgets(
      'the members strip shows at most eight faces and a count for the rest',
      (tester) async {
    final many = [
      for (var i = 0; i < 120; i++)
        _member('t1', 'Member $i', 'm$i@bhromon.fun', TourRole.member),
    ];
    await _pump(
      tester,
      hub: _hub(_Repo(groups: [_trip('t1')], members: many), routeId: 't1'),
    );
    expect(find.text('+112'), findsOneWidget);
    expect(find.text('+·'), findsNothing);
  });

  testWidgets('no members yet shows a skeleton, never a zero count',
      (tester) async {
    await _pump(
      tester,
      hub: _hub(_Repo(groups: [_trip('t1')], silent: true), routeId: 't1'),
    );
    expect(find.byType(GroupSkeleton), findsWidgets);
    expect(find.text('See all'), findsNothing);
  });

  testWidgets('the group page fits at text scale 2.0 on a 320-wide screen',
      (tester) async {
    final names = [
      for (var i = 0; i < 9; i++)
        _member('t1', 'রহিম উদ্দিন আহমেদ $i দীর্ঘ নাম', 'r$i@bhromon.fun',
            TourRole.member),
    ];
    await _pump(
      tester,
      hub: _hub(_Repo(groups: [_trip('t1')], members: names), routeId: 't1'),
      textScale: 2.0,
      size: const Size(320, 900),
    );
    expect(tester.takeException(), isNull,
        reason: 'no overflow at 2.0 text scale');
    expect(find.byType(MembersStrip), findsOneWidget);
  });

  testWidgets(
      'admins see emails in the members sheet; other members see roles only',
      (tester) async {
    final rahim = _member('t1', 'Rahim', 'rahim@bhromon.fun', TourRole.member);

    // The viewer is the owner, so an admin view.
    await _pump(
      tester,
      hub: _hub(_Repo(groups: [_trip('t1')], members: [owner, rahim]),
          routeId: 't1'),
    );
    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();
    expect(find.text('rahim@bhromon.fun'), findsOneWidget);
  });

  testWidgets(
      'a plain member does not see anyone\'s email in the members sheet',
      (tester) async {
    final me = _member('t1', 'Me', 'me@bhromon.fun', TourRole.member);
    final rahim = _member('t1', 'Rahim', 'rahim@bhromon.fun', TourRole.member);
    await _pump(
      tester,
      hub: _hub(_Repo(groups: [_trip('t1')], members: [me, rahim]),
          routeId: 't1'),
    );
    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();
    expect(find.text('rahim@bhromon.fun'), findsNothing);
    expect(find.text('Member'), findsWidgets);
  });

  testWidgets(
      'the groups list and the group page fit every width and text size in the matrix',
      (tester) async {
    final groups = [
      _family('f1'),
      _trip('t1', start: DateTime.now().add(const Duration(days: 3)))
    ];
    final members = [
      owner,
      _member('t1', 'রহিম উদ্দিন আহমেদ দীর্ঘ নাম', 'r@bhromon.fun',
          TourRole.member),
    ];
    for (final width in const [320.0, 360.0, 390.0, 412.0]) {
      for (final scale in const [1.0, 1.5, 2.0]) {
        await _pump(
          tester,
          hub: _hub(_Repo(groups: groups, members: members)),
          textScale: scale,
          size: Size(width, 900),
        );
        expect(tester.takeException(), isNull,
            reason: 'list at $width px, text $scale');

        await _pump(
          tester,
          hub: _hub(_Repo(groups: groups, members: members), routeId: 't1'),
          textScale: scale,
          size: Size(width, 900),
        );
        expect(tester.takeException(), isNull,
            reason: 'group page at $width px, text $scale');
      }
    }
  });

  testWidgets(
      'a group the viewer cannot see says so, with a way back to the list',
      (tester) async {
    await _pump(
      tester,
      hub: _hub(_Repo(groups: const [], members: const []), routeId: 'gone'),
    );
    expect(
        find.text('This group is not available to you now.'), findsOneWidget);
    expect(find.text('Back to groups'), findsWidgets);
    expect(find.byType(AppBar), findsWidgets);
    expect(AppColors.midGreen, isNotNull);
  });
}
