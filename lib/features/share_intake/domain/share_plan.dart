import 'package:bhromon/features/chat/data/chat_deletion_service.dart';
import 'package:bhromon/features/chat/domain/chat_deletion.dart';
import 'package:bhromon/features/share_intake/domain/shared_file.dart';
import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/group_contacts.dart';

/// The most photos one channel message can hold.
const int kMaxPhotosPerChannelMessage = 4;

/// The files of each channel message, in the order they were shared. Up to four photos
/// go together. A video, voice note or document is sent alone.
List<List<SharedFile>> planChannelMessages(List<SharedFile> files) {
  final batches = <List<SharedFile>>[];
  List<SharedFile>? photos;
  for (final file in files) {
    if (sharedFileKind(file.name) == SharedFileKind.image) {
      if (photos == null || photos.length >= kMaxPhotosPerChannelMessage) {
        photos = <SharedFile>[];
        batches.add(photos);
      }
      photos.add(file);
    } else {
      photos = null;
      batches.add([file]);
    }
  }
  return batches;
}

/// A one-to-one chat the user can send files to.
class ChatDestination {
  const ChatDestination({
    required this.chatId,
    required this.otherUid,
    this.title,
    this.tourName,
    this.sharedTourId,
    this.otherEmail,
    this.lastMessageAt,
  });

  final String chatId;

  /// The other person's name, or null when no name is known. A row with no name shows a
  /// neutral label instead. It never shows the sender's own name.
  final String? title;

  final String otherUid;

  /// The group the chat belongs to, or null for a chat from before groups.
  final String? tourName;

  final String? sharedTourId;
  final String? otherEmail;
  final DateTime? lastMessageAt;
}

/// The chats the user can send files to, newest first. It applies the same rules as the
/// chats list: no chat with a blocked person, no locked chat, no chat deleted since its
/// last message, and only chats in tours the user is in. [chats] holds the chat id and
/// the chat document's data. [namesByUid] holds the names from each person's profile, the
/// same source the chats list reads. [tourNames] names each group by its id.
List<ChatDestination> chatDestinationsFor({
  required Iterable<MapEntry<String, Map<String, dynamic>>> chats,
  required String currentUid,
  required Set<String> myTourIds,
  required Set<String> blockedUids,
  required Set<String> lockedChatIds,
  Map<String, String> namesByUid = const {},
  Map<String, String> tourNames = const {},
}) {
  final out = <ChatDestination>[];
  for (final entry in chats) {
    final chatId = entry.key;
    final data = entry.value;
    if (!isInMyTours(data, myTourIds)) continue;
    final participants = List<String>.from(
        data['participants'] as Iterable? ?? const <dynamic>[]);
    final otherUid =
        participants.firstWhere((p) => p != currentUid, orElse: () => '');
    if (otherUid.isEmpty || blockedUids.contains(otherUid)) continue;
    if (lockedChatIds.contains(chatId)) continue;
    final lastMessageAt =
        ChatDeletionService.timestampOf(data['lastMessageTime']);
    if (isChatHiddenByCutoff(
      clearedAt: ChatDeletionService.clearedAtOf(data, currentUid),
      lastMessageAt: lastMessageAt,
    )) {
      continue;
    }
    final profiles = data['participantProfiles'];
    final profile = profiles is Map ? profiles[otherUid] : null;
    final storedName = profile is Map ? profile['displayName'] : null;
    final sharedTourId = data['sharedTourId'] as String?;
    out.add(ChatDestination(
      chatId: chatId,
      title: _nameOf(namesByUid[otherUid]) ?? _nameOf(storedName),
      otherUid: otherUid,
      tourName: sharedTourId == null ? null : tourNames[sharedTourId],
      sharedTourId: sharedTourId,
      otherEmail: (data['memberEmails'] as Map?)?[otherUid] as String?,
      lastMessageAt: lastMessageAt,
    ));
  }
  out.sort((a, b) {
    final at = a.lastMessageAt;
    final bt = b.lastMessageAt;
    if (at == null && bt == null) {
      return (a.title ?? '').compareTo(b.title ?? '');
    }
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  });
  return out;
}

/// A name as typed, or null when it is missing or blank.
String? _nameOf(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// A text channel the user can post files to, with the group it belongs to.
class ChannelDestination {
  const ChannelDestination({required this.group, required this.channel});

  final TourGroup group;
  final TourChannel channel;

  String get tourId => group.id;
  String get tourName => group.name;
  String get channelId => channel.id;
}

/// The text channels in [group] the user can post files to. These are the built-in
/// channels the group starts with, even before anyone has edited them, and the channels
/// admins added, in the same order the channels screen shows them. Hidden and voice
/// channels are left out, and admin-only channels are left out for everyone but admins
/// and owners.
List<ChannelDestination> channelDestinationsFor({
  required TourGroup group,
  required bool isAdmin,
  required List<TourChannel> docs,
}) {
  final channels = channelsForList(
    builtInIds: builtInChannelIdsFor(
      family: group.isFamily,
      office: group.isOffice,
      campus: group.isCampus,
      mess: group.isMess,
      society: group.isSociety,
      samity: group.isSamity,
      school: group.isSchool,
      sports: group.isSports,
      study: group.isStudy,
      committee: group.isCommittee,
      friends: group.isFriends,
    ),
    docs: docs,
  );
  return [
    for (final channel in channels)
      if (!channel.isVoice &&
          channel.kind == ChannelKind.text &&
          !channel.hidden &&
          (!channel.adminOnly || isAdmin))
        ChannelDestination(group: group, channel: channel),
  ];
}
