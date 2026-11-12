import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/doc_future_cache.dart';
import '../../../core/utils/logger.dart';
import '../../chat/data/chat_local_cache.dart';
import '../../tour_group/data/tour_channel_repository.dart';
import '../../tour_group/data/tour_group_repository.dart';
import '../../tour_group/domain/models/date_codec.dart';
import '../../tour_group/domain/models/tour_group.dart';
import '../../tour_group/domain/services/group_contacts.dart';
import '../domain/share_plan.dart';

/// Where a share can go, for one user.
class ShareDestinations {
  const ShareDestinations({
    required this.chats,
    required this.channels,
    this.incomplete = false,
  });

  final List<ChatDestination> chats;
  final List<ChannelDestination> channels;

  /// True when a group's channels or members could not be read, so some groups are not
  /// listed. The sheet says so and offers to read them again.
  final bool incomplete;
}

/// Reads the chats and channels the user can send files to. The reads are one-shot, so
/// the sheet keeps no listeners open.
///
/// The load fails when the groups or the chats cannot be read: a partial list would look
/// complete, and the sheet offers a retry instead. A group whose channels cannot be read is
/// left out, and [ShareDestinations.incomplete] says so. A blocked person is never offered
/// as a destination.
class ShareDestinationsLoader {
  ShareDestinationsLoader({
    TourGroupRepository? groups,
    FirebaseFirestore? firestore,
  })  : _groups = groups ?? TourGroupRepository(),
        _firestore = firestore ?? FirebaseFirestore.instance;

  final TourGroupRepository _groups;
  final FirebaseFirestore _firestore;

  static const Duration _readTimeout = Duration(seconds: 8);

  Future<ShareDestinations> load({required String currentUid}) async {
    final groups = await _groups.watchMyGroups().first.timeout(_readTimeout);
    final myTourIds = {for (final group in groups) group.id};
    final tourNames = {for (final group in groups) group.id: group.name};

    final blocked = await _blockedUids(currentUid);
    await ChatLocalCache().init();
    final locked = ChatLocalCache().getLockedChatIds();
    final snapshot = await _firestore
        .collection('chats')
        .where('participants', arrayContains: currentUid)
        .get()
        .timeout(_readTimeout);
    final entries = [
      for (final doc in snapshot.docs) MapEntry(doc.id, doc.data()),
    ];
    final otherUids = <String>{
      for (final entry in entries)
        if (isInMyTours(entry.value, myTourIds))
          _otherUidOf(entry.value, currentUid),
    }..remove('');
    final names = await _namesOf(otherUids);
    final chats = chatDestinationsFor(
      chats: entries,
      currentUid: currentUid,
      myTourIds: myTourIds,
      blockedUids: blocked,
      lockedChatIds: locked,
      namesByUid: names,
      tourNames: tourNames,
    );

    final me = normalizeEmail(_groups.currentEmail);
    final channelRepository =
        TourChannelRepository(groups: _groups, firestore: _firestore);
    final results = await Future.wait([
      for (final group in groups) _channelsOf(channelRepository, group, me),
    ]);
    final channels = <ChannelDestination>[];
    var incomplete = false;
    for (final result in results) {
      if (result == null) {
        incomplete = true;
      } else {
        channels.addAll(result);
      }
    }
    return ShareDestinations(
      chats: chats,
      channels: channels,
      incomplete: incomplete,
    );
  }

  /// The channels of one group, or null when they or the members could not be read.
  Future<List<ChannelDestination>?> _channelsOf(
    TourChannelRepository channelRepository,
    TourGroup group,
    String me,
  ) async {
    try {
      final docs = await channelRepository
          .watchChannels(group.id)
          .first
          .timeout(_readTimeout);
      final members =
          await _groups.watchMembers(group.id).first.timeout(_readTimeout);
      final isAdmin = members
          .any((m) => normalizeEmail(m.email) == me && m.role.isAdminOrOwner);
      return channelDestinationsFor(group: group, isAdmin: isAdmin, docs: docs);
    } catch (e, st) {
      // One group whose channels cannot be read should not hide the others.
      logWarning(
          '[ShareIntake] could not read the channels of ${group.id}', e, st);
      return null;
    }
  }

  /// The other person in a one-to-one chat, or an empty string when there is none.
  String _otherUidOf(Map<String, dynamic> data, String currentUid) {
    final participants = List<String>.from(
        data['participants'] as Iterable? ?? const <dynamic>[]);
    return participants.firstWhere((p) => p != currentUid, orElse: () => '');
  }

  /// The names in each person's profile, which the chats list shows too. A name that
  /// cannot be read is left out, and its row shows the neutral label.
  Future<Map<String, String>> _namesOf(Set<String> uids) async {
    final names = <String, String>{};
    await Future.wait([
      for (final uid in uids)
        _nameOf(uid).then((name) {
          if (name != null) names[uid] = name;
        }),
    ]);
    return names;
  }

  Future<String?> _nameOf(String uid) async {
    try {
      final snapshot = await DocFutureCache.instance
          .get(_firestore.collection('explorer_profiles').doc(uid))
          .timeout(_readTimeout);
      final name = snapshot.data()?['displayName'];
      return name is String && name.trim().isNotEmpty ? name.trim() : null;
    } catch (e, st) {
      logWarning(
          '[ShareIntake] could not read the name of a chat member', e, st);
      return null;
    }
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
