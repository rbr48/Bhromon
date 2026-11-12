import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// One entry in a member's notification list, as the server or the app writes it.
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
      read: readFlagMeansRead(data['read']),
    );
  }
}

/// Whether a stored read flag says the entry has been read. Only an explicit `false` means
/// unread. Entries written before the flag existed have none, and they read as read.
bool readFlagMeansRead(Object? flag) => flag != false;

/// Whether [n] needs the member's attention: it is not marked read, and it is newer than
/// [seenAt], the last time the member opened the list. The bell counts these.
bool notificationIsUnread(AppNotification n, DateTime seenAt) =>
    !n.read && n.timestamp.isAfter(seenAt);

/// How many of [items] the bell counts as new, since the list was last opened.
int unseenCount(Iterable<AppNotification> items, DateTime seenAt) =>
    items.where((n) => notificationIsUnread(n, seenAt)).length;

/// The ids of the entries that are still unread, in list order.
List<String> unreadIds(Iterable<AppNotification> items) => [
      for (final n in items)
        if (!n.read) n.id
    ];

/// The ids of the entries that have been read, in list order.
List<String> readIds(Iterable<AppNotification> items) => [
      for (final n in items)
        if (n.read) n.id
    ];

/// Reads and changes a member's notifications in `users/{uid}/notifications`.
class NotificationCenterRepository {
  NotificationCenterRepository({FirebaseFirestore? firestore})
      : _injected = firestore;

  /// The newest notifications the list shows. Older ones stay in Firestore.
  static const int pageSize = 100;
  static const String _boxName = 'notification_prefs';

  /// Firestore batches hold at most 500 writes.
  static const int _batchSize = 400;

  /// Resolved on first use, so that building the repository never needs Firebase.
  final FirebaseFirestore? _injected;
  FirebaseFirestore get _firestore => _injected ?? FirebaseFirestore.instance;

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

  /// When the member last opened the list on this device. Before the first time, every
  /// unread entry counts as new.
  Future<DateTime> seenAt(String uid) async {
    final box = await _box();
    final raw = box.get('seen_at_$uid');
    return raw is int
        ? DateTime.fromMillisecondsSinceEpoch(raw)
        : DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Records that the list was opened now, so the bell's count clears.
  Future<void> markSeen(String uid) async {
    final box = await _box();
    await box.put('seen_at_$uid', DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> markRead(String uid, String id) =>
      _col(uid).doc(id).update({'read': true});

  Future<void> markUnread(String uid, String id) =>
      _col(uid).doc(id).update({'read': false});

  /// Marks every listed notification read, and clears the bell's count.
  Future<void> markAllRead(String uid, Iterable<AppNotification> items) async {
    await markSeen(uid);
    await _batchWrite(uid, unreadIds(items),
        (batch, ref) => batch.update(ref, {'read': true}));
  }

  /// Removes the read notifications from the list. The unread ones stay.
  Future<void> clearRead(String uid, Iterable<AppNotification> items) =>
      _batchWrite(uid, readIds(items), (batch, ref) => batch.delete(ref));

  Future<void> deleteMany(String uid, Iterable<String> ids) =>
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
