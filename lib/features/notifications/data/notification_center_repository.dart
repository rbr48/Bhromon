import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// One entry in a member's notification list, as the server writes it.
class AppNotification {
  final String id;
  final String title;
  final String body;
  final String? action;
  final String? uid;
  final String? itemId;
  final String? tourId;
  final String? imageUrl;
  final DateTime timestamp;
  final bool read;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.action,
    required this.uid,
    required this.itemId,
    required this.tourId,
    required this.imageUrl,
    required this.timestamp,
    required this.read,
  });

  factory AppNotification.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final stamp = data['timestamp'];
    return AppNotification(
      id: doc.id,
      title: (data['title'] as String?) ?? 'Bhromon',
      body: (data['body'] as String?) ?? '',
      action: data['action'] as String?,
      uid: data['uid'] as String?,
      itemId: (data['itemId'] as String?) ?? (data['chatId'] as String?),
      tourId: data['tourId'] as String?,
      imageUrl: data['imageUrl'] as String?,
      // A write the server has not stamped yet has no time, so it reads as old.
      timestamp: stamp is Timestamp
          ? stamp.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      read: data['read'] == true,
    );
  }
}

/// Whether [n] needs the member's attention: it is not marked read, and it is
/// newer than [seenAt], the last time the member opened the list.
bool notificationIsUnread(AppNotification n, DateTime seenAt) =>
    !n.read && n.timestamp.isAfter(seenAt);

/// Reads and changes a member's notifications in `users/{uid}/notifications`.
class NotificationCenterRepository {
  NotificationCenterRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// The newest notifications the list shows. Older ones stay in Firestore.
  static const int pageSize = 100;
  static const String _boxName = 'notification_prefs';

  /// Firestore batches hold at most 500 writes.
  static const int _batchSize = 400;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _firestore.collection('users').doc(uid).collection('notifications');

  /// The newest [pageSize] notifications, kept up to date.
  Stream<List<AppNotification>> watch(String uid) {
    return _col(uid)
        .orderBy('timestamp', descending: true)
        .limit(pageSize)
        .snapshots()
        .map((s) => [for (final d in s.docs) AppNotification.fromDoc(d)]);
  }

  /// When the member last opened the list on this device. The first time, the
  /// existing history counts as seen, so only later notifications are unread.
  Future<DateTime> seenAtOrSeed(String uid) async {
    final box = await _box();
    final raw = box.get('seen_at_$uid');
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    final now = DateTime.now();
    await box.put('seen_at_$uid', now.millisecondsSinceEpoch);
    return now;
  }

  /// Records that the list was opened now, so the badge clears.
  Future<void> markSeen(String uid) async {
    final box = await _box();
    await box.put('seen_at_$uid', DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> markRead(String uid, String id) =>
      _col(uid).doc(id).update({'read': true});

  /// Marks every listed notification read, and clears the badge.
  Future<void> markAllRead(String uid, Iterable<AppNotification> items) async {
    await markSeen(uid);
    final unread = [
      for (final n in items)
        if (!n.read) n.id
    ];
    await _batchWrite(
        uid, unread, (batch, ref) => batch.update(ref, {'read': true}));
  }

  Future<void> deleteAll(String uid, Iterable<String> ids) =>
      _batchWrite(uid, ids, (batch, ref) => batch.delete(ref));

  Future<void> _batchWrite(
    String uid,
    Iterable<String> ids,
    void Function(WriteBatch batch, DocumentReference<Map<String, dynamic>> ref)
        write,
  ) async {
    final list = ids.toList();
    for (var start = 0; start < list.length; start += _batchSize) {
      final batch = _firestore.batch();
      for (final id in list.skip(start).take(_batchSize)) {
        write(batch, _col(uid).doc(id));
      }
      await batch.commit();
    }
  }

  Future<Box<dynamic>> _box() {
    if (Hive.isBoxOpen(_boxName)) {
      return Future.value(Hive.box<dynamic>(_boxName));
    }
    return Hive.openBox<dynamic>(_boxName);
  }
}
