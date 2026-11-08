import 'package:bhromon/features/share_intake/domain/share_plan.dart';
import 'package:bhromon/features/share_intake/domain/shared_file.dart';
import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:flutter_test/flutter_test.dart';

SharedFile _file(String name) =>
    SharedFile(name: name, sizeBytes: 1000, path: '/cache/$name');

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
}) {
  return chatDestinationsFor(
    chats: chats,
    currentUid: 'me',
    myTourIds: tours,
    blockedUids: blocked,
    lockedChatIds: locked,
    fallbackName: 'Member',
  );
}

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
    test('offers a chat in one of my tours under the name the chat stores', () {
      final result = _destinations([MapEntry('c1', _chat(name: 'Rahim'))]);

      expect(result, hasLength(1));
      expect(result.single.chatId, 'c1');
      expect(result.single.otherUid, 'you');
      expect(result.single.title, 'Rahim');
      expect(result.single.sharedTourId, 't1');
    });

    test('leaves out a chat outside my tours, and a chat from before tours',
        () {
      final result = _destinations([
        MapEntry('elsewhere', _chat(tour: 't9')),
        MapEntry('legacy', _chat(tour: null)),
      ]);

      expect(result.map((destination) => destination.chatId), isEmpty);
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

    test('uses the given name when the stored one is blank', () {
      final result = _destinations([MapEntry('c1', _chat(name: '   '))]);

      expect(result.single.title, 'Member');
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
    const channels = [
      TourChannel(id: 'general', name: 'General'),
      TourChannel(id: 'old', name: 'Old', hidden: true),
      TourChannel(id: 'lounge', name: 'Lounge', kind: ChannelKind.voice),
      TourChannel(id: 'admins', name: 'Admins', adminOnly: true),
    ];

    test('offers a member only the text channels that are not hidden', () {
      final result = channelDestinationsFor(
        tourId: 't1',
        tourName: 'Cox',
        isAdmin: false,
        channels: channels,
      );

      expect(result.map((channel) => channel.channelId), ['general']);
      expect(result.single.channelName, 'General');
      expect(result.single.tourName, 'Cox');
      expect(result.single.tourId, 't1');
    });

    test('adds the admin-only channels for an admin', () {
      final result = channelDestinationsFor(
        tourId: 't1',
        tourName: 'Cox',
        isAdmin: true,
        channels: channels,
      );

      expect(result.map((channel) => channel.channelId), ['general', 'admins']);
    });
  });
}
