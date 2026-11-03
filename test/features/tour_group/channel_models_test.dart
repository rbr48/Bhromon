import 'package:bhromon/features/tour_group/data/voice_room_service.dart';
import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:bhromon/features/tour_group/domain/models/date_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChannelMessage', () {
    test('is not pending unless the local cache still holds the write', () {
      final base = {
        'text': 'Hi',
        'senderEmail': 'own@x.com',
        'timestamp': DateTime(2026, 1, 2),
      };
      expect(ChannelMessage.fromMap('m1', base).isPending, isFalse);
      expect(ChannelMessage.fromMap('m1', base, isPending: true).isPending,
          isTrue);
    });

    test('reads a poll with its options and votes', () {
      final m = ChannelMessage.fromMap('p1', {
        'kind': 'poll',
        'text': 'Dinner?',
        'senderEmail': 'Own@X.com',
        'senderName': 'Own',
        'timestamp': DateTime(2026, 1, 2),
        'pollOptions': ['Hilsa', 'Chicken', 'Pizza'],
        'votes': {'A@x.com': 0, 'b@x.com': 0, 'c@x.com': 2, 'bad@x.com': 'x'},
      });
      expect(m.kind, ChannelMessageKind.poll);
      expect(m.senderEmail, 'own@x.com');
      expect(m.voteCounts, [2, 0, 1]);
      expect(m.voteBy('A@X.com'), 0);
      expect(m.votes.containsKey('bad@x.com'), isFalse);
    });

    test('reads reactions, mentions, a reply and an expense card', () {
      final m = ChannelMessage.fromMap('m1', {
        'text': 'see you',
        'senderEmail': 'a@x.com',
        'timestamp': DateTime(2026, 1, 2),
        'reactions': {'B@x.com': '👍', 'c@x.com': '👍', 'd@x.com': '🔥'},
        'mentions': ['E@x.com'],
        'replyTo': {'id': 'r', 'senderName': 'Rahim', 'text': 'lunch?'},
      });
      expect(m.reactionCounts, {'👍': 2, '🔥': 1});
      expect(m.reactionBy('b@x.com'), '👍');
      expect(m.mentionsEmail('e@x.com'), isTrue);
      expect(m.replyTo!.senderName, 'Rahim');

      final expense = ChannelMessage.fromMap('x1', {
        'kind': 'expense',
        'text': 'Dinner',
        'expenseId': 'e1',
        'expenseTitle': 'Dinner',
        'expenseAmountPaisa': 240000,
        'timestamp': DateTime(2026, 1, 2),
      });
      expect(expense.kind, ChannelMessageKind.expense);
      expect(expense.expenseAmountPaisa, 240000);
    });

    test('keeps only https attachments, and reads video kinds', () {
      final m = ChannelMessage.fromMap('a1', {
        'text': '',
        'timestamp': DateTime(2026, 1, 2),
        'attachments': [
          {'url': 'https://media.example/a.jpg', 'kind': 'image'},
          {'url': 'file:///device/b.jpg', 'kind': 'image'},
          {'url': 'https://media.example/c.mp4', 'kind': 'video'},
        ],
      });
      expect(m.attachments.map((a) => a.url),
          ['https://media.example/a.jpg', 'https://media.example/c.mp4']);
      expect(m.attachments.last.isVideo, isTrue);
    });

    test(
        'reads document file attachments and separates visual vs file attachments',
        () {
      final m = ChannelMessage.fromMap('doc1', {
        'text': 'Here is the tour plan',
        'timestamp': DateTime(2026, 1, 2),
        'attachments': [
          {'url': 'https://media.example/a.jpg', 'kind': 'image'},
          {
            'url': 'https://media.example/plan.pdf',
            'kind': 'file',
            'fileName': 'tour_plan.pdf',
            'fileSizeBytes': 1048576,
          },
        ],
      });
      expect(m.visualAttachments.length, 1);
      expect(m.visualAttachments.first.url, 'https://media.example/a.jpg');
      expect(m.fileAttachments.length, 1);
      expect(m.fileAttachments.first.isFile, isTrue);
      expect(m.fileAttachments.first.fileName, 'tour_plan.pdf');
      expect(m.fileAttachments.first.fileSizeBytes, 1048576);

      final map = m.fileAttachments.first.toMap();
      expect(map['kind'], 'file');
      expect(map['fileName'], 'tour_plan.pdf');
      expect(map['fileSizeBytes'], 1048576);

      final reply = ChannelReply.quoting(ChannelMessage(
        id: 'msg1',
        senderEmail: 'a@b.com',
        senderName: 'Rahim',
        text: '',
        timestamp: DateTime.now(),
        attachments: [m.fileAttachments.first],
      ));
      expect(reply.text, '📄 tour_plan.pdf');
    });

    test('an unknown kind is read as an ordinary message', () {
      final m = ChannelMessage.fromMap('k', {
        'kind': 'hologram',
        'text': 'hi',
        'timestamp': DateTime(2026, 1, 2),
      });
      expect(m.kind, ChannelMessageKind.text);
    });

    test('reads location metadata correctly and reports hasLocation', () {
      final m = ChannelMessage.fromMap('loc1', {
        'text': 'Meet here!',
        'senderEmail': 'guide@x.com',
        'timestamp': DateTime(2026, 1, 2),
        'locationLatitude': 21.4272,
        'locationLongitude': 92.0058,
        'locationTitle': "Cox's Bazar Beach",
      });
      expect(m.hasLocation, isTrue);
      expect(m.locationLatitude, 21.4272);
      expect(m.locationLongitude, 92.0058);
      expect(m.locationTitle, "Cox's Bazar Beach");

      final withoutLoc = ChannelMessage.fromMap('loc2', {
        'text': 'Plain text',
        'senderEmail': 'guide@x.com',
        'timestamp': DateTime(2026, 1, 2),
      });
      expect(withoutLoc.hasLocation, isFalse);
    });
  });

  group('countUnread', () {
    final base = DateTime(2026, 1, 2, 10);
    ChannelMessage msg(String id, String sender, Duration after) =>
        ChannelMessage.fromMap(id, {
          'text': id,
          'senderEmail': sender,
          'timestamp': base.add(after),
        });

    test('counts other people\'s messages newer than the last read time', () {
      final messages = [
        msg('1', 'me@x.com', const Duration(minutes: 5)),
        msg('2', 'you@x.com', const Duration(minutes: 4)),
        msg('3', 'you@x.com', const Duration(minutes: 1)),
      ];
      expect(
          countUnread(
              messages, base.add(const Duration(minutes: 2)), 'ME@x.com'),
          1);
      expect(countUnread(messages, null, 'me@x.com'), 2);
    });
  });

  group('TourChannel', () {
    test('the four starting channels are built in', () {
      expect(const TourChannel(id: 'food').isBuiltIn, isTrue);
      expect(
          const TourChannel(id: 'k7x2qa9p', name: 'Photos').isBuiltIn, isFalse);
    });

    test('supports voice kind and built-in voice lounge', () {
      const lounge = TourChannel(id: kBuiltInVoiceChannelId);
      expect(lounge.isBuiltIn, isTrue);
      expect(lounge.isVoice, isTrue);

      final customVoice = TourChannel.fromMap('v1', {
        'name': 'Campfire Chat',
        'kind': 'voice',
        'adminOnly': true,
      });
      expect(customVoice.isVoice, isTrue);
      expect(customVoice.kind, ChannelKind.voice);
      expect(customVoice.name, 'Campfire Chat');
      expect(customVoice.adminOnly, isTrue);

      final map = customVoice.toMap();
      expect(map['kind'], 'voice');
      expect(map['name'], 'Campfire Chat');
    });
  });

  group('VoiceParticipant', () {
    test('serializes and deserializes correctly', () {
      final now = DateTime(2026, 10, 26, 12, 0);
      final p = VoiceParticipant(
        email: 'Alice@Example.Com',
        displayName: 'Alice',
        uid: 'uid_alice',
        photoUrl: 'https://example.com/alice.jpg',
        isAudioMuted: true,
        isVideoOn: false,
        joinedAt: now,
      );

      final map = p.toMap();
      expect(map['email'], 'alice@example.com');
      expect(map['displayName'], 'Alice');
      expect(map['uid'], 'uid_alice');
      expect(map['photoUrl'], 'https://example.com/alice.jpg');
      expect(map['isAudioMuted'], isTrue);
      expect(map['isVideoOn'], isFalse);

      final deserialized = VoiceParticipant.fromMap(map);
      expect(deserialized.email, 'alice@example.com');
      expect(deserialized.displayName, 'Alice');
      expect(deserialized.uid, 'uid_alice');
      expect(deserialized.photoUrl, 'https://example.com/alice.jpg');
      expect(deserialized.isAudioMuted, isTrue);
      expect(deserialized.isVideoOn, isFalse);
    });
  });

  group('typing', () {
    test('a signal goes stale after the typing window', () {
      final at = DateTime(2026, 1, 2, 10);
      final t = TypingMember(email: 'a@x.com', name: 'A', at: at);
      expect(t.isFreshAt(at.add(const Duration(seconds: 2))), isTrue);
      expect(t.isFreshAt(at.add(kTypingWindow)), isFalse);
    });
  });

  test('readDate returns null for missing or non-date values', () {
    expect(readDate(null), isNull);
    expect(readDate('later'), isNull);
  });

  group('built-in channels', () {
    test('a built-in title is its name, and empty means the standard title',
        () {
      expect(const TourChannel(id: 'food', name: 'Dinner plans').titleOverride,
          'Dinner plans');
      expect(const TourChannel(id: 'food').titleOverride, '');
    });

    test('the voice lounge and custom channels have no title override', () {
      expect(
          const TourChannel(id: kBuiltInVoiceChannelId, name: 'Lounge')
              .titleOverride,
          '');
      expect(const TourChannel(id: 'c1', name: 'Kitchen').titleOverride, '');
    });

    test('the hidden flag is read and written', () {
      final hidden = TourChannel.fromMap('food', {'name': '', 'hidden': true});
      expect(hidden.hidden, isTrue);
      expect(TourChannel.fromMap('food', {'name': ''}).hidden, isFalse);
      expect(hidden.toMap()['hidden'], isTrue);
    });

    test('hiding writes the name, topic and posting rule the rules need', () {
      const channel = TourChannel(
          id: 'food', name: 'Dinner', topic: 'Menu', adminOnly: true);
      expect(builtInChannelFields(channel, hidden: true), {
        'name': 'Dinner',
        'topic': 'Menu',
        'adminOnly': true,
        'hidden': true,
      });
      expect(builtInChannelFields(channel, hidden: false)['hidden'], isFalse);
    });

    test('only hidden built-in channels other than the voice lounge are hidden',
        () {
      final docs = [
        const TourChannel(id: 'food', hidden: true),
        const TourChannel(id: 'general'),
        const TourChannel(id: kBuiltInVoiceChannelId, hidden: true),
        const TourChannel(id: 'c1', name: 'Kitchen', hidden: true),
      ];
      expect(hiddenBuiltInChannelIds(docs), {'food'});
    });

    test(
        'the list leaves out hidden built-in channels, but never the voice lounge',
        () {
      final list = channelsForList(
        builtInIds: const ['general', 'food', kBuiltInVoiceChannelId],
        docs: const [
          TourChannel(id: 'food', hidden: true),
          TourChannel(id: kBuiltInVoiceChannelId, hidden: true),
          TourChannel(id: 'c2', name: 'Zoo'),
          TourChannel(id: 'c1', name: 'apples'),
        ],
      );
      expect(list.map((c) => c.id).toList(),
          ['general', kBuiltInVoiceChannelId, 'c1', 'c2']);
    });

    test('a built-in channel with no document is listed with the defaults', () {
      final list =
          channelsForList(builtInIds: const ['sightseeing'], docs: const []);
      expect(list.single.id, 'sightseeing');
      expect(list.single.titleOverride, '');
    });
  });
}
