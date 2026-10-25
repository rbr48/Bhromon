import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../domain/models/channel_models.dart';
import '../domain/models/date_codec.dart';
import '../domain/services/media_rules.dart';
import 'tour_group_repository.dart';
import 'tour_media_uploader.dart';

/// Firestore batches hold at most 500 writes; stay well under that.
const int _batchLimit = 400;

/// Channels, their messages, reactions, votes, pins, typing signals and the
/// live itinerary stop. Every write is checked by the security rules.
class TourChannelRepository {
  final TourGroupRepository _groups;
  final FirebaseFirestore _firestore;
  final Uuid _uuid = const Uuid();

  TourChannelRepository({
    required TourGroupRepository groups,
    FirebaseFirestore? firestore,
  })  : _groups = groups,
        _firestore = firestore ?? groups.firestore;

  String get currentEmail => _groups.currentEmail;

  String get currentDisplayName => _groups.currentDisplayName;

  CollectionReference<Map<String, dynamic>> _channels(String tourId) =>
      _firestore.collection('tours').doc(tourId).collection('channels');

  CollectionReference<Map<String, dynamic>> _messages(
          String tourId, String channelId) =>
      _channels(tourId).doc(channelId).collection('messages');

  DocumentReference<Map<String, dynamic>> _message(
          String tourId, String channelId, String messageId) =>
      _messages(tourId, channelId).doc(messageId);

  DocumentReference<Map<String, dynamic>> _liveDoc(String tourId) => _firestore
      .collection('tours')
      .doc(tourId)
      .collection('meta')
      .doc('itinerary');

  // ---------------------------------------------------------------------------
  // Channels
  // ---------------------------------------------------------------------------

  Stream<List<TourChannel>> watchChannels(String tourId) {
    return _channels(tourId).snapshots().map(
        (s) => s.docs.map((d) => TourChannel.fromMap(d.id, d.data())).toList());
  }

  /// Adds a channel and returns its id. Admins only.
  Future<String> createChannel(
    String tourId, {
    required String name,
    required String topic,
    required bool adminOnly,
  }) async {
    final email = _groups.requireEmail();
    final id = _uuid.v4().substring(0, 8);
    await _channels(tourId).doc(id).set({
      ...TourChannel(
        id: id,
        name: name.trim(),
        topic: topic.trim(),
        adminOnly: adminOnly,
        createdByEmail: email,
      ).toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  /// Saves a channel's topic and posting rule. Admins only. A built-in channel
  /// keeps its (empty) name, so its title still comes from the translations.
  Future<void> updateChannel(
    String tourId, {
    required String channelId,
    required String name,
    required String topic,
    required bool adminOnly,
  }) async {
    _groups.requireEmail();
    await _channels(tourId).doc(channelId).set({
      'name': name.trim(),
      'topic': topic.trim(),
      'adminOnly': adminOnly,
    }, SetOptions(merge: true));
  }

  /// Deletes a channel with its messages and their photos and videos. Admins
  /// only. The uploads are removed on a best-effort basis.
  Future<void> deleteChannel(String tourId, String channelId) async {
    _groups.requireEmail();
    final snapshot = await _messages(tourId, channelId).get();
    for (var i = 0; i < snapshot.docs.length; i += _batchLimit) {
      final batch = _firestore.batch();
      for (final doc in snapshot.docs.skip(i).take(_batchLimit)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    for (final doc in snapshot.docs) {
      final attachments = doc.data()['attachments'];
      if (attachments is! List) continue;
      for (final raw in attachments) {
        if (raw is Map && raw['url'] is String) {
          await _deleteUpload(raw['url'] as String);
        }
      }
    }
    await _channels(tourId).doc(channelId).delete();
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  /// The newest [limit] messages, newest first.
  Stream<List<ChannelMessage>> watchMessages(
    String tourId,
    String channelId, {
    int limit = 100,
  }) {
    return _messages(tourId, channelId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map(_toMessages);
  }

  /// The single newest message. Used to show an unread dot on a channel.
  Stream<List<ChannelMessage>> watchLatestMessage(
      String tourId, String channelId) {
    return _messages(tourId, channelId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map(_toMessages);
  }

  /// Recent messages that mention [email]. Not ordered, since only the count
  /// of unread ones is used.
  Stream<List<ChannelMessage>> watchMentionsOf(
    String tourId,
    String channelId,
    String email,
  ) {
    return _messages(tourId, channelId)
        .where('mentions', arrayContains: normalizeEmail(email))
        .limit(50)
        .snapshots()
        .map(_toMessages);
  }

  /// Pinned messages, newest first.
  Stream<List<ChannelMessage>> watchPinned(String tourId, String channelId) {
    return _messages(tourId, channelId)
        .where('isPinned', isEqualTo: true)
        .limit(kChannelMaxPins)
        .snapshots()
        .map((s) =>
            _toMessages(s)..sort((a, b) => b.timestamp.compareTo(a.timestamp)));
  }

  List<ChannelMessage> _toMessages(QuerySnapshot<Map<String, dynamic>> s) {
    return s.docs.map((d) => ChannelMessage.fromMap(d.id, d.data())).toList();
  }

  /// Posts a text message, optionally with photos or a video, a reply and
  /// mentions. The text is trimmed; a message needs text or an attachment.
  Future<void> sendMessage(
    String tourId,
    String channelId, {
    required String text,
    List<ChannelAttachment> attachments = const [],
    ChannelReply? replyTo,
    List<String> mentions = const [],
  }) async {
    final email = _groups.requireEmail();
    final trimmed = _checkedText(text, hasAttachments: attachments.isNotEmpty);
    _checkedAttachments(attachments);
    final id = _uuid.v4();
    await _message(tourId, channelId, id).set({
      'id': id,
      'kind': ChannelMessageKind.text.name,
      'text': trimmed,
      'senderEmail': email,
      'senderName': currentDisplayName,
      'timestamp': FieldValue.serverTimestamp(),
      'attachments': [for (final a in attachments) a.toMap()],
      'mentions': mentions.map(normalizeEmail).toList(),
      'isPinned': false,
      if (replyTo != null) 'replyTo': replyTo.toMap(),
    });
  }

  /// Changes the text of your own message, and the mentions it now holds.
  Future<void> editMessage(
    String tourId,
    String channelId,
    String messageId,
    String text, {
    required List<String> mentions,
  }) async {
    _groups.requireEmail();
    final trimmed = _checkedText(text, hasAttachments: false);
    await _message(tourId, channelId, messageId).update({
      'text': trimmed,
      'mentions': mentions.map(normalizeEmail).toList(),
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes a message and its uploads. Allowed for its author and admins.
  Future<void> deleteMessage(
    String tourId,
    String channelId,
    ChannelMessage message,
  ) async {
    _groups.requireEmail();
    await _message(tourId, channelId, message.id).delete();
    for (final a in message.attachments) {
      await _deleteUpload(a.url);
    }
  }

  /// Posts a poll with [options]. Members vote once; a new vote replaces the old.
  Future<void> sendPoll(
    String tourId,
    String channelId, {
    required String question,
    required List<String> options,
  }) async {
    final email = _groups.requireEmail();
    final trimmed = _checkedText(question, hasAttachments: false);
    if (options.length < 2 || options.length > kChannelMaxPollOptions) {
      throw const TourAccessException('ভোটের বিকল্প ২ থেকে ৬টি হতে হবে।');
    }
    final id = _uuid.v4();
    await _message(tourId, channelId, id).set({
      'id': id,
      'kind': ChannelMessageKind.poll.name,
      'text': trimmed,
      'pollOptions': options,
      'votes': <String, int>{},
      'senderEmail': email,
      'senderName': currentDisplayName,
      'timestamp': FieldValue.serverTimestamp(),
      'attachments': <Map<String, dynamic>>[],
      'mentions': <String>[],
      'isPinned': false,
    });
  }

  /// Records an expense for the whole tour and posts a card for it in the
  /// channel. The payer is the sender.
  Future<void> sendExpense(
    String tourId,
    String channelId, {
    required String title,
    required int amountPaisa,
    required String category,
  }) async {
    final email = _groups.requireEmail();
    final expenseId = await _groups.addExpense(
      tourId: tourId,
      title: title,
      amountPaisa: amountPaisa,
      paidById: email,
      paidByName: currentDisplayName,
      category: category,
    );
    final id = _uuid.v4();
    await _message(tourId, channelId, id).set({
      'id': id,
      'kind': ChannelMessageKind.expense.name,
      'text': title,
      'expenseId': expenseId,
      'expenseTitle': title,
      'expenseAmountPaisa': amountPaisa,
      'senderEmail': email,
      'senderName': currentDisplayName,
      'timestamp': FieldValue.serverTimestamp(),
      'attachments': <Map<String, dynamic>>[],
      'mentions': <String>[],
      'isPinned': false,
    });
  }

  // ---------------------------------------------------------------------------
  // Reactions, votes and pins
  // ---------------------------------------------------------------------------

  /// Sets your reaction to [emoji], or clears it if it is already yours. Only
  /// your own entry changes, which the rules check.
  Future<void> toggleReaction(
    String tourId,
    String channelId,
    String messageId,
    String emoji,
  ) async {
    final email = _groups.requireEmail();
    final ref = _message(tourId, channelId, messageId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final reactions = readStringMap(snap.data()?['reactions']);
      if (reactions[email] == emoji) {
        reactions.remove(email);
      } else {
        reactions[email] = emoji;
      }
      tx.update(ref, {'reactions': reactions});
    });
  }

  /// Votes for poll option [option], or withdraws the vote if it is already
  /// yours.
  Future<void> vote(
    String tourId,
    String channelId,
    String messageId,
    int option,
  ) async {
    final email = _groups.requireEmail();
    final ref = _message(tourId, channelId, messageId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final votes = readIntMap(snap.data()?['votes']);
      if (votes[email] == option) {
        votes.remove(email);
      } else {
        votes[email] = option;
      }
      tx.update(ref, {'votes': votes});
    });
  }

  /// Pins or unpins a message. Admins only, up to [kChannelMaxPins] pins.
  Future<void> setPinned(
    String tourId,
    String channelId,
    String messageId,
    bool pinned,
  ) async {
    final email = _groups.requireEmail();
    if (pinned) {
      final count = await _messages(tourId, channelId)
          .where('isPinned', isEqualTo: true)
          .count()
          .get();
      if ((count.count ?? 0) >= kChannelMaxPins) {
        throw const TourAccessException(
            'একটি চ্যানেলে সর্বোচ্চ ৫০টি বার্তা পিন করা যায়।');
      }
    }
    await _message(tourId, channelId, messageId).update({
      'isPinned': pinned,
      'pinnedByEmail': pinned ? email : '',
    });
  }

  // ---------------------------------------------------------------------------
  // Typing
  // ---------------------------------------------------------------------------

  /// Shows or clears your typing signal in a channel. Signed-out callers are
  /// ignored.
  Future<void> setTyping(
    String tourId,
    String channelId, {
    required bool typing,
  }) async {
    final email = currentEmail;
    if (email.isEmpty) return;
    final ref =
        _channels(tourId).doc(channelId).collection('typing').doc(email);
    try {
      if (typing) {
        await ref.set({
          'name': currentDisplayName,
          'at': FieldValue.serverTimestamp(),
        });
      } else {
        await ref.delete();
      }
    } catch (e) {
      // A missed typing signal is harmless.
      debugPrint('[TourChannelRepository] typing signal not sent: $e');
    }
  }

  /// Everyone whose typing signal has been written in this channel. Stale
  /// entries are filtered by the caller.
  Stream<List<TypingMember>> watchTyping(String tourId, String channelId) {
    return _channels(tourId)
        .doc(channelId)
        .collection('typing')
        .snapshots()
        .map((s) => s.docs
            .map((d) => TypingMember(
                  email: normalizeEmail(d.id),
                  name: d.data()['name'] as String? ?? 'Member',
                  at: readDate(d.data()['at']) ?? DateTime.now(),
                ))
            .toList());
  }

  // ---------------------------------------------------------------------------
  // Live itinerary stop
  // ---------------------------------------------------------------------------

  /// The route stop the group is at now, or null when none is set.
  Stream<String?> watchLiveStop(String tourId) {
    return _liveDoc(tourId)
        .snapshots()
        .map((s) => s.data()?['currentStopId'] as String?);
  }

  /// Sets or clears the stop the group is at. Admins only.
  Future<void> setLiveStop(String tourId, String? stopId) async {
    final email = _groups.requireEmail();
    await _liveDoc(tourId).set({
      'currentStopId': stopId,
      'updatedByEmail': email,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ---------------------------------------------------------------------------
  // Attachments
  // ---------------------------------------------------------------------------

  /// Starts uploading a photo or video for a message. Throws if the file type
  /// is not one the storage accepts.
  Future<TourMediaUpload> startAttachment(
    String tourId,
    XFile file, {
    required bool isVideo,
  }) {
    final email = _groups.requireEmail();
    final name = file.name;
    final contentType =
        isVideo ? videoContentType(name) : imageContentType(name);
    if (contentType == null) {
      throw TourUploadException(isVideo
          ? 'এই ধরনের ভিডিও পাঠানো যাবে না।'
          : 'এই ধরনের ছবি পাঠানো যাবে না।');
    }
    return TourMediaUploader.start(
      tourId: tourId,
      folder: 'channels',
      file: file,
      contentType: contentType,
      extension: storedExtension(name, isVideo ? 'mp4' : 'jpg'),
      maxBytes: isVideo ? kMaxVideoBytes : kMaxImageBytes,
      uploaderEmail: email,
    );
  }

  Future<void> _deleteUpload(String url) async {
    try {
      await TourMediaUploader.deleteMedia(url);
    } catch (e) {
      debugPrint('[TourChannelRepository] could not delete $url: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Checks
  // ---------------------------------------------------------------------------

  String _checkedText(String text, {required bool hasAttachments}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty && !hasAttachments) {
      throw const TourAccessException('বার্তা খালি রাখা যাবে না।');
    }
    if (trimmed.length > kChannelMessageMaxLength) {
      throw const TourAccessException('বার্তা ১০০০ অক্ষরের বেশি হতে পারবে না।');
    }
    return trimmed;
  }

  void _checkedAttachments(List<ChannelAttachment> attachments) {
    final images = attachments.where((a) => !a.isVideo).length;
    final videos = attachments.length - images;
    if (images > kChannelMaxImages || (videos > 0 && attachments.length > 1)) {
      throw const TourAccessException(
          'একটি বার্তায় সর্বোচ্চ ৪টি ছবি, অথবा একটি ভিডিও পাঠানো যায়।');
    }
  }
}
