import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a message with every field reads back the same from its cache map', () {
    final original = ChannelMessage(
      id: 'm1',
      senderEmail: 'asha@example.com',
      senderName: 'Asha',
      text: 'Bazar on **Friday**',
      timestamp: DateTime(2026, 11, 2, 9, 30, 15, 250),
      kind: ChannelMessageKind.poll,
      replyTo: const ChannelReply(id: 'm0', senderName: 'Babu', text: 'Ok'),
      attachments: const [
        ChannelAttachment(url: 'https://media.example/a.jpg'),
        ChannelAttachment(url: 'https://media.example/v.mp4', isVideo: true),
        ChannelAttachment(
          url: 'https://media.example/v.m4a',
          isAudio: true,
          durationSeconds: 12,
        ),
        ChannelAttachment(
          url: 'https://media.example/list.pdf',
          isFile: true,
          fileName: 'list.pdf',
          fileSizeBytes: 2048,
        ),
      ],
      reactions: const {'babu@example.com': '👍'},
      mentions: const ['babu@example.com'],
      pollOptions: const ['Fish', 'Chicken'],
      votes: const {'fish': 2, 'chicken': 1},
      isPinned: true,
      editedAt: DateTime(2026, 11, 2, 10),
      expenseId: 'e1',
      expenseTitle: 'Lunch',
      expenseAmountPaisa: 150000,
      locationLatitude: 23.8103,
      locationLongitude: 90.4125,
      locationTitle: 'Dhaka',
    );

    final restored = ChannelMessage.fromMap(original.id, original.toCacheMap());

    expect(restored.id, original.id);
    expect(restored.senderEmail, original.senderEmail);
    expect(restored.senderName, original.senderName);
    expect(restored.text, original.text);
    expect(restored.timestamp, original.timestamp);
    expect(restored.kind, original.kind);
    expect(restored.replyTo?.id, 'm0');
    expect(restored.replyTo?.text, 'Ok');
    expect(restored.attachments.length, 4);
    expect(restored.attachments[0].isVideo, isFalse);
    expect(restored.attachments[1].isVideo, isTrue);
    expect(restored.attachments[2].isAudio, isTrue);
    expect(restored.attachments[2].durationSeconds, 12);
    expect(restored.attachments[3].isFile, isTrue);
    expect(restored.attachments[3].fileName, 'list.pdf');
    expect(restored.attachments[3].fileSizeBytes, 2048);
    expect(restored.reactions, original.reactions);
    expect(restored.mentions, original.mentions);
    expect(restored.pollOptions, original.pollOptions);
    expect(restored.votes, original.votes);
    expect(restored.isPinned, isTrue);
    expect(restored.editedAt, original.editedAt);
    expect(restored.expenseId, 'e1');
    expect(restored.expenseTitle, 'Lunch');
    expect(restored.expenseAmountPaisa, 150000);
    expect(restored.locationLatitude, 23.8103);
    expect(restored.locationLongitude, 90.4125);
    expect(restored.locationTitle, 'Dhaka');
  });

  test(
      'a plain message keeps its text and time, and a pending flag is not cached',
      () {
    final pending = ChannelMessage(
      id: 'm2',
      senderEmail: 'babu@example.com',
      senderName: 'Babu',
      text: 'Hello',
      timestamp: DateTime(2026, 11, 2, 9),
      isPending: true,
    );

    final map = pending.toCacheMap();
    expect(map.containsKey('isPending'), isFalse);

    final restored = ChannelMessage.fromMap(pending.id, map);
    expect(restored.text, 'Hello');
    expect(restored.isPending, isFalse);
    expect(restored.attachments, isEmpty);
    expect(restored.replyTo, isNull);
  });
}
