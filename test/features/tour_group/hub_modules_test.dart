import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/hub_modules.dart';
import 'package:flutter_test/flutter_test.dart';

TourGroup _group({
  bool family = false,
  String? preset,
  TourType type = TourType.beach,
  bool moments = true,
  bool games = true,
  bool chat = true,
  bool seats = true,
  bool tide = true,
}) {
  return TourGroup(
    id: 'g',
    name: 'G',
    ownerEmail: 'a@b.c',
    inviteCode: 'ABCDEFGH',
    startDate: DateTime(2026, 11, 1),
    endDate: DateTime(2026, 11, 4),
    createdAt: DateTime(2026, 10, 1),
    kind: family ? GroupKind.family : GroupKind.tour,
    preset: preset,
    tourType: type,
    momentsEnabled: moments,
    modules: TourModules(
        games: games, chat: chat, seatsRooms: seats, tideSafety: tide),
  );
}

void main() {
  test('a trip shows the trip tools in the trip order', () {
    expect(hubModulesFor(_group()), [
      'feed',
      'ledger',
      'seats',
      'calendar',
      'tide',
      'notices',
      'journey',
      'safety',
      'games',
      'quiz',
      'scrapbook',
      'checklist',
      'channels',
      'news',
    ]);
  });

  test('a trip without seats, tide or chat drops those tools only', () {
    expect(
      hubModulesFor(_group(seats: false, tide: false, chat: false)),
      isNot(anyOf(contains('seats'), contains('tide'), contains('channels'))),
    );
  });

  test('a household shows its family tools, and no trip tools', () {
    final ids = hubModulesFor(_group(family: true));
    expect(
        ids,
        containsAll(
            ['family_tasks', 'dependents', 'album', 'calendar', 'safety']));
    expect(ids,
        isNot(anyOf(contains('quiz'), contains('journey'), contains('seats'))));
    expect(ids.first, 'channels',
        reason: 'a family leads with what it uses every day');
  });

  test('an office has no safety tile and no household tools, but keeps important dates', () {
    final ids =
        hubModulesFor(_group(family: true, preset: TourGroup.officePreset));
    expect(
        ids,
        isNot(anyOf(
            contains('safety'), contains('dependents'))));
    expect(ids, contains('calendar'));
  });

  test('Moments follows its setting only where it can be turned off', () {
    expect(hubModulesFor(_group(moments: false)), contains('feed'),
        reason: 'a trip always has Moments');
    final office =
        _group(family: true, preset: TourGroup.officePreset, moments: false);
    expect(hubModulesFor(office), isNot(contains('feed')));
    expect(hubModulesFor(office, momentsOpen: true), contains('feed'),
        reason: 'an explicit value overrides the group setting');
  });

  test('a mess shows meals; a samity shows the samity tool', () {
    expect(hubModulesFor(_group(family: true, preset: TourGroup.messPreset)),
        contains('meals'));
    expect(hubModulesFor(_group(family: true, preset: TourGroup.samityPreset)),
        contains('samity'));
  });

  test('family tools keep the family order, so meals comes after the channels',
      () {
    // Every family tool that is not in the family order is appended in its own order.
    final ids =
        hubModulesFor(_group(family: true, preset: TourGroup.messPreset));
    expect(ids.indexOf('meals'), greaterThan(ids.indexOf('channels')));
  });
}
