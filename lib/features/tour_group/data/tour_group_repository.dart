import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/utils/app_logger.dart';
import '../domain/models/date_codec.dart';
import '../domain/models/expense_models.dart';
import '../domain/models/itinerary_models.dart';
import '../domain/models/logistics_models.dart';
import '../domain/models/safety_alert_models.dart';
import '../domain/models/tour_activity_models.dart';
import '../domain/models/tour_group.dart';
import '../domain/models/tour_post_models.dart';
import '../domain/models/vehicle_models.dart';
import '../domain/services/invite_code.dart';
import '../domain/services/seat_layout_engine.dart';
import '../domain/services/seat_planner.dart';
import 'channel_read_store.dart';
import 'tour_hub_preference.dart';
import 'tour_media_journal.dart';
import 'tour_media_uploader.dart';
import 'vps_notification_service.dart';

/// Thrown when an action needs a signed-in member. The message is shown to users.
class TourAccessException implements Exception {
  final String message;
  const TourAccessException(this.message);

  @override
  String toString() => message;
}

/// How long a write may wait for the server before the UI is told it is still
/// syncing. Firestore keeps the write queued, so this never loses data.
const Duration _serverAckTimeout = Duration(seconds: 8);

/// Firestore delete/update batches hold at most 500 operations.
const int _batchLimit = 400;

class TourGroupRepository {
  final FirebaseFirestore? _firestoreInstance;
  final FirebaseAuth? _authInstance;
  final Uuid _uuid = const Uuid();

  TourGroupRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestoreInstance = firestore,
        _authInstance = auth;

  FirebaseFirestore get _firestore =>
      _firestoreInstance ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _authInstance ?? FirebaseAuth.instance;

  // ---------------------------------------------------------------------------
  // Identity
  // ---------------------------------------------------------------------------

  bool get isSignedIn {
    try {
      return _auth.currentUser != null;
    } catch (_) {
      return currentEmail.isNotEmpty;
    }
  }

  /// Empty when signed out. There is no shared guest identity any more.
  String get currentUid {
    try {
      return _auth.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  String get currentEmail {
    try {
      final email = _auth.currentUser?.email;
      if (email != null && email.trim().isNotEmpty) {
        return normalizeEmail(email);
      }
      final uid = _auth.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        return '$uid@bhromon.app';
      }
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
    return '';
  }

  String get currentDisplayName {
    // Prefer in-app profile from the encrypted Hive cache (set by
    // AuthRepositoryImpl), then Firebase Auth (which is kept in sync by
    // AuthRepositoryImpl._syncFirebaseAuthProfile).
    final cached = _cachedExplorerProfile();
    if (cached != null && cached['displayName'] is String) {
      final name = (cached['displayName'] as String).trim();
      if (name.isNotEmpty) return name;
    }
    try {
      final name = _auth.currentUser?.displayName;
      if (name != null && name.trim().isNotEmpty) return name.trim();
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
    return 'Explorer';
  }

  String? get currentPhotoUrl {
    final cached = _cachedExplorerProfile();
    if (cached != null && cached['avatarUrl'] is String) {
      final url = cached['avatarUrl'] as String;
      if (url.isNotEmpty) return url;
    }
    try {
      return _auth.currentUser?.photoURL;
    } catch (_) {
      return null;
    }
  }

  /// Reads the locally-cached explorer profile map from the encrypted Hive
  /// `auth_box`, which [AuthRepositoryImpl] populates on every sign-in and
  /// profile update. Returns `null` when the box is not open or empty.
  static Map<String, dynamic>? _cachedExplorerProfile() {
    try {
      if (!Hive.isBoxOpen('auth_box')) return null;
      final raw = Hive.box<dynamic>('auth_box').get('profile');
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
    return null;
  }

  String _requireEmail() {
    if (!isSignedIn || currentEmail.isEmpty) {
      throw const TourAccessException(
          'ট্যুর গ্রুপ ব্যবহার করতে আগে সাইন-ইন করুন।');
    }
    return currentEmail;
  }

  /// The signed-in member's email. Throws if nobody is signed in.
  String requireEmail() => _requireEmail();

  /// The database, shared with the repositories that work beside this one.
  FirebaseFirestore get firestore => _firestore;

  // ---------------------------------------------------------------------------
  // Collections
  // ---------------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> get _tours =>
      _firestore.collection('tours');

  CollectionReference<Map<String, dynamic>> get _memberships =>
      _firestore.collection('memberships');

  CollectionReference<Map<String, dynamic>> get _invites =>
      _firestore.collection('invites');

  DocumentReference<Map<String, dynamic>> _tour(String tourId) =>
      _tours.doc(tourId);

  CollectionReference<Map<String, dynamic>> _sub(String tourId, String name) =>
      _tours.doc(tourId).collection(name);

  String _membershipId(String tourId, String email) => '${tourId}__$email';

  // ---------------------------------------------------------------------------
  // Offline cache (Hive). Used only to show something before the network
  // answers. Membership is the source of truth for which tours are listed.
  // ---------------------------------------------------------------------------

  Future<Box<dynamic>> _openBox() async {
    try {
      if (Hive.isBoxOpen('tour_groups_box')) {
        return Hive.box<dynamic>('tour_groups_box');
      }
      return await Hive.openBox<dynamic>('tour_groups_box');
    } catch (e, st) {
      logWarning(
          '[TourGroupRepository] Corrupt Hive box: $e. Purging and recovering...',
          e,
          st);
      try {
        await Hive.deleteBoxFromDisk('tour_groups_box');
        return await Hive.openBox<dynamic>('tour_groups_box');
      } catch (inner, ist) {
        logError('[TourGroupRepository] Hive recovery failed', inner, ist);
        rethrow;
      }
    }
  }

  static dynamic _deepSanitizeForHive(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    } else if (value is DateTime) {
      return value.toIso8601String();
    } else if (value is Map) {
      return value
          .map((k, v) => MapEntry(k.toString(), _deepSanitizeForHive(v)));
    } else if (value is List) {
      return value.map((v) => _deepSanitizeForHive(v)).toList();
    }
    return value;
  }

  Future<void> _cacheLocalGroup(TourGroup group) async {
    try {
      final box = await _openBox();
      await box.put('tour_${group.id}', _deepSanitizeForHive(group.toMap()));
      final List<String> myIds = List<String>.from(
          box.get('my_tour_ids', defaultValue: <String>[]) as List);
      if (!myIds.contains(group.id)) {
        myIds.add(group.id);
        await box.put('my_tour_ids', myIds);
      }
    } catch (e, st) {
      logWarning('[TourGroupRepository] Error caching local group', e, st);
    }
  }

  Future<void> _removeLocalGroup(String tourId) async {
    try {
      final box = await _openBox();
      await box.delete('tour_$tourId');
      final List<String> myIds = List<String>.from(
          box.get('my_tour_ids', defaultValue: <String>[]) as List);
      myIds.remove(tourId);
      await box.put('my_tour_ids', myIds);
    } catch (e, st) {
      logWarning('[TourGroupRepository] Error clearing local group', e, st);
    }
  }

  /// Removes what this device keeps about [tourId] once the user has left it or
  /// was removed from it: the cached tour, the feed bookmarks and post draft,
  /// the channel read and mute state, pending media journal entries, and the
  /// hub's remembered pick. Other tours are not touched. Each step is
  /// best-effort, so one failure does not stop the rest.
  Future<void> clearLocalTourData(String tourId) async {
    await _removeLocalGroup(tourId);
    try {
      final box = await _openBox();
      await box.delete(_feedPrefsKey(tourId));
      await box.delete(_postDraftKey(tourId));
    } catch (e, st) {
      logWarning('[TourGroupRepository] Could not clear tour prefs', e, st);
    }
    await ChannelReadStore().clearTour(tourId);
    await TourMediaJournal.instance.dropTour(tourId);
    await TourHubPreference().forget(tourId);
    try {
      // Photos and videos the tour loaded sit in the image cache, which cannot
      // tell one tour's files from another's, so the whole cache is emptied.
      await emptyImageCache();
    } catch (e, st) {
      logWarning(
          '[TourGroupRepository] Could not empty the image cache', e, st);
    }
  }

  /// Empties the image cache on mobile. Web keeps tour images out of it, and
  /// tests override this so they need no platform plugins.
  Future<void> emptyImageCache() async {
    if (kIsWeb) return;
    await DefaultCacheManager().emptyCache();
  }

  Future<List<TourGroup>> getLocalGroups() async {
    try {
      final box = await _openBox();
      final List<String> myIds = List<String>.from(
          box.get('my_tour_ids', defaultValue: <String>[]) as List);
      final groups = <TourGroup>[];
      for (final id in myIds) {
        final data = box.get('tour_$id');
        if (data is Map) {
          groups.add(TourGroup.fromMap(id, Map<String, dynamic>.from(data)));
        }
      }
      return groups;
    } catch (_) {
      return [];
    }
  }

  /// Waits for a write to reach the server. If the network is down, returns
  /// false and leaves the write queued; a rejected write is re-thrown.
  Future<bool> _awaitServer(Future<void> write) async {
    try {
      await write.timeout(_serverAckTimeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Feed preferences (bookmarks and seen stories), kept on this device only
  // ---------------------------------------------------------------------------

  String _feedPrefsKey(String tourId) =>
      'feed_prefs_${currentUid.isEmpty ? 'anon' : currentUid}_$tourId';

  Future<FeedPrefs> loadFeedPrefs(String tourId) async {
    try {
      final box = await _openBox();
      final raw = box.get(_feedPrefsKey(tourId));
      if (raw is Map) {
        final rawCollections = raw['collections'] as Map?;
        final collections = <String, List<String>>{};
        if (rawCollections != null) {
          rawCollections.forEach((k, v) {
            if (v is List) {
              collections[k.toString()] = v.map((e) => e.toString()).toList();
            }
          });
        }
        return FeedPrefs(
          bookmarks: Set<String>.from((raw['bookmarks'] as List?) ?? const []),
          seenStories:
              Set<String>.from((raw['seenStories'] as List?) ?? const []),
          collections: collections,
        );
      }
    } catch (e, st) {
      logWarning('[TourGroupRepository] Could not read feed prefs', e, st);
    }
    return const FeedPrefs();
  }

  Future<void> saveFeedPrefs(String tourId, FeedPrefs prefs) async {
    try {
      final box = await _openBox();
      await box.put(_feedPrefsKey(tourId), {
        'bookmarks': prefs.bookmarks.toList(),
        // Keep only the most recent 500 so the box does not grow forever.
        'seenStories': prefs.seenStories.toList().reversed.take(500).toList(),
        'collections': prefs.collections,
      });
    } catch (e, st) {
      logWarning('[TourGroupRepository] Could not save feed prefs', e, st);
    }
  }

  String _postDraftKey(String tourId) =>
      'post_draft_${currentUid.isEmpty ? 'anon' : currentUid}_$tourId';

  Future<TourPostDraft?> loadPostDraft(String tourId) async {
    try {
      final box = await _openBox();
      final raw = box.get(_postDraftKey(tourId));
      if (raw is Map) {
        return TourPostDraft.fromMap(Map<String, dynamic>.from(raw));
      }
    } catch (e, st) {
      logWarning('[TourGroupRepository] Could not read post draft', e, st);
    }
    return null;
  }

  Future<void> savePostDraft(String tourId, TourPostDraft draft) async {
    try {
      final box = await _openBox();
      await box.put(_postDraftKey(tourId), draft.toMap());
    } catch (e, st) {
      logWarning('[TourGroupRepository] Could not save post draft', e, st);
    }
  }

  Future<void> clearPostDraft(String tourId) async {
    try {
      final box = await _openBox();
      await box.delete(_postDraftKey(tourId));
    } catch (e, st) {
      logWarning('[TourGroupRepository] Could not clear post draft', e, st);
    }
  }

  // ---------------------------------------------------------------------------
  // Groups
  // ---------------------------------------------------------------------------

  /// Tours the signed-in user is an active member of, live.
  ///
  /// Membership decides the list. Cached tours show only until the first
  /// membership answer arrives, so tours the user left or was removed from
  /// stop appearing.
  Stream<List<TourGroup>> watchMyGroups() {
    late StreamController<List<TourGroup>> controller;
    StreamSubscription<User?>? authSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? membershipSub;
    final tourSubs =
        <String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};
    final tours = <String, TourGroup>{};
    var listedIds = <String>{};
    var heardFromServer = false;
    // Role each membership row says we have, by tour id.
    final rolesByTour = <String, String>{};
    String? boundUserId;

    void emit() {
      if (controller.isClosed) return;
      final groups = tours.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      controller.add(groups);
    }

    void stopTour(String tourId) {
      tourSubs.remove(tourId)?.cancel();
      tours.remove(tourId);
    }

    void startTour(String tourId, String email) {
      // Eager one-off fetch for fast Web and desktop startup
      _tour(tourId).get().then((doc) {
        try {
          final data = doc.data();
          if (doc.exists && data != null && !controller.isClosed) {
            final group = TourGroup.fromMap(doc.id, data);
            tours[tourId] = group;
            _cacheLocalGroup(group);
            emit();
          }
        } catch (e, st) {
          logWarning(
              '[TourGroupRepository] eager get tour $tourId failed', e, st);
        }
      }).catchError((Object e, StackTrace st) {
        logWarning('[TourGroupRepository] eager get tour $tourId error', e, st);
      });

      tourSubs[tourId] = _tour(tourId).snapshots().listen(
        (doc) {
          try {
            final data = doc.data();
            if (doc.exists && data != null) {
              final group = TourGroup.fromMap(doc.id, data);
              tours[tourId] = group;
              _cacheLocalGroup(group);
              // Owner rows written before role 'owner' was saved as 'admin'.
              // The owner's own app repairs them here.
              if (group.ownerEmail == email &&
                  rolesByTour[tourId] != TourRole.owner.toValue()) {
                _memberships
                    .doc(_membershipId(tourId, email))
                    .update({'role': TourRole.owner.toValue()}).catchError(
                        (Object e, StackTrace st) => logWarning(
                            '[TourGroupRepository] owner role repair failed',
                            e,
                            st));
                rolesByTour[tourId] = TourRole.owner.toValue();
              }
            } else {
              tours.remove(tourId);
              // Only the server can say the tour is gone. A cache miss while
              // offline is not that, so the local copy stays.
              if (!doc.metadata.isFromCache) {
                unawaited(clearLocalTourData(tourId));
              }
            }
            emit();
          } catch (e, st) {
            logWarning(
                '[TourGroupRepository] parse tour $tourId failed', e, st);
          }
        },
        onError: (Object e) {
          // Losing access to a tour means the user is no longer a member.
          logWarning('[TourGroupRepository] tour $tourId unavailable', e);
          stopTour(tourId);
          listedIds.remove(tourId);
          unawaited(clearLocalTourData(tourId));
          emit();
        },
      );
    }

    void clearUserTours() {
      membershipSub?.cancel();
      membershipSub = null;
      for (final sub in tourSubs.values) {
        sub.cancel();
      }
      tourSubs.clear();
      tours.clear();
      listedIds.clear();
      rolesByTour.clear();
      heardFromServer = false;
      boundUserId = null;
    }

    void bindUser(User? user) {
      if (user == null) {
        clearUserTours();
        emit();
        return;
      }
      if (boundUserId == user.uid) {
        // Already bound to this user, do not clear tours.
        return;
      }
      clearUserTours();
      boundUserId = user.uid;

      final rawEmail = user.email;
      final email = (rawEmail != null && rawEmail.trim().isNotEmpty)
          ? normalizeEmail(rawEmail)
          : (user.uid.isNotEmpty ? '${user.uid}@bhromon.app' : '');
      if (email.isEmpty) {
        emit();
        return;
      }

      getLocalGroups().then((local) {
        if (!heardFromServer && !controller.isClosed) {
          controller.add(local);
        }
      });

      membershipSub =
          _memberships.where('email', isEqualTo: email).snapshots().listen(
        (snapshot) {
          heardFromServer = true;
          rolesByTour.clear();
          final myName = currentDisplayName;
          final myPhoto = currentPhotoUrl;
          final myUid = currentUid;
          for (final d in snapshot.docs) {
            final data = d.data();
            final id = data['tourId'] as String? ?? '';
            // A row an admin added has no uid, and chats and calls need one. The member
            // writes their own, which the rules allow and nothing else on the row.
            if ((data['uid'] as String? ?? '').isEmpty && myUid.isNotEmpty) {
              d.reference.update({'uid': myUid}).catchError((Object _) {});
            }
            final rawStatus = (data['status'] as String?)?.toLowerCase();
            final isActive = rawStatus == null || rawStatus == 'active';
            if (isActive && id.isNotEmpty) {
              rolesByTour[id] = data['role'] as String? ?? 'member';
            }
            // Proactively self-heal membership row with latest in-app profile.
            final updates = <String, dynamic>{};
            if (myUid.isNotEmpty &&
                (data['uid'] == null || (data['uid'] as String).isEmpty)) {
              updates['uid'] = myUid;
            }
            if (myName != 'Explorer' && data['displayName'] != myName) {
              updates['displayName'] = myName;
            }
            if (myPhoto != null && data['photoUrl'] != myPhoto) {
              updates['photoUrl'] = myPhoto;
            }
            if (updates.isNotEmpty) {
              unawaited(d.reference.update(updates).catchError((_) {}));
            }
          }
          final ids = rolesByTour.keys.toSet();
          for (final id in listedIds.difference(ids)) {
            stopTour(id);
            // A cache-only answer may be incomplete, so only the server's
            // answer clears the device.
            if (!snapshot.metadata.isFromCache) {
              unawaited(clearLocalTourData(id));
            }
          }
          for (final id in ids.difference(listedIds)) {
            startTour(id, email);
          }
          listedIds = ids;
          // If there are no tours for this user, emit empty list.
          // If there are tour IDs, wait for startTour / eager fetch to populate
          // tours before emitting, or emit if tours already populated.
          if (ids.isEmpty || tours.isNotEmpty) {
            emit();
          }
        },
        onError: (Object e) {
          logWarning('[TourGroupRepository] memberships error', e);
          if (!controller.isClosed) controller.addError(e);
        },
      );
    }

    controller = StreamController<List<TourGroup>>.broadcast(
      onListen: () {
        try {
          if (_auth.currentUser != null) {
            bindUser(_auth.currentUser);
          }
          authSub = _auth.authStateChanges().listen((user) {
            bindUser(user);
          });
        } catch (_) {
          // If Firebase is uninitialized (e.g. In unit tests)
          if (currentEmail.isNotEmpty) {
            emit();
          }
        }
      },
      onCancel: () async {
        await authSub?.cancel();
        clearUserTours();
      },
    );

    return controller.stream;
  }

  /// Live view of one tour. Null when the tour no longer exists.
  Stream<TourGroup?> watchGroup(String tourId) {
    return _tour(tourId).snapshots().map((doc) {
      final data = doc.data();
      if (!doc.exists || data == null) return null;
      return TourGroup.fromMap(doc.id, data);
    });
  }

  /// One-off read of a tour, falling back to the cache when offline.
  /// Whether the signed-in user is an active member of [tourId], as the server
  /// last answered. Answers from the local cache are skipped, so a device that
  /// is offline never treats a tour as gone. Emits nothing until the server
  /// answers, and errors (not signed in, no Firebase) reach the listener.
  Stream<bool> watchIsMember(String tourId) async* {
    final membership = _memberships.doc(_membershipId(tourId, _requireEmail()));
    await for (final row in membership.snapshots()) {
      if (row.metadata.isFromCache) continue;
      final status = (row.data()?['status'] as String?)?.toLowerCase();
      yield row.exists && (status == null || status == 'active');
    }
  }

  Future<TourGroup?> getGroup(String tourId) async {
    try {
      final doc = await _tour(tourId).get();
      final data = doc.data();
      if (doc.exists && data != null) {
        final group = TourGroup.fromMap(doc.id, data);
        await _cacheLocalGroup(group);
        return group;
      }
      return null;
    } catch (e, st) {
      logWarning('[TourGroupRepository] getGroup($tourId) error', e, st);
      final local = await getLocalGroups();
      return local.where((g) => g.id == tourId).firstOrNull;
    }
  }

  /// Creates a tour, makes the creator its owner, and issues an invite code.
  /// Returns as soon as the server accepts the writes, or as soon as they are
  /// queued offline. A rejected write throws and leaves no local copy behind.
  Future<TourGroup> createGroup({
    required String name,
    required String description,
    required String destination,
    String originCity = 'ঢাকা',
    TourType tourType = TourType.beach,
    required DateTime startDate,
    required DateTime endDate,
    TourModules modules = const TourModules(),
    List<String> customSpots = const [],
    String? meetingPointTitle,
    String? meetingPointNote,
    String? meetingPointMapUrl,
    GroupKind kind = GroupKind.tour,
  }) async {
    final email = _requireEmail();
    final uid = currentUid;
    final tourId = _uuid.v4().replaceAll('-', '').substring(0, 20);
    final inviteCode = generateInviteCode();
    final now = DateTime.now();

    final group = TourGroup(
      id: tourId,
      name: name,
      description: description,
      destination: destination,
      originCity: originCity,
      tourType: tourType,
      ownerEmail: email,
      ownerUid: uid,
      inviteCode: inviteCode,
      startDate: startDate,
      endDate: endDate,
      modules: modules,
      customSpots: customSpots,
      meetingPointTitle: meetingPointTitle,
      meetingPointNote: meetingPointNote,
      meetingPointMapUrl: meetingPointMapUrl,
      createdAt: now,
      kind: kind,
    );

    final tourData = group.toMap()
      ..addAll({
        if (meetingPointTitle != null) 'meetingPointTitle': meetingPointTitle,
        if (meetingPointNote != null) 'meetingPointNote': meetingPointNote,
        if (meetingPointMapUrl != null)
          'meetingPointMapUrl': meetingPointMapUrl,
      });

    // The rules check that the tour exists before they accept the owner's
    // membership and invite, so the owner rows are written after the tour.
    final tourWrite = _tour(tourId).set(tourData);
    final ownerWrite = tourWrite.then((_) {
      final batch = _firestore.batch();
      batch.set(
        _memberships.doc(_membershipId(tourId, email)),
        TourMember(
          tourId: tourId,
          tourName: name,
          email: email,
          displayName: currentDisplayName,
          photoUrl: currentPhotoUrl,
          role: TourRole.owner,
          status: TourMemberStatus.active,
          joinedAt: now,
          uid: currentUid,
        ).toMap(),
      );
      batch.set(_invites.doc(inviteCode), {
        'tourId': tourId,
        'code': inviteCode,
        'createdAt': writeDate(now),
      });
      return batch.commit();
    });
    // A rejected write, whenever it happens, drops the local copy.
    unawaited(ownerWrite.catchError((Object e) => _discardGroup(tourId, e)));

    await _cacheLocalGroup(group);
    try {
      await _awaitServer(tourWrite);
      await _awaitServer(ownerWrite);
    } catch (e) {
      await _discardGroup(tourId, e);
      rethrow;
    }
    return group;
  }

  Future<void> _discardGroup(String tourId, Object error) async {
    logWarning('[TourGroupRepository] Group $tourId rejected', error);
    await _removeLocalGroup(tourId);
  }

  /// Joins a tour with its invite code. Joining is always as a plain member.
  /// Someone who is already a member keeps their role.
  Future<TourGroup> joinGroupWithCode(String inviteCode) async {
    final email = _requireEmail();
    final code = inviteCode.trim().toUpperCase();
    if (!isValidInviteCode(code)) {
      throw const FormatException(
          'সঠিক আমন্ত্রণ কোড দিন (৮ অক্ষরের কোড, যেমন: 7KQ2M9XB)।');
    }

    String? tourId;
    try {
      final invite = await _invites.doc(code).get();
      if (invite.exists) {
        tourId = invite.data()?['tourId'] as String?;
      }
    } catch (e, st) {
      logWarning('[TourGroupRepository] invite lookup error', e, st);
    }

    // Fallback: check if the input code itself is directly a tourId
    if (tourId == null || tourId.isEmpty) {
      try {
        final directDoc = await _tour(code).get();
        if (directDoc.exists) {
          tourId = code;
        }
      } catch (error, stackTrace) {
        logSkipped(error, stackTrace);
      }
    }

    if (tourId == null || tourId.isEmpty) {
      throw const FormatException(
          'এই আমন্ত্রণ কোডে কোনো ট্যুর গ্রুপ পাওয়া যায়নি।');
    }

    final membershipRef = _memberships.doc(_membershipId(tourId, email));
    // Already a member: keep the existing role and just open the tour.
    final existing = await _readOwnRow(membershipRef);
    if (existing == null) {
      final member = TourMember(
        tourId: tourId,
        email: email,
        displayName: currentDisplayName,
        photoUrl: currentPhotoUrl,
        role: TourRole.member,
        status: TourMemberStatus.active,
        joinedAt: DateTime.now(),
        uid: currentUid,
      ).toMap()
        ..['joinCode'] = code;
      try {
        final synced = await _awaitServer(membershipRef.set(member));
        if (!synced) {
          throw const TourAccessException(
              'ইন্টারনেট সংযোগ নেই। সংযোগ ফিরে এলে আবার চেষ্টা করুন।');
        }
      } on FirebaseException catch (e, st) {
        logWarning('[TourGroupRepository] join membership set failed', e, st);
        throw const TourAccessException(
            'এই ট্যুরে যোগ দেওয়ার অনুমতি নেই। কোড ঠিক আছে কি না দেখুন, অথবা অ্যাডমিনের সাথে যোগাযোগ করুন।');
      }
    } else {
      // If already a member but inactive, reactivate membership so security rules permit reading
      final status = existing.data()?['status'] as String?;
      if (status != 'active') {
        try {
          await membershipRef.update({'status': 'active'});
        } catch (e, st) {
          logWarning(
              '[TourGroupRepository] membership reactivation failed', e, st);
        }
      }
    }

    // Try reading the group with retries in case Firestore rules propagation has a slight delay
    TourGroup? group;
    for (var attempt = 0; attempt < 3; attempt++) {
      group = await getGroup(tourId);
      if (group != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }

    if (group == null) {
      throw const TourAccessException('ট্যুরটি এখন আর পাওয়া যাচ্ছে না।');
    }
    await _cacheLocalGroup(group);

    // Eagerly prefetch and cache the group's members and key subcollections
    // into Firestore cache so all tabs load with 0ms delay.
    unawaited(Future.wait<Object?>([
      _memberships.where('tourId', isEqualTo: group.id).get(),
      _sub(group.id, 'vehicles').get(),
      _sub(group.id, 'notices').get(),
    ]).then<void>((_) {}).catchError((Object _) {}));

    return group;
  }

  /// Directly adds a new member by email address (for owners and admins).
  Future<void> addMemberByEmail({
    required String tourId,
    required String email,
    String? displayName,
  }) async {
    _requireEmail();
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw const FormatException('সঠিক ইমেইল ঠিকানা দিন।');
    }

    final tourDoc = await _tour(tourId).get();
    if (!tourDoc.exists) {
      throw StateError('ট্যুরটি খুঁজে পাওয়া যায়নি।');
    }
    final tourName = tourDoc.data()?['name'] as String? ?? 'Tour';

    final membershipRef = _memberships.doc(_membershipId(tourId, cleanEmail));
    try {
      final existing = await membershipRef.get();
      if (existing.exists && existing.data()?['status'] == 'active') {
        throw StateError('$cleanEmail ইতিমধ্যে এই গ্রুপের সদস্য।');
      }
    } on StateError {
      rethrow;
    } on FirebaseException catch (e) {
      // Row doesn't exist yet; proceed safely with creation.
      logDebug(
          '[TourGroupRepository] Member row does not exist yet: ${e.code}');
    }

    final member = TourMember(
      tourId: tourId,
      email: cleanEmail,
      displayName: displayName?.trim().isNotEmpty == true
          ? displayName!.trim()
          : cleanEmail.split('@').first,
      photoUrl: null,
      role: TourRole.member,
      status: TourMemberStatus.active,
      tourName: tourName,
      joinedAt: DateTime.now(),
    ).toMap();

    try {
      final synced = await _awaitServer(
          membershipRef.set(member, SetOptions(merge: true)));
      if (!synced) {
        throw const TourAccessException(
            'ইন্টারনেট সংযোগ নেই। সংযোগ ফিরে এলে আবার চেষ্টা করুন।');
      }
    } on FirebaseException catch (e) {
      throw TourAccessException(
          'সদস্য যোগ করার অনুমতি নেই: ${e.message ?? e.code}');
    }
  }

  /// Reads the caller's own membership row. Returns null when there is none.
  Future<DocumentSnapshot<Map<String, dynamic>>?> _readOwnRow(
      DocumentReference<Map<String, dynamic>> ref) async {
    try {
      final snap = await ref.get();
      return snap.exists ? snap : null;
    } on FirebaseException {
      // Rules deny reading a row that does not exist yet.
      return null;
    }
  }

  /// Updates settings the admin can change. Null arguments are left as they are.
  Future<void> updateGroupSettings({
    required String tourId,
    String? name,
    String? description,
    String? destination,
    String? originCity,
    TourType? tourType,
    DateTime? startDate,
    DateTime? endDate,
    TourModules? modules,
    List<String>? customSpots,
  }) async {
    _requireEmail();
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    if (destination != null) updates['destination'] = destination;
    if (originCity != null) updates['originCity'] = originCity;
    if (tourType != null) updates['tourType'] = tourType.toValue();
    if (startDate != null) updates['startDate'] = writeDate(startDate);
    if (endDate != null) updates['endDate'] = writeDate(endDate);
    if (modules != null) updates['modules'] = modules.toMap();
    if (customSpots != null) updates['customSpots'] = customSpots;
    if (updates.isEmpty) return;
    await _tour(tourId).update(updates);
  }

  /// Admins save the itinerary. The summary fields older screens read are
  /// kept in step: the destination becomes "A → B → C", the tour type is
  /// beach when any stop is (so beach items and tide tools show), and the
  /// tour's dates widen to cover every stop.
  Future<void> saveItinerary(
    String tourId, {
    required List<TourStop> stops,
    required bool returnHome,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    _requireEmail();
    final ordered = [...stops]..sort((a, b) => a.arrive.compareTo(b.arrive));
    final updates = <String, dynamic>{
      'stops': [for (final s in ordered) s.toMap()],
      'returnHome': returnHome,
    };
    if (ordered.isNotEmpty) {
      updates['destination'] = ordered.map((s) => s.name).join(' → ');
      updates['tourType'] = (ordered.any((s) => s.kind == TourType.beach)
              ? TourType.beach
              : ordered.first.kind)
          .toValue();
      var start = startDate, end = endDate;
      for (final s in ordered) {
        if (s.arrive.isBefore(start)) start = s.arrive;
        if (s.leave.isAfter(end)) end = s.leave;
      }
      updates['startDate'] = writeDate(start);
      updates['endDate'] = writeDate(end);
    }
    await _tour(tourId).update(updates);
  }

  /// Admins save one leg's plan or progress. The key has a '>' in it, so it
  /// is written with a field path rather than a dotted string.
  Future<void> saveLegPlan(String tourId, String legKey, LegPlan plan) async {
    _requireEmail();
    await _tour(tourId).update({
      FieldPath(['legPlans', legKey]): plan.toMap(),
    });
  }

  /// Saves the meeting point. Empty values remove the field rather than
  /// storing an empty string.
  Future<void> updateMeetingPoint(
    String tourId, {
    String? title,
    String? note,
    String? mapUrl,
  }) async {
    _requireEmail();
    await _tour(tourId).update({
      'meetingPointTitle': _orDelete(title),
      'meetingPointNote': _orDelete(note),
      'meetingPointMapUrl': _orDelete(mapUrl),
      // The notice board used to store a nested map; drop it once replaced.
      'meetingPoint': FieldValue.delete(),
    });
  }

  static Object _orDelete(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? FieldValue.delete() : trimmed;
  }

  /// Adds a custom spot. arrayUnion keeps spots added by others at the same time.
  Future<void> addCustomSpot(String tourId, String spot) async {
    _requireEmail();
    final trimmed = spot.trim();
    if (trimmed.isEmpty) return;
    await _tour(tourId).update({
      'customSpots': FieldValue.arrayUnion([trimmed]),
    });
  }

  /// Issues a new invite code and retires the old one.
  Future<String> rotateInviteCode(String tourId, String oldCode) async {
    _requireEmail();
    final newCode = generateInviteCode();
    final batch = _firestore.batch();
    batch.update(_tour(tourId), {'inviteCode': newCode});
    batch.set(_invites.doc(newCode), {
      'tourId': tourId,
      'code': newCode,
      'createdAt': writeDate(DateTime.now()),
    });
    if (oldCode.isNotEmpty) batch.delete(_invites.doc(oldCode));
    await batch.commit();
    return newCode;
  }

  // ---------------------------------------------------------------------------
  // Members & roles
  // ---------------------------------------------------------------------------

  /// The signed-in person's role on [tourId], or null when they are not a member.
  Future<TourRole?> myRole(String tourId) async {
    final email = currentEmail;
    if (email.isEmpty) return null;
    try {
      final row = await _memberships.doc(_membershipId(tourId, email)).get();
      final data = row.data();
      if (!row.exists || data == null) return null;
      return TourRole.fromString(data['role'] as String?);
    } on FirebaseException {
      return null;
    }
  }

  /// Active members of a tour, owner first, then by join date.
  Stream<List<TourMember>> watchMembers(String tourId) {
    return _memberships
        .where('tourId', isEqualTo: tourId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) {
      final myEmail = currentEmail;
      final myUid = currentUid;
      if (myEmail.isNotEmpty && myUid.isNotEmpty) {
        for (final d in snapshot.docs) {
          final data = d.data();
          if (normalizeEmail(data['email'] as String? ?? '') == myEmail) {
            final updates = <String, dynamic>{};
            // Back-fill uid if missing.
            if (data['uid'] == null || (data['uid'] as String).isEmpty) {
              updates['uid'] = myUid;
            }
            // Self-heal displayName / photoUrl from in-app profile so that
            // other members always see the latest name and avatar.
            final myName = currentDisplayName;
            final myPhoto = currentPhotoUrl;
            if (data['displayName'] != myName && myName != 'Explorer') {
              updates['displayName'] = myName;
            }
            if (data['photoUrl'] != myPhoto && myPhoto != null) {
              updates['photoUrl'] = myPhoto;
            }
            if (updates.isNotEmpty) {
              unawaited(d.reference.update(updates).catchError((_) {}));
            }
            break;
          }
        }
      }
      final members =
          snapshot.docs.map((d) => TourMember.fromMap(d.data())).toList();
      members.sort((a, b) {
        final byRole = _roleRank(a.role).compareTo(_roleRank(b.role));
        return byRole != 0 ? byRole : a.joinedAt.compareTo(b.joinedAt);
      });
      return members;
    });
  }

  static int _roleRank(TourRole role) => switch (role) {
        TourRole.owner => 0,
        TourRole.admin => 1,
        TourRole.member => 2,
      };

  /// Owner promotes a member to admin, or demotes an admin to member.
  Future<void> updateMemberRole(
      String tourId, String email, TourRole newRole) async {
    _requireEmail();
    if (newRole == TourRole.owner) {
      throw const TourAccessException(
          'মালিকানা হস্তান্তর করতে "মালিকানা হস্তান্তর" ব্যবহার করুন।');
    }
    await _memberships
        .doc(_membershipId(tourId, normalizeEmail(email)))
        .update({'role': newRole.toValue()});
  }

  /// Sets how many people the signed-in member's family counts as (1 to 20).
  /// Expenses are shared by this weight.
  Future<void> setMyFamilyCount(String tourId, int count) async {
    final email = _requireEmail();
    await _memberships
        .doc(_membershipId(tourId, email))
        .update({'familyCount': count.clamp(1, 20)});
  }

  /// Removes a member and bans the email, so the invite code cannot be used
  /// to come back. Only a bans document plus the membership row are written.
  Future<void> removeMember(String tourId, String email) async {
    final actor = _requireEmail();
    final target = normalizeEmail(email);
    if (target == actor) {
      throw const TourAccessException(
          'নিজেকে সরাতে "ট্যুর ছেড়ে যান" ব্যবহার করুন।');
    }
    final batch = _firestore.batch();
    batch.set(_tour(tourId).collection('bans').doc(target), {
      'email': target,
      'removedBy': actor,
      'removedAt': writeDate(DateTime.now()),
    });
    batch.delete(_memberships.doc(_membershipId(tourId, target)));
    await batch.commit();
  }

  /// Current owner hands the tour to another active member. Their membership
  /// role becomes owner and the owner becomes admin, in one batch.
  Future<void> transferOwnership(String tourId, String newOwnerEmail) async {
    final actor = _requireEmail();
    final target = normalizeEmail(newOwnerEmail);
    if (target == actor) {
      throw const TourAccessException('আপনি ইতিমধ্যে এই ট্যুরের মালিক।');
    }
    final targetRow =
        await _memberships.doc(_membershipId(tourId, target)).get();
    if (!targetRow.exists || targetRow.data()?['status'] != 'active') {
      throw const TourAccessException(
          'মালিকানা শুধু এই ট্যুরের সক্রিয় সদস্যকে দেওয়া যাবে।');
    }

    final batch = _firestore.batch();
    batch.update(_tour(tourId), {'ownerEmail': target});
    batch.update(_memberships.doc(_membershipId(tourId, target)),
        {'role': TourRole.owner.toValue()});
    batch.update(_memberships.doc(_membershipId(tourId, actor)),
        {'role': TourRole.admin.toValue()});
    await batch.commit();
  }

  /// Leaves a tour. The owner must transfer ownership first.
  Future<void> leaveTour(String tourId) async {
    final email = _requireEmail();
    // The tour's owner is the source of truth; older owner rows may say 'admin'.
    final tour = await _tour(tourId).get();
    if (normalizeEmail(tour.data()?['ownerEmail'] as String? ?? '') == email) {
      throw const TourAccessException(
          'মালিক হিসেবে আগে মালিকানা অন্য সদস্যকে হস্তান্তর করুন।');
    }
    await _memberships.doc(_membershipId(tourId, email)).delete();
    await clearLocalTourData(tourId);
  }

  /// Owner deletes the tour. Other members' rows and the invite go first, the
  /// tour document after, and the owner's own row last.
  Future<void> deleteTour(String tourId, {required String inviteCode}) async {
    final actor = _requireEmail();
    final rows = await _memberships.where('tourId', isEqualTo: tourId).get();
    final others = rows.docs
        .where((d) => d.data()['role'] != TourRole.owner.toValue())
        .toList();
    for (var i = 0; i < others.length; i += _batchLimit) {
      final batch = _firestore.batch();
      for (final row in others.skip(i).take(_batchLimit)) {
        batch.delete(row.reference);
      }
      await batch.commit();
    }
    final cleanup = _firestore.batch();
    if (inviteCode.isNotEmpty) cleanup.delete(_invites.doc(inviteCode));
    await cleanup.commit();
    await _tour(tourId).delete();
    await _memberships.doc(_membershipId(tourId, actor)).delete();
    await clearLocalTourData(tourId);
  }

  // ---------------------------------------------------------------------------
  // Money
  // ---------------------------------------------------------------------------

  /// Expenses, newest first. Sorted here because older documents store dates
  /// as strings, which Firestore cannot order alongside timestamps.
  Stream<List<ExpenseItem>> watchExpenses(String tourId) {
    return _sub(tourId, 'expenses').snapshots().map((snapshot) {
      final items = snapshot.docs
          .map((d) => ExpenseItem.fromMap(d.id, d.data()))
          .toList();
      items.sort((a, b) => b.date.compareTo(a.date));
      return items;
    });
  }

  /// Adds an expense and returns its id. [participantIds] null means all
  /// current members share it.
  Future<String> addExpense({
    required String tourId,
    required String title,
    required int amountPaisa,
    String? paidById,
    String? paidByName,
    required String category,
    DateTime? date,
    String? notes,
    List<String>? participantIds,
    SplitMode splitMode = SplitMode.family,
    Map<String, int>? splitShares,
    String? stopId,
    String? currency,
    int? originalMinor,
    double? fxRate,
    String? receiptUrl,
  }) async {
    final email = _requireEmail();
    final expense = ExpenseItem(
      id: _uuid.v4(),
      tourId: tourId,
      title: title,
      amountPaisa: amountPaisa,
      paidById: paidById,
      paidByName: paidByName,
      category: category,
      date: date ?? DateTime.now(),
      notes: notes,
      addedByEmail: email,
      participantIds: participantIds,
      splitMode: splitMode,
      splitShares: splitShares,
      stopId: stopId,
      currency: currency,
      originalMinor: originalMinor,
      fxRate: fxRate,
      receiptUrl: receiptUrl,
    );
    await _sub(tourId, 'expenses').doc(expense.id).set(expense.toMap());
    return expense.id;
  }

  /// Saves an edited expense. [expense] must keep its original addedByEmail.
  Future<void> updateExpense(ExpenseItem expense) async {
    _requireEmail();
    await _sub(expense.tourId, 'expenses').doc(expense.id).set(expense.toMap());
  }

  Future<void> deleteExpense(String tourId, String expenseId) async {
    _requireEmail();
    await _sub(tourId, 'expenses').doc(expenseId).delete();
  }

  /// Deposits, newest first.
  Stream<List<DepositItem>> watchDeposits(String tourId) {
    return _sub(tourId, 'deposits').snapshots().map((snapshot) {
      final items = snapshot.docs
          .map((d) => DepositItem.fromMap(d.id, d.data()))
          .toList();
      items.sort((a, b) => b.date.compareTo(a.date));
      return items;
    });
  }

  Future<void> addDeposit({
    required String tourId,
    required String memberId,
    required String memberName,
    required int amountPaisa,
    DateTime? date,
    String? notes,
  }) async {
    final email = _requireEmail();
    final deposit = DepositItem(
      id: _uuid.v4(),
      tourId: tourId,
      memberId: memberId,
      memberName: memberName,
      amountPaisa: amountPaisa,
      date: date ?? DateTime.now(),
      notes: notes,
      addedByEmail: email,
    );
    await _sub(tourId, 'deposits').doc(deposit.id).set(deposit.toMap());
  }

  /// Saves an edited deposit. [deposit] must keep its original addedByEmail.
  Future<void> updateDeposit(DepositItem deposit) async {
    _requireEmail();
    await _sub(deposit.tourId, 'deposits').doc(deposit.id).set(deposit.toMap());
  }

  Future<void> deleteDeposit(String tourId, String depositId) async {
    _requireEmail();
    await _sub(tourId, 'deposits').doc(depositId).delete();
  }

  /// Settle-up payments, newest first.
  Stream<List<TransferItem>> watchTransfers(String tourId) {
    return _sub(tourId, 'transfers').snapshots().map((snapshot) {
      final items = snapshot.docs
          .map((d) => TransferItem.fromMap(d.id, d.data()))
          .toList();
      items.sort((a, b) => b.date.compareTo(a.date));
      return items;
    });
  }

  /// Records money handed over to settle up. A null [fromId] is the fund
  /// paying out; a null [toId] is money paid into the fund.
  Future<void> addTransfer({
    required String tourId,
    String? fromId,
    required String fromName,
    String? toId,
    required String toName,
    required int amountPaisa,
    DateTime? date,
    String? notes,
  }) async {
    final email = _requireEmail();
    final t = TransferItem(
      id: _uuid.v4(),
      tourId: tourId,
      fromId: fromId,
      fromName: fromName,
      toId: toId,
      toName: toName,
      amountPaisa: amountPaisa,
      date: date ?? DateTime.now(),
      notes: notes,
      addedByEmail: email,
    );
    await _sub(tourId, 'transfers').doc(t.id).set(t.toMap());
  }

  Future<void> deleteTransfer(String tourId, String transferId) async {
    _requireEmail();
    await _sub(tourId, 'transfers').doc(transferId).delete();
  }

  /// Admins set the budget and the per-person collection target.
  Future<void> saveFundBudget(String tourId, FundBudget budget) async {
    _requireEmail();
    await _tour(tourId).update({'fundBudget': budget.toMap()});
  }

  // ---------------------------------------------------------------------------
  // Notices & meeting point
  // ---------------------------------------------------------------------------

  Stream<List<TourNotice>> watchNotices(String tourId) {
    return _sub(tourId, 'notices')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => TourNotice.fromMap(d.id, d.data())).toList());
  }

  /// Admins post notices. The author is the signed-in admin, not free text;
  /// [notice] supplies everything else.
  Future<void> postNotice(String tourId, TourNotice notice) async {
    final email = _requireEmail();
    await _sub(tourId, 'notices').add({
      ...notice.toEditableMap(),
      'author': currentDisplayName,
      'authorEmail': email,
      'ackBy': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Saves an edited notice. The author, original time and answers stay as
  /// they were; only the edit time is added.
  Future<void> updateNotice(String tourId, TourNotice notice) async {
    _requireEmail();
    await _sub(tourId, 'notices').doc(notice.id).update({
      ...notice.toEditableMap(),
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setNoticePinned(
      String tourId, String noticeId, bool pinned) async {
    _requireEmail();
    await _sub(tourId, 'notices').doc(noticeId).update({'pinned': pinned});
  }

  /// Answers a notice for [email] ("Got it", or "I'm here" in a roll call),
  /// or takes the answer back. Members may answer only for themselves;
  /// admins may mark anyone present.
  Future<void> answerNotice(String tourId, String noticeId,
      {String? email, required bool answered}) async {
    final who = normalizeEmail(email ?? _requireEmail());
    await _sub(tourId, 'notices').doc(noticeId).update({
      'ackBy': answered
          ? FieldValue.arrayUnion([who])
          : FieldValue.arrayRemove([who]),
    });
  }

  Future<void> deleteNotice(String tourId, String noticeId) async {
    _requireEmail();
    await _sub(tourId, 'notices').doc(noticeId).delete();
  }

  // ---------------------------------------------------------------------------
  // Packing checklist
  // ---------------------------------------------------------------------------

  Stream<List<ChecklistItem>> watchChecklist(String tourId) {
    return _sub(tourId, 'checklist').snapshots().map((s) =>
        s.docs.map((d) => ChecklistItem.fromMap(d.id, d.data())).toList());
  }

  /// Ticks or unticks an item for the signed-in person only.
  Future<void> setChecklistItemPacked(
      String tourId, String itemId, bool packed) async {
    final email = _requireEmail();
    await _sub(tourId, 'checklist').doc(itemId).set({
      'checkedBy': packed
          ? FieldValue.arrayUnion([email])
          : FieldValue.arrayRemove([email]),
    }, SetOptions(merge: true));
  }

  Future<void> addChecklistItem(
      String tourId, String title, String category) async {
    _requireEmail();
    final id = 'custom_${_uuid.v4()}';
    await _sub(tourId, 'checklist').doc(id).set({
      'id': id,
      'title': title,
      'category': category,
      'checkedBy': <String>[],
    });
  }

  Future<void> deleteChecklistItem(String tourId, String itemId) async {
    _requireEmail();
    await _sub(tourId, 'checklist').doc(itemId).delete();
  }

  // ---------------------------------------------------------------------------
  // Highway roadmap checkpoints
  // ---------------------------------------------------------------------------

  Stream<List<RouteCheckpoint>> watchCheckpoints(String tourId) {
    return _sub(tourId, 'checkpoints').snapshots().map((s) {
      final items = s.docs
          .map((d) => RouteCheckpoint.fromMap(d.id, d.data()))
          .toList()
        ..sort((a, b) => a.kmFromStart.compareTo(b.kmFromStart));
      return items;
    });
  }

  Future<void> addCheckpoint({
    required String tourId,
    required String name,
    required int kmFromStart,
    String highlight = '',
    double? lat,
    double? lng,
    String? legKey,
    CheckpointKind kind = CheckpointKind.custom,
    DateTime? plannedAt,
    String notes = '',
  }) async {
    final email = _requireEmail();
    final id = _uuid.v4();
    await _sub(tourId, 'checkpoints').doc(id).set({
      'id': id,
      'name': name,
      'kmFromStart': kmFromStart,
      'highlight': highlight,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      'addedByEmail': email,
      if (legKey != null) 'legKey': legKey,
      'kind': kind.name,
      if (plannedAt != null) 'plannedAt': writeDate(plannedAt),
      'notes': notes,
    });
  }

  /// The author or an admin edits a stop. The author stays the same.
  Future<void> updateCheckpoint(String tourId, RouteCheckpoint c) async {
    _requireEmail();
    await _sub(tourId, 'checkpoints').doc(c.id).update({
      'name': c.name,
      'kmFromStart': c.kmFromStart,
      'highlight': c.highlight,
      'lat': c.lat,
      'lng': c.lng,
      'legKey': c.legKey,
      'kind': c.kind.name,
      'plannedAt': c.plannedAt == null ? null : writeDate(c.plannedAt!),
      'notes': c.notes,
    });
  }

  /// Marks a stop as passed now, or clears the mark.
  Future<void> setCheckpointVisited(
      String tourId, String checkpointId, bool visited) async {
    _requireEmail();
    await _sub(tourId, 'checkpoints').doc(checkpointId).update({
      'visitedAt': visited ? FieldValue.serverTimestamp() : null,
    });
  }

  Future<void> deleteCheckpoint(String tourId, String checkpointId) async {
    _requireEmail();
    await _sub(tourId, 'checkpoints').doc(checkpointId).delete();
  }

  // ---------------------------------------------------------------------------
  // Safety alerts (SOS)
  // ---------------------------------------------------------------------------

  /// Id for an alert about to be raised. The caller keeps it so the alert can
  /// be resolved later, even if the raise is still queued.
  String newSafetyAlertId() => _uuid.v4();

  /// Raises an alert the whole tour can see. Returns false when the network is
  /// down: the alert stays queued and reaches the others once it connects.
  Future<bool> raiseSafetyAlert({
    required String tourId,
    required String alertId,
    double? latitude,
    double? longitude,
  }) async {
    final email = _requireEmail();
    final synced = await _awaitServer(_sub(tourId, 'sos').doc(alertId).set({
      'id': alertId,
      'senderEmail': email,
      'senderName': currentDisplayName,
      'resolved': false,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'createdAt': FieldValue.serverTimestamp(),
    }));
    if (synced) {
      unawaited(VpsNotificationService().notifySos(
        tourId: tourId,
        alertId: alertId,
        senderName: currentDisplayName,
      ));
    }
    return synced;
  }

  /// Marks an alert resolved. Only the sender or an admin may do this.
  Future<bool> resolveSafetyAlert(String tourId, String alertId) async {
    final email = _requireEmail();
    return _awaitServer(_sub(tourId, 'sos').doc(alertId).update({
      'resolved': true,
      'resolvedByEmail': email,
      'resolvedAt': FieldValue.serverTimestamp(),
    }));
  }

  /// The most recent alerts, newest first. Callers pick out the open ones.
  Stream<List<SafetyAlert>> watchSafetyAlerts(String tourId, {int limit = 30}) {
    return _sub(tourId, 'sos')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => SafetyAlert.fromMap(d.id, d.data())).toList());
  }

  /// Publishes this member's battery status and coordinates.
  Future<bool> updateBatteryTelemetry({
    required String tourId,
    required int batteryLevel,
    bool isCharging = false,
    double? latitude,
    double? longitude,
  }) async {
    final email = _requireEmail();
    return _awaitServer(_sub(tourId, 'telemetry').doc(email).set({
      'email': email,
      'name': currentDisplayName,
      'batteryLevel': batteryLevel,
      'isCharging': isCharging,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)));
  }

  /// Live stream of members' battery and location telemetry.
  Stream<List<BatteryTelemetry>> watchBatteryTelemetry(String tourId) {
    return _sub(tourId, 'telemetry').snapshots().map(
        (s) => s.docs.map((d) => BatteryTelemetry.fromMap(d.data())).toList());
  }

  // ---------------------------------------------------------------------------
  // Bus seats
  // ---------------------------------------------------------------------------

  /// Every seat anyone holds: the original coach and every vehicle. The
  /// channels and the feed read this for seat badges. Vehicle seats that
  /// cannot be read yet (rules not deployed) count as none.
  Stream<List<BusSeat>> watchBusSeats(String tourId) {
    StreamSubscription<List<BusSeat>>? coach;
    StreamSubscription<List<BusSeat>>? vehicles;
    List<BusSeat>? coachSeats;
    List<BusSeat>? vehicleSeats;
    late final StreamController<List<BusSeat>> out;
    void emit() {
      if (coachSeats != null && vehicleSeats != null) {
        out.add([...coachSeats!, ...vehicleSeats!]);
      }
    }

    out = StreamController<List<BusSeat>>(
      onListen: () {
        coach = watchCoachSeats(tourId).listen((s) {
          coachSeats = s;
          emit();
        }, onError: out.addError);
        vehicles = _sub(tourId, 'vehicle_seats')
            .snapshots()
            .map((s) => s.docs.map((d) => BusSeat.fromMap(d.data())).toList())
            .listen((s) {
          vehicleSeats = s;
          emit();
        }, onError: (Object _) {
          vehicleSeats = const [];
          emit();
        });
      },
      onCancel: () async {
        await coach?.cancel();
        await vehicles?.cancel();
      },
    );
    return out.stream;
  }

  /// The tour's original coach, stored in `bus_seats`.
  Stream<List<BusSeat>> watchCoachSeats(String tourId) {
    return _sub(tourId, 'bus_seats')
        .snapshots()
        .map((s) => s.docs.map((d) => BusSeat.fromMap(d.data())).toList());
  }

  /// The seats of one vehicle, or of the original coach when [vehicleId] is
  /// null.
  Stream<List<BusSeat>> watchSeatsOf(String tourId, String? vehicleId) {
    if (vehicleId == null) return watchCoachSeats(tourId);
    return _sub(tourId, 'vehicle_seats')
        .where('vehicleId', isEqualTo: vehicleId)
        .snapshots()
        .map((s) => s.docs.map((d) => BusSeat.fromMap(d.data())).toList());
  }

  CollectionReference<Map<String, dynamic>> _seatCollection(
          String tourId, String? vehicleId) =>
      _sub(tourId, vehicleId == null ? 'bus_seats' : 'vehicle_seats');

  static String _seatDocId(String? vehicleId, String seatNumber) =>
      vehicleId == null ? seatNumber : '${vehicleId}__$seatNumber';

  /// Puts [email] in [seatNumber] on a vehicle (the original coach when
  /// [vehicleId] is null). A member may hold up to [familySize] seats on one
  /// vehicle, one for each person travelling with them; at that limit their
  /// last seat moves here. A null [email] frees the seat.
  Future<void> assignSeat(
    String tourId,
    String seatNumber, {
    String? vehicleId,
    String? email,
    String? name,
    int familySize = 1,
    bool isWindow = false,
  }) async {
    _requireEmail();
    final seats = _seatCollection(tourId, vehicleId);
    final batch = _firestore.batch();
    final target = email == null ? null : normalizeEmail(email);
    var slot = 0;

    if (target != null) {
      Query<Map<String, dynamic>> query =
          seats.where('assignedMemberEmail', isEqualTo: target);
      if (vehicleId != null) {
        query = query.where('vehicleId', isEqualTo: vehicleId);
      }
      final held = (await query.get())
          .docs
          .where((d) => d.id != _seatDocId(vehicleId, seatNumber))
          .map((d) => (d, BusSeat.fromMap(d.data())))
          .toList()
        ..sort((a, b) => a.$2.familySlot.compareTo(b.$2.familySlot));
      final used = {for (final h in held) h.$2.familySlot};
      if (held.length >= familySize.clamp(1, 20)) {
        // At the limit: the member's last seat moves here.
        final last = held.last;
        slot = last.$2.familySlot;
        batch.set(
            last.$1.reference,
            last.$2
                .copyWith(assignedMemberEmail: null, assignedMemberName: null)
                .toMap());
      } else {
        while (used.contains(slot)) {
          slot++;
        }
      }
    }

    final seat = BusSeat(
      seatNumber: seatNumber,
      assignedMemberEmail: target,
      assignedMemberName: target == null ? null : name,
      isWindow: vehicleId == null ? _isWindowSeat(seatNumber) : isWindow,
      vehicleId: vehicleId,
      familySlot: target == null ? 0 : slot,
    );
    batch.set(seats.doc(_seatDocId(vehicleId, seatNumber)), seat.toMap());
    await batch.commit();
  }

  /// Writes an auto-seating plan in one batch.
  Future<void> applySeatPlan(
    String tourId,
    String? vehicleId,
    List<SeatAssignment> plan, {
    Set<String> windowSeats = const {},
  }) async {
    _requireEmail();
    if (plan.isEmpty) return;
    final seats = _seatCollection(tourId, vehicleId);
    for (var i = 0; i < plan.length; i += 400) {
      final batch = _firestore.batch();
      for (final a in plan.skip(i).take(400)) {
        batch.set(
          seats.doc(_seatDocId(vehicleId, a.seatId)),
          BusSeat(
            seatNumber: a.seatId,
            assignedMemberEmail: normalizeEmail(a.email),
            assignedMemberName: a.name,
            isWindow: vehicleId == null
                ? _isWindowSeat(a.seatId)
                : windowSeats.contains(a.seatId),
            vehicleId: vehicleId,
            familySlot: a.familySlot,
          ).toMap(),
        );
      }
      await batch.commit();
    }
  }

  /// Frees every seat on a vehicle (the original coach when [vehicleId] is
  /// null).
  Future<void> clearSeats(String tourId, String? vehicleId) async {
    _requireEmail();
    Query<Map<String, dynamic>> query = _seatCollection(tourId, vehicleId);
    if (vehicleId != null) {
      query = query.where('vehicleId', isEqualTo: vehicleId);
    }
    final docs = (await query.get()).docs;
    for (var i = 0; i < docs.length; i += 400) {
      final batch = _firestore.batch();
      for (final d in docs.skip(i).take(400)) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }

  /// Window seats on the original coach are the outer columns: A1/A4 and so on.
  static bool _isWindowSeat(String seatNumber) =>
      legacyCoachLayout().windowSeats.contains(seatNumber);

  // ---------------------------------------------------------------------------
  // Vehicles
  // ---------------------------------------------------------------------------

  /// The tour's vehicles in the order they were added.
  Stream<List<TourVehicle>> watchVehicles(String tourId) {
    return _sub(tourId, 'vehicles').snapshots().map((s) {
      final list =
          s.docs.map((d) => TourVehicle.fromMap(d.id, d.data())).toList();
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return list;
    });
  }

  /// Admins add or edit a vehicle. A smaller seat map frees the seats that
  /// no longer exist on it.
  Future<void> saveVehicle(String tourId, TourVehicle vehicle) async {
    _requireEmail();
    final v = vehicle.normalized();
    await _sub(tourId, 'vehicles').doc(v.id).set(v.toMap());
    final seatIds = buildLayout(v).seatOrder.toSet();
    final stale = (await _sub(tourId, 'vehicle_seats')
            .where('vehicleId', isEqualTo: v.id)
            .get())
        .docs
        .where((d) => !seatIds.contains(d.data()['seatNumber']))
        .toList();
    if (stale.isEmpty) return;
    final batch = _firestore.batch();
    for (final d in stale) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  /// Admins remove a vehicle and its seats. Seats go first, while the
  /// vehicle still exists for the rules to read.
  Future<void> deleteVehicle(String tourId, String vehicleId) async {
    await clearSeats(tourId, vehicleId);
    await _sub(tourId, 'vehicles').doc(vehicleId).delete();
  }

  // ---------------------------------------------------------------------------
  // Hotel rooms
  // ---------------------------------------------------------------------------

  Stream<List<HotelRoom>> watchHotelRooms(String tourId) {
    return _sub(tourId, 'hotel_rooms').snapshots().map((s) {
      final rooms =
          s.docs.map((d) => HotelRoom.fromMap(d.id, d.data())).toList();
      rooms.sort((a, b) => a.roomNumber.compareTo(b.roomNumber));
      return rooms;
    });
  }

  /// Admins create or edit a room's details.
  Future<void> saveHotelRoom(String tourId, HotelRoom room) async {
    _requireEmail();
    await _sub(tourId, 'hotel_rooms').doc(room.id).set(room.toMap());
  }

  Future<void> deleteHotelRoom(String tourId, String roomId) async {
    _requireEmail();
    await _sub(tourId, 'hotel_rooms').doc(roomId).delete();
  }

  /// Moves a guest into a room, out of any other room in the same hotel.
  /// Throws [StateError] when the room is full.
  Future<void> assignHotelGuest(
    String tourId,
    String roomId, {
    required String email,
    required String name,
  }) async {
    _requireEmail();
    final guest = normalizeEmail(email);
    final rooms = _sub(tourId, 'hotel_rooms');
    final target = await rooms.doc(roomId).get();
    final hotel = target.data()?['hotelName'] as String? ?? '';
    // One room per hotel: a guest moves out of other rooms in the same hotel
    // and keeps their rooms in other hotels.
    final elsewhere =
        await rooms.where('assignedMemberEmails', arrayContains: guest).get();
    for (final doc in elsewhere.docs) {
      if (doc.id == roomId) continue;
      if ((doc.data()['hotelName'] as String? ?? '') != hotel) continue;
      await _removeGuestFromRoom(tourId, doc.id, guest);
    }
    await _firestore.runTransaction((tx) async {
      final ref = rooms.doc(roomId);
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('রুমটি আর পাওয়া যাচ্ছে না।');
      final room = HotelRoom.fromMap(snap.id, snap.data()!);
      tx.set(ref, room.addGuest(guest, name).toMap());
    });
  }

  /// Applies an auto-rooming plan, one guest at a time.
  Future<void> applyRoomPlan(String tourId, List<RoomAssignment> plan) async {
    for (final a in plan) {
      await assignHotelGuest(tourId, a.roomId, email: a.email, name: a.name);
    }
  }

  Future<void> removeHotelGuest(
      String tourId, String roomId, String email) async {
    _requireEmail();
    await _removeGuestFromRoom(tourId, roomId, normalizeEmail(email));
  }

  Future<void> _removeGuestFromRoom(
      String tourId, String roomId, String guest) async {
    final rooms = _sub(tourId, 'hotel_rooms');
    await _firestore.runTransaction((tx) async {
      final ref = rooms.doc(roomId);
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final room = HotelRoom.fromMap(snap.id, snap.data()!);
      tx.set(ref, room.removeGuest(guest).toMap());
    });
  }

  // ---------------------------------------------------------------------------
  // Luggage & Cargo Tracking
  // ---------------------------------------------------------------------------

  /// Streams the list of all tracked luggage and cargo items for the tour.
  Stream<List<LuggageItem>> watchLuggage(String tourId) {
    return _sub(tourId, 'luggage').snapshots().map((s) {
      final list =
          s.docs.map((d) => LuggageItem.fromMap(d.id, d.data())).toList();
      list.sort((a, b) => a.title.compareTo(b.title));
      return list;
    });
  }

  /// Adds or updates a luggage item.
  Future<void> saveLuggage(String tourId, LuggageItem item) async {
    _requireEmail();
    await _sub(tourId, 'luggage')
        .doc(item.id)
        .set(item.toMap(), SetOptions(merge: true));
  }

  /// Deletes a luggage item.
  Future<void> deleteLuggage(String tourId, String luggageId) async {
    _requireEmail();
    await _sub(tourId, 'luggage').doc(luggageId).delete();
  }

  // ---------------------------------------------------------------------------
  // Posts & InstaFeed
  // ---------------------------------------------------------------------------

  /// The newest [limit] posts. The feed raises the limit to load more.
  Stream<List<TourPostItem>> watchPosts(String tourId, {int limit = 60}) {
    return _sub(tourId, 'posts')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => TourPostItem.fromMap(d.id, d.data())).toList());
  }

  /// Posts created before [upper] (any time when null) and not before [lower]
  /// (any time when null), newest first. Live: a post added or deleted in the
  /// range shows at once.
  Stream<List<TourPostItem>> watchPostRange(
    String tourId, {
    DateTime? upper,
    DateTime? lower,
  }) {
    Query<Map<String, dynamic>> query =
        _sub(tourId, 'posts').orderBy('createdAt', descending: true);
    if (upper != null) {
      query = query.where('createdAt', isLessThan: Timestamp.fromDate(upper));
    }
    if (lower != null) {
      query = query.where('createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(lower));
    }
    return query.snapshots().map((s) =>
        s.docs.map((d) => TourPostItem.fromMap(d.id, d.data())).toList());
  }

  /// Where the next page of the feed starts: the creation time of the [limit]th
  /// newest post older than [upper]. Null when fewer than [limit] posts are, so
  /// that page is the last one.
  Future<DateTime?> feedPageBoundary(
    String tourId, {
    DateTime? upper,
    int limit = 60,
  }) async {
    Query<Map<String, dynamic>> query =
        _sub(tourId, 'posts').orderBy('createdAt', descending: true);
    if (upper != null) {
      query = query.where('createdAt', isLessThan: Timestamp.fromDate(upper));
    }
    final snap = await query.limit(limit).get();
    if (snap.docs.length < limit) return null;
    return readDate(snap.docs.last.data()['createdAt']);
  }

  /// Fetches posts by id, such as bookmarks older than the loaded feed. An id
  /// whose post was deleted is left out of the result.
  Future<List<TourPostItem>> getPostsByIds(
      String tourId, Iterable<String> ids) async {
    final unique = ids.toSet().toList();
    // Each `in` query takes at most 10 ids, a limit every Firestore version accepts.
    final snaps = await Future.wait([
      for (var i = 0; i < unique.length; i += 10)
        _sub(tourId, 'posts')
            .where(FieldPath.documentId,
                whereIn: unique.skip(i).take(10).toList())
            .get(),
    ]);
    return [
      for (final snap in snaps)
        for (final d in snap.docs) TourPostItem.fromMap(d.id, d.data()),
    ];
  }

  Stream<TourPostItem?> watchPost(String tourId, String postId) {
    return _sub(tourId, 'posts').doc(postId).snapshots().map((doc) {
      final data = doc.data();
      if (!doc.exists || data == null) return null;
      return TourPostItem.fromMap(doc.id, data);
    });
  }

  /// Publishes a post. Media must already be uploaded: a local path or blob URL
  /// would show only on the uploader's device, so it is refused here.
  Future<void> addPost({
    required String tourId,
    required String caption,
    required List<String> images,
    String? videoUrl,
    bool isReel = false,
    String location = '',
    String tourDay = 'day1',
    String filterId = 'normal',
    List<String> tags = const [],
    bool isPinned = false,
    bool hideLikeCount = false,
    bool disableComments = false,
    String? audioTitle,
    String? audioUrl,
    double? aspectRatio,
    double? expenseAmount,
    String? expenseCategory,
    String? coverUrl,
  }) async {
    final email = _requireEmail();
    final mediaUrls = [...images, if (videoUrl != null) videoUrl];
    if (mediaUrls.isEmpty) {
      throw const TourAccessException('পোস্টে অন্তত একটি ছবি বা ভিডিও দিন।');
    }
    if (!mediaUrls.every(isRemoteMediaUrl)) {
      throw const TourAccessException(
          'আপলোড এখনও শেষ হয়নি। ছবি বা ভিডিও সম্পূর্ণ আপলোড হওয়ার পর পোস্ট করুন।');
    }
    final id = _uuid.v4();
    final post = TourPostItem(
      id: id,
      tourId: tourId,
      authorEmail: email,
      authorName: currentDisplayName,
      authorPhoto: currentPhotoUrl,
      caption: caption.trim(),
      images: images,
      videoUrl: videoUrl,
      isReel: isReel,
      location: location,
      tourDay: tourDay,
      filterId: filterId,
      likes: const [],
      commentCount: 0,
      createdAt: DateTime.now(),
      tags: tags,
      isPinned: isPinned,
      hideLikeCount: hideLikeCount,
      disableComments: disableComments,
      audioTitle: audioTitle,
      audioUrl: audioUrl,
      aspectRatio: aspectRatio,
      expenseAmount: expenseAmount,
      expenseCategory: expenseCategory,
      coverUrl: coverUrl,
    );
    final map = post.toMap()..['createdAt'] = FieldValue.serverTimestamp();
    await _sub(tourId, 'posts').doc(id).set(map);
  }

  Future<void> updatePostCaption(
      String tourId, String postId, String caption) async {
    _requireEmail();
    await _sub(tourId, 'posts').doc(postId).update({'caption': caption.trim()});
  }

  Future<void> updatePost(
    String tourId,
    String postId, {
    String? caption,
    String? location,
    String? tourDay,
    List<String>? tags,
  }) async {
    _requireEmail();
    final updates = <String, dynamic>{
      'isEdited': true,
      'editedAt': writeDate(DateTime.now()),
    };
    if (caption != null) updates['caption'] = caption.trim();
    if (location != null) updates['location'] = location.trim();
    if (tourDay != null) updates['tourDay'] = tourDay;
    if (tags != null) updates['tags'] = tags;
    await _sub(tourId, 'posts').doc(postId).update(updates);
  }

  Future<void> setPostArchived(
    String tourId,
    String postId, {
    required bool isArchived,
  }) async {
    _requireEmail();
    await _sub(tourId, 'posts').doc(postId).update({'isArchived': isArchived});
  }

  /// Likes or unlikes a post. arrayUnion/arrayRemove mean two people liking at
  /// the same moment both count.
  Future<void> setPostLiked(String tourId, String postId,
      {required bool liked}) async {
    final email = _requireEmail();
    await _sub(tourId, 'posts').doc(postId).update({
      'likes': liked
          ? FieldValue.arrayUnion([email])
          : FieldValue.arrayRemove([email]),
    });
  }

  /// Records a member's view on a post. A member counts once: the count moves
  /// only the first time this member's email is added to the viewers.
  Future<void> recordPostView({
    required String tourId,
    required String postId,
  }) async {
    try {
      final email = currentEmail;
      if (email.isEmpty) return;
      final postRef = _sub(tourId, 'posts').doc(postId);
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(postRef);
        final data = snap.data();
        if (data == null) return;
        final viewers = (data['viewers'] as List?)?.cast<Object?>() ?? const [];
        if (viewers.contains(email)) return;
        tx.update(postRef, {
          'viewers': FieldValue.arrayUnion([email]),
          'viewCount': FieldValue.increment(1),
        });
      });
    } catch (e, st) {
      logWarning('[recordPostView] Failed to record view on $postId', e, st);
    }
  }

  Future<void> setPostPinned(String tourId, String postId,
      {required bool isPinned}) async {
    _requireEmail();
    await _sub(tourId, 'posts').doc(postId).update({'isPinned': isPinned});
  }

  Future<void> setPostSettings(String tourId, String postId,
      {bool? hideLikeCount, bool? disableComments}) async {
    _requireEmail();
    final updates = <String, dynamic>{};
    if (hideLikeCount != null) updates['hideLikeCount'] = hideLikeCount;
    if (disableComments != null) updates['disableComments'] = disableComments;
    if (updates.isNotEmpty) {
      await _sub(tourId, 'posts').doc(postId).update(updates);
    }
  }

  /// Deletes a post. The post goes first, so it leaves every feed at once; its
  /// comments and files are unreachable after that. Each file is journaled
  /// before its delete is sent, and the comments are removed in batches.
  Future<void> deletePost(TourPostItem post) async {
    _requireEmail();
    final postRef = _sub(post.tourId, 'posts').doc(post.id);

    // Comments go first. Their delete rules read the post, so it must still
    // exist; if this fails the post stays and can be deleted again.
    final comments = await postRef.collection('comments').get();
    for (var i = 0; i < comments.docs.length; i += _batchLimit) {
      final batch = _firestore.batch();
      for (final c in comments.docs.skip(i).take(_batchLimit)) {
        batch.delete(c.reference);
      }
      await batch.commit();
    }

    await postRef.delete();
    await _deleteMediaFiles([
      ...post.images,
      post.videoUrl,
      post.coverUrl,
    ]);
  }

  /// Deletes a story, and the files it uploaded unless a highlight still shows
  /// its image as the cover.
  Future<void> deleteStory(String tourId, TourStoryItem story) async {
    _requireEmail();
    await _sub(tourId, 'stories').doc(story.id).delete();

    final coverInUse = await _isHighlightCover(tourId, story.mediaUrl);
    await _deleteMediaFiles([
      if (!coverInUse) story.mediaUrl,
      story.videoUrl,
    ]);
  }

  /// Journals each remote media file in [urls] and removes it from the server.
  /// A file the server refuses to remove stays journaled for the sweep.
  Future<void> _deleteMediaFiles(Iterable<String?> urls) async {
    final refs = <TourMediaRef>[];
    for (final url in urls) {
      if (url == null || !isRemoteMediaUrl(url)) continue;
      final ref = TourMediaRef.tryParse(url);
      if (ref != null) refs.add(ref);
    }

    final journal = TourMediaJournal.instance;
    for (final ref in refs) {
      await journal.markDelete(ref);
    }
    for (final ref in refs) {
      if (await TourMediaUploader.deleteMedia(ref.url)) {
        await journal.resolve(ref.url);
      }
    }
  }

  /// Whether a highlight uses [url] as its cover. Unknown counts as in use, so
  /// the file is kept.
  Future<bool> _isHighlightCover(String tourId, String url) async {
    try {
      final match = await _sub(tourId, 'highlights')
          .where('coverUrl', isEqualTo: url)
          .limit(1)
          .get();
      return match.docs.isNotEmpty;
    } catch (e, st) {
      logWarning(
          '[TourGroupRepository] Could not check highlight covers', e, st);
      return true;
    }
  }

  /// Folders the sweep may clean up. Every URL field that can hold one of
  /// these files is checked by [isMediaReferenced].
  static const Set<String> _sweptFolders = {
    'posts',
    'reels',
    'covers',
    'stories'
  };

  /// Whether a post, story or highlight still uses the file. Null when this
  /// cannot be decided, which keeps the file.
  Future<bool?> isMediaReferenced(JournalEntry entry) async {
    if (!_sweptFolders.contains(entry.folder)) return null;
    final url = entry.url;
    final posts = _sub(entry.tourId, 'posts');
    final stories = _sub(entry.tourId, 'stories');
    final highlights = _sub(entry.tourId, 'highlights');
    Future<bool> used(Query<Map<String, dynamic>> query) async {
      return (await query.limit(1).get()).docs.isNotEmpty;
    }

    try {
      final results = await Future.wait<bool>([
        used(posts.where('images', arrayContains: url)),
        used(posts.where('videoUrl', isEqualTo: url)),
        used(posts.where('coverUrl', isEqualTo: url)),
        used(stories.where('mediaUrl', isEqualTo: url)),
        used(stories.where('videoUrl', isEqualTo: url)),
        used(highlights.where('coverUrl', isEqualTo: url)),
      ]);
      return results.any((r) => r);
    } catch (e, st) {
      logWarning('[TourGroupRepository] Could not check media use', e, st);
      return null;
    }
  }

  Stream<List<TourCommentItem>> watchComments(String tourId, String postId) {
    return _sub(tourId, 'posts')
        .doc(postId)
        .collection('comments')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((s) => s.docs
            .map((d) => TourCommentItem.fromMap(d.id, d.data()))
            .toList());
  }

  /// Adds a comment and bumps the post's count in one batch. A comment needs
  /// text or a reaction.
  Future<void> addComment({
    required String tourId,
    required String postId,
    required String text,
    String? reaction,
    String? parentId,
  }) async {
    final email = _requireEmail();
    final trimmed = text.trim();
    if (trimmed.isEmpty && (reaction == null || reaction.isEmpty)) return;
    if (trimmed.length > 500) {
      throw const TourAccessException('মন্তব্য ৫০০ অক্ষরের বেশি হতে পারবে না।');
    }
    final commentId = _uuid.v4();
    final comment = TourCommentItem(
      id: commentId,
      authorEmail: email,
      authorName: currentDisplayName,
      authorPhoto: currentPhotoUrl,
      text: trimmed,
      reaction: reaction,
      createdAt: DateTime.now(),
      parentId: parentId,
    );
    final postRef = _sub(tourId, 'posts').doc(postId);
    final batch = _firestore.batch();
    final map = comment.toMap()..['createdAt'] = FieldValue.serverTimestamp();
    batch.set(postRef.collection('comments').doc(commentId), map);
    batch.update(postRef, {'commentCount': FieldValue.increment(1)});
    await batch.commit();
  }

  Future<void> deleteComment(
      String tourId, String postId, String commentId) async {
    _requireEmail();
    final postRef = _sub(tourId, 'posts').doc(postId);
    final batch = _firestore.batch();
    batch.delete(postRef.collection('comments').doc(commentId));
    batch.update(postRef, {'commentCount': FieldValue.increment(-1)});
    await batch.commit();
  }

  Future<void> setCommentLiked(String tourId, String postId, String commentId,
      {required bool liked}) async {
    final email = _requireEmail();
    await _sub(tourId, 'posts')
        .doc(postId)
        .collection('comments')
        .doc(commentId)
        .update({
      'likes': liked
          ? FieldValue.arrayUnion([email])
          : FieldValue.arrayRemove([email]),
    });
  }

  Future<void> setCommentPinned(String tourId, String postId, String commentId,
      {required bool isPinned, bool? isAuthorLiked}) async {
    _requireEmail();
    final updates = <String, dynamic>{'isPinned': isPinned};
    if (isAuthorLiked != null) updates['isAuthorLiked'] = isAuthorLiked;
    await _sub(tourId, 'posts')
        .doc(postId)
        .collection('comments')
        .doc(commentId)
        .update(updates);
  }

  // ---------------------------------------------------------------------------
  // Stories
  // ---------------------------------------------------------------------------

  /// Recent stories. The caller filters to those still within their 24 hours,
  /// which keeps the cutoff current instead of frozen at subscription time.
  Stream<List<TourStoryItem>> watchStories(String tourId) {
    return _sub(tourId, 'stories')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => TourStoryItem.fromMap(d.id, d.data())).toList());
  }

  Future<void> addStory({
    required String tourId,
    required String mediaUrl,
    String? caption,
    bool isVideo = false,
    String? videoUrl,
    TourStoryPoll? poll,
    TourStorySticker? sticker,
    String? highlightId,
  }) async {
    final email = _requireEmail();
    if (!isRemoteMediaUrl(mediaUrl)) {
      throw const TourAccessException(
          'আপলোড এখনও শেষ হয়নি। ছবি সম্পূর্ণ আপলোড হওয়ার পর স্টোরি দিন।');
    }
    final id = _uuid.v4();
    final story = TourStoryItem(
      id: id,
      authorEmail: email,
      authorName: currentDisplayName,
      authorPhoto: currentPhotoUrl,
      mediaUrl: mediaUrl,
      caption: caption?.trim().isEmpty ?? true ? null : caption!.trim(),
      createdAt: DateTime.now(),
      isVideo: isVideo,
      videoUrl: videoUrl,
      poll: poll,
      sticker: sticker,
      highlightId: highlightId,
    );
    final map = story.toMap()..['createdAt'] = FieldValue.serverTimestamp();
    await _sub(tourId, 'stories').doc(id).set(map);
  }

  Future<void> recordStoryView(String tourId, String storyId) async {
    if (!isSignedIn) return;
    final email = currentEmail;
    if (email.isEmpty) return;
    try {
      await _sub(tourId, 'stories').doc(storyId).update({
        'viewers': FieldValue.arrayUnion([email]),
      });
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
  }

  // The keys are FieldPaths, not dotted strings: an email's dots would
  // otherwise split it into nested maps.
  Future<void> voteStoryPoll(
      String tourId, String storyId, int optionIndex) async {
    final email = _requireEmail();
    await _sub(tourId, 'stories').doc(storyId).update({
      FieldPath(['poll', 'votes', email]): optionIndex,
    });
  }

  Future<void> addStoryReaction(
      String tourId, String storyId, String emoji) async {
    final email = _requireEmail();
    await _sub(tourId, 'stories').doc(storyId).update({
      FieldPath(['reactions', email]): emoji,
    });
  }

  // ---------------------------------------------------------------------------
  // Highlights
  // ---------------------------------------------------------------------------

  Stream<List<TourStoryHighlight>> watchHighlights(String tourId) {
    return _sub(tourId, 'highlights')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => TourStoryHighlight.fromMap(d.id, d.data()))
            .toList());
  }

  Future<void> addHighlight(
    String tourId, {
    required String title,
    required String coverUrl,
    required List<String> storyIds,
  }) async {
    final email = _requireEmail();
    final id = _uuid.v4();
    final highlight = TourStoryHighlight(
      id: id,
      tourId: tourId,
      title: title.trim().isEmpty ? 'স্মৃতি' : title.trim(),
      coverUrl: coverUrl,
      storyIds: storyIds,
      createdAt: DateTime.now(),
    );
    final map = highlight.toMap()..['createdByEmail'] = email;
    await _sub(tourId, 'highlights').doc(id).set(map);
  }

  Future<void> deleteHighlight(String tourId, String highlightId) async {
    _requireEmail();
    await _sub(tourId, 'highlights').doc(highlightId).delete();
  }

  // ---------------------------------------------------------------------------
  // Live locations & safety
  // ---------------------------------------------------------------------------

  /// Shares the signed-in person's position. Each person writes only their own doc.
  Future<void> setMyLocation(String tourId,
      {required double lat, required double lng}) async {
    final email = _requireEmail();
    await _sub(tourId, 'locations').doc(email).set({
      'email': email,
      'displayName': currentDisplayName,
      'lat': lat,
      'lng': lng,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // Backup
  // ---------------------------------------------------------------------------

  /// Everything the owner needs to keep a copy of the tour. Member emails are
  /// left out; names are kept so the backup still reads well.
  Future<Map<String, dynamic>> fetchFullTourSnapshot(String tourId) async {
    _requireEmail();
    final tourDoc = await _tour(tourId).get();
    final tourData = Map<String, dynamic>.from(tourDoc.data() ?? {});
    tourData.remove('inviteCode');

    Future<List<Map<String, dynamic>>> collect(String name) async {
      final snap = await _sub(tourId, name).get();
      return snap.docs.map((d) => d.data()).toList();
    }

    final members = await _memberships.where('tourId', isEqualTo: tourId).get();
    final posts = await _sub(tourId, 'posts')
        .orderBy('createdAt', descending: true)
        .limit(500)
        .get();
    final comments = <Map<String, dynamic>>[];
    for (final post in posts.docs) {
      final c = await post.reference.collection('comments').get();
      for (final doc in c.docs) {
        comments.add({'postId': post.id, ...doc.data()});
      }
    }

    return {
      'exportedAt': DateTime.now().toIso8601String(),
      'app': 'Bhromon Tour Group',
      'tour': tourData,
      'members': members.docs
          .map((d) => {
                'displayName': d.data()['displayName'],
                'role': d.data()['role'],
                'familyCount': d.data()['familyCount'],
              })
          .toList(),
      'expenses': await collect('expenses'),
      'deposits': await collect('deposits'),
      'transfers': await collect('transfers'),
      'notices': await collect('notices'),
      'checklist': await collect('checklist'),
      'checkpoints': await collect('checkpoints'),
      'bus_seats': await collect('bus_seats'),
      'vehicles': await collect('vehicles'),
      'vehicle_seats': await collect('vehicle_seats'),
      'hotel_rooms': await collect('hotel_rooms'),
      'posts': posts.docs.map((d) => d.data()).toList(),
      'comments': comments,
      'stories': await collect('stories'),
    };
  }

  /// Every post in the tour, oldest first, read in pages of 200. The PDF export
  /// reads the whole record this way; the feed only shows the newest page.
  Future<List<TourPostItem>> fetchAllPostsForExport(String tourId) async {
    _requireEmail();
    const pageSize = 200;
    final posts = <TourPostItem>[];
    DocumentSnapshot<Map<String, dynamic>>? last;
    while (true) {
      var query = _sub(tourId, 'posts').orderBy('createdAt').limit(pageSize);
      if (last != null) query = query.startAfterDocument(last);
      final snap = await query.get();
      posts.addAll(snap.docs.map((d) => TourPostItem.fromMap(d.id, d.data())));
      if (snap.docs.length < pageSize) return posts;
      last = snap.docs.last;
    }
  }

  /// Every comment on a post, oldest first, for the PDF export.
  Future<List<TourCommentItem>> fetchCommentsForExport(
    String tourId,
    String postId,
  ) async {
    _requireEmail();
    final snap = await _sub(tourId, 'posts')
        .doc(postId)
        .collection('comments')
        .orderBy('createdAt')
        .get();
    return snap.docs
        .map((d) => TourCommentItem.fromMap(d.id, d.data()))
        .toList();
  }
}
