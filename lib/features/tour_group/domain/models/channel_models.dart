// Discussion channels: the built-in channels, channels admins add, and the
// messages posted in them.

import 'date_codec.dart';

/// Channels every tour starts with. Their titles come from the translation table.
const List<String> kBuiltInTextChannelIds = [
  'general',
  'food',
  'sightseeing',
  'emergency',
];

const String kBuiltInVoiceChannelId = 'voice_lounge';

/// Most people one voice room holds. Everyone connects to everyone else, so a
/// person's upload grows with the room's size.
const int kVoiceRoomMaxParticipants = 8;

/// A seat whose heartbeat is older than this counts as empty. Each phone in a
/// room refreshes its seat every 45 seconds. A phone that crashes or loses its
/// network never removes its own seat, so without this the seat would stay
/// taken, and the room could fill with ghosts. Three minutes allows for
/// clock drift between phones and the server.
const Duration kVoiceSeatStaleAfter = Duration(minutes: 3);

/// Whether a seat's heartbeat (`lastSeenAt`) is recent enough to be live. A
/// seat with no heartbeat is not live.
bool isVoiceSeatLive(Map<String, dynamic> seat, {required DateTime now}) {
  final seenAt = readDate(seat['lastSeenAt']);
  return seenAt != null && now.difference(seenAt) <= kVoiceSeatStaleAfter;
}

/// How many people hold a live seat in a voice room, leaving out [exceptEmail].
/// [seats] maps each seat's email to its stored data. See [isVoiceSeatLive].
int countSeatedVoiceParticipants(
  Map<String, Map<String, dynamic>> seats, {
  required String exceptEmail,
  required DateTime now,
}) {
  var count = 0;
  for (final entry in seats.entries) {
    if (entry.key == exceptEmail) continue;
    if (isVoiceSeatLive(entry.value, now: now)) count++;
  }
  return count;
}

const List<String> kBuiltInChannelIds = [
  ...kBuiltInTextChannelIds,
  kBuiltInVoiceChannelId,
];

/// The kind of channel: text messaging or voice lounge.
enum ChannelKind { text, voice }

/// Longest text a message may carry.
const int kChannelMessageMaxLength = 1000;

/// Most photos one message can carry. A video is sent on its own.
const int kChannelMaxImages = 4;

/// Most pinned messages a channel can hold.
const int kChannelMaxPins = 50;

/// Most options a poll can offer.
const int kChannelMaxPollOptions = 6;

/// The quick reactions offered on every message.
const List<String> kQuickReactions = ['👍', '❤️', '😂', '😮', '🙏', '🔥'];

/// How long a typing signal stays on screen without a refresh.
const Duration kTypingWindow = Duration(seconds: 6);

/// A channel as stored in `tours/{id}/channels/{channelId}`. A built-in channel
/// may have no document; it then uses the defaults here.
class TourChannel {
  final String id;
  final String name;
  final String topic;
  final bool adminOnly;
  final String createdByEmail;
  final ChannelKind kind;

  const TourChannel({
    required this.id,
    this.name = '',
    this.topic = '',
    this.adminOnly = false,
    this.createdByEmail = '',
    this.kind = ChannelKind.text,
  });

  bool get isBuiltIn => kBuiltInChannelIds.contains(id);
  bool get isVoice => kind == ChannelKind.voice || id == kBuiltInVoiceChannelId;

  factory TourChannel.fromMap(String id, Map<String, dynamic> map) {
    final rawKind = map['kind'] as String?;
    final isVoice = rawKind == 'voice' || id == kBuiltInVoiceChannelId;
    return TourChannel(
      id: id,
      name: (map['name'] as String?)?.trim() ?? '',
      topic: (map['topic'] as String?)?.trim() ?? '',
      adminOnly: map['adminOnly'] == true,
      createdByEmail: normalizeEmail(map['createdByEmail'] as String? ?? ''),
      kind: isVoice ? ChannelKind.voice : ChannelKind.text,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'topic': topic,
      'adminOnly': adminOnly,
      'createdByEmail': createdByEmail,
      'kind': kind == ChannelKind.voice ? 'voice' : 'text',
    };
  }
}

/// A photo or video attached to a message. The file lives on the media server.
class ChannelAttachment {
  final String url;
  final bool isVideo;

  const ChannelAttachment({required this.url, this.isVideo = false});

  factory ChannelAttachment.fromMap(Map<String, dynamic> map) {
    return ChannelAttachment(
      url: map['url'] as String? ?? '',
      isVideo: map['kind'] == 'video',
    );
  }

  Map<String, dynamic> toMap() {
    return {'url': url, 'kind': isVideo ? 'video' : 'image'};
  }
}

/// The message a reply quotes. Only a short excerpt is kept.
class ChannelReply {
  final String id;
  final String senderName;
  final String text;

  const ChannelReply({
    required this.id,
    required this.senderName,
    required this.text,
  });

  factory ChannelReply.quoting(ChannelMessage message) {
    final clipped = message.text.length > 140
        ? '${message.text.substring(0, 140)}…'
        : message.text;
    return ChannelReply(
      id: message.id,
      senderName: message.senderName,
      text: clipped,
    );
  }

  factory ChannelReply.fromMap(Map<String, dynamic> map) {
    return ChannelReply(
      id: map['id'] as String? ?? '',
      senderName: map['senderName'] as String? ?? 'Member',
      text: map['text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'senderName': senderName, 'text': text};
  }
}

/// Kinds of message. A poll and an expense card are created by slash commands.
enum ChannelMessageKind {
  text,
  poll,
  expense;

  static ChannelMessageKind fromString(String? value) {
    switch (value) {
      case 'poll':
        return ChannelMessageKind.poll;
      case 'expense':
        return ChannelMessageKind.expense;
      default:
        return ChannelMessageKind.text;
    }
  }
}

class ChannelMessage {
  final String id;
  final String senderEmail;
  final String senderName;
  final String text;
  final DateTime timestamp;
  final ChannelMessageKind kind;
  final ChannelReply? replyTo;
  final List<ChannelAttachment> attachments;

  /// Each member's reaction: email to emoji. One reaction per member.
  final Map<String, String> reactions;

  /// Emails of the members this message mentions.
  final List<String> mentions;

  /// Poll options, in order. Empty for other kinds.
  final List<String> pollOptions;

  /// Each member's vote: email to option index.
  final Map<String, int> votes;

  final bool isPinned;
  final DateTime? editedAt;
  final String? expenseId;
  final String expenseTitle;
  final int expenseAmountPaisa;

  const ChannelMessage({
    required this.id,
    required this.senderEmail,
    required this.senderName,
    required this.text,
    required this.timestamp,
    this.kind = ChannelMessageKind.text,
    this.replyTo,
    this.attachments = const [],
    this.reactions = const {},
    this.mentions = const [],
    this.pollOptions = const [],
    this.votes = const {},
    this.isPinned = false,
    this.editedAt,
    this.expenseId,
    this.expenseTitle = '',
    this.expenseAmountPaisa = 0,
    this.locationLatitude,
    this.locationLongitude,
    this.locationTitle,
    this.isPending = false,
  });

  bool get hasLocation => locationLatitude != null && locationLongitude != null;

  final double? locationLatitude;
  final double? locationLongitude;
  final String? locationTitle;

  /// True while this device's write is still waiting for the server. Set from
  /// the Firestore cache, so a message sent offline shows as pending.
  final bool isPending;

  bool isSentBy(String email) => senderEmail == normalizeEmail(email);

  bool mentionsEmail(String email) => mentions.contains(normalizeEmail(email));

  String? reactionBy(String email) => reactions[normalizeEmail(email)];

  int? voteBy(String email) => votes[normalizeEmail(email)];

  /// How many members chose each emoji.
  Map<String, int> get reactionCounts {
    final counts = <String, int>{};
    for (final emoji in reactions.values) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    return counts;
  }

  /// How many members chose each poll option, in option order.
  List<int> get voteCounts {
    return [
      for (var i = 0; i < pollOptions.length; i++)
        votes.values.where((v) => v == i).length,
    ];
  }

  factory ChannelMessage.fromMap(
    String id,
    Map<String, dynamic> map, {
    bool isPending = false,
  }) {
    final rawAttachments = map['attachments'];
    return ChannelMessage(
      id: id,
      senderEmail: normalizeEmail(map['senderEmail'] as String? ?? ''),
      senderName: map['senderName'] as String? ?? 'Member',
      text: map['text'] as String? ?? '',
      timestamp: readDate(map['timestamp']) ?? DateTime.now(),
      kind: ChannelMessageKind.fromString(map['kind'] as String?),
      replyTo: map['replyTo'] is Map
          ? ChannelReply.fromMap(
              Map<String, dynamic>.from(map['replyTo'] as Map))
          : null,
      attachments: rawAttachments is List
          ? [
              for (final a in rawAttachments)
                if (a is Map)
                  ChannelAttachment.fromMap(Map<String, dynamic>.from(a)),
            ].where((a) => a.url.startsWith('https://')).toList()
          : const [],
      reactions: readStringMap(map['reactions']),
      mentions: [
        for (final m in (map['mentions'] as List?) ?? const [])
          normalizeEmail(m.toString()),
      ],
      pollOptions: [
        for (final o in (map['pollOptions'] as List?) ?? const []) o.toString(),
      ],
      votes: readIntMap(map['votes']),
      isPinned: map['isPinned'] == true,
      editedAt: readDate(map['editedAt']),
      isPending: isPending,
      expenseId: map['expenseId'] as String?,
      expenseTitle: map['expenseTitle'] as String? ?? '',
      expenseAmountPaisa: (map['expenseAmountPaisa'] as num?)?.toInt() ?? 0,
      locationLatitude: (map['locationLatitude'] as num?)?.toDouble(),
      locationLongitude: (map['locationLongitude'] as num?)?.toDouble(),
      locationTitle: map['locationTitle'] as String?,
    );
  }
}

/// Someone currently typing in a channel.
class TypingMember {
  final String email;
  final String name;
  final DateTime at;

  const TypingMember(
      {required this.email, required this.name, required this.at});

  bool isFreshAt(DateTime now) => now.difference(at) < kTypingWindow;
}

/// How many of [messages] arrived after [lastRead] and were not sent by
/// [myEmail]. A null [lastRead] means nothing has been read yet.
int countUnread(
  Iterable<ChannelMessage> messages,
  DateTime? lastRead,
  String myEmail,
) {
  final me = normalizeEmail(myEmail);
  return messages
      .where((m) =>
          m.senderEmail != me &&
          (lastRead == null || m.timestamp.isAfter(lastRead)))
      .length;
}

/// Reads a Firestore map of strings, dropping anything else.
Map<String, String> readStringMap(Object? raw) {
  if (raw is! Map) return <String, String>{};
  return {
    for (final entry in raw.entries)
      if (entry.value is String)
        normalizeEmail(entry.key.toString()): entry.value as String,
  };
}

/// Reads a Firestore map of ints, dropping anything else.
Map<String, int> readIntMap(Object? raw) {
  if (raw is! Map) return <String, int>{};
  return {
    for (final entry in raw.entries)
      if (entry.value is int)
        normalizeEmail(entry.key.toString()): entry.value as int,
  };
}
