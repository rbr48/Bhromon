import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../../core/utils/app_logger.dart';
import '../domain/official_reel.dart';

/// Reads the official feed, and keeps this device subscribed to its new-post pushes.
class OfficialFeedRepository {
  OfficialFeedRepository({FirebaseFirestore? firestore})
      : _firestore = firestore;

  /// The topic the server pushes new official posts to.
  static const String topic = 'official_instafeed';

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  /// The newest official posts, newest first. A post whose video is not an official file
  /// is left out.
  Stream<List<OfficialReel>> watchReels({int limit = 50}) {
    return _db
        .collection('official_instafeed')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => [
              for (final doc in snapshot.docs)
                if (OfficialReel.fromMap(doc.id, doc.data()) case final reel?)
                  reel,
            ]);
  }

  /// Subscribes this device to new-post pushes, or unsubscribes it. Mobile only: the web
  /// has no push topics here, so this does nothing there. A failure is logged.
  Future<void> setFollowing(bool follow) async {
    if (kIsWeb) return;
    try {
      final messaging = FirebaseMessaging.instance;
      if (follow) {
        await messaging.subscribeToTopic(topic);
      } else {
        await messaging.unsubscribeFromTopic(topic);
      }
    } catch (error, stackTrace) {
      logWarning('[OfficialFeed] Could not change the push subscription', error,
          stackTrace);
    }
  }
}
