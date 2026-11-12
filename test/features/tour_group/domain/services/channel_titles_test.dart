import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/channel_titles.dart';
import 'package:flutter_test/flutter_test.dart';

// The translation table is not needed here: each key comes back as itself, so a test reads
// the key that a title would be translated from.
String _key(String key) => key;

TourGroup _group({
  GroupKind kind = GroupKind.tour,
  String? preset,
}) =>
    TourGroup(
      id: 't1',
      name: 'Cox',
      ownerEmail: 'owner@example.com',
      inviteCode: 'ABCDEFGH',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 2),
      createdAt: DateTime(2026, 1, 1),
      kind: kind,
      preset: preset,
    );

String _title(String id, {TourGroup? group, String name = ''}) =>
    channelTitleText(
      channel: TourChannel(id: id, name: name),
      group: group,
      translate: _key,
    );

void main() {
  test('the voice lounge keeps its own title', () {
    expect(
      channelTitleText(
        channel: const TourChannel(
          id: kBuiltInVoiceChannelId,
          kind: ChannelKind.voice,
        ),
        translate: _key,
      ),
      'chan_voice_lounge',
    );
  });

  test('an admin\'s title for a built-in channel replaces the standard one',
      () {
    expect(_title('general', name: 'Lobby'), 'Lobby');
  });

  test('a custom channel shows its name, and an unnamed one its id', () {
    expect(_title('rules', name: 'Rules'), '# Rules');
    expect(_title('rules'), '#rules');
  });

  test('a custom voice channel is marked as voice', () {
    expect(
      channelTitleText(
        channel: const TourChannel(
          id: 'band',
          name: 'Band',
          kind: ChannelKind.voice,
        ),
        translate: _key,
      ),
      '🔊 Band',
    );
  });

  test('the general and safety channels have one standard title each', () {
    expect(_title('general'), 'tour_channel_general');
    expect(_title('emergency'), 'tour_channel_safety');
  });

  test('a food channel is named for the kind of group', () {
    expect(_title('food', group: _group()), 'tour_channel_food');
    expect(
      _title('food', group: _group(preset: TourGroup.friendsPreset)),
      'friends_channel_food',
    );
    expect(
      _title('food', group: _group(preset: TourGroup.officePreset)),
      'office_channel_food',
    );
    expect(_title('food', group: _group(preset: TourGroup.messPreset)),
        'mess_channel_food');
    expect(
      _title('food', group: _group(kind: GroupKind.family)),
      'family_channel_food',
    );
  });

  test('a sightseeing channel is named for the kind of group', () {
    expect(_title('sightseeing', group: _group()), 'tour_channel_places');
    // A mess keeps its bills in the channel that a trip calls sightseeing.
    expect(
      _title('sightseeing', group: _group(preset: TourGroup.messPreset)),
      'mess_channel_bills',
    );
    expect(
      _title('sightseeing', group: _group(preset: TourGroup.officePreset)),
      'office_channel_events',
    );
    expect(
      _title('sightseeing', group: _group(kind: GroupKind.family)),
      'family_channel_sightseeing',
    );
  });

  test('a household has its own home, kids and shopping channels', () {
    final household = _group(kind: GroupKind.family);
    expect(_title('home', group: household), 'family_channel_home');
    expect(_title('kids', group: household), 'family_channel_kids');
    expect(_title('shopping', group: household), 'family_channel_shopping');
  });
}
