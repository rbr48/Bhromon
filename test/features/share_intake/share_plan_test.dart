import 'package:bhromon/features/share_intake/domain/share_plan.dart';
import 'package:bhromon/features/share_intake/domain/shared_file.dart';
import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:flutter_test/flutter_test.dart';

SharedFile _file(String name) =>
    SharedFile(name: name, sizeBytes: 1000, path: '/cache/$name');

/// A chat as the app writes it. The stored profile belongs to the other person ('you').
Map<String, dynamic> _chat({
  String? tour = 't1',
  List<String> participants = const ['me', 'you'],
  String? name,
  DateTime? lastMessage,
  DateTime? clearedAt,
}) {
  return {
    if (tour != null) 'sharedTourId': tour,
    'participants': participants,
    if (name != null)
      'participantProfiles': {
        'you': {'displayName': name}
      },
    if (lastMessage != null) 'lastMessageTime': lastMessage,
    if (clearedAt != null) 'clearedAt': {'me': clearedAt},
  };
}

List<ChatDestination> _destinations(
  List<MapEntry<String, Map<String, dynamic>>> chats, {
  Set<String> tours = const {'t1'},
  Set<String> blocked = const {},
  Set<String> locked = const {},
  Map<String, String> names = const {},
  Map<String, String> tourNames = const {},
}) {
  return chatDestinationsFor(
    chats: chats,
    currentUid: 'me',
    myTourIds: tours,
    blockedUids: blocked,
    lockedChatIds: locked,
    namesByUid: names,
    tourNames: tourNames,
  );
}

TourGroup _group({
  String id = 't1',
  String name = 'Cox',
  GroupKind kind = GroupKind.tour,
  String? preset,
}) =>
    TourGroup(
      id: id,
      name: name,
      ownerEmail: 'owner@example.com',
      inviteCode: 'ABCDEFGH',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 2),
      createdAt: DateTime(2026, 1, 1),
      kind: kind,
      preset: preset,
    );

void main() {
  group('planChannelMessages', () {
    test('sends nothing for no files', () {
      expect(planChannelMessages(const []), isEmpty);
    });

    test('groups photos four to a message', () {
      final files = [for (var i = 0; i < 5; i++) _file('p$i.jpg')];

      final batches = planChannelMessages(files);

      expect(batches.map((batch) => batch.length), [4, 1]);
    });

    test('sends a video, voice note or document alone, in order', () {
      final files = [
        _file('a.jpg'),
        _file('clip.mp4'),
        _file('b.jpg'),
        _file('notes.pdf'),
        _file('c.jpg'),
      ];

      final names = [
        for (final batch in planChannelMessages(files))
          [for (final file in batch) file.name],
      ];

      expect(names, [
        ['a.jpg'],
        ['clip.mp4'],
        ['b.jpg'],
        ['notes.pdf'],
        ['c.jpg'],
      ]);
    });

    test('starts a new message for the photos after a document', () {
      final files = [
        for (var i = 0; i < 4; i++) _file('p$i.jpg'),
        _file('report.zip'),
        _file('p4.jpg'),
      ];

      final sizes = [
        for (final batch in planChannelMessages(files)) batch.length,
      ];

      expect(sizes, [4, 1, 1]);
    });
  });

  group('chatDestinationsFor', () {
    test('offers a chat in one of my tours under the other person\'s name', () {
      final result = _destinations([MapEntry('c1', _chat(name: 'Rahim'))]);

      expect(result, hasLength(1));
      expect(result.single.chatId, 'c1');
      expect(result.single.otherUid, 'you');
      expect(result.single.title, 'Rahim');
      expect(result.single.sharedTourId, 't1');
    });

    test('prefers the name in the person\'s profile to the one the chat stores',
        () {
      final result = _destinations(
        [MapEntry('c1', _chat(name: 'Old name'))],
        names: const {'you': 'Rahim'},
      );

      expect(result.single.title, 'Rahim');
    });

    test('never shows my own name for a chat without the other person\'s name',
        () {
      // Only my own profile is stored, which is what a chat has until the other person
      // writes to it. The row must not take my name, or it would look like a chat with me.
      final result = _destinations([
        const MapEntry(
          'c1',
          {
            'sharedTourId': 't1',
            'participants': ['me', 'you'],
            'participantProfiles': {
              'me': {'displayName': 'Asha'},
            },
          },
        ),
      ]);

      expect(result.single.title, isNull);
    });

    test('names a group on its chat, and a chat from before tours has none',
        () {
      final result = _destinations(
        [
          MapEntry('c1', _chat(name: 'Rahim')),
          MapEntry('legacy', _chat(tour: null, name: 'Karim')),
        ],
        tourNames: const {'t1': 'Cox Trip'},
      );

      final byId = {for (final chat in result) chat.chatId: chat};
      expect(byId['c1']!.tourName, 'Cox Trip');
      expect(byId['legacy']!.tourName, isNull);
    });

    test(
        'leaves out a chat outside my tours, and offers a chat from before tours',
        () {
      final result = _destinations([
        MapEntry('elsewhere', _chat(tour: 't9')),
        MapEntry('legacy', _chat(tour: null)),
      ]);

      expect(result.map((destination) => destination.chatId), ['legacy']);
    });

    test('leaves out a blocked person, a locked chat and a chat alone', () {
      final result = _destinations(
        [
          MapEntry('blocked', _chat(participants: const ['me', 'bad'])),
          MapEntry('locked', _chat()),
          MapEntry('alone', _chat(participants: const ['me'])),
          MapEntry('open', _chat(name: 'Karim')),
        ],
        blocked: const {'bad'},
        locked: const {'locked'},
      );

      expect(result.map((chat) => chat.chatId), ['open']);
    });

    test('leaves out a chat deleted after its last message', () {
      final cleared = DateTime(2026, 1, 2);
      final result = _destinations([
        MapEntry(
          'hidden',
          _chat(clearedAt: cleared, lastMessage: DateTime(2026, 1, 1)),
        ),
        MapEntry(
          'back',
          _chat(clearedAt: cleared, lastMessage: DateTime(2026, 1, 3)),
        ),
      ]);

      expect(result.map((chat) => chat.chatId), ['back']);
    });

    test('shows no name when the stored one is blank', () {
      final result = _destinations([MapEntry('c1', _chat(name: '   '))]);

      expect(result.single.title, isNull);
    });

    test('lists the newest chat first, and a chat with no message last', () {
      final result = _destinations([
        MapEntry('none', _chat(name: 'Zed')),
        MapEntry(
          'older',
          _chat(name: 'Bina', lastMessage: DateTime(2026, 1, 1)),
        ),
        MapEntry(
          'newer',
          _chat(name: 'Asha', lastMessage: DateTime(2026, 2, 1)),
        ),
      ]);

      expect(result.map((chat) => chat.chatId), ['newer', 'older', 'none']);
    });
  });

  group('channelDestinationsFor', () {
    const lounge = TourChannel(
      id: 'lounge',
      name: 'Lounge',
      kind: ChannelKind.voice,
    );

    test('offers the built-in channels a group starts with, even unedited', () {
      final result = channelDestinationsFor(
        group: _group(),
        isAdmin: false,
        docs: const [],
      );

      expect(result.map((channel) => channel.channelId),
          ['general', 'food', 'sightseeing', 'emergency']);
      expect(result.first.tourId, 't1');
      expect(result.first.tourName, 'Cox');
    });

    test('a family circle has its own built-in channels', () {
      final result = channelDestinationsFor(
        group: _group(kind: GroupKind.family),
        isAdmin: false,
        docs: const [],
      );

      final ids = result.map((channel) => channel.channelId).toList();
      expect(ids, containsAll(['home', 'kids', 'shopping']));
    });

    test('leaves out a built-in channel an admin has hidden', () {
      final result = channelDestinationsFor(
        group: _group(),
        isAdmin: false,
        docs: const [TourChannel(id: 'food', hidden: true)],
      );

      expect(result.map((channel) => channel.channelId),
          ['general', 'sightseeing', 'emergency']);
    });

    test('never offers the voice lounge, which is a voice channel', () {
      final result = channelDestinationsFor(
        group: _group(),
        isAdmin: true,
        docs: const [lounge],
      );

      expect(result.map((channel) => channel.channelId),
          isNot(contains('voice_lounge')));
      expect(result.map((channel) => channel.channelId),
          isNot(contains('lounge')));
    });

    test('adds the admin-only channels for an admin only', () {
      const admins = TourChannel(id: 'admins', name: 'Admins', adminOnly: true);
      final member = channelDestinationsFor(
        group: _group(),
        isAdmin: false,
        docs: const [admins],
      );
      final admin = channelDestinationsFor(
        group: _group(),
        isAdmin: true,
        docs: const [admins],
      );

      expect(member.map((channel) => channel.channelId),
          isNot(contains('admins')));
      expect(admin.map((channel) => channel.channelId), contains('admins'));
    });

    test('lists the channels admins added after the built-in ones, by name',
        () {
      final result = channelDestinationsFor(
        group: _group(),
        isAdmin: false,
        docs: const [
          TourChannel(id: 'zz', name: 'Zoo'),
          TourChannel(id: 'aa', name: 'alpha'),
        ],
      );

      expect(result.map((channel) => channel.channelId), [
        'general',
        'food',
        'sightseeing',
        'emergency',
        'aa',
        'zz',
      ]);
    });
  });
}
