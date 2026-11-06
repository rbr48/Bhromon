import 'package:bhromon/features/chat/data/chat_deletion_service.dart';
import 'package:bhromon/features/chat/domain/chat_deletion.dart';
import 'package:bhromon/features/share_intake/domain/shared_file.dart';
import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
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
    required this.title,
    required this.otherUid,
    this.sharedTourId,
    this.otherEmail,
    this.lastMessageAt,
  });

  final String chatId;

  /// The other person's name as the chat stores it.
  final String title;
  final String otherUid;
  final String? sharedTourId;
  final String? otherEmail;
  final DateTime? lastMessageAt;
}

/// The chats the user can send files to, newest first. It applies the same rules as the
/// chats list: no chat with a blocked person, no locked chat, no chat deleted since its
/// last message, and only chats in tours the user is in. [chats] holds the chat id and
/// the chat document's data.
List<ChatDestination> chatDestinationsFor({
  required Iterable<MapEntry<String, Map<String, dynamic>>> chats,
  required String currentUid,
  required Set<String> myTourIds,
  required Set<String> blockedUids,
  required Set<String> lockedChatIds,
  required String fallbackName,
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
    final title = storedName is String && storedName.trim().isNotEmpty
        ? storedName
        : fallbackName;
    out.add(ChatDestination(
      chatId: chatId,
      title: title,
      otherUid: otherUid,
      sharedTourId: data['sharedTourId'] as String?,
      otherEmail: (data['memberEmails'] as Map?)?[otherUid] as String?,
      lastMessageAt: lastMessageAt,
    ));
  }
  out.sort((a, b) {
    final at = a.lastMessageAt;
    final bt = b.lastMessageAt;
    if (at == null && bt == null) return a.title.compareTo(b.title);
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  });
  return out;
}

/// A text channel the user can post files to.
class ChannelDestination {
  const ChannelDestination({
    required this.tourId,
    required this.channelId,
    required this.channelName,
    required this.tourName,
  });

  final String tourId;
  final String channelId;
  final String channelName;
  final String tourName;
}

/// The channels in one tour the user can post files to: text channels that are not
/// hidden, and admin-only channels only for admins and owners.
List<ChannelDestination> channelDestinationsFor({
  required String tourId,
  required String tourName,
  required bool isAdmin,
  required List<TourChannel> channels,
}) {
  return [
    for (final channel in channels)
      if (channel.kind == ChannelKind.text &&
          !channel.hidden &&
          (!channel.adminOnly || isAdmin))
        ChannelDestination(
          tourId: tourId,
          channelId: channel.id,
          channelName: channel.name,
          tourName: tourName,
        ),
  ];
}
