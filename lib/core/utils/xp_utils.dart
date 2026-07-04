import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class XpUtils {
  /// Awards standard XP amount to the explorer by writing a trust event.
  /// The Cloud Function then aggregates these events and updates the explorer's score.
  static Future<void> awardXp(String uid, int amount) async {
    if (uid.isEmpty || uid == 'explorer_user') return;

    try {
      final firestore = FirebaseFirestore.instance;

      // Map amount to standard event types for breakdown visualization
      String type = 'custom_xp_adjustment';
      if (amount == 25) {
        type = 'trip_published';
      } else if (amount == 10) {
        type = 'endorsement';
      } else if (amount == -5) {
        type = 'spam_flag'; // Or safety_flag depending on context
      } else if (amount == 5) {
        type = 'helpful_vote'; // appeal submission or validation
      }

      final docId =
          'event_${DateTime.now().millisecondsSinceEpoch}_${uid.hashCode.remainder(1000)}';
      await firestore.collection('trust_events').doc(docId).set({
        'type': type,
        'targetUid': uid,
        'actorId': uid,
        'timestamp': FieldValue.serverTimestamp(),
        'weight': amount,
      });

      debugPrint(
          '[XpUtils] Successfully enqueued trust event for $uid: $type ($amount XP)');

      // Recalculate score immediately via the Callable Cloud Function
      try {
        final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
            .httpsCallable('computeExplorerScore');
        await callable.call<dynamic>();
        debugPrint(
            '[XpUtils] Recalculated explorer score successfully via Cloud Function');
      } catch (e) {
        debugPrint(
            '[XpUtils] Failed to invoke computeExplorerScore Callable function: $e');
      }
    } catch (e) {
      debugPrint('[XpUtils] Error awarding XP: $e');
    }
  }

  /// Sets the XP score directly. Kept for backwards compatibility if needed,
  /// but writes an event to adjust the score to the target value.
  static Future<void> setXp(String uid, int newValue) async {
    if (uid.isEmpty || uid == 'explorer_user') return;

    try {
      final firestore = FirebaseFirestore.instance;

      // Fetch the current score first
      final scoreDoc =
          await firestore.collection('explorer_scores').doc(uid).get();
      int currentScore = 0;
      if (scoreDoc.exists && scoreDoc.data() != null) {
        currentScore = scoreDoc.data()!['score'] as int? ?? 0;
      }

      final difference = newValue - currentScore;
      if (difference == 0) return;

      await awardXp(uid, difference);
      debugPrint(
          '[XpUtils] Set XP by adjusting difference of $difference for $uid');
    } catch (e) {
      debugPrint('[XpUtils] Error setting XP: $e');
    }
  }
}
