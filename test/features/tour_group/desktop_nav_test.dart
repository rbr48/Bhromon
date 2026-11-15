import 'package:bhromon/core/layout/breakpoints.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/desktop_nav.dart';
import 'package:bhromon/features/tour_group/domain/services/hub_modules.dart';
import 'package:flutter_test/flutter_test.dart';

TourGroup _group({String id = 'g', bool family = false, String? preset}) {
  return TourGroup(
    id: id,
    name: 'G',
    ownerEmail: 'a@b.c',
    inviteCode: 'ABCDEFGH',
    startDate: DateTime(2026, 11, 1),
    endDate: DateTime(2026, 11, 4),
    createdAt: DateTime(2026, 10, 1),
    kind: family ? GroupKind.family : GroupKind.tour,
    preset: preset,
  );
}

void main() {
  group('the name of a group type', () {
    test('every preset has its own name', () {
      final keys = {
        for (final preset in const [
          TourGroup.friendsPreset,
          TourGroup.officePreset,
          TourGroup.campusPreset,
          TourGroup.messPreset,
          TourGroup.societyPreset,
          TourGroup.samityPreset,
          TourGroup.schoolPreset,
          TourGroup.sportsPreset,
          TourGroup.studyPreset,
          TourGroup.committeePreset,
        ])
          preset: groupTypeLabelKey(_group(family: true, preset: preset)),
      };
      expect(keys.values, everyElement(isNotNull));
      expect(keys.values.toSet(), hasLength(keys.length));
      expect(keys[TourGroup.studyPreset], 'hub_study_badge');
    });

    test('a plain family circle is a family, and a trip has no type name', () {
      expect(groupTypeLabelKey(_group(family: true)), 'hub_family_badge');
      expect(groupTypeLabelKey(_group()), isNull);
    });
  });

  group('the sidebar tools of a group', () {
    test('a study circle is offered its study tools and no trip tool', () {
      final tools = sidebarGroupTools(
          _group(family: true, preset: TourGroup.studyPreset));
      expect(
          tools,
          containsAll(<String>[
            'study_subjects',
            'study_reading',
            'study_books',
            'notices',
            'channels',
          ]));
      for (final trip in const [
        'journey',
        'seats',
        'checklist',
        'tide',
        'scrapbook',
        'quiz',
        'ledger',
      ]) {
        expect(tools, isNot(contains(trip)), reason: trip);
      }
    });

    test('a trip is offered its trip tools and no study tool', () {
      final tools = sidebarGroupTools(_group());
      expect(tools,
          containsAll(<String>['journey', 'seats', 'checklist', 'quiz']));
      expect(tools, isNot(contains('study_subjects')));
    });

    test('games and news are not group tools', () {
      for (final group in [
        _group(),
        _group(family: true, preset: TourGroup.studyPreset),
      ]) {
        final tools = sidebarGroupTools(group);
        expect(tools, isNot(contains('games')));
        expect(tools, isNot(contains('news')));
      }
    });

    test('the tools keep the hub order and each has a route', () {
      for (final preset in const [
        null,
        TourGroup.studyPreset,
        TourGroup.messPreset,
        TourGroup.societyPreset,
        TourGroup.samityPreset,
        TourGroup.officePreset,
      ]) {
        final group = _group(family: true, preset: preset);
        final hub = hubModulesFor(group)
            .where((id) => id != 'games' && id != 'news')
            .toList();
        expect(sidebarGroupTools(group), hub, reason: '$preset');
        for (final id in hub) {
          expect(groupToolRoute('g', id), startsWith('/group/g/'),
              reason: '$preset $id');
        }
      }
    });

    test('every tool the hub can show is a group tool, a game or the news', () {
      for (final id in {...tripModuleOrder, ...familyModuleOrder}) {
        expect(
          kGroupToolRoutes.containsKey(id) || id == 'games' || id == 'news',
          isTrue,
          reason: id,
        );
      }
    });
  });

  group('the tool of a path', () {
    test('a tool page names its tool', () {
      expect(groupToolOfPath('/group/x/study-subjects'), 'study_subjects');
      expect(groupToolOfPath('/group/x/logistics'), 'seats');
      expect(groupToolOfPath('/group/x/family-dates'), 'calendar');
    });

    test('other paths name none', () {
      expect(groupToolOfPath('/group-hub'), isNull);
      expect(groupToolOfPath('/chats'), isNull);
      expect(groupToolOfPath('/group/x'), isNull);
      expect(groupToolOfPath('/group/x/unknown'), isNull);
    });
  });

  group('picking another group', () {
    final study = _group(id: 's', family: true, preset: TourGroup.studyPreset);
    final trip = _group(id: 't');

    test('the same tool opens when the new group has it', () {
      expect(pathForGroupSwitch(study, '/group/t/notices'), '/group/s/notices');
      expect(
          pathForGroupSwitch(trip, '/group/s/channels'), '/group/t/channels');
    });

    test('a tool the new group lacks opens the group page instead', () {
      expect(pathForGroupSwitch(study, '/group/t/logistics'),
          '/group-hub?tourId=s');
      expect(
          pathForGroupSwitch(study, '/group/t/journey'), '/group-hub?tourId=s');
      expect(pathForGroupSwitch(trip, '/group/s/study-subjects'),
          '/group-hub?tourId=t');
    });

    test('from a page of no group the group page opens', () {
      expect(pathForGroupSwitch(study, '/chats'), '/group-hub?tourId=s');
      expect(pathForGroupSwitch(study, '/game-zone'), '/group-hub?tourId=s');
    });
  });

  group('the grid of group tools', () {
    test('a phone has two tiles across, half as tall as they are wide', () {
      final grid = hubToolGridFor(328);
      expect(grid.columns, 2);
      expect(grid.tileHeight, 80);
    });

    test('a wider space gives each tile room for its text', () {
      expect(hubToolGridFor(560).columns, 2);
      expect(hubToolGridFor(858).columns, 3);
      expect(hubToolGridFor(1000).columns, 4);
      for (final width in [500.0, 560.0, 749.0, 750.0, 858.0, 928.0]) {
        final grid = hubToolGridFor(width);
        final tileWidth = (width - 8 * (grid.columns - 1)) / grid.columns;
        expect(tileWidth, greaterThanOrEqualTo(240), reason: '$width');
        expect(grid.tileHeight, 84);
      }
    });
  });

  group('desktop widths', () {
    test('the shell starts at 900 and the dock at 1280', () {
      expect(isDesktopShellWidth(899), isFalse);
      expect(isDesktopShellWidth(900), isTrue);
      expect(isDesktopDockWidth(1279), isFalse);
      expect(isDesktopDockWidth(1280), isTrue);
    });

    test('the page gets what the panels leave, up to the cap', () {
      expect(desktopContentWidth(1150, sidebarWidth: 260, dockWidth: 0), 890);
      expect(desktopContentWidth(1366, sidebarWidth: 260, dockWidth: 280), 826);
      expect(desktopContentWidth(1920, sidebarWidth: 260, dockWidth: 320), 960);
      expect(desktopContentWidth(200, sidebarWidth: 260, dockWidth: 0), 0);
    });
  });
}
