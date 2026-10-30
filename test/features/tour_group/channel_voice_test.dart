import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:bhromon/features/tour_group/domain/services/media_rules.dart';
import 'package:flutter_test/flutter_test.dart';

ChannelMessage _message({
  String text = '',
  List<ChannelAttachment> attachments = const [],
}) {
  return ChannelMessage(
    isPending: false,
    isPinned: false,
    id: 'm1',
    senderEmail: 'rahim@x.com',
    senderName: 'Rahim',
    text: text,
    timestamp: DateTime(2026, 1, 2, 9, 30),
    kind: ChannelMessageKind.text,
    pollOptions: const [],
    votes: const {},
    expenseAmountPaisa: 0,
    expenseTitle: 'Dinner',
    reactions: const {},
    attachments: attachments,
  );
}

void main() {
  group('voice note attachments', () {
    test('a voice note keeps its length through storage', () {
      const voice = ChannelAttachment(
        url: 'https://bhromon.fun/media/t/channels/n.m4a',
        isAudio: true,
        durationSeconds: 12,
      );

      expect(voice.toMap(), {
        'url': 'https://bhromon.fun/media/t/channels/n.m4a',
        'kind': 'audio',
        'durationSeconds': 12,
      });
      final back = ChannelAttachment.fromMap(voice.toMap());
      expect(back.isAudio, isTrue);
      expect(back.isVideo, isFalse);
      expect(back.durationSeconds, 12);
    });

    test('photos and video keep the shape they were stored with', () {
      expect(const ChannelAttachment(url: 'u').toMap(),
          {'url': 'u', 'kind': 'image'});
      expect(
        const ChannelAttachment(url: 'v', isVideo: true).toMap(),
        {'url': 'v', 'kind': 'video'},
      );
      final video = ChannelAttachment.fromMap({'url': 'v', 'kind': 'video'});
      expect(video.isVideo, isTrue);
      expect(video.isAudio, isFalse);
    });

    test('a voice note message shows its voice note, not a photo grid', () {
      const voice =
          ChannelAttachment(url: 'n', isAudio: true, durationSeconds: 3);
      final message = _message(attachments: const [voice]);

      expect(message.isVoiceNote, isTrue);
      expect(message.voiceAttachments, [voice]);
      expect(message.visualAttachments, isEmpty);
    });

    test('a photo message is not a voice note', () {
      final message = _message(
        text: 'Sunset',
        attachments: const [ChannelAttachment(url: 'p.jpg')],
      );

      expect(message.isVoiceNote, isFalse);
      expect(message.visualAttachments, hasLength(1));
    });

    test('a reply to a voice note quotes it by name', () {
      final message = _message(
        attachments: const [ChannelAttachment(url: 'n', isAudio: true)],
      );

      expect(ChannelReply.quoting(message).text, '🎤 Voice message');
    });

    test('voice notes are m4a, and the size limit matches the media server',
        () {
      expect(audioContentType('note.m4a'), 'audio/mp4');
      expect(audioContentType('NOTE.MP3'), 'audio/mpeg');
      expect(audioContentType('photo.jpg'), isNull);
      expect(kMaxAudioBytes, 25 * 1024 * 1024);
    });
  });
}
