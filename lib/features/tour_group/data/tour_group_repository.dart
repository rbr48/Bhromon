import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../domain/models/date_codec.dart';
import '../domain/models/expense_models.dart';
import '../domain/models/logistics_models.dart';
import '../domain/models/safety_alert_models.dart';
import '../domain/models/tour_activity_models.dart';
import '../domain/models/tour_group.dart';
import '../domain/models/tour_post_models.dart';
import '../domain/services/invite_code.dart';
import 'tour_media_uploader.dart';

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
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Uuid _uuid = const Uuid();

  TourGroupRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  // ---------------------------------------------------------------------------
  // Identity
  // ---------------------------------------------------------------------------

  bool get isSignedIn => _auth.currentUser != null;

  /// Empty when signed out. There is no shared guest identity any more.
  String get currentUid => _auth.currentUser?.uid ?? '';

  String get currentEmail {
    final email = _auth.currentUser?.email;
    if (email != null && email.trim().isNotEmpty) {
      return normalizeEmail(email);
    }
    final uid = _auth.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      return '$uid@bhromon.app';
    }
    return '';
  }

  String get currentDisplayName {
    final name = _auth.currentUser?.displayName;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    return 'Explorer';
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
    if (Hive.isBoxOpen('tour_groups_box')) {
      return Hive.box<dynamic>('tour_groups_box');
    }
    return await Hive.openBox<dynamic>('tour_groups_box');
  }

  Future<void> _cacheLocalGroup(TourGroup group) async {
    try {
      final box = await _openBox();
      await box.put('tour_${group.id}', group.toMap());
      final List<String> myIds = List<String>.from(
          box.get('my_tour_ids', defaultValue: <String>[]) as List);
      if (!myIds.contains(group.id)) {
        myIds.add(group.id);
        await box.put('my_tour_ids', myIds);
      }
    } catch (e) {
      debugPrint('[TourGroupRepository] Error caching local group: $e');
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
    } catch (e) {
      debugPrint('[TourGroupRepository] Error clearing local group: $e');
    }
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
        return FeedPrefs(
          bookmarks: Set<String>.from((raw['bookmarks'] as List?) ?? const []),
          seenStories:
              Set<String>.from((raw['seenStories'] as List?) ?? const []),
        );
      }
    } catch (e) {
      debugPrint('[TourGroupRepository] Could not read feed prefs: $e');
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
      });
    } catch (e) {
      debugPrint('[TourGroupRepository] Could not save feed prefs: $e');
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
    if (!isSignedIn) return Stream.value(const []);
    final email = currentEmail;

    late StreamController<List<TourGroup>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? membershipSub;
    final tourSubs =
        <String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};
    final tours = <String, TourGroup>{};
    var listedIds = <String>{};
    var heardFromServer = false;
    // Role each membership row says we have, by tour id.
    final rolesByTour = <String, String>{};

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

    void startTour(String tourId) {
      tourSubs[tourId] = _tour(tourId).snapshots().listen(
        (doc) {
          final data = doc.data();
          if (doc.exists && data != null) {
            final group = TourGroup.fromMap(doc.id, data);
            tours[tourId] = group;
            _cacheLocalGroup(group);
            // Owner rows written before role 'owner' was saved as 'admin'.
            // The owner's own app repairs them here.
            if (group.ownerEmail == email &&
                rolesByTour[tourId] != TourRole.owner.toValue()) {
              _memberships.doc(_membershipId(tourId, email)).update({
                'role': TourRole.owner.toValue()
              }).catchError((Object e) => debugPrint(
                  '[TourGroupRepository] owner role repair failed: $e'));
              rolesByTour[tourId] = TourRole.owner.toValue();
            }
          } else {
            tours.remove(tourId);
            _removeLocalGroup(tourId);
          }
          emit();
        },
        onError: (Object e) {
          // Losing access to a tour means the user is no longer a member.
          debugPrint('[TourGroupRepository] tour $tourId unavailable: $e');
          stopTour(tourId);
          listedIds.remove(tourId);
          _removeLocalGroup(tourId);
          emit();
        },
      );
    }

    controller = StreamController<List<TourGroup>>(
      onListen: () {
        getLocalGroups().then((local) {
          if (!heardFromServer && !controller.isClosed) {
            controller.add(local);
          }
        });

        membershipSub = _memberships
            .where('email', isEqualTo: email)
            .where('status', isEqualTo: 'active')
            .snapshots()
            .listen(
          (snapshot) {
            heardFromServer = true;
            rolesByTour.clear();
            for (final d in snapshot.docs) {
              final id = d.data()['tourId'] as String? ?? '';
              if (id.isNotEmpty) {
                rolesByTour[id] = d.data()['role'] as String? ?? 'member';
              }
            }
            final ids = rolesByTour.keys.toSet();
            for (final id in listedIds.difference(ids)) {
              stopTour(id);
              _removeLocalGroup(id);
            }
            for (final id in ids.difference(listedIds)) {
              startTour(id);
            }
            listedIds = ids;
            emit();
          },
          onError: (Object e) {
            debugPrint('[TourGroupRepository] memberships error: $e');
            if (!controller.isClosed) controller.addError(e);
          },
        );
      },
      onCancel: () async {
        await membershipSub?.cancel();
        for (final sub in tourSubs.values) {
          await sub.cancel();
        }
        tourSubs.clear();
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
    } catch (_) {
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
          photoUrl: _auth.currentUser?.photoURL,
          role: TourRole.owner,
          status: TourMemberStatus.active,
          joinedAt: now,
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
    debugPrint('[TourGroupRepository] Group $tourId rejected: $error');
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

    final invite = await _invites.doc(code).get();
    final tourId = invite.data()?['tourId'] as String?;
    if (!invite.exists || tourId == null) {
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
        photoUrl: _auth.currentUser?.photoURL,
        role: TourRole.member,
        status: TourMemberStatus.active,
        joinedAt: DateTime.now(),
      ).toMap()
        ..['joinCode'] = code;
      try {
        final synced = await _awaitServer(membershipRef.set(member));
        if (!synced) {
          throw const TourAccessException(
              'ইন্টারনেট সংযোগ নেই। সংযোগ ফিরে এলে আবার চেষ্টা করুন।');
        }
      } on FirebaseException {
        throw const TourAccessException(
            'এই ট্যুরে যোগ দেওয়ার অনুমতি নেই। কোড ঠিক আছে কি না দেখুন, অথবা অ্যাডমিনের সাথে যোগাযোগ করুন।');
      }
    }

    final group = await getGroup(tourId);
    if (group == null) {
      throw const TourAccessException('ট্যুরটি এখন আর পাওয়া যাচ্ছে না।');
    }
    return group;
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

  /// Admins post notices. The author is the signed-in admin, not free text.
  Future<void> postNotice({
    required String tourId,
    required String title,
    required String content,
    required bool urgent,
  }) async {
    final email = _requireEmail();
    await _sub(tourId, 'notices').add({
      'title': title,
      'content': content,
      'author': currentDisplayName,
      'authorEmail': email,
      'urgent': urgent,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Edits a notice's text and urgency. The author and original time stay as
  /// they were; only the edit time is added.
  Future<void> updateNotice({
    required String tourId,
    required String noticeId,
    required String title,
    required String content,
    required bool urgent,
  }) async {
    _requireEmail();
    await _sub(tourId, 'notices').doc(noticeId).update({
      'title': title,
      'content': content,
      'urgent': urgent,
      'editedAt': FieldValue.serverTimestamp(),
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
    return _awaitServer(_sub(tourId, 'sos').doc(alertId).set({
      'id': alertId,
      'senderEmail': email,
      'senderName': currentDisplayName,
      'resolved': false,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'createdAt': FieldValue.serverTimestamp(),
    }));
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

  // ---------------------------------------------------------------------------
  // Bus seats
  // ---------------------------------------------------------------------------

  Stream<List<BusSeat>> watchBusSeats(String tourId) {
    return _sub(tourId, 'bus_seats')
        .snapshots()
        .map((s) => s.docs.map((d) => BusSeat.fromMap(d.data())).toList());
  }

  /// Puts [email] in [seatNumber], first freeing any other seat they hold, so
  /// one member never holds two seats. A null [email] vacates the seat.
  Future<void> assignBusSeat(
    String tourId,
    String seatNumber, {
    String? email,
    String? name,
  }) async {
    _requireEmail();
    final seats = _sub(tourId, 'bus_seats');
    final batch = _firestore.batch();
    final target = email == null ? null : normalizeEmail(email);

    if (target != null) {
      final held =
          await seats.where('assignedMemberEmail', isEqualTo: target).get();
      for (final doc in held.docs) {
        if (doc.id != seatNumber) {
          batch.set(
              doc.reference,
              BusSeat.fromMap(doc.data())
                  .copyWith(assignedMemberEmail: null, assignedMemberName: null)
                  .toMap());
        }
      }
    }

    final seat = BusSeat(
      seatNumber: seatNumber,
      assignedMemberEmail: target,
      assignedMemberName: target == null ? null : name,
      isWindow: _isWindowSeat(seatNumber),
    );
    batch.set(seats.doc(seatNumber), seat.toMap());
    await batch.commit();
  }

  /// Window seats are the outer columns: A1/A4, B1/B4 and so on.
  static bool _isWindowSeat(String seatNumber) =>
      seatNumber.endsWith('1') || seatNumber.endsWith('4');

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

  /// Moves a guest into a room, out of any other room, inside one transaction.
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
    final elsewhere =
        await rooms.where('assignedMemberEmails', arrayContains: guest).get();
    for (final doc in elsewhere.docs) {
      if (doc.id != roomId) await _removeGuestFromRoom(tourId, doc.id, guest);
    }
    await _firestore.runTransaction((tx) async {
      final ref = rooms.doc(roomId);
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('রুমটি আর পাওয়া যাচ্ছে না।');
      final room = HotelRoom.fromMap(snap.id, snap.data()!);
      tx.set(ref, room.addGuest(guest, name).toMap());
    });
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
      authorPhoto: _auth.currentUser?.photoURL,
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
    );
    await _sub(tourId, 'posts').doc(id).set(post.toMap());
  }

  Future<void> updatePostCaption(
      String tourId, String postId, String caption) async {
    _requireEmail();
    await _sub(tourId, 'posts').doc(postId).update({'caption': caption.trim()});
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

  /// Deletes a post with its comments, then removes its files from Storage
  /// (best effort: the post is removed even if a file cannot be deleted).
  Future<void> deletePost(TourPostItem post) async {
    _requireEmail();
    final postRef = _sub(post.tourId, 'posts').doc(post.id);
    final comments = await postRef.collection('comments').get();
    for (var i = 0; i < comments.docs.length; i += _batchLimit) {
      final batch = _firestore.batch();
      for (final c in comments.docs.skip(i).take(_batchLimit)) {
        batch.delete(c.reference);
      }
      await batch.commit();
    }
    await postRef.delete();
    for (final url in [
      ...post.images,
      if (post.videoUrl != null) post.videoUrl!
    ]) {
      if (!isRemoteMediaUrl(url)) continue;
      try {
        await TourMediaUploader.deleteMedia(url);
      } catch (e) {
        debugPrint('[TourGroupRepository] Could not delete media: $e');
      }
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
      authorPhoto: _auth.currentUser?.photoURL,
      text: trimmed,
      reaction: reaction,
      createdAt: DateTime.now(),
    );
    final postRef = _sub(tourId, 'posts').doc(postId);
    final batch = _firestore.batch();
    batch.set(postRef.collection('comments').doc(commentId), comment.toMap());
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
      authorPhoto: _auth.currentUser?.photoURL,
      mediaUrl: mediaUrl,
      caption: caption?.trim().isEmpty ?? true ? null : caption!.trim(),
      createdAt: DateTime.now(),
    );
    await _sub(tourId, 'stories').doc(id).set(story.toMap());
  }

  Future<void> deleteStory(String tourId, String storyId) async {
    _requireEmail();
    await _sub(tourId, 'stories').doc(storyId).delete();
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
      'notices': await collect('notices'),
      'checklist': await collect('checklist'),
      'checkpoints': await collect('checkpoints'),
      'bus_seats': await collect('bus_seats'),
      'hotel_rooms': await collect('hotel_rooms'),
      'posts': posts.docs.map((d) => d.data()).toList(),
      'comments': comments,
      'stories': await collect('stories'),
    };
  }
}
