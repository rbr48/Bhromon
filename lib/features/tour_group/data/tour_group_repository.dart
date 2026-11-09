import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'package:bhromon/core/utils/session_shared_stream.dart';
import 'package:bhromon/core/utils/shared_stream_registry.dart';

import '../../../../core/utils/app_logger.dart';
import '../domain/models/date_codec.dart';
import '../domain/models/expense_models.dart';
import '../domain/models/itinerary_models.dart';
import '../domain/models/logistics_models.dart';
import '../domain/models/safety_alert_models.dart';
import '../domain/models/tour_activity_models.dart';
import '../domain/models/family_date_models.dart';
import '../domain/models/dependent_models.dart';
import '../domain/models/family_task_models.dart';
import '../domain/models/study_models.dart';
import '../domain/models/study_glossary_models.dart';
import '../domain/models/study_material_models.dart';
import '../domain/models/study_quiz_models.dart';
import '../domain/models/study_summary_models.dart';
import '../domain/services/study_quiz_rules.dart';
import '../domain/models/study_session_models.dart';
import '../domain/models/study_thread_models.dart';
import '../domain/models/study_subject_models.dart';
import '../domain/models/study_finding_models.dart';
import '../domain/models/study_problem_models.dart';
import '../domain/services/study_chapter_rules.dart';
import '../domain/services/study_material_rules.dart';
import '../domain/models/meal_log.dart';
import '../domain/models/mess_bazar_model.dart';
import '../domain/models/samity_models.dart';
import '../domain/models/service_request_models.dart';
import '../domain/services/meal_engine.dart';
import '../domain/services/dependent_rules.dart';
import '../domain/services/family_date_rules.dart';
import '../domain/models/tour_group.dart';
import '../domain/models/tour_post_models.dart';
import '../domain/models/vehicle_models.dart';
import '../domain/services/call_partner.dart';
import '../domain/services/emergency_numbers.dart';
import '../domain/services/media_references.dart';
import '../domain/services/media_rules.dart';
import '../domain/services/member_profile_sync.dart';
import 'active_group.dart';
import 'group_stream_budget.dart';
import '../domain/services/family_telemetry_publisher.dart';
import '../domain/services/invite_code.dart';
import '../domain/services/seat_layout_engine.dart';
import '../domain/services/seat_planner.dart';
import 'channel_message_cache.dart';
import 'channel_read_store.dart';
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
      throw const TourAccessException('গ্রুপ ব্যবহার করতে আগে সাইন-ইন করুন।');
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
    await ActiveGroup.instance.clearIf(tourId);
    await ChannelMessageCache().clearTour(tourId);
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

  /// One groups list for the whole app. Screens each build their own repository, so the
  /// sharing lives in static state: one upstream however many screens listen.
  static SessionSharedStream<List<TourGroup>>? _sharedMyGroups;

  /// One members stream per tour, shared by every screen that shows that tour's members.
  /// Its upstreams are counted by [GroupStreamBudget].
  static final SharedStreamRegistry<String, List<TourMember>> _sharedMembers =
      SharedStreamRegistry<String, List<TourMember>>(
    onUpstreamStart: (tourId) =>
        GroupStreamBudget.open(GroupStreamBudget.membersKey(tourId)),
    onUpstreamEnd: (tourId) =>
        GroupStreamBudget.close(GroupStreamBudget.membersKey(tourId)),
  );

  /// The tours as they were last seen this session. A new listen starts from these, so
  /// the eager fetch runs once per session, not once per listen.
  static final Map<String, TourGroup> _sessionTourDocs = {};

  /// True while the groups list is answered from this device's cache rather than the
  /// server. The groups list shows an offline banner when this stays true.
  static final ValueNotifier<bool> groupsServedFromCache =
      ValueNotifier<bool>(false);

  /// Tours the signed-in user is an active member of, live.
  ///
  /// Membership decides the list. Cached tours show only until the first
  /// membership answer arrives, so tours the user left or was removed from
  /// stop appearing. Every caller shares one upstream (see [_sharedMyGroups]).
  Stream<List<TourGroup>> watchMyGroups() {
    final shared = _sharedMyGroups ??= SessionSharedStream<List<TourGroup>>(
      _openMyGroups,
      onUpstreamStart: () => GroupStreamBudget.open(GroupStreamBudget.myGroups),
      onUpstreamEnd: () => GroupStreamBudget.close(GroupStreamBudget.myGroups),
    );
    return shared.stream;
  }

  /// Starts [watchMyGroups] again from nothing, for a retry after an error. The old
  /// listeners are closed, so a screen must listen to the stream returned here.
  Stream<List<TourGroup>> restartMyGroups() {
    final old = _sharedMyGroups;
    _sharedMyGroups = null;
    unawaited(old?.reset());
    return watchMyGroups();
  }

  /// The upstream of [watchMyGroups]: the membership rows, then each tour, live.
  Stream<List<TourGroup>> _openMyGroups() {
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
      _sessionTourDocs.remove(tourId);
      unawaited(forgetMembers(tourId));
    }

    void startTour(String tourId, String email) {
      final known = _sessionTourDocs[tourId];
      if (known != null) {
        tours[tourId] = known;
      } else {
        // Eager one-off fetch for fast Web and desktop startup, once per session.
        _tour(tourId).get().then((doc) {
          try {
            final data = doc.data();
            if (doc.exists && data != null && !controller.isClosed) {
              final group = TourGroup.fromMap(doc.id, data);
              tours[tourId] = group;
              _sessionTourDocs[tourId] = group;
              _cacheLocalGroup(group);
              emit();
            }
          } catch (e, st) {
            logWarning(
                '[TourGroupRepository] eager get tour $tourId failed', e, st);
          }
        }).catchError((Object e, StackTrace st) {
          logWarning(
              '[TourGroupRepository] eager get tour $tourId error', e, st);
        });
      }

      tourSubs[tourId] = _tour(tourId).snapshots().listen(
        (doc) {
          try {
            final data = doc.data();
            if (doc.exists && data != null) {
              final group = TourGroup.fromMap(doc.id, data);
              tours[tourId] = group;
              _sessionTourDocs[tourId] = group;
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
        _sessionTourDocs.clear();
        unawaited(_sharedMembers.clear());
        clearUserTours();
        emit();
        return;
      }
      if (boundUserId == user.uid) {
        // Already bound to this user, do not clear tours.
        return;
      }
      clearUserTours();
      _sessionTourDocs.clear();
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
          groupsServedFromCache.value = snapshot.metadata.isFromCache;
          rolesByTour.clear();
          for (final d in snapshot.docs) {
            final data = d.data();
            final id = data['tourId'] as String? ?? '';
            final rawStatus = (data['status'] as String?)?.toLowerCase();
            final isActive = rawStatus == null || rawStatus == 'active';
            if (isActive && id.isNotEmpty) {
              rolesByTour[id] = data['role'] as String? ?? 'member';
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
        groupsServedFromCache.value = false;
      },
    );

    return controller.stream;
  }

  /// Live view of one tour. Null when the tour no longer exists.
  Stream<TourGroup?> watchGroup(String tourId) {
    if (tourId.trim().isEmpty) return Stream.value(null);
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
    int ownerFamilyCount = 1,
    String? preset,
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
      preset: preset,
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
          familyCount: ownerFamilyCount.clamp(1, 20),
          uid: currentUid,
        ).toMap(),
      );
      batch.set(_invites.doc(inviteCode), {
        'tourId': tourId,
        'code': inviteCode,
        'tourName': group.name,
        'groupName': group.name,
        'photoUrl': group.photoUrl,
        'preset': group.preset,
        'tourType': group.tourType.name,
        'destination': group.destination,
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
      throw const FormatException('এই আমন্ত্রণ কোডে কোনো গ্রুপ পাওয়া যায়নি।');
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
            'এই গ্রুপে যোগ দেওয়ার অনুমতি নেই। কোড ঠিক আছে কি না দেখুন, অথবা অ্যাডমিনের সাথে যোগাযোগ করুন।');
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
      throw const TourAccessException('গ্রুপটি এখন আর পাওয়া যাচ্ছে না।');
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

  /// Synchronizes group metadata (name, photo, preset) to the invite document
  /// so that prospective members can preview the group before joining.
  Future<void> syncInviteMetadata(TourGroup group) async {
    final code = group.inviteCode.trim().toUpperCase();
    if (code.isEmpty || !isValidInviteCode(code)) return;
    try {
      await _invites.doc(code).set({
        'tourId': group.id,
        'code': code,
        'tourName': group.name,
        'groupName': group.name,
        'photoUrl': group.photoUrl,
        'preset': group.preset,
        'tourType': group.tourType.name,
        'destination': group.destination,
        'updatedAt': writeDate(DateTime.now()),
      }, SetOptions(merge: true));
    } catch (e, st) {
      logSkipped(e, st);
    }
  }

  /// Fetches preview metadata for a group by its invite code.
  /// Works for prospective members and existing members.
  Future<TourGroupPreview?> fetchInvitePreview(String inviteCode) async {
    final code = inviteCode.trim().toUpperCase();
    if (!isValidInviteCode(code)) return null;

    String? tourId;
    String? name;
    String? photoUrl;
    String? preset;
    TourType? tourType;
    String? destination;
    bool isAlreadyMember = false;

    try {
      final invite = await _invites.doc(code).get();
      if (invite.exists) {
        final data = invite.data();
        tourId = data?['tourId'] as String?;
        name = (data?['tourName'] ?? data?['groupName'] ?? data?['name'])
            as String?;
        photoUrl = data?['photoUrl'] as String?;
        preset = data?['preset'] as String?;
        destination = data?['destination'] as String?;
        final tTypeStr = data?['tourType'] as String?;
        if (tTypeStr != null && tTypeStr.isNotEmpty) {
          tourType = TourType.values.firstWhere(
            (t) => t.name == tTypeStr,
            orElse: () => TourType.nature,
          );
        }
      }
    } catch (e, st) {
      logSkipped(e, st);
    }

    if (tourId == null || tourId.isEmpty) {
      tourId = code;
    }

    // If caller is authenticated, try fetching the tour document directly
    if (currentEmail.isNotEmpty) {
      try {
        final directGroup = await getGroup(tourId);
        if (directGroup != null) {
          name = directGroup.name;
          photoUrl = directGroup.photoUrl;
          preset = directGroup.preset;
          tourType = directGroup.tourType;
          destination = directGroup.destination;

          final role = await myRole(tourId);
          if (role != null) {
            isAlreadyMember = true;
          }

          // If the caller is the owner and the invite was missing metadata, backfill it
          if (directGroup.ownerEmail == currentEmail &&
              directGroup.inviteCode.isNotEmpty) {
            unawaited(syncInviteMetadata(directGroup));
          }
        }
      } catch (e, st) {
        logSkipped(e, st);
      }
    }

    if (name != null && name.isNotEmpty) {
      return TourGroupPreview(
        tourId: tourId,
        name: name,
        photoUrl: photoUrl,
        preset: preset,
        tourType: tourType,
        destination: destination,
        isAlreadyMember: isAlreadyMember,
      );
    }

    return null;
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
      throw StateError('গ্রুপটি খুঁজে পাওয়া যায়নি।');
    }
    final tourName = tourDoc.data()?['name'] as String? ?? 'Group';

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

  /// Turns Moments on or off for an office or campus. The owner or an admin may do it;
  /// the rules refuse it for any other circle.
  Future<void> setMomentsEnabled(String tourId, bool enabled) async {
    _requireEmail();
    await _tour(tourId).update({'momentsEnabled': enabled});
  }

  /// Uploads [file] as the group's photo and records it on the group, then removes the
  /// photo it replaces. The file goes to the group's own media space, so only members
  /// can read it. The owner or an admin may do this; the rules refuse anyone else.
  /// [onProgress] reports the upload from 0 to 1. Returns the new photo's URL.
  Future<String> changeGroupPhoto({
    required String tourId,
    required XFile file,
    String? previousUrl,
    void Function(double progress)? onProgress,
  }) async {
    _requireEmail();
    final contentType = imageContentType(file.name);
    if (contentType == null) {
      throw ArgumentError.value(
          file.name, 'file', 'not an image type the media server accepts');
    }
    final upload = await TourMediaUploader.start(
      tourId: tourId,
      folder: 'avatars',
      file: file,
      contentType: contentType,
      extension: storedExtension(file.name, 'jpg'),
      maxBytes: kMaxImageBytes,
      journal: TourMediaJournal.untracked,
    );
    final progressSub =
        onProgress == null ? null : upload.progress.listen(onProgress);
    final String url;
    try {
      url = await upload.finish();
      await _tour(tourId).update({'photoUrl': url});
    } catch (_) {
      // The group does not point at the new file, so it must not stay on the server.
      await upload.discard();
      rethrow;
    } finally {
      await progressSub?.cancel();
    }
    if (previousUrl != null && previousUrl != url) {
      await TourMediaUploader.deleteMedia(previousUrl);
    }
    return url;
  }

  /// Removes the group's photo. The owner or an admin may do this. The file is deleted
  /// once the group no longer points at it.
  Future<void> removeGroupPhoto(
      {required String tourId, String? previousUrl}) async {
    _requireEmail();
    await _tour(tourId).update({'photoUrl': null});
    if (previousUrl != null) {
      await TourMediaUploader.deleteMedia(previousUrl);
    }
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
    final group = await getGroup(tourId);
    final batch = _firestore.batch();
    batch.update(_tour(tourId), {'inviteCode': newCode});
    batch.set(_invites.doc(newCode), {
      'tourId': tourId,
      'code': newCode,
      if (group != null) ...{
        'tourName': group.name,
        'groupName': group.name,
        'photoUrl': group.photoUrl,
        'preset': group.preset,
        'tourType': group.tourType.name,
        'destination': group.destination,
      },
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

  /// The active members of a tour, owner first, then by join date. Every screen that asks
  /// for the same tour shares one upstream (see [forgetMembers]).
  Stream<List<TourMember>> watchMembers(String tourId) {
    return _sharedMembers.stream(tourId, () => _openMembers(tourId));
  }

  /// Ends the shared members stream of [tourId], when the user leaves the group or is
  /// removed from it. The next listen opens a fresh upstream.
  Future<void> forgetMembers(String tourId) => _sharedMembers.remove(tourId);

  /// Ends every shared stream and cached value. Called at sign-out.
  Future<void> resetSessionCaches() async {
    groupsServedFromCache.value = false;
    _sessionTourDocs.clear();
    await _sharedMembers.clear();
    // Drop the holder as well, so the next sign-in opens a new groups upstream.
    final old = _sharedMyGroups;
    _sharedMyGroups = null;
    await old?.reset();
    await ActiveGroup.instance.clear();
  }

  /// The upstream of [watchMembers]. It only reads: a member's own row is brought up to
  /// date by [syncMyMemberProfile].
  Stream<List<TourMember>> _openMembers(String tourId) {
    return _memberships
        .where('tourId', isEqualTo: tourId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) {
      final members =
          snapshot.docs.map((d) => TourMember.fromMap(d.data())).toList();
      members.sort((a, b) {
        final byRole = _roleRank(a.role).compareTo(_roleRank(b.role));
        return byRole != 0 ? byRole : a.joinedAt.compareTo(b.joinedAt);
      });
      return members;
    });
  }

  /// Brings the signed-in person's own membership rows up to date with the in-app name,
  /// photo and uid. It writes only the fields that differ, logs each failed write, and
  /// runs on sign-in and after a profile save. It never runs from a read.
  /// Returns how many rows were written.
  Future<int> syncMyMemberProfile() async {
    final email = currentEmail;
    if (email.isEmpty) return 0;
    final uid = currentUid;
    final name = currentDisplayName;
    final photo = currentPhotoUrl;
    final snapshot = await _memberships.where('email', isEqualTo: email).get();
    return applyMemberRowSync<QueryDocumentSnapshot<Map<String, dynamic>>>(
      snapshot.docs,
      updatesFor: (doc) => memberRowUpdates(
        row: doc.data(),
        uid: uid,
        displayName: name,
        photoUrl: photo,
      ),
      write: (doc, updates) => doc.reference.update(updates),
      onFailure: (error, stackTrace) => logWarning(
          '[TourGroupRepository] member profile sync failed',
          error,
          stackTrace),
    );
  }

  /// The tours the signed-in person is an active member of, read from the server.
  /// Unlike [watchMyGroups] this never answers from the local cache, so a tour the
  /// person has left, or was removed from, is not returned. Throws when offline.
  Future<List<TourGroup>> fetchMyGroupsFromServer() async {
    const server = GetOptions(source: Source.server);
    final groups = <TourGroup>[];
    for (final tourId in await _activeTourIdsFromServer()) {
      final doc = await _tour(tourId).get(server);
      final data = doc.data();
      if (doc.exists && data != null) {
        groups.add(TourGroup.fromMap(doc.id, data));
      }
    }
    groups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return groups;
  }

  /// The ids of the tours the signed-in person is an active member of, read from the
  /// server.
  Future<Set<String>> _activeTourIdsFromServer() async {
    final email = currentEmail;
    if (email.isEmpty) return <String>{};
    final rows = await _memberships
        .where('email', isEqualTo: email)
        .get(const GetOptions(source: Source.server));
    final tourIds = <String>{};
    for (final row in rows.docs) {
      final data = row.data();
      final status = (data['status'] as String?)?.toLowerCase();
      final tourId = data['tourId'] as String? ?? '';
      if (tourId.isNotEmpty && (status == null || status == 'active')) {
        tourIds.add(tourId);
      }
    }
    return tourIds;
  }

  /// The tour a call between the signed-in person and [partnerUid] is rung through.
  /// It is [preferredTourId], the tour the chat names, when both are still active in
  /// it. Otherwise it is another tour they both belong to. When there is none, the
  /// status says why: the status for the preferred tour, or
  /// [CallPartnerStatus.noSharedTour] when there is no preferred tour.
  Future<({String? tourId, CallPartnerStatus status})> resolveCallTour({
    required String? preferredTourId,
    required String partnerUid,
    required String partnerEmail,
  }) async {
    final myTourIds = await _activeTourIdsFromServer();
    final ordered = [
      if (preferredTourId != null) preferredTourId,
      for (final tourId in myTourIds)
        if (tourId != preferredTourId) tourId,
    ];
    var status = CallPartnerStatus.noSharedTour;
    for (final tourId in ordered) {
      final tourStatus = await callPartnerStatus(
        tourId: tourId,
        partnerUid: partnerUid,
        partnerEmail: partnerEmail,
      );
      if (tourStatus == CallPartnerStatus.ready) {
        return (tourId: tourId, status: tourStatus);
      }
      if (tourId == preferredTourId) status = tourStatus;
    }
    return (tourId: null, status: status);
  }

  /// Active members of [tourId], read from the server (see [fetchMyGroupsFromServer]).
  Future<List<TourMember>> fetchMembersFromServer(String tourId) async {
    final rows = await _memberships
        .where('tourId', isEqualTo: tourId)
        .where('status', isEqualTo: 'active')
        .get(const GetOptions(source: Source.server));
    return [for (final row in rows.docs) TourMember.fromMap(row.data())];
  }

  /// Which of [tourIds] (groups the signed-in person is in) the person with
  /// [uid] is also an active member of, and that person's email from their
  /// membership row. [email] is a hint, such as the address a chat knows; it
  /// finds rows that have no uid yet. Each group is read with its own query,
  /// because the rules let a member list only their own group's roster.
  Future<({Set<String> tourIds, String? email})> sharedGroupsWith({
    required String uid,
    String? email,
    required Iterable<String> tourIds,
  }) async {
    final shared = <String>{};
    String? knownEmail =
        (email == null || email.trim().isEmpty) ? null : normalizeEmail(email);
    for (final tourId in tourIds) {
      try {
        final rows = await _memberships
            .where('tourId', isEqualTo: tourId)
            .where('status', isEqualTo: 'active')
            .where('uid', isEqualTo: uid)
            .limit(1)
            .get();
        if (rows.docs.isNotEmpty) {
          shared.add(tourId);
          final rowEmail = rows.docs.first.data()['email'] as String? ?? '';
          if (rowEmail.isNotEmpty) knownEmail ??= normalizeEmail(rowEmail);
          continue;
        }
        if (knownEmail != null) {
          final row = await _memberships.doc('${tourId}__$knownEmail').get();
          if (row.exists && row.data()?['status'] == 'active') {
            shared.add(tourId);
          }
        }
      } catch (error, stackTrace) {
        logWarning('Could not check shared group $tourId', error, stackTrace);
      }
    }
    return (tourIds: shared, email: knownEmail);
  }

  /// Whether the signed-in person and [partnerUid] (at [partnerEmail]) can call each
  /// other inside [tourId], as the call rules judge it. Reads the server, never the
  /// cache. When the signed-in person's own row has no uid, it is filled in first,
  /// which the membership rules allow.
  Future<CallPartnerStatus> callPartnerStatus({
    required String tourId,
    required String partnerUid,
    required String partnerEmail,
  }) async {
    const server = GetOptions(source: Source.server);
    final myEmail = currentEmail;
    final myUid = currentUid;
    if (myEmail.isEmpty || myUid.isEmpty) return CallPartnerStatus.youLeft;
    final myRef = _memberships.doc(_membershipId(tourId, myEmail));
    var myRow = (await myRef.get(server)).data();
    if (myRow != null &&
        myRow['status'] == 'active' &&
        (myRow['uid'] as String? ?? '').isEmpty) {
      await myRef.update({'uid': myUid});
      myRow = {...myRow, 'uid': myUid};
    }
    final partnerRow = (await _memberships
            .doc(_membershipId(tourId, normalizeEmail(partnerEmail)))
            .get(server))
        .data();
    return callPartnerStatusFor(
      myRow: myRow,
      partnerRow: partnerRow,
      partnerUid: partnerUid,
    );
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

  /// Replaces the family's emergency numbers. Only the owner and admins can do
  /// this, and the tour rules check the length of the list.
  Future<void> setEmergencyContacts(
    String tourId,
    List<EmergencyContact> contacts,
  ) {
    if (contacts.length > kMaxEmergencyContacts) {
      throw ArgumentError.value(contacts.length, 'contacts',
          'at most $kMaxEmergencyContacts numbers');
    }
    return _tour(tourId).update({
      'emergencyContacts': [for (final c in contacts) c.toMap()],
    });
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
          'নিজেকে সরাতে "গ্রুপ ছেড়ে যান" ব্যবহার করুন।');
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
      throw const TourAccessException('আপনি ইতিমধ্যে এই গ্রুপের মালিক।');
    }
    final targetRow =
        await _memberships.doc(_membershipId(tourId, target)).get();
    if (!targetRow.exists || targetRow.data()?['status'] != 'active') {
      throw const TourAccessException(
          'মালিকানা শুধু এই গ্রুপের সক্রিয় সদস্যকে দেওয়া যাবে।');
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
    await forgetMembers(tourId);
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
    MfsPaymentInfo? mfsInfo,
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
      mfsInfo: mfsInfo,
    );
    final batch = _firestore.batch();
    batch.set(_sub(tourId, 'expenses').doc(expense.id), expense.toMap());

    final trxId = mfsInfo?.trxId?.trim().toUpperCase();
    if (trxId != null &&
        trxId.isNotEmpty &&
        mfsInfo?.provider.requiresTrxId == true) {
      final regDoc = _sub(tourId, 'mfs_trx_registry').doc(trxId);
      batch.set(regDoc, {
        'trxId': trxId,
        'provider': mfsInfo!.provider.name,
        'recordType': 'expense',
        'recordId': expense.id,
        'amountPaisa': expense.amountPaisa,
        'addedByEmail': email,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    unawaited(VpsNotificationService().notifyLedger(
      tourId: tourId,
      expenseId: expense.id,
      payerName: (expense.paidByName != null && expense.paidByName!.isNotEmpty)
          ? expense.paidByName!
          : currentDisplayName,
      title: expense.title,
      amountPaisa: expense.amountPaisa,
    ));
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

  // ---------------------------------------------------------------------------
  // Structured MFS Settlements & TrxID Registry
  // ---------------------------------------------------------------------------

  /// Structured MFS settlements (bKash/Nagad/Rocket/Upay) and peer settlements, newest first.
  Stream<List<SettlementRecord>> watchSettlements(String tourId) {
    return _sub(tourId, 'settlements').snapshots().map((snapshot) {
      final items =
          snapshot.docs.map((d) => SettlementRecord.fromMap(d.data())).toList();
      items.sort((a, b) => b.date.compareTo(a.date));
      return items;
    });
  }

  /// Records a structured MFS settlement. If the provider uses a TrxID,
  /// atomically reserves it in the tour's `mfs_trx_registry` to prevent duplicate reuse.
  Future<void> addSettlement(String tourId, SettlementRecord record) async {
    final email = _requireEmail();
    final batch = _firestore.batch();
    final settlementDoc = _sub(tourId, 'settlements').doc(record.id);
    batch.set(settlementDoc, record.toMap());

    final trxId = record.mfsInfo.trxId?.trim().toUpperCase();
    if (trxId != null &&
        trxId.isNotEmpty &&
        record.mfsInfo.provider.requiresTrxId) {
      final regDoc = _sub(tourId, 'mfs_trx_registry').doc(trxId);
      batch.set(regDoc, {
        'trxId': trxId,
        'provider': record.mfsInfo.provider.name,
        'recordType': 'settlement',
        'recordId': record.id,
        'amountPaisa': record.amountPaisa,
        'addedByEmail': email,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// Checks whether an MFS transaction ID has already been recorded in the tour's registry.
  Future<bool> isMfsTrxRegistered(String tourId, String trxId) async {
    final clean = trxId.trim().toUpperCase();
    if (clean.isEmpty) return false;
    final doc = await _sub(tourId, 'mfs_trx_registry').doc(clean).get();
    return doc.exists;
  }

  /// Updates an MFS settlement's verification status (e.g., verified or disputed by admin).
  Future<void> updateSettlementStatus(
    String tourId,
    String settlementId,
    MfsVerificationStatus status, {
    String? disputeReason,
  }) async {
    final email = _requireEmail();
    final docRef = _sub(tourId, 'settlements').doc(settlementId);
    final updates = <String, dynamic>{
      'mfsInfo.status': status.name,
      if (status == MfsVerificationStatus.verified) ...{
        'mfsInfo.verifiedByUserId': email,
        'mfsInfo.verifiedByName': currentDisplayName,
        'mfsInfo.verifiedAt': DateTime.now().toIso8601String(),
      },
      if (status == MfsVerificationStatus.disputed && disputeReason != null)
        'mfsInfo.disputeReason': disputeReason,
    };
    await docRef.update(updates);
  }

  /// Deletes a settlement record and frees its registered TrxID in `mfs_trx_registry` if present.
  Future<void> deleteSettlement(String tourId, SettlementRecord record) async {
    _requireEmail();
    final batch = _firestore.batch();
    batch.delete(_sub(tourId, 'settlements').doc(record.id));
    final trxId = record.mfsInfo.trxId?.trim().toUpperCase();
    if (trxId != null &&
        trxId.isNotEmpty &&
        record.mfsInfo.provider.requiresTrxId) {
      batch.delete(_sub(tourId, 'mfs_trx_registry').doc(trxId));
    }
    await batch.commit();
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
    final docRef = await _sub(tourId, 'notices').add({
      ...notice.toEditableMap(),
      'author': currentDisplayName,
      'authorEmail': email,
      'ackBy': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
    unawaited(VpsNotificationService().notifyNotice(
      tourId: tourId,
      noticeId: docRef.id,
      title: notice.title,
      body: notice.content,
      priority: notice.urgent ? 'high' : 'normal',
    ));
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
  // Family dates
  // ---------------------------------------------------------------------------

  /// The circle's dates. A stored date that does not read is left out.
  Stream<List<FamilyDate>> watchFamilyDates(String tourId) {
    return _sub(tourId, 'family_dates').limit(200).snapshots().map((s) => [
          for (final d in s.docs)
            if (FamilyDate.fromMap(d.id, d.data()) case final date?) date,
        ]);
  }

  /// Adds a family date, or saves changes to one. The reminder days are worked
  /// out from the start day and today, the way the reminder job works them out.
  /// A new date is stamped with the signed-in member; an edit keeps its creator.
  Future<void> saveFamilyDate(
    String tourId, {
    String? id,
    required String title,
    required FamilyDateKind kind,
    required FamilyRecurrence recurrence,
    required DateTime startOn,
    required int remindDays,
    String note = '',
    DateTime? now,
  }) async {
    final email = _requireEmail();
    final schedule = FamilyDateRules.scheduleFor(
      startOn: startOn,
      recurrence: recurrence,
      remindDays: remindDays,
      today: now ?? DateTime.now(),
    );
    final fields = {
      'title': title.trim(),
      'kind': kind.name,
      'recurrence': recurrence.name,
      'startOn': FamilyDateRules.dayKey(startOn),
      'nextOn': schedule.nextOn,
      'remindDays': remindDays,
      'remindOn': schedule.remindOn,
      'note': note.trim(),
    };
    if (id == null) {
      await _sub(tourId, 'family_dates').add({
        ...fields,
        'createdByEmail': email,
      });
    } else {
      await _sub(tourId, 'family_dates').doc(id).update(fields);
    }
  }

  /// Removes a family date. Its creator or an admin may do it; the rules decide.
  Future<void> deleteFamilyDate(String tourId, String dateId) async {
    _requireEmail();
    await _sub(tourId, 'family_dates').doc(dateId).delete();
  }

  // ---------------------------------------------------------------------------
  // Family shopping and to-do
  // ---------------------------------------------------------------------------

  /// The circle's shared items. A stored item that does not read is left out.
  Stream<List<FamilyTask>> watchFamilyTasks(String tourId) {
    return _sub(tourId, 'family_tasks').limit(300).snapshots().map((s) => [
          for (final d in s.docs)
            if (FamilyTask.fromMap(d.id, d.data()) case final task?) task,
        ]);
  }

  /// Adds an item for the whole circle, or for one member when [assigneeEmail] is
  /// given. The signed-in member is recorded as its creator.
  Future<void> addFamilyTask(
    String tourId, {
    required String title,
    required FamilyTaskKind kind,
    String? assigneeEmail,
  }) async {
    final email = _requireEmail();
    final assignee = assigneeEmail == null || assigneeEmail.trim().isEmpty
        ? null
        : normalizeEmail(assigneeEmail);
    final task = FamilyTask(
      id: '',
      title: title.trim(),
      kind: kind,
      assigneeEmail: assignee,
      createdByEmail: email,
    );
    await _sub(tourId, 'family_tasks').add(task.toFields());
  }

  /// Ticks an item off, or takes the tick back. The tick is recorded as the
  /// signed-in member's; taking it back clears the name.
  Future<void> setFamilyTaskDone(
      String tourId, String taskId, bool done) async {
    final email = _requireEmail();
    await _sub(tourId, 'family_tasks').doc(taskId).update({
      'done': done,
      'doneByEmail': done ? email : null,
    });
  }

  /// Changes an item's text, kind or assignee. Its creator or an admin does this.
  /// The tick is not written here, so an edit cannot undo someone else's tick.
  Future<void> editFamilyTask(
    String tourId,
    String taskId, {
    required String title,
    required FamilyTaskKind kind,
    String? assigneeEmail,
  }) async {
    _requireEmail();
    final assignee = assigneeEmail == null || assigneeEmail.trim().isEmpty
        ? null
        : normalizeEmail(assigneeEmail);
    await _sub(tourId, 'family_tasks').doc(taskId).update({
      'title': title.trim(),
      'kind': kind.name,
      'assigneeEmail': assignee,
    });
  }

  /// One mess's meal counts for a month. A member's row is written with [saveMeal].
  Stream<List<MealLog>> watchMealsForMonth(String tourId, DateTime month) {
    return _mealsForMonth(tourId, month).snapshots().map((s) => [
          for (final d in s.docs)
            if (MealLog.fromMap(d.data()) case final log?) log,
        ]);
  }

  /// Each member's meals in the month, keyed by email, for splitting a bazar.
  Future<Map<String, int>> mealTotalsForMonth(
      String tourId, DateTime month) async {
    final snap = await _mealsForMonth(tourId, month).get();
    return mealTotalsByEmail([
      for (final d in snap.docs)
        if (MealLog.fromMap(d.data()) case final log?) log,
    ]);
  }

  /// Writes one member's meals for a day. A member writes their own row; an owner or
  /// admin writes any row.
  Future<void> saveMeal(String tourId, MealLog log) async {
    await _sub(tourId, 'meals').doc(log.id).set({
      ...log.toFields(currentEmail),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Query<Map<String, dynamic>> _mealsForMonth(String tourId, DateTime month) =>
      _sub(tourId, 'meals')
          .where('dateKey', isGreaterThanOrEqualTo: mealMonthFirstKey(month))
          .where('dateKey', isLessThanOrEqualTo: mealMonthLastKey(month));

  /// Watches upcoming and recent mess bazar duty assignments.
  Stream<List<MessBazarSchedule>> watchBazarSchedules(String tourId,
      {int limit = 60}) {
    return _sub(tourId, 'mess_bazar_schedule')
        .orderBy('dateKey', descending: false)
        .limit(limit)
        .snapshots()
        .map((s) => [
              for (final d in s.docs)
                if (MessBazarSchedule.fromDoc(d.id, d.data())
                    case final schedule?)
                  schedule,
            ]);
  }

  /// Watches today\'s or a specific day\'s bazar schedule.
  Stream<MessBazarSchedule?> watchBazarScheduleForDay(
      String tourId, String dateKey) {
    return _sub(tourId, 'mess_bazar_schedule').doc(dateKey).snapshots().map(
        (doc) =>
            doc.exists ? MessBazarSchedule.fromDoc(doc.id, doc.data()) : null);
  }

  /// Saves or updates a bazar duty assignment. Admins can assign anyone;
  /// assigned members can update the completion status or shopping note.
  Future<void> saveBazarSchedule(
      String tourId, MessBazarSchedule schedule) async {
    final email = _requireEmail();
    await _sub(tourId, 'mess_bazar_schedule').doc(schedule.dateKey).set({
      ...schedule.toMap(),
      'updatedByEmail': email,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Deletes a bazar schedule entry (owner/admin only).
  Future<void> deleteBazarSchedule(String tourId, String dateKey) async {
    await _sub(tourId, 'mess_bazar_schedule').doc(dateKey).delete();
  }

  // ---------------------------------------------------------------------------
  // Housing society service requests
  // ---------------------------------------------------------------------------

  /// The society's service requests. A stored request that does not read is left out.
  Stream<List<ServiceRequest>> watchServiceRequests(String tourId) {
    return _sub(tourId, 'service_requests').limit(300).snapshots().map((s) => [
          for (final d in s.docs)
            if (ServiceRequest.fromMap(d.id, d.data()) case final request?)
              request,
        ]);
  }

  /// Raises a request under the signed-in resident's email. It starts open.
  Future<void> addServiceRequest(
    String tourId, {
    required String title,
    required String details,
    required ServiceRequestCategory category,
    List<String> photoUrls = const [],
  }) async {
    final email = _requireEmail();
    final photos = photoUrls
        .where((url) => url.isNotEmpty)
        .take(kServiceRequestPhotosMax)
        .toList();
    await _sub(tourId, 'service_requests').add({
      'title': title.trim(),
      'details': details.trim(),
      'category': category.name,
      'status': ServiceRequestStatus.open.stored,
      'adminNote': '',
      if (photos.isNotEmpty) 'photoUrls': photos,
      'createdByEmail': email,
      'createdByName': currentDisplayName,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByEmail': email,
    });
  }

  /// Corrects a request's words. The rules let only its author do this, and only while
  /// it is open.
  Future<void> editServiceRequestText(
    String tourId,
    String requestId, {
    required String title,
    required String details,
    required ServiceRequestCategory category,
    List<String> photoUrls = const [],
  }) async {
    final email = _requireEmail();
    final photos = photoUrls
        .where((url) => url.isNotEmpty)
        .take(kServiceRequestPhotosMax)
        .toList();
    await _sub(tourId, 'service_requests').doc(requestId).update({
      'title': title.trim(),
      'details': details.trim(),
      'category': category.name,
      // An empty list removes the field, so every photo can be taken off a request. The
      // single photo that requests kept before the list is dropped here too.
      'photoUrls': photos.isEmpty ? FieldValue.delete() : photos,
      'photoUrl': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByEmail': email,
    });
  }

  /// Moves a request on and leaves a note for the residents. Only an owner or admin.
  Future<void> setServiceRequestStatus(
    String tourId,
    String requestId, {
    required ServiceRequestStatus status,
    required String note,
  }) async {
    final email = _requireEmail();
    final updates = <String, dynamic>{
      'status': status.stored,
      'adminNote': note.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByEmail': email,
    };
    if (status == ServiceRequestStatus.inProgress) {
      updates['inProgressAt'] = FieldValue.serverTimestamp();
    } else if (status == ServiceRequestStatus.resolved) {
      updates['resolvedAt'] = FieldValue.serverTimestamp();
      updates['resolvedByName'] = currentDisplayName;
    }
    await _sub(tourId, 'service_requests').doc(requestId).update(updates);
  }

  /// Removes a request. Its author or an owner or admin does this.
  Future<void> deleteServiceRequest(String tourId, String requestId) async {
    _requireEmail();
    await _sub(tourId, 'service_requests').doc(requestId).delete();
  }

  // ---------------------------------------------------------------------------
  // Samity (rotating savings group)
  // ---------------------------------------------------------------------------

  /// Saves the schedule on the tour. The rules let only an owner or admin do this, and
  /// only on a samity.
  Future<void> saveSamityConfig(String tourId, SamityConfig config) async {
    _requireEmail();
    await _tour(tourId).update({'samity': config.toMap()});
  }

  /// Every payment recorded in the samity. A stored record that does not read is left out.
  Stream<List<SamityPayment>> watchSamityPayments(String tourId) {
    return _sub(tourId, 'samity_payments').limit(3000).snapshots().map((s) => [
          for (final d in s.docs)
            if (SamityPayment.fromMap(d.data()) case final payment?) payment,
        ]);
  }

  /// Records what has been paid into a cycle so far. A member records their own; an
  /// owner or admin records anyone's.
  Future<void> saveSamityPayment(String tourId, SamityPayment payment) async {
    final by = _requireEmail();
    await _sub(tourId, 'samity_payments').doc(payment.id).set({
      ...payment.toFields(by),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Removes a payment record. The member it belongs to or an owner or admin does this.
  Future<void> deleteSamityPayment(String tourId, String paymentId) async {
    _requireEmail();
    await _sub(tourId, 'samity_payments').doc(paymentId).delete();
  }

  /// Every handover recorded in the samity, one per cycle at most.
  Stream<List<SamityPayout>> watchSamityPayouts(String tourId) {
    return _sub(tourId, 'samity_payouts').limit(300).snapshots().map((s) => [
          for (final d in s.docs)
            if (SamityPayout.fromMap(d.data()) case final payout?) payout,
        ]);
  }

  /// Records that a cycle's pot was handed to its recipient. Only an owner or admin.
  Future<void> saveSamityPayout(String tourId, SamityPayout payout) async {
    final by = _requireEmail();
    await _sub(tourId, 'samity_payouts').doc(payout.cycleKey).set({
      ...payout.toFields(by),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Allows the recipient member or an admin to verify receipt of the pot handover.
  Future<void> verifySamityPayout(String tourId, String cycleKey) async {
    _requireEmail();
    await _sub(tourId, 'samity_payouts').doc(cycleKey).update({
      'isVerified': true,
      'verifiedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Removes a recorded handover, by its three-digit cycle key. Only an owner or admin.
  Future<void> deleteSamityPayout(String tourId, String cycleKey) async {
    _requireEmail();
    await _sub(tourId, 'samity_payouts').doc(cycleKey).delete();
  }

  Future<void> deleteFamilyTask(String tourId, String taskId) async {
    _requireEmail();
    await _sub(tourId, 'family_tasks').doc(taskId).delete();
  }

  // ---------------------------------------------------------------------------
  // Study groups: the shared book list and the reading plan (study_models.dart).
  // The rules in firestore.rules say who may write each of these.
  // ---------------------------------------------------------------------------

  Stream<List<StudyBook>> watchStudyBooks(String tourId) {
    return _sub(tourId, 'study_books').limit(300).snapshots().map((s) => [
          for (final d in s.docs)
            if (StudyBook.fromMap(d.id, d.data()) case final book?) book,
        ]);
  }

  /// Adds a book to the list. An admin lists it at once; a member's book is a proposal
  /// until an admin lists it or declines it. The signed-in member is recorded as its
  /// creator and as the one who set its status.
  Future<void> addStudyBook(
    String tourId, {
    required String title,
    required StudyBookApproval approval,
    String author = '',
    String notes = '',
    StudyBookStatus status = StudyBookStatus.toRead,
  }) async {
    final email = _requireEmail();
    final book = StudyBook(
      id: '',
      title: title.trim(),
      author: author.trim(),
      notes: notes.trim(),
      status: status,
      createdByEmail: email,
      statusByEmail: email,
      approval: approval,
    );
    await _sub(tourId, 'study_books').add(book.toFields());
  }

  /// Moves a listed book to another status. Any member may do this, and the change is
  /// recorded under the signed-in member's name.
  Future<void> setStudyBookStatus(
    String tourId,
    String bookId,
    StudyBookStatus status,
  ) async {
    final email = _requireEmail();
    await _sub(tourId, 'study_books').doc(bookId).update({
      'status': status.name,
      'statusByEmail': email,
    });
  }

  /// Changes a book's details. Its creator or an admin does this. A new status is
  /// recorded under the signed-in member's name, and the old name stays otherwise.
  Future<void> editStudyBook(
    String tourId,
    StudyBook original, {
    required String title,
    required String author,
    required String notes,
    required StudyBookStatus status,
  }) async {
    final email = _requireEmail();
    final cleanAuthor = author.trim();
    final cleanNotes = notes.trim();
    await _sub(tourId, 'study_books').doc(original.id).update({
      'title': title.trim(),
      'author': cleanAuthor.isEmpty ? null : cleanAuthor,
      'notes': cleanNotes.isEmpty ? null : cleanNotes,
      'status': status.name,
      'statusByEmail':
          status == original.status ? original.statusByEmail : email,
    });
  }

  Future<void> deleteStudyBook(String tourId, String bookId) async {
    _requireEmail();
    await _sub(tourId, 'study_books').doc(bookId).delete();
  }

  /// Lists a proposed or declined book. Only an admin does this. The note of a declined
  /// book goes, since the book is on the list.
  Future<void> approveStudyBook(String tourId, String bookId) async {
    _requireEmail();
    await _sub(tourId, 'study_books').doc(bookId).update({
      'approval': StudyBookApproval.listed.name,
      'declineNote': FieldValue.delete(),
    });
  }

  /// Declines a proposed book, with an optional note for the person who proposed it. Only
  /// an admin does this.
  Future<void> declineStudyBook(
    String tourId,
    String bookId, {
    String note = '',
  }) async {
    _requireEmail();
    final cleanNote = note.trim();
    await _sub(tourId, 'study_books').doc(bookId).update({
      'approval': StudyBookApproval.declined.name,
      'declineNote': cleanNote.isEmpty ? FieldValue.delete() : cleanNote,
    });
  }

  // ---------------------------------------------------------------------------
  // Study subjects: the modules of each subject and the posts in them
  // (study_subject_models.dart). The rules in firestore.rules say who may write each.
  // ---------------------------------------------------------------------------

  /// Turns stored timestamps into dates, so the models read plain values.
  Map<String, dynamic> _datesAsDateTimes(Map<String, dynamic> data) => {
        for (final entry in data.entries)
          entry.key: entry.value is Timestamp
              ? (entry.value as Timestamp).toDate()
              : entry.value,
      };

  Map<StudyModuleKey, StudyModuleSettings> _modulesFrom(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final result = <StudyModuleKey, StudyModuleSettings>{};
    for (final doc in snap.docs) {
      final key = StudyModuleKey.fromName(doc.id);
      if (key == null) continue;
      final settings = StudyModuleSettings.fromMap(key, doc.data());
      if (settings != null) result[key] = settings;
    }
    return result;
  }

  Stream<List<StudySubject>> watchStudySubjects(String tourId) {
    return _sub(tourId, 'study_subjects').limit(200).snapshots().map((s) => [
          for (final d in s.docs)
            if (StudySubject.fromMap(d.id, _datesAsDateTimes(d.data()))
                case final subject?)
              subject,
        ]);
  }

  /// Adds a subject. An admin lists it at once; a member's subject waits for an admin.
  Future<void> addStudySubject(
    String tourId, {
    required String title,
    required StudyBookApproval approval,
    String code = '',
    String description = '',
    DateTime? examDate,
  }) async {
    final email = _requireEmail();
    final subject = StudySubject(
      id: '',
      title: title.trim(),
      code: code.trim(),
      description: description.trim(),
      examDate: examDate,
      approval: approval,
      createdByEmail: email,
    );
    await _sub(tourId, 'study_subjects').add(subject.toFields());
  }

  /// Changes a subject's details. Its creator or an admin does this.
  Future<void> editStudySubject(
    String tourId,
    StudySubject original, {
    required String title,
    required String code,
    required String description,
    required DateTime? examDate,
  }) async {
    _requireEmail();
    await _sub(tourId, 'study_subjects').doc(original.id).update({
      'title': title.trim(),
      'code': code.trim().isEmpty ? null : code.trim(),
      'description': description.trim().isEmpty ? null : description.trim(),
      'examDate': examDate,
    });
  }

  /// Lists a proposed or declined subject. Only an admin does this.
  Future<void> approveStudySubject(String tourId, String subjectId) async {
    _requireEmail();
    await _sub(tourId, 'study_subjects').doc(subjectId).update({
      'approval': StudyBookApproval.listed.name,
      'declineNote': FieldValue.delete(),
    });
  }

  /// Declines a proposed subject, with an optional note for the person who proposed it.
  /// Only an admin does this.
  Future<void> declineStudySubject(
    String tourId,
    String subjectId, {
    String note = '',
  }) async {
    _requireEmail();
    final clean = note.trim();
    await _sub(tourId, 'study_subjects').doc(subjectId).update({
      'approval': StudyBookApproval.declined.name,
      'declineNote': clean.isEmpty ? FieldValue.delete() : clean,
    });
  }

  /// The modules of a subject, by key. A module with no stored settings is off.
  Stream<Map<StudyModuleKey, StudyModuleSettings>> watchStudyModules(
    String tourId,
    String subjectId,
  ) {
    return _sub(tourId, 'study_subjects')
        .doc(subjectId)
        .collection('modules')
        .snapshots()
        .map(_modulesFrom);
  }

  /// Turns a module on or off, renames it, or changes who may post in it. Only an admin does
  /// this.
  Future<void> setStudyModule(
    String tourId,
    String subjectId,
    StudyModuleSettings settings,
  ) async {
    _requireEmail();
    await _sub(tourId, 'study_subjects')
        .doc(subjectId)
        .collection('modules')
        .doc(settings.key.name)
        .set(settings.toFields());
  }

  /// The posts in one module of a subject, newest first.
  Stream<List<StudyPost>> watchStudyPosts(
    String tourId,
    String subjectId,
    StudyModuleKey key,
  ) {
    return _sub(tourId, 'study_subjects')
        .doc(subjectId)
        .collection(key.name)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((s) => [
              for (final d in s.docs)
                if (StudyPost.fromMap(d.id, _datesAsDateTimes(d.data()))
                    case final post?)
                  post,
            ]);
  }

  /// Adds a post to a module. [shown] is false for a post an admin still has to show.
  Future<void> addStudyPost(
    String tourId,
    String subjectId,
    StudyModuleKey key, {
    required String text,
    required bool shown,
    String title = '',
    String url = '',
  }) async {
    final email = _requireEmail();
    await _sub(tourId, 'study_subjects')
        .doc(subjectId)
        .collection(key.name)
        .add({
      'text': text.trim(),
      'title': title.trim().isEmpty ? null : title.trim(),
      'url': url.trim().isEmpty ? null : url.trim(),
      'createdByEmail': email,
      'createdAt': FieldValue.serverTimestamp(),
      'helpfulCount': 0,
      'shown': shown,
      'pinned': false,
    });
  }

  /// Changes a post's words. Its author does this.
  Future<void> editStudyPost(
    String tourId,
    String subjectId,
    StudyModuleKey key,
    StudyPost original, {
    required String text,
    String title = '',
    String url = '',
  }) async {
    _requireEmail();
    await _sub(tourId, 'study_subjects')
        .doc(subjectId)
        .collection(key.name)
        .doc(original.id)
        .update({
      'text': text.trim(),
      'title': title.trim().isEmpty ? null : title.trim(),
      'url': url.trim().isEmpty ? null : url.trim(),
    });
  }

  /// Shows a waiting post to members, or pins or unpins a post. Only an admin does this.
  Future<void> setStudyPostFlags(
    String tourId,
    String subjectId,
    StudyModuleKey key,
    String postId, {
    bool? shown,
    bool? pinned,
  }) async {
    _requireEmail();
    await _sub(tourId, 'study_subjects')
        .doc(subjectId)
        .collection(key.name)
        .doc(postId)
        .update({
      if (shown != null) 'shown': shown,
      if (pinned != null) 'pinned': pinned,
    });
  }

  /// Removes a post. Its author or an admin does this.
  Future<void> deleteStudyPost(
    String tourId,
    String subjectId,
    StudyModuleKey key,
    String postId,
  ) async {
    _requireEmail();
    await _sub(tourId, 'study_subjects')
        .doc(subjectId)
        .collection(key.name)
        .doc(postId)
        .delete();
  }

  /// Marks a post helpful, or takes the mark back when it is already marked. The mark and the
  /// count change in one batch. Returns true when the post is marked afterwards.
  Future<bool> toggleStudyPostHelpful(
    String tourId,
    String subjectId,
    StudyModuleKey key,
    String postId,
  ) async {
    final email = _requireEmail();
    final post = _sub(tourId, 'study_subjects')
        .doc(subjectId)
        .collection(key.name)
        .doc(postId);
    final mark = post.collection('helpful').doc(email);
    final existing = await mark.get();
    final batch = _firestore.batch();
    if (existing.exists) {
      batch.delete(mark);
      batch.update(post, {'helpfulCount': FieldValue.increment(-1)});
      await batch.commit();
      return false;
    }
    batch.set(mark, {'createdAt': FieldValue.serverTimestamp()});
    batch.update(post, {'helpfulCount': FieldValue.increment(1)});
    await batch.commit();
    return true;
  }

  // Shared findings: a result a member reached and how it was checked. Others confirm or
  // challenge it, once each. A check and the count it moves are written in one batch, which
  // firestore.rules checks (study_finding_models.dart).
  // ---------------------------------------------------------------------------

  /// A finding's document in a subject.
  DocumentReference<Map<String, dynamic>> _findingRef(
    String tourId,
    String subjectId,
    String findingId,
  ) =>
      _sub(tourId, 'study_subjects')
          .doc(subjectId)
          .collection('findings')
          .doc(findingId);

  /// The findings of a subject, newest first.
  Stream<List<StudyFinding>> watchStudyFindings(
    String tourId,
    String subjectId,
  ) {
    return _sub(tourId, 'study_subjects')
        .doc(subjectId)
        .collection('findings')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((s) => [
              for (final d in s.docs)
                if (StudyFinding.fromMap(d.id, _datesAsDateTimes(d.data()))
                    case final finding?)
                  finding,
            ]);
  }

  /// The signed-in member's own check of each listed finding, by finding id. A finding the
  /// member has not checked has no entry.
  Future<Map<String, StudyFindingCheck>> loadMyFindingChecks(
    String tourId,
    String subjectId,
    List<String> findingIds,
  ) async {
    final email = _requireEmail();
    final snaps = await Future.wait([
      for (final id in findingIds)
        _findingRef(tourId, subjectId, id)
            .collection('checks')
            .doc(email)
            .get(),
    ]);
    final checks = <String, StudyFindingCheck>{};
    for (var i = 0; i < findingIds.length; i++) {
      final snap = snaps[i];
      if (!snap.exists) continue;
      final check = StudyFindingCheck.fromMap(email, snap.data() ?? const {});
      if (check != null) checks[findingIds[i]] = check;
    }
    return checks;
  }

  /// Posts a finding. [shown] is false for a finding an admin still has to show.
  Future<void> addStudyFinding(
    String tourId,
    String subjectId, {
    required String text,
    required String method,
    required bool shown,
  }) async {
    final email = _requireEmail();
    await _sub(tourId, 'study_subjects')
        .doc(subjectId)
        .collection('findings')
        .add({
      'text': text.trim(),
      'method': method.trim(),
      'createdByEmail': email,
      'createdAt': FieldValue.serverTimestamp(),
      'confirmCount': 0,
      'challengeCount': 0,
      'shown': shown,
      'pinned': false,
    });
  }

  /// Changes a finding's result or its method. Its author does this.
  Future<void> editStudyFinding(
    String tourId,
    String subjectId,
    StudyFinding original, {
    required String text,
    required String method,
  }) async {
    _requireEmail();
    await _findingRef(tourId, subjectId, original.id).update({
      'text': text.trim(),
      'method': method.trim(),
    });
  }

  /// Shows a waiting finding, or pins or unpins one. Only an admin does this.
  Future<void> setStudyFindingFlags(
    String tourId,
    String subjectId,
    String findingId, {
    bool? shown,
    bool? pinned,
  }) async {
    _requireEmail();
    await _findingRef(tourId, subjectId, findingId).update({
      if (shown != null) 'shown': shown,
      if (pinned != null) 'pinned': pinned,
    });
  }

  /// Removes a finding. Its author or an admin does this. Its checks stay in the database,
  /// unread, as the marks of a deleted post do.
  Future<void> deleteStudyFinding(
    String tourId,
    String subjectId,
    String findingId,
  ) async {
    _requireEmail();
    await _findingRef(tourId, subjectId, findingId).delete();
  }

  /// Confirms or challenges a finding, once per member. The check and the count it moves are
  /// written in one batch. The note is optional and is kept only when it has words.
  Future<void> checkStudyFinding(
    String tourId,
    String subjectId,
    String findingId, {
    required FindingVerdict verdict,
    String note = '',
  }) async {
    final email = _requireEmail();
    final finding = _findingRef(tourId, subjectId, findingId);
    final cleanNote = note.trim();
    final countField =
        verdict == FindingVerdict.confirm ? 'confirmCount' : 'challengeCount';
    final batch = _firestore.batch();
    batch.set(finding.collection('checks').doc(email), {
      'verdict': verdict.name,
      if (cleanNote.isNotEmpty) 'note': cleanNote,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(finding, {countField: FieldValue.increment(1)});
    await batch.commit();
  }

  /// Takes a member's own check back. The check goes and its count falls, in one batch.
  Future<void> withdrawStudyFindingCheck(
    String tourId,
    String subjectId,
    String findingId,
    FindingVerdict verdict,
  ) async {
    final email = _requireEmail();
    final finding = _findingRef(tourId, subjectId, findingId);
    final countField =
        verdict == FindingVerdict.confirm ? 'confirmCount' : 'challengeCount';
    final batch = _firestore.batch();
    batch.delete(finding.collection('checks').doc(email));
    batch.update(finding, {countField: FieldValue.increment(-1)});
    await batch.commit();
  }

  // Problem solving: problems a group works through, each with a reference solution an admin writes
  // and the members' own working. A member sees and reviews the working only after submitting their
  // own. The rules say who may read and write each (firestore.rules).
  // ---------------------------------------------------------------------------

  /// A problem's document in a subject.
  DocumentReference<Map<String, dynamic>> _problemRef(
    String tourId,
    String subjectId,
    String problemId,
  ) =>
      _sub(tourId, 'study_subjects')
          .doc(subjectId)
          .collection('problems')
          .doc(problemId);

  /// A member's working on a problem, by the member's email.
  DocumentReference<Map<String, dynamic>> _workRef(
    String tourId,
    String subjectId,
    String problemId,
    String solverEmail,
  ) =>
      _problemRef(tourId, subjectId, problemId)
          .collection('solutions')
          .doc(solverEmail);

  /// The problems of a subject, newest first.
  Stream<List<StudyProblem>> watchStudyProblems(
    String tourId,
    String subjectId,
  ) {
    return _sub(tourId, 'study_subjects')
        .doc(subjectId)
        .collection('problems')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((s) => [
              for (final d in s.docs)
                if (StudyProblem.fromMap(d.id, _datesAsDateTimes(d.data()))
                    case final problem?)
                  problem,
            ]);
  }

  /// Adds a problem. [shown] is false for a problem an admin still has to show. [releaseAt] is when
  /// the reference solution opens to members; null leaves it unset.
  Future<void> addStudyProblem(
    String tourId,
    String subjectId, {
    required String text,
    required String title,
    required DateTime? releaseAt,
    required bool shown,
  }) async {
    final email = _requireEmail();
    await _sub(tourId, 'study_subjects')
        .doc(subjectId)
        .collection('problems')
        .add({
      'text': text.trim(),
      if (title.trim().isNotEmpty) 'title': title.trim(),
      'createdByEmail': email,
      'createdAt': FieldValue.serverTimestamp(),
      if (releaseAt != null) 'releaseAt': releaseAt,
      'shown': shown,
      'pinned': false,
    });
  }

  /// Changes a problem's words or title. Its author does this.
  Future<void> editStudyProblem(
    String tourId,
    String subjectId,
    StudyProblem original, {
    required String text,
    required String title,
  }) async {
    _requireEmail();
    await _problemRef(tourId, subjectId, original.id).update({
      'text': text.trim(),
      'title': title.trim().isEmpty ? FieldValue.delete() : title.trim(),
    });
  }

  /// Shows a waiting problem, or pins or unpins one. Only an admin does this.
  Future<void> setStudyProblemFlags(
    String tourId,
    String subjectId,
    String problemId, {
    bool? shown,
    bool? pinned,
  }) async {
    _requireEmail();
    await _problemRef(tourId, subjectId, problemId).update({
      if (shown != null) 'shown': shown,
      if (pinned != null) 'pinned': pinned,
    });
  }

  /// Sets when the reference solution opens to members, or clears the release time. Only an admin
  /// does this.
  Future<void> setStudyProblemRelease(
    String tourId,
    String subjectId,
    String problemId,
    DateTime? releaseAt,
  ) async {
    _requireEmail();
    await _problemRef(tourId, subjectId, problemId).update({
      'releaseAt': releaseAt ?? FieldValue.delete(),
    });
  }

  /// Removes a problem. Its author or an admin does this. The reference solution, the working and
  /// the reviews under it stay in the database, unread, as a deleted post's marks do.
  Future<void> deleteStudyProblem(
    String tourId,
    String subjectId,
    String problemId,
  ) async {
    _requireEmail();
    await _problemRef(tourId, subjectId, problemId).delete();
  }

  /// The reference solution of a problem, or null when there is none, or when it has not opened to
  /// this member yet. A member who may not read it yet gets an error from the server, so the caller
  /// treats an error the same way.
  Future<StudyReferenceSolution?> loadStudyReference(
    String tourId,
    String subjectId,
    String problemId,
  ) async {
    _requireEmail();
    final snap = await _problemRef(tourId, subjectId, problemId)
        .collection('reference')
        .doc('solution')
        .get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return StudyReferenceSolution.fromMap(_datesAsDateTimes(data));
  }

  /// Writes the reference solution of a problem. The admin who writes it is its reviewer, which is
  /// the mark that an admin reviewed it. Only an admin does this.
  Future<void> saveStudyReference(
    String tourId,
    String subjectId,
    String problemId, {
    required String text,
  }) async {
    final email = _requireEmail();
    await _problemRef(tourId, subjectId, problemId)
        .collection('reference')
        .doc('solution')
        .set({
      'text': text.trim(),
      'reviewedByEmail': email,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Removes the reference solution of a problem. Only an admin does this.
  Future<void> deleteStudyReference(
    String tourId,
    String subjectId,
    String problemId,
  ) async {
    _requireEmail();
    await _problemRef(tourId, subjectId, problemId)
        .collection('reference')
        .doc('solution')
        .delete();
  }

  /// The signed-in member's own working on each listed problem, by problem id. A problem the
  /// member has not worked on has no entry.
  Future<Map<String, StudyProblemSolution>> loadMyWork(
    String tourId,
    String subjectId,
    List<String> problemIds,
  ) async {
    final email = _requireEmail();
    final snaps = await Future.wait([
      for (final id in problemIds) _workRef(tourId, subjectId, id, email).get(),
    ]);
    final work = <String, StudyProblemSolution>{};
    for (var i = 0; i < problemIds.length; i++) {
      final snap = snaps[i];
      if (!snap.exists) continue;
      final solution = StudyProblemSolution.fromMap(
        email,
        _datesAsDateTimes(snap.data() ?? const {}),
      );
      if (solution != null) work[problemIds[i]] = solution;
    }
    return work;
  }

  /// The working of a problem's members, newest first. The rules let a member read it only after
  /// they have submitted their own working, so the caller subscribes only then.
  Stream<List<StudyProblemSolution>> watchStudyWork(
    String tourId,
    String subjectId,
    String problemId,
  ) {
    return _problemRef(tourId, subjectId, problemId)
        .collection('solutions')
        .orderBy('updatedAt', descending: true)
        .limit(200)
        .snapshots()
        .map((s) => [
              for (final d in s.docs)
                if (StudyProblemSolution.fromMap(
                        d.id, _datesAsDateTimes(d.data()))
                    case final work?)
                  work,
            ]);
  }

  /// Submits the signed-in member's working on a problem. There is one working per member, so a
  /// second submission is refused; the member edits it instead.
  Future<void> submitStudyWork(
    String tourId,
    String subjectId,
    String problemId, {
    required String text,
  }) async {
    final email = _requireEmail();
    await _workRef(tourId, subjectId, problemId, email).set({
      'text': text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'rightCount': 0,
      'gapCount': 0,
    });
  }

  /// Changes the signed-in member's own working on a problem.
  Future<void> editStudyWork(
    String tourId,
    String subjectId,
    String problemId, {
    required String text,
  }) async {
    final email = _requireEmail();
    await _workRef(tourId, subjectId, problemId, email).update({
      'text': text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// The signed-in member's own review of each listed working, by the solver's email. A working the
  /// member has not reviewed has no entry.
  Future<Map<String, StudyWorkReview>> loadMyWorkReviews(
    String tourId,
    String subjectId,
    String problemId,
    List<String> solverEmails,
  ) async {
    final email = _requireEmail();
    final snaps = await Future.wait([
      for (final solver in solverEmails)
        _workRef(tourId, subjectId, problemId, solver)
            .collection('reviews')
            .doc(email)
            .get(),
    ]);
    final reviews = <String, StudyWorkReview>{};
    for (var i = 0; i < solverEmails.length; i++) {
      final snap = snaps[i];
      if (!snap.exists) continue;
      final review = StudyWorkReview.fromMap(email, snap.data() ?? const {});
      if (review != null) reviews[solverEmails[i]] = review;
    }
    return reviews;
  }

  /// Gives a verdict on a peer's working, once per member. The review and the count it moves are
  /// written in one batch.
  Future<void> reviewStudyWork(
    String tourId,
    String subjectId,
    String problemId,
    String solverEmail, {
    required WorkVerdict verdict,
    String note = '',
  }) async {
    final email = _requireEmail();
    final work = _workRef(tourId, subjectId, problemId, solverEmail);
    final cleanNote = note.trim();
    final countField = verdict == WorkVerdict.right ? 'rightCount' : 'gapCount';
    final batch = _firestore.batch();
    batch.set(work.collection('reviews').doc(email), {
      'verdict': verdict.name,
      if (cleanNote.isNotEmpty) 'note': cleanNote,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(work, {countField: FieldValue.increment(1)});
    await batch.commit();
  }

  /// Takes the signed-in member's own review of a working back. The review goes and its count
  /// falls, in one batch.
  Future<void> withdrawStudyWorkReview(
    String tourId,
    String subjectId,
    String problemId,
    String solverEmail,
    WorkVerdict verdict,
  ) async {
    final email = _requireEmail();
    final work = _workRef(tourId, subjectId, problemId, solverEmail);
    final countField = verdict == WorkVerdict.right ? 'rightCount' : 'gapCount';
    final batch = _firestore.batch();
    batch.delete(work.collection('reviews').doc(email));
    batch.update(work, {countField: FieldValue.increment(-1)});
    await batch.commit();
  }

  Stream<List<ReadingSession>> watchReadingSessions(String tourId) {
    return _sub(tourId, 'reading_sessions').limit(300).snapshots().map((s) => [
          for (final d in s.docs)
            if (ReadingSession.fromMap(d.id, _sessionFields(d.data()))
                case final session?)
              session,
        ]);
  }

  /// The stored fields of a session with its start read as a [DateTime], which is what
  /// the model expects.
  Map<String, dynamic> _sessionFields(Map<String, dynamic> data) => {
        ...data,
        'startsAt': (data['startsAt'] as Timestamp?)?.toDate(),
        'timerStartsAt': (data['timerStartsAt'] as Timestamp?)?.toDate(),
      };

  /// Plans a session. The signed-in member is recorded as its creator.
  Future<void> addReadingSession(
    String tourId, {
    required String title,
    required DateTime startsAt,
    String? bookId,
    List<String> chapterIds = const [],
    String place = '',
    String notes = '',
  }) async {
    final email = _requireEmail();
    final session = ReadingSession(
      id: '',
      title: title.trim(),
      startsAt: startsAt,
      bookId: bookId,
      chapterIds: chapterIds,
      place: place.trim(),
      notes: notes.trim(),
      createdByEmail: email,
    );
    await _sub(tourId, 'reading_sessions').add(session.toFields());
  }

  /// Changes a session. Its creator or an admin does this. Its creator is not changed.
  /// Changes a session. Its creator or an admin does this, and its creator is not changed. When the start
  /// moves, the reminders are cleared, so the media server sends them again for the new time.
  Future<void> editReadingSession(
    String tourId,
    ReadingSession session, {
    bool startChanged = false,
  }) async {
    _requireEmail();
    final place = session.place.trim();
    final notes = session.notes.trim();
    final update = <String, dynamic>{
      'title': session.title.trim(),
      'startsAt': session.startsAt,
      'bookId': session.bookId,
      'chapterIds': session.chapterIds.isEmpty ? null : session.chapterIds,
      'place': place.isEmpty ? null : place,
      'notes': notes.isEmpty ? null : notes,
    };
    if (startChanged) {
      update['reminder24Sent'] = FieldValue.delete();
      update['reminder30Sent'] = FieldValue.delete();
    }
    await _sub(tourId, 'reading_sessions').doc(session.id).update(update);
  }

  Future<void> deleteReadingSession(String tourId, String sessionId) async {
    _requireEmail();
    await _sub(tourId, 'reading_sessions').doc(sessionId).delete();
  }

  // Reading sessions, Phase 4: each member's answer and check-in, the shared focus timer, the agenda and
  // link, and the recap. The rules in firestore.rules say who may write each one.

  /// The answers to a session, with each check-in as a [DateTime].
  Stream<List<StudySessionRsvp>> watchSessionRsvps(
    String tourId,
    String sessionId,
  ) {
    return _sub(tourId, 'reading_sessions')
        .doc(sessionId)
        .collection('rsvps')
        .limit(300)
        .snapshots()
        .map((s) => [
              for (final d in s.docs)
                if (StudySessionRsvp.fromMap(d.id, {
                  ...d.data(),
                  'checkedInAt':
                      (d.data()['checkedInAt'] as Timestamp?)?.toDate(),
                })
                    case final answer?)
                  answer,
            ]);
  }

  /// Answers a session for the signed-in member. A check-in they already made is kept.
  Future<void> setSessionAnswer(
    String tourId,
    String sessionId,
    StudySessionResponse response,
  ) async {
    final email = _requireEmail();
    await _sub(tourId, 'reading_sessions')
        .doc(sessionId)
        .collection('rsvps')
        .doc(email)
        .set({
      'response': response.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Marks the signed-in member present. The session must have started, which the rules check. A member who
  /// has not answered yet is recorded as going.
  Future<void> checkInToSession(String tourId, String sessionId) async {
    final email = _requireEmail();
    final answer = _sub(tourId, 'reading_sessions')
        .doc(sessionId)
        .collection('rsvps')
        .doc(email);
    final existing = await answer.get();
    await answer.set({
      'response':
          existing.data()?['response'] ?? StudySessionResponse.going.name,
      'checkedInAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Starts the shared focus timer for [seconds], from now. Its creator or an admin does this.
  Future<void> startSessionTimer(
    String tourId,
    String sessionId, {
    required int seconds,
  }) async {
    _requireEmail();
    await _sub(tourId, 'reading_sessions').doc(sessionId).update({
      'timerStartsAt': FieldValue.serverTimestamp(),
      'timerSeconds': seconds,
    });
  }

  /// Stops the shared focus timer. Its creator or an admin does this.
  Future<void> stopSessionTimer(String tourId, String sessionId) async {
    _requireEmail();
    await _sub(tourId, 'reading_sessions').doc(sessionId).update({
      'timerStartsAt': FieldValue.delete(),
      'timerSeconds': FieldValue.delete(),
    });
  }

  /// Writes the agenda and the meeting link. An empty value is removed. Its creator or an admin does this.
  Future<void> setSessionDetails(
    String tourId,
    String sessionId, {
    required String agenda,
    required String link,
  }) async {
    _requireEmail();
    final trimmedAgenda = agenda.trim();
    final trimmedLink = link.trim();
    await _sub(tourId, 'reading_sessions').doc(sessionId).update({
      'agenda': trimmedAgenda.isEmpty ? FieldValue.delete() : trimmedAgenda,
      'link': trimmedLink.isEmpty ? FieldValue.delete() : trimmedLink,
    });
  }

  /// Writes the recap of a session, and starts a thread on the session's book for each of [newQuestions]: the
  /// questions that were not in the recap before, so saving again does not repeat them. A session with no
  /// book keeps its questions in the recap only. Its creator or an admin does this.
  Future<void> saveSessionRecap(
    String tourId,
    ReadingSession session,
    StudySessionRecap recap, {
    required List<String> newQuestions,
  }) async {
    _requireEmail();
    await _sub(tourId, 'reading_sessions').doc(session.id).update({
      'recap': recap.toFields(),
      'recapAt': FieldValue.serverTimestamp(),
    });
    final bookId = session.bookId;
    if (bookId == null) return;
    for (final question in newQuestions) {
      final title = question.length > StudySessionLimits.threadTitleMax
          ? question.substring(0, StudySessionLimits.threadTitleMax)
          : question;
      await addStudyThread(tourId, bookId, title: title, body: question);
    }
  }

  // ---------------------------------------------------------------------------
  // Study books: votes on a proposal, chapters, read marks and the reading pace.
  // The rules in firestore.rules say who may write each; the dates come from
  // study_chapter_rules.dart.
  // ---------------------------------------------------------------------------

  DocumentReference<Map<String, dynamic>> _studyBookDoc(
    String tourId,
    String bookId,
  ) =>
      _sub(tourId, 'study_books').doc(bookId);

  DocumentReference<Map<String, dynamic>> _readMarkDoc(
    String tourId,
    String bookId,
    String chapterId,
    String email,
  ) =>
      _studyBookDoc(tourId, bookId)
          .collection('chapters')
          .doc(chapterId)
          .collection('reads')
          .doc(email);

  /// How many members would read a proposed book, and whether the signed-in member is one.
  Stream<StudyVoteTally> watchStudyBookVotes(String tourId, String bookId) {
    final me = currentEmail;
    return _studyBookDoc(tourId, bookId)
        .collection('votes')
        .limit(500)
        .snapshots()
        .map((s) => StudyVoteTally(
              count: s.docs.length,
              mine: s.docs.any((d) => d.id == me),
            ));
  }

  /// Says that the signed-in member would read a proposed book, or takes that back.
  Future<void> setStudyBookVote(
    String tourId,
    String bookId, {
    required bool voted,
  }) async {
    final email = _requireEmail();
    final vote = _studyBookDoc(tourId, bookId).collection('votes').doc(email);
    if (voted) {
      await vote.set({'createdAt': FieldValue.serverTimestamp()});
    } else {
      await vote.delete();
    }
  }

  /// The chapters of a book, in no particular order; sort them with sortStudyChapters.
  Stream<List<StudyChapter>> watchStudyChapters(String tourId, String bookId) {
    return _studyBookDoc(tourId, bookId)
        .collection('chapters')
        .limit(200)
        .snapshots()
        .map((s) => [
              for (final d in s.docs)
                if (StudyChapter.fromMap(d.id, _datesAsDateTimes(d.data()))
                    case final chapter?)
                  chapter,
            ]);
  }

  /// Adds a chapter to a book. Only an admin does this.
  Future<void> addStudyChapter(
    String tourId,
    String bookId,
    StudyChapter chapter,
  ) async {
    _requireEmail();
    await _studyBookDoc(tourId, bookId)
        .collection('chapters')
        .add(chapter.toFields());
  }

  /// Changes a chapter's number, title, pages, due date or guide questions. Only an admin
  /// does this.
  Future<void> editStudyChapter(
    String tourId,
    String bookId,
    StudyChapter chapter,
  ) async {
    _requireEmail();
    await _studyBookDoc(tourId, bookId)
        .collection('chapters')
        .doc(chapter.id)
        .update(chapter.toFields());
  }

  /// Removes a chapter. Only an admin does this. Other members' read marks under it are not
  /// removed with it, since the rules let each member remove only their own.
  Future<void> deleteStudyChapter(
    String tourId,
    String bookId,
    String chapterId,
  ) async {
    _requireEmail();
    await _studyBookDoc(tourId, bookId)
        .collection('chapters')
        .doc(chapterId)
        .delete();
  }

  /// Sets every chapter's due date from a start date and a number of chapters a week. The
  /// chapters are taken in reading order, so the first ones fall due first. Only an admin
  /// does this, and any date can be changed afterwards.
  Future<void> setStudyReadingPace(
    String tourId,
    String bookId, {
    required List<StudyChapter> chapters,
    required DateTime start,
    required int perWeek,
  }) async {
    _requireEmail();
    final ordered = sortStudyChapters(chapters);
    final dues =
        chapterDueDates(start: start, perWeek: perWeek, count: ordered.length);
    final batch = _firestore.batch();
    final col = _studyBookDoc(tourId, bookId).collection('chapters');
    for (var i = 0; i < ordered.length; i++) {
      batch.update(col.doc(ordered[i].id), {'dueOn': dues[i]});
    }
    await batch.commit();
  }

  /// The signed-in member's read marks on a book's chapters, by chapter id. It follows the
  /// chapters as they change and each mark as it is made or taken back. A member who is not
  /// signed in gets an empty map.
  Stream<Map<String, StudyReadMark>> watchMyReadMarks(
    String tourId,
    String bookId,
  ) {
    final email = currentEmail;
    final controller = StreamController<Map<String, StudyReadMark>>();
    final marks = <String, StudyReadMark>{};
    final perChapter =
        <String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? chapters;

    void emit() {
      if (!controller.isClosed) controller.add(Map.of(marks));
    }

    controller
      ..onListen = () {
        if (email.isEmpty) {
          emit();
          return;
        }
        chapters = _studyBookDoc(tourId, bookId)
            .collection('chapters')
            .limit(200)
            .snapshots()
            .listen((snap) {
          final ids = {for (final d in snap.docs) d.id};
          for (final gone
              in perChapter.keys.where((id) => !ids.contains(id)).toList()) {
            perChapter.remove(gone)?.cancel();
            marks.remove(gone);
          }
          for (final id in ids) {
            perChapter.putIfAbsent(id, () {
              return _readMarkDoc(tourId, bookId, id, email).snapshots().listen(
                  (doc) {
                if (doc.exists) {
                  marks[id] = StudyReadMark.fromMap(
                    id,
                    _datesAsDateTimes(doc.data() ?? const {}),
                  );
                } else {
                  marks.remove(id);
                }
                emit();
              }, onError: controller.addError);
            });
          }
          emit();
        }, onError: controller.addError);
      }
      ..onCancel = () {
        chapters?.cancel();
        for (final sub in perChapter.values) {
          sub.cancel();
        }
        perChapter.clear();
      };
    return controller.stream;
  }

  /// Marks a chapter read in the signed-in member's own name. A counted mark joins the group
  /// total; an uncounted one stays private to its member.
  Future<void> markStudyChapterRead(
    String tourId,
    String bookId,
    String chapterId, {
    required bool counted,
  }) async {
    final email = _requireEmail();
    await _readMarkDoc(tourId, bookId, chapterId, email).set({
      'readAt': FieldValue.serverTimestamp(),
      'counted': counted,
    });
  }

  /// Changes whether the member's read mark counts towards the group total.
  Future<void> setStudyChapterReadCounted(
    String tourId,
    String bookId,
    String chapterId, {
    required bool counted,
  }) async {
    final email = _requireEmail();
    await _readMarkDoc(tourId, bookId, chapterId, email)
        .update({'counted': counted});
  }

  /// Takes the member's read mark back.
  Future<void> unmarkStudyChapterRead(
    String tourId,
    String bookId,
    String chapterId,
  ) async {
    final email = _requireEmail();
    await _readMarkDoc(tourId, bookId, chapterId, email).delete();
  }

  // ---------------------------------------------------------------------------
  // Discussions: threads on a book, their replies, helpful votes, reports, the accepted answer,
  // pins and locks (study_thread_models.dart). The rules in firestore.rules say who may write
  // each one.
  // ---------------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _threadsCol(
    String tourId,
    String bookId,
  ) =>
      _studyBookDoc(tourId, bookId).collection('threads');

  DocumentReference<Map<String, dynamic>> _threadDoc(
    String tourId,
    String bookId,
    String threadId,
  ) =>
      _threadsCol(tourId, bookId).doc(threadId);

  DocumentReference<Map<String, dynamic>> _replyDoc(
    String tourId,
    String bookId,
    String threadId,
    String replyId,
  ) =>
      _threadDoc(tourId, bookId, threadId).collection('replies').doc(replyId);

  /// The threads of a book, in no particular order; sort them with sortStudyThreads.
  Stream<List<StudyThread>> watchStudyThreads(String tourId, String bookId) {
    return _threadsCol(tourId, bookId).limit(300).snapshots().map((s) => [
          for (final d in s.docs)
            if (StudyThread.fromMap(d.id, _datesAsDateTimes(d.data()))
                case final thread?)
              thread,
        ]);
  }

  /// Starts a thread on a book. The signed-in member is its author.
  Future<void> addStudyThread(
    String tourId,
    String bookId, {
    required String title,
    required String body,
    String? chapterId,
    String pageRef = '',
  }) async {
    final email = _requireEmail();
    final thread = StudyThread(
      id: '',
      title: title.trim(),
      body: body.trim(),
      pageRef: pageRef.trim(),
      chapterId: chapterId,
      createdByEmail: email,
    );
    await _threadsCol(tourId, bookId).add({
      ...thread.toFields(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// The replies of a thread, oldest first.
  Stream<List<StudyReply>> watchStudyReplies(
    String tourId,
    String bookId,
    String threadId,
  ) {
    return _threadDoc(tourId, bookId, threadId)
        .collection('replies')
        .orderBy('createdAt')
        .limit(500)
        .snapshots()
        .map((s) => [
              for (final d in s.docs)
                if (StudyReply.fromMap(d.id, _datesAsDateTimes(d.data()))
                    case final reply?)
                  reply,
            ]);
  }

  /// Adds a reply under an id the app made, so a reply sent again after being written offline
  /// arrives once. The signed-in member is its author.
  Future<void> addStudyReply(
    String tourId,
    String bookId,
    String threadId, {
    required String replyId,
    required String text,
  }) async {
    final email = _requireEmail();
    final reply =
        StudyReply(id: replyId, text: text.trim(), createdByEmail: email);
    await _replyDoc(tourId, bookId, threadId, replyId).set({
      ...reply.toFields(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Marks a reply helpful, or takes the mark back. The mark and the count change in one batch.
  /// Returns true when the reply is marked afterwards.
  Future<bool> toggleStudyReplyHelpful(
    String tourId,
    String bookId,
    String threadId,
    String replyId,
  ) async {
    final email = _requireEmail();
    final reply = _replyDoc(tourId, bookId, threadId, replyId);
    final mark = reply.collection('helpful').doc(email);
    final existing = await mark.get();
    final batch = _firestore.batch();
    if (existing.exists) {
      batch.delete(mark);
      batch.update(reply, {'helpfulCount': FieldValue.increment(-1)});
      await batch.commit();
      return false;
    }
    batch.set(mark, {'createdAt': FieldValue.serverTimestamp()});
    batch.update(reply, {'helpfulCount': FieldValue.increment(1)});
    await batch.commit();
    return true;
  }

  /// Reports a reply, once for each member. The report and the count change in one batch.
  Future<void> reportStudyReply(
    String tourId,
    String bookId,
    String threadId,
    String replyId, {
    required StudyReportReason reason,
  }) async {
    final email = _requireEmail();
    final reply = _replyDoc(tourId, bookId, threadId, replyId);
    final batch = _firestore.batch();
    batch.set(reply.collection('reports').doc(email), {
      'reason': reason.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(reply, {'reportCount': FieldValue.increment(1)});
    await batch.commit();
  }

  /// Accepts a reply as the answer, or takes the acceptance back when [replyId] is null. The
  /// member who asked, or an admin, does this.
  Future<void> setStudyAcceptedAnswer(
    String tourId,
    String bookId,
    String threadId, {
    String? replyId,
  }) async {
    _requireEmail();
    await _threadDoc(tourId, bookId, threadId)
        .update({'acceptedReplyId': replyId});
  }

  /// Pins a thread to the top of the book, or unpins it. Only an admin does this.
  Future<void> setStudyThreadPinned(
    String tourId,
    String bookId,
    String threadId, {
    required bool pinned,
  }) async {
    _requireEmail();
    await _threadDoc(tourId, bookId, threadId).update({'pinned': pinned});
  }

  /// Locks a thread, so it takes no more replies, or unlocks it. Only an admin does this.
  Future<void> setStudyThreadLocked(
    String tourId,
    String bookId,
    String threadId, {
    required bool locked,
  }) async {
    _requireEmail();
    await _threadDoc(tourId, bookId, threadId).update({'locked': locked});
  }

  /// Removes a reply. Its author or an admin does this. When the reply was the accepted answer,
  /// the acceptance goes with it in the same batch.
  Future<void> deleteStudyReply(
    String tourId,
    String bookId,
    String threadId,
    String replyId, {
    required bool wasAccepted,
  }) async {
    _requireEmail();
    final batch = _firestore.batch();
    batch.delete(_replyDoc(tourId, bookId, threadId, replyId));
    if (wasAccepted) {
      batch.update(
          _threadDoc(tourId, bookId, threadId), {'acceptedReplyId': null});
    }
    await batch.commit();
  }

  /// Removes a thread with the replies its signed-in member may remove: an admin removes them
  /// all, and anyone else removes their own. The thread's author or an admin does this.
  Future<void> deleteStudyThread(
    String tourId,
    String bookId,
    String threadId,
  ) async {
    final email = _requireEmail();
    final admin = (await myRole(tourId))?.isAdminOrOwner ?? false;
    final thread = _threadDoc(tourId, bookId, threadId);
    final replies = await thread.collection('replies').get();
    final batch = _firestore.batch();
    for (final reply in replies.docs) {
      if (admin || reply.data()['createdByEmail'] == email) {
        batch.delete(reply.reference);
      }
    }
    batch.delete(thread);
    await batch.commit();
  }

  // Study materials: notes, files, links and recordings filed under a book. A member's material waits
  // for an admin unless the group publishes directly (tours/{id}.studyPolicy). The rules in
  // firestore.rules say who may write each change.

  CollectionReference<Map<String, dynamic>> _materialsCol(String tourId) =>
      _sub(tourId, 'study_materials');

  DocumentReference<Map<String, dynamic>> _materialDoc(
    String tourId,
    String materialId,
  ) =>
      _materialsCol(tourId).doc(materialId);

  /// Whether a member's material waits for an admin. On unless the group publishes directly.
  Stream<bool> watchMaterialsNeedApproval(String tourId) {
    return _firestore.collection('tours').doc(tourId).snapshots().map((s) {
      final policy = s.data()?['studyPolicy'];
      final value = policy is Map ? policy['materialsNeedApproval'] : null;
      return value is bool ? value : true;
    });
  }

  /// Turns the approval of members' materials on or off. Only an owner or admin does this.
  Future<void> setMaterialsNeedApproval(
    String tourId, {
    required bool needsApproval,
  }) async {
    _requireEmail();
    await _firestore.collection('tours').doc(tourId).update({
      'studyPolicy.materialsNeedApproval': needsApproval,
    });
  }

  /// The materials filed under a book, in no particular order; the screen sorts and filters them.
  Stream<List<StudyMaterial>> watchStudyMaterials(
      String tourId, String bookId) {
    return _materialsCol(tourId)
        .where('bookId', isEqualTo: bookId)
        .limit(500)
        .snapshots()
        .map((s) => [
              for (final d in s.docs)
                if (StudyMaterial.fromMap(d.id, _datesAsDateTimes(d.data()))
                    case final material?)
                  material,
            ]);
  }

  /// Files a material under a book. Its file, when it has one, is uploaded first and its address
  /// passed here; the caller commits the upload once this returns. The signed-in member is its author.
  /// The status comes from the group's policy: an admin's material is published at once.
  Future<void> addStudyMaterial(
    String tourId, {
    required String bookId,
    required StudyMaterialKind kind,
    required String title,
    required bool isAdmin,
    required bool needsApproval,
    String? chapterId,
    String? url,
    String? fileName,
    int? sizeBytes,
    String? body,
    String? replacesId,
  }) async {
    final email = _requireEmail();
    final status = initialStudyMaterialStatus(
      isAdmin: isAdmin,
      needsApproval: needsApproval,
    );
    final material = StudyMaterial(
      id: '',
      title: title.trim(),
      kind: kind,
      bookId: bookId,
      chapterId: chapterId,
      url: url,
      fileName: fileName,
      sizeBytes: sizeBytes,
      body: body?.trim(),
      status: status,
      createdByEmail: email,
      replacesId: replacesId,
    );
    await _materialsCol(tourId).add({
      ...material.toFields(status: status),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Changes a material's title. Its uploader or an admin does this.
  Future<void> setStudyMaterialTitle(
    String tourId,
    String materialId,
    String title,
  ) async {
    _requireEmail();
    await _materialDoc(tourId, materialId).update({'title': title.trim()});
  }

  /// Publishes a pending material, or restores a hidden one. Only an admin does this.
  Future<void> publishStudyMaterial(String tourId, String materialId) async {
    _requireEmail();
    await _materialDoc(tourId, materialId).update({'status': 'published'});
  }

  /// Reports a material, once for each member. The report, the count and the hiding change in one
  /// transaction. The first report starts the 24 hours an admin has to decide.
  Future<void> reportStudyMaterial(
    String tourId,
    String materialId, {
    required StudyMaterialReportReason reason,
  }) async {
    final email = _requireEmail();
    final material = _materialDoc(tourId, materialId);
    final report = material.collection('reports').doc(email);
    await _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(material);
      final alreadyReported = snapshot.data()?['reportedAt'] != null;
      tx.set(report, {
        'reason': reason.name,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.update(material, {
        'reportCount': FieldValue.increment(1),
        'status': 'hidden',
        if (!alreadyReported) 'reportedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Removes a material and the file it uploaded. Its uploader or an admin does this. An admin also
  /// clears its reports and opens, which only an admin may delete. A file that cannot be deleted now is
  /// retried by the media journal.
  Future<void> removeStudyMaterial(
    String tourId,
    StudyMaterial material, {
    required bool isAdmin,
  }) async {
    _requireEmail();
    final doc = _materialDoc(tourId, material.id);
    final batch = _firestore.batch();
    if (isAdmin) {
      for (final report in (await doc.collection('reports').get()).docs) {
        batch.delete(report.reference);
      }
      for (final open in (await doc.collection('opens').get()).docs) {
        batch.delete(open.reference);
      }
    }
    batch.delete(doc);
    await batch.commit();
    final url = material.url;
    final ref = url == null ? null : TourMediaRef.tryParse(url);
    if (ref != null) {
      final journal = TourMediaJournal.instance;
      await journal.markDelete(ref);
      if (await TourMediaUploader.deleteMedia(ref.url)) {
        await journal.resolve(ref.url);
      }
    }
  }

  /// Records that the signed-in member opened a published material, once.
  Future<void> markStudyMaterialOpened(String tourId, String materialId) async {
    final email = _requireEmail();
    final mark =
        _materialDoc(tourId, materialId).collection('opens').doc(email);
    if ((await mark.get()).exists) return;
    await mark.set({'openedAt': FieldValue.serverTimestamp()});
  }

  // ---------------------------------------------------------------------------
  // Dependents: people in the family who have no account
  // ---------------------------------------------------------------------------

  /// The circle's dependents. A stored entry that does not read is left out.
  Stream<List<Dependent>> watchDependents(String tourId) {
    return _sub(tourId, 'dependents').limit(200).snapshots().map((s) => [
          for (final d in s.docs)
            if (Dependent.fromMap(d.id, d.data()) case final dependent?)
              dependent,
        ]);
  }

  /// Lists a person under the signed-in member. The member's family size goes up
  /// by one unless it is already at the largest size. Both writes happen in one
  /// transaction, so the list and the size never disagree.
  Future<void> addDependent(
    String tourId, {
    required String name,
    String relation = '',
  }) async {
    final email = _requireEmail();
    final dependentRef = _sub(tourId, 'dependents').doc();
    final memberRef = _memberships.doc(_membershipId(tourId, email));
    await _firestore.runTransaction((tx) async {
      final member = await tx.get(memberRef);
      final current = (member.data()?['familyCount'] as num?)?.toInt() ?? 1;
      final change = familySizeWithDependent(current);
      final dependent = Dependent(
        id: dependentRef.id,
        name: name.trim(),
        parentEmail: email,
        relation: relation.trim(),
        countedInFamily: change.counted,
      );
      tx.set(dependentRef, dependent.toFields());
      if (member.exists && change.counted) {
        tx.update(memberRef, {'familyCount': change.size});
      }
    });
  }

  /// Removes a person the signed-in member listed. If they were counted in the
  /// family size when added, the size goes back down, in the same transaction.
  Future<void> removeDependent(String tourId, Dependent dependent) async {
    final email = _requireEmail();
    final dependentRef = _sub(tourId, 'dependents').doc(dependent.id);
    final memberRef = _memberships.doc(_membershipId(tourId, email));
    await _firestore.runTransaction((tx) async {
      final member = await tx.get(memberRef);
      if (member.exists && dependent.countedInFamily) {
        final current = (member.data()?['familyCount'] as num?)?.toInt() ?? 1;
        tx.update(memberRef, {
          'familyCount': familySizeWithoutDependent(current, counted: true),
        });
      }
      tx.delete(dependentRef);
    });
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
    final docRef = _sub(tourId, 'sos').doc(alertId);
    try {
      final docSnap = await docRef.get();
      if (!docSnap.exists) {
        return true;
      }
      final data = docSnap.data();
      if (data?['resolved'] == true) {
        return true;
      }
      return await _awaitServer(docRef.update({
        'resolved': true,
        'resolvedByEmail': email,
        'resolvedAt': FieldValue.serverTimestamp(),
      }));
    } catch (e, st) {
      logWarning('[TourGroupRepository] resolveSafetyAlert failed for $alertId',
          e, st);
      rethrow;
    }
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

  /// Publishes this member's battery and place sharing to the family. Only the
  /// member's own record can be written (see the telemetry rules). A null
  /// coordinate clears the stored place.
  Future<void> publishFamilyTelemetry(
    String tourId,
    FamilyTelemetryWrite write,
  ) async {
    final email = _requireEmail();
    await _sub(tourId, 'telemetry').doc(email).set({
      'email': email,
      'name': currentDisplayName,
      'batteryLevel': write.battery.level,
      'isCharging': write.battery.isCharging,
      'sharing': write.sharing,
      'latitude': write.latitude,
      'longitude': write.longitude,
      'updatedAt': FieldValue.serverTimestamp(),
      if (write.checkedIn) 'safeAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Live stream of members' battery and place-sharing records.
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
    String? resharedFromTourId,
    String? resharedFromTourName,
    String? resharedFromAuthorName,
    String? resharedPostId,
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
      resharedFromTourId: resharedFromTourId,
      resharedFromTourName: resharedFromTourName,
      resharedFromAuthorName: resharedFromAuthorName,
      resharedPostId: resharedPostId,
    );
    final map = post.toMap()..['createdAt'] = FieldValue.serverTimestamp();
    await _sub(tourId, 'posts').doc(id).set(map);
    unawaited(VpsNotificationService().notifyPost(
      tourId: tourId,
      postId: id,
      authorName: currentDisplayName,
      caption: caption,
      isReel: videoUrl != null && videoUrl.isNotEmpty,
      imageUrl: coverUrl ?? (images.isNotEmpty ? images.first : null),
    ));
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
  Future<void> setPostLiked(
    String tourId,
    String postId, {
    required bool liked,
    String? postAuthorEmail,
  }) async {
    final email = _requireEmail();
    await _sub(tourId, 'posts').doc(postId).update({
      'likes': liked
          ? FieldValue.arrayUnion([email])
          : FieldValue.arrayRemove([email]),
    });
    if (liked) {
      unawaited(VpsNotificationService().notifyReaction(
        tourId: tourId,
        postId: postId,
        reactorName: currentDisplayName,
        reaction: 'like',
        postAuthorEmail: postAuthorEmail,
      ));
    }
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

  /// Records this member's view of each post in [postIds]. The posts go through
  /// transactions of 25, and a post that already lists the member as a viewer is
  /// left alone, so each view is counted once.
  Future<void> recordPostViews({
    required String tourId,
    required List<String> postIds,
  }) async {
    final email = currentEmail;
    if (email.isEmpty || postIds.isEmpty) return;
    const batchSize = 25;
    for (var start = 0; start < postIds.length; start += batchSize) {
      final end = start + batchSize < postIds.length
          ? start + batchSize
          : postIds.length;
      final batch = postIds.sublist(start, end);
      try {
        await _firestore.runTransaction((tx) async {
          // A transaction reads everything before it writes anything.
          final refs = [for (final id in batch) _sub(tourId, 'posts').doc(id)];
          final snaps = <DocumentSnapshot<Map<String, dynamic>>>[];
          for (final ref in refs) {
            snaps.add(await tx.get(ref));
          }
          for (var i = 0; i < refs.length; i++) {
            final data = snaps[i].data();
            if (data == null) continue;
            final viewers =
                (data['viewers'] as List?)?.cast<Object?>() ?? const [];
            if (viewers.contains(email)) continue;
            tx.update(refs[i], {
              'viewers': FieldValue.arrayUnion([email]),
              'viewCount': FieldValue.increment(1),
            });
          }
        });
      } catch (e, st) {
        logWarning(
            '[recordPostViews] Failed to record ${batch.length} views', e, st);
      }
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
    await _deleteMediaFiles(post.tourId, [
      ...post.images,
      post.videoUrl,
      post.coverUrl,
      post.audioUrl,
    ]);
  }

  /// Deletes a story and the files it uses. A file that a post, story or
  /// highlight still uses stays (see [_deleteMediaFiles]).
  Future<void> deleteStory(String tourId, TourStoryItem story) async {
    _requireEmail();
    await _sub(tourId, 'stories').doc(story.id).delete();

    await _deleteMediaFiles(tourId, [story.mediaUrl, story.videoUrl]);
  }

  /// Removes the remote files in [urls] that no post, story or highlight of
  /// [tourId] still uses. A file another item shares stays, so deleting one
  /// post or story never breaks another. A file whose use cannot be checked
  /// stays too. Each removed file is journaled before its delete is sent, and a
  /// file the server refuses to remove stays journaled for the sweep.
  Future<void> _deleteMediaFiles(String tourId, Iterable<String?> urls) async {
    final candidates = [
      for (final url in urls)
        if (url != null && isRemoteMediaUrl(url)) url,
    ];
    final stillInUse = <String>{};
    for (final url in candidates) {
      try {
        if (await _isMediaUrlInUse(tourId, url)) stillInUse.add(url);
      } catch (e, st) {
        logWarning('[TourGroupRepository] Could not check media use', e, st);
        stillInUse.add(url); // Unknown counts as in use: the file is kept.
      }
    }
    final refs = <TourMediaRef>[];
    for (final url in mediaUrlsSafeToRemove(candidates, stillInUse)) {
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

  /// Whether a post, story or highlight of [tourId] uses [url] in any field that
  /// holds a media file. Throws when the check cannot be made.
  Future<bool> _isMediaUrlInUse(String tourId, String url) async {
    final posts = _sub(tourId, 'posts');
    final stories = _sub(tourId, 'stories');
    final highlights = _sub(tourId, 'highlights');
    Future<bool> used(Query<Map<String, dynamic>> query) async {
      return (await query.limit(1).get()).docs.isNotEmpty;
    }

    final results = await Future.wait<bool>([
      used(posts.where('images', arrayContains: url)),
      used(posts.where('videoUrl', isEqualTo: url)),
      used(posts.where('coverUrl', isEqualTo: url)),
      used(posts.where('audioUrl', isEqualTo: url)),
      used(stories.where('mediaUrl', isEqualTo: url)),
      used(stories.where('videoUrl', isEqualTo: url)),
      used(highlights.where('coverUrl', isEqualTo: url)),
    ]);
    return results.any((r) => r);
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
    try {
      return await _isMediaUrlInUse(entry.tourId, entry.url);
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
    String? postAuthorEmail,
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
    unawaited(VpsNotificationService().notifyComment(
      tourId: tourId,
      postId: postId,
      commentId: commentId,
      commenterName: currentDisplayName,
      text: trimmed,
      postAuthorEmail: postAuthorEmail,
    ));
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
    return _sub(tourId, 'stories').snapshots().map((s) {
      final items =
          s.docs.map((d) => TourStoryItem.fromMap(d.id, d.data())).toList();
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (items.length > 100) return items.sublist(0, 100);
      return items;
    });
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
      'app': 'Bhromon',
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

  // The learning tools of a book (Phase 5): the quizzes on its chapters, their questions, a member's private
  // attempts, and the glossary. An admin writes quizzes and approves; a member proposes and takes them. The rules
  // check each write.

  CollectionReference<Map<String, dynamic>> _quizzesCol(
    String tourId,
    String bookId,
  ) =>
      _studyBookDoc(tourId, bookId).collection('quizzes');

  CollectionReference<Map<String, dynamic>> _questionsCol(
    String tourId,
    String bookId,
    String quizId,
  ) =>
      _quizzesCol(tourId, bookId).doc(quizId).collection('questions');

  CollectionReference<Map<String, dynamic>> _glossaryCol(
    String tourId,
    String bookId,
  ) =>
      _studyBookDoc(tourId, bookId).collection('glossary');

  /// The quizzes of a book, in no particular order; the screen sorts them.
  Stream<List<StudyQuiz>> watchStudyQuizzes(String tourId, String bookId) {
    return _quizzesCol(tourId, bookId).limit(100).snapshots().map((s) => [
          for (final d in s.docs)
            if (StudyQuiz.fromMap(d.id, _datesAsDateTimes(d.data()))
                case final quiz?)
              quiz,
        ]);
  }

  /// Writes a quiz on a chapter. Only an admin does this. A new quiz has no takers yet.
  Future<void> addStudyQuiz(
    String tourId,
    String bookId, {
    required String chapterId,
    required String title,
  }) async {
    final email = _requireEmail();
    final quiz = StudyQuiz(
      id: '',
      chapterId: chapterId,
      title: title.trim(),
      createdByEmail: email,
    );
    await _quizzesCol(tourId, bookId).add(quiz.toFields());
  }

  /// The questions of a quiz, proposals and approved ones alike, oldest first. A quiz shows only the approved
  /// ones (quizQuestions in study_quiz_rules.dart).
  Stream<List<StudyQuizQuestion>> watchQuizQuestions(
    String tourId,
    String bookId,
    String quizId,
  ) {
    return _questionsCol(tourId, bookId, quizId)
        .orderBy('createdAt')
        .limit(300)
        .snapshots()
        .map((s) => [
              for (final d in s.docs)
                if (StudyQuizQuestion.fromMap(d.id, _datesAsDateTimes(d.data()))
                    case final question?)
                  question,
            ]);
  }

  /// Adds a question to a quiz in the signed-in member's name. A member's question is a proposal and waits for an
  /// admin; an admin's is added approved when [approved] is set.
  Future<void> addQuizQuestion(
    String tourId,
    String bookId,
    String quizId, {
    required StudyQuizQuestion question,
    required bool approved,
  }) async {
    final email = _requireEmail();
    await _questionsCol(tourId, bookId, quizId).add({
      ...question.toFields(),
      'approved': approved,
      'proposedByEmail': email,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Approves a proposed question so it joins the quiz. Only an admin does this.
  Future<void> approveQuizQuestion(
    String tourId,
    String bookId,
    String quizId,
    String questionId,
  ) async {
    _requireEmail();
    await _questionsCol(tourId, bookId, quizId)
        .doc(questionId)
        .update({'approved': true});
  }

  /// Removes a question: an admin, or the member who proposed it while it is still a proposal.
  Future<void> deleteQuizQuestion(
    String tourId,
    String bookId,
    String quizId,
    String questionId,
  ) async {
    _requireEmail();
    await _questionsCol(tourId, bookId, quizId).doc(questionId).delete();
  }

  /// The signed-in member's own record on a quiz, or null when they have not taken it. Nobody else reads it.
  Stream<StudyQuizAttempt?> watchMyQuizAttempt(
    String tourId,
    String bookId,
    String quizId,
  ) {
    final email = currentEmail;
    if (email.isEmpty) return Stream.value(null);
    return _quizzesCol(tourId, bookId)
        .doc(quizId)
        .collection('attempts')
        .doc(email)
        .snapshots()
        .map((s) {
      final data = s.data();
      if (!s.exists || data == null) return null;
      return StudyQuizAttempt.fromMap(data);
    });
  }

  /// Records one attempt as [correct] answers out of [total]. The first attempt also moves the quiz's taker count
  /// up by one, in the same transaction, so the count stays exact. Returns the member's record afterwards.
  Future<StudyQuizAttempt> recordQuizAttempt(
    String tourId,
    String bookId,
    String quizId, {
    required int correct,
    required int total,
  }) {
    final email = _requireEmail();
    final quiz = _quizzesCol(tourId, bookId).doc(quizId);
    final attempt = quiz.collection('attempts').doc(email);
    final percent = scorePercent(correct: correct, total: total);
    return _firestore.runTransaction<StudyQuizAttempt>((tx) async {
      final snap = await tx.get(attempt);
      final data = snap.data();
      final previous =
          snap.exists && data != null ? StudyQuizAttempt.fromMap(data) : null;
      final next = nextAttempt(previous, percent);
      tx.set(attempt, {
        ...next.toFields(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (previous == null) {
        tx.update(quiz, {'takerCount': FieldValue.increment(1)});
      }
      return next;
    });
  }

  /// The glossary of a book: approved terms and proposals alike. The screen sorts and filters them.
  Stream<List<StudyGlossaryTerm>> watchGlossary(String tourId, String bookId) {
    return _glossaryCol(tourId, bookId).limit(500).snapshots().map((s) => [
          for (final d in s.docs)
            if (StudyGlossaryTerm.fromMap(d.id, _datesAsDateTimes(d.data()))
                case final term?)
              term,
        ]);
  }

  /// Adds a term in the signed-in member's name. A member's term is a proposal; an admin's is added approved when
  /// [approved] is set.
  Future<void> addGlossaryTerm(
    String tourId,
    String bookId, {
    required String term,
    required String definition,
    String? chapterId,
    required bool approved,
  }) async {
    final email = _requireEmail();
    final entry = StudyGlossaryTerm(
      id: '',
      term: term.trim(),
      definition: definition.trim(),
      chapterId: chapterId,
      approved: approved,
      createdByEmail: email,
    );
    await _glossaryCol(tourId, bookId).add({
      ...entry.toFields(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Approves a proposed term. Only an admin does this.
  Future<void> approveGlossaryTerm(
    String tourId,
    String bookId,
    String termId,
  ) async {
    _requireEmail();
    await _glossaryCol(tourId, bookId).doc(termId).update({'approved': true});
  }

  /// Removes a term: an admin, or the member who proposed it while it is still a proposal.
  Future<void> deleteGlossaryTerm(
    String tourId,
    String bookId,
    String termId,
  ) async {
    _requireEmail();
    await _glossaryCol(tourId, bookId).doc(termId).delete();
  }

  // Progress and shared summaries (Phase 6). A chapter summary is a shared page written as revisions: a member adds
  // one, nothing is overwritten, and an admin pins the revision the group reads. Totals and a member's own record are
  // counted from what the rules already let members read: counted reads, takerCount, threads and replies, and the
  // member's own attempts.

  CollectionReference<Map<String, dynamic>> _summariesCol(
    String tourId,
    String bookId,
    String chapterId,
  ) =>
      _studyBookDoc(tourId, bookId)
          .collection('chapters')
          .doc(chapterId)
          .collection('summaries');

  /// The revisions of a chapter's summary, newest first.
  Stream<List<StudySummaryRevision>> watchSummaries(
    String tourId,
    String bookId,
    String chapterId,
  ) {
    return _summariesCol(tourId, bookId, chapterId)
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((s) => [
              for (final d in s.docs)
                if (StudySummaryRevision.fromMap(
                  d.id,
                  _datesAsDateTimes(d.data()),
                )
                    case final revision?)
                  revision,
            ]);
  }

  /// Adds a revision of a chapter's summary in the signed-in member's name. [restoredFromId] names the revision this
  /// one restores: its text is written again as a new revision, so nothing is overwritten.
  Future<void> addSummaryRevision(
    String tourId,
    String bookId,
    String chapterId, {
    required String text,
    String? restoredFromId,
  }) async {
    final email = _requireEmail();
    final name = currentDisplayName.trim();
    final revision = StudySummaryRevision(
      id: '',
      text: text.trim(),
      editorEmail: email,
      editorName: name.length > StudySummaryLimits.nameMax
          ? name.substring(0, StudySummaryLimits.nameMax)
          : name,
      restoredFromId: restoredFromId,
    );
    await _summariesCol(tourId, bookId, chapterId).add({
      ...revision.toFields(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Pins a revision of a chapter's summary for the group, or unpins it when [revisionId] is null. Only an admin
  /// does this. The pin is written on its own, so a chapter edit does not clear it.
  Future<void> setChapterPin(
    String tourId,
    String bookId,
    String chapterId, {
    String? revisionId,
  }) async {
    _requireEmail();
    await _studyBookDoc(tourId, bookId)
        .collection('chapters')
        .doc(chapterId)
        .update({
      'pinnedSummaryId': revisionId ?? FieldValue.delete(),
    });
  }

  /// The counted flag of every read mark the member can see on each chapter. An uncounted mark is visible only to
  /// its own member, so the group's total is made of counted marks alone.
  Future<Map<String, List<bool>>> loadReadFlags(
    String tourId,
    String bookId,
    Iterable<String> chapterIds,
  ) async {
    final result = <String, List<bool>>{};
    for (final chapterId in chapterIds) {
      final snap = await _studyBookDoc(tourId, bookId)
          .collection('chapters')
          .doc(chapterId)
          .collection('reads')
          .get();
      result[chapterId] = [
        for (final d in snap.docs) d.data()['counted'] == true,
      ];
    }
    return result;
  }

  /// Every reply of each thread in [threadIds], read once, in time order.
  Future<Map<String, List<StudyReply>>> loadReplies(
    String tourId,
    String bookId,
    Iterable<String> threadIds,
  ) async {
    final result = <String, List<StudyReply>>{};
    for (final threadId in threadIds) {
      final snap = await _threadDoc(tourId, bookId, threadId)
          .collection('replies')
          .orderBy('createdAt')
          .limit(1000)
          .get();
      result[threadId] = [
        for (final d in snap.docs)
          if (StudyReply.fromMap(d.id, _datesAsDateTimes(d.data()))
              case final reply?)
            reply,
      ];
    }
    return result;
  }

  /// How many of [quizIds] the signed-in member has taken: each quiz with an attempt of their own.
  Future<int> countMyQuizAttempts(
    String tourId,
    String bookId,
    Iterable<String> quizIds,
  ) async {
    final email = currentEmail;
    if (email.isEmpty) return 0;
    var count = 0;
    for (final quizId in quizIds) {
      final snap = await _quizzesCol(tourId, bookId)
          .doc(quizId)
          .collection('attempts')
          .doc(email)
          .get();
      if (snap.exists) count++;
    }
    return count;
  }

  /// The revisions of each chapter's summary, read once, for the study pack.
  Future<Map<String, List<StudySummaryRevision>>> loadSummaryRevisions(
    String tourId,
    String bookId,
    Iterable<String> chapterIds,
  ) async {
    final result = <String, List<StudySummaryRevision>>{};
    for (final chapterId in chapterIds) {
      final snap = await _summariesCol(tourId, bookId, chapterId).get();
      result[chapterId] = [
        for (final d in snap.docs)
          if (StudySummaryRevision.fromMap(d.id, _datesAsDateTimes(d.data()))
              case final revision?)
            revision,
      ];
    }
    return result;
  }

  /// The accepted answer of each thread that has one: the question the thread asked, and the reply accepted.
  Future<List<({String question, String answer})>> loadAcceptedAnswers(
    String tourId,
    String bookId,
    Iterable<StudyThread> threads,
  ) async {
    final result = <({String question, String answer})>[];
    for (final thread in threads) {
      final acceptedId = thread.acceptedReplyId;
      if (acceptedId == null) continue;
      final snap = await _threadDoc(tourId, bookId, thread.id)
          .collection('replies')
          .doc(acceptedId)
          .get();
      final data = snap.data();
      if (!snap.exists || data == null) continue;
      final reply = StudyReply.fromMap(snap.id, _datesAsDateTimes(data));
      if (reply == null) continue;
      result.add((question: thread.title, answer: reply.text));
    }
    return result;
  }
}
