import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/logger.dart';
import '../../chat/data/chat_local_cache.dart';
import '../../tour_group/data/tour_channel_repository.dart';
import '../../tour_group/data/tour_group_repository.dart';
import '../../tour_group/domain/models/date_codec.dart';
import '../../tour_group/domain/models/tour_group.dart';
import '../domain/share_plan.dart';

/// Where a share can go, for one user.
class ShareDestinations {
  const ShareDestinations({required this.chats, required this.channels});

  final List<ChatDestination> chats;
  final List<ChannelDestination> channels;
}

/// Reads the chats and channels the user can send files to. The reads are one-shot, so
/// the sheet keeps no listeners open. A failure to read the chats or the blocked list
/// fails the whole load, because a blocked person must not be offered as a destination.
class ShareDestinationsLoader {
  ShareDestinationsLoader({
    TourGroupRepository? groups,
    FirebaseFirestore? firestore,
  })  : _groups = groups ?? TourGroupRepository(),
        _firestore = firestore ?? FirebaseFirestore.instance;

  final TourGroupRepository _groups;
  final FirebaseFirestore _firestore;

  static const Duration _readTimeout = Duration(seconds: 8);

  Future<ShareDestinations> load({
    required String currentUid,
    required String fallbackName,
  }) async {
    final groups = await _groups
        .watchMyGroups()
        .first
        .timeout(_readTimeout, onTimeout: () => const <TourGroup>[]);
    final myTourIds = {for (final group in groups) group.id};

    final blocked = await _blockedUids(currentUid);
    await ChatLocalCache().init();
    final locked = ChatLocalCache().getLockedChatIds();
    final snapshot = await _firestore
        .collection('chats')
        .where('participants', arrayContains: currentUid)
        .get()
        .timeout(_readTimeout);
    final chats = chatDestinationsFor(
      chats: [for (final doc in snapshot.docs) MapEntry(doc.id, doc.data())],
      currentUid: currentUid,
      myTourIds: myTourIds,
      blockedUids: blocked,
      lockedChatIds: locked,
      fallbackName: fallbackName,
    );

    final channels = <ChannelDestination>[];
    final channelRepository =
        TourChannelRepository(groups: _groups, firestore: _firestore);
    final me = normalizeEmail(_groups.currentEmail);
    for (final group in groups) {
      try {
        final tourChannels = await channelRepository
            .watchChannels(group.id)
            .first
            .timeout(_readTimeout);
        final members =
            await _groups.watchMembers(group.id).first.timeout(_readTimeout);
        final isAdmin = members
            .any((m) => normalizeEmail(m.email) == me && m.role.isAdminOrOwner);
        channels.addAll(channelDestinationsFor(
          tourId: group.id,
          tourName: group.name,
          isAdmin: isAdmin,
          channels: tourChannels,
        ));
      } catch (e, st) {
        // One tour whose channels cannot be read should not hide the others.
        logWarning(
            '[ShareIntake] could not read the channels of ${group.id}', e, st);
      }
    }
    return ShareDestinations(chats: chats, channels: channels);
  }

  Future<Set<String>> _blockedUids(String uid) async {
    final snapshot = await _firestore
        .collection('explorer_profiles')
        .doc(uid)
        .collection('blocked_users')
        .get()
        .timeout(_readTimeout);
    return {for (final doc in snapshot.docs) doc.id};
  }
}
