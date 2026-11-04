import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/utils/app_logger.dart';
import 'live_journey_session.dart';
import 'tour_group_repository.dart';

/// Writes a member's arrivals and departures to `tours/{id}/journey_events`
/// (roadmap LJ-4.2). The event carries the stop, the member and the time, and no
/// coordinates. The document id is the stop, the member and the type, so a repeat
/// write is the same document. The rules refuse that second write, and the
/// event is already recorded.
class FirestoreJourneyEventSink implements JourneyEventSink {
  FirestoreJourneyEventSink({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore,
        _auth = auth;

  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;

  @override
  Future<void> record({
    required String tourId,
    required String stopId,
    required JourneyEventType type,
  }) async {
    final firestore = _firestore ?? FirebaseFirestore.instance;
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    final email = TourGroupRepository().currentEmail;
    if (user == null || email.isEmpty) return;
    final id = '${stopId}__${email}__${type.name}';
    try {
      await firestore
          .collection('tours')
          .doc(tourId)
          .collection('journey_events')
          .doc(id)
          .set({
        'type': type.name,
        'stopId': stopId,
        'email': email,
        'uid': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error, stackTrace) {
      if (error.code == 'permission-denied') {
        logSkipped(error, stackTrace);
        return;
      }
      rethrow;
    }
  }
}
