import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../domain/models/tour_group.dart';
import '../domain/models/expense_models.dart';
import '../domain/models/tour_post_models.dart';

class TourGroupRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Uuid _uuid = const Uuid();

  TourGroupRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String get currentUid => _auth.currentUser?.uid ?? 'explorer_guest';

  String get currentEmail =>
      _auth.currentUser?.email?.toLowerCase().trim() ??
      '$currentUid@bhromon.app';

  String get currentDisplayName {
    final name = _auth.currentUser?.displayName;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    return 'Explorer';
  }

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
      final List<dynamic> rawIds = box.get('my_tour_ids', defaultValue: <dynamic>[]) as List<dynamic>;
      final List<String> myIds = List<String>.from(rawIds);
      if (!myIds.contains(group.id)) {
        myIds.add(group.id);
        await box.put('my_tour_ids', myIds);
      }
    } catch (e) {
      debugPrint('[TourGroupRepository] Error caching local group: $e');
    }
  }

  Future<List<TourGroup>> getLocalGroups() async {
    try {
      final box = await _openBox();
      final List<dynamic> rawIds = box.get('my_tour_ids', defaultValue: <dynamic>[]) as List<dynamic>;
      final List<String> myIds = List<String>.from(rawIds);
      final List<TourGroup> groups = [];
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

  /// Stream of groups the current user is a member of.
  /// Yields local Hive-cached groups immediately, then updates from Firestore.
  Stream<List<TourGroup>> watchMyGroups() async* {
    // 1. Immediately emit offline/cached groups
    final initialLocal = await getLocalGroups();
    yield initialLocal;

    final email = currentEmail;

    // 2. Stream from Firestore
    final membershipStream = _firestore
        .collection('memberships')
        .where('email', isEqualTo: email)
        .where('status', isEqualTo: 'active')
        .snapshots();

    await for (final snapshot in membershipStream.handleError((Object error) {
      debugPrint('[TourGroupRepository] Error watching memberships: $error');
    })) {
      final tourIds = snapshot.docs
          .map((d) => d.data()['tourId'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final List<TourGroup> groups = [];

      for (final id in tourIds) {
        try {
          final doc = await _firestore.collection('tours').doc(id).get();
          if (doc.exists && doc.data() != null) {
            final group = TourGroup.fromMap(doc.id, doc.data()!);
            groups.add(group);
            await _cacheLocalGroup(group);
          }
        } catch (_) {}
      }

      // Also query tours owned by user if memberships didn't catch them
      try {
        final ownedSnap = await _firestore
            .collection('tours')
            .where('ownerEmail', isEqualTo: email)
            .get();
        for (final doc in ownedSnap.docs) {
          if (!groups.any((g) => g.id == doc.id)) {
            final group = TourGroup.fromMap(doc.id, doc.data());
            groups.add(group);
            await _cacheLocalGroup(group);
          }
        }
      } catch (_) {}

      // Merge with any local groups
      final local = await getLocalGroups();
      for (final lg in local) {
        if (!groups.any((g) => g.id == lg.id)) {
          groups.add(lg);
        }
      }

      yield groups;
    }
  }

  /// Creates a new tour group and registers the creator as the Owner/Admin.
  Future<TourGroup> createGroup({
    required String name,
    required String description,
    required String destination,
    required DateTime startDate,
    required DateTime endDate,
    TourModules modules = const TourModules(),
  }) async {
    final email = currentEmail;
    final uid = currentUid;

    final tourId = _uuid.v4().substring(0, 20);
    final inviteCode = _uuid.v4().substring(0, 6).toUpperCase();

    final group = TourGroup(
      id: tourId,
      name: name,
      description: description,
      destination: destination,
      ownerEmail: email,
      ownerUid: uid,
      inviteCode: inviteCode,
      startDate: startDate,
      endDate: endDate,
      modules: modules,
      createdAt: DateTime.now(),
    );

    // Cache locally immediately so the user sees their group right away
    await _cacheLocalGroup(group);

    // Persist to remote Firestore with subcollection private/invite
    try {
      final batch = _firestore.batch();
      final tourRef = _firestore.collection('tours').doc(tourId);
      batch.set(tourRef, group.toMap());

      final membershipId = '${tourId}__$email';
      final membershipRef = _firestore.collection('memberships').doc(membershipId);
      final member = TourMember(
        tourId: tourId,
        tourName: name,
        email: email,
        displayName: currentDisplayName,
        photoUrl: _auth.currentUser?.photoURL,
        role: TourRole.owner,
        status: TourMemberStatus.active,
        joinedAt: DateTime.now(),
      );
      batch.set(membershipRef, member.toMap());

      final inviteRef = tourRef.collection('private').doc('invite');
      batch.set(inviteRef, {
        'code': inviteCode,
        'rotatedAt': DateTime.now().toIso8601String(),
      });

      await batch.commit();
    } catch (e) {
      debugPrint('[TourGroupRepository] Remote write failed; saved locally: $e');
    }

    return group;
  }

  /// Joins an existing tour using its 6-character invite code.
  Future<TourGroup> joinGroupWithCode(String inviteCode) async {
    final email = currentEmail;
    final code = inviteCode.trim().toUpperCase();

    TourGroup? matchedGroup;

    try {
      final query = await _firestore
          .collection('tours')
          .where('inviteCode', isEqualTo: code)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final tourDoc = query.docs.first;
        matchedGroup = TourGroup.fromMap(tourDoc.id, tourDoc.data());
      }
    } catch (e) {
      debugPrint('[TourGroupRepository] Query inviteCode failed: $e');
    }

    if (matchedGroup == null) {
      final localGroups = await getLocalGroups();
      for (final g in localGroups) {
        if (g.inviteCode.toUpperCase() == code) {
          matchedGroup = g;
          break;
        }
      }
    }

    if (matchedGroup == null) {
      throw ArgumentError('সঠিক ৬-সংখ্যার আমন্ত্রণ কোড দিন। কোনো ট্যুর গ্রুপ পাওয়া যায়নি।');
    }

    await _cacheLocalGroup(matchedGroup);

    try {
      final membershipId = '${matchedGroup.id}__$email';
      final memberRef = _firestore.collection('memberships').doc(membershipId);

      final member = TourMember(
        tourId: matchedGroup.id,
        tourName: matchedGroup.name,
        email: email,
        displayName: currentDisplayName,
        photoUrl: _auth.currentUser?.photoURL,
        role: TourRole.member,
        status: TourMemberStatus.active,
        joinedAt: DateTime.now(),
      );

      await memberRef.set(member.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('[TourGroupRepository] Join membership set failed: $e');
    }

    return matchedGroup;
  }

  /// Stream of active members in a tour.
  Stream<List<TourMember>> watchMembers(String tourId) {
    return _firestore
        .collection('memberships')
        .where('tourId', isEqualTo: tourId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((d) => TourMember.fromMap(d.data())).toList())
        .handleError((Object e) {
      debugPrint('[TourGroupRepository] watchMembers error: $e');
      return <TourMember>[];
    });
  }

  /// Stream of expenses for a tour.
  Stream<List<ExpenseItem>> watchExpenses(String tourId) {
    return _firestore
        .collection('tours')
        .doc(tourId)
        .collection('expenses')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((d) => ExpenseItem.fromMap(d.id, d.data())).toList())
        .handleError((Object e) {
      debugPrint('[TourGroupRepository] watchExpenses error: $e');
      return <ExpenseItem>[];
    });
  }

  /// Adds a new expense item.
  Future<void> addExpense({
    required String tourId,
    required String title,
    required int amountPaisa,
    String? paidById,
    String? paidByName,
    required String category,
    DateTime? date,
    String? notes,
  }) async {
    final expId = _uuid.v4();
    final expense = ExpenseItem(
      id: expId,
      tourId: tourId,
      title: title,
      amountPaisa: amountPaisa,
      paidById: paidById,
      paidByName: paidByName,
      category: category,
      date: date ?? DateTime.now(),
      notes: notes,
    );

    await _firestore
        .collection('tours')
        .doc(tourId)
        .collection('expenses')
        .doc(expId)
        .set(expense.toMap());
  }

  /// Stream of deposits for a tour.
  Stream<List<DepositItem>> watchDeposits(String tourId) {
    return _firestore
        .collection('tours')
        .doc(tourId)
        .collection('deposits')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((d) => DepositItem.fromMap(d.id, d.data())).toList())
        .handleError((Object e) {
      debugPrint('[TourGroupRepository] watchDeposits error: $e');
      return <DepositItem>[];
    });
  }

  /// Adds a new deposit contribution into the shared fund.
  Future<void> addDeposit({
    required String tourId,
    required String memberId,
    required String memberName,
    required int amountPaisa,
    DateTime? date,
    String? notes,
  }) async {
    final depId = _uuid.v4();
    final deposit = DepositItem(
      id: depId,
      tourId: tourId,
      memberId: memberId,
      memberName: memberName,
      amountPaisa: amountPaisa,
      date: date ?? DateTime.now(),
      notes: notes,
    );

    await _firestore
        .collection('tours')
        .doc(tourId)
        .collection('deposits')
        .doc(depId)
        .set(deposit.toMap());
  }

  // --- Tour Posts & InstaFeed ---

  Stream<List<TourPostItem>> watchPosts(String tourId) {
    return _firestore
        .collection('tours')
        .doc(tourId)
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => TourPostItem.fromMap(d.id, d.data())).toList())
        .handleError((Object e) {
      debugPrint('[TourGroupRepository] watchPosts error: $e');
      return <TourPostItem>[];
    });
  }

  Future<void> addPost({
    required String tourId,
    required String caption,
    required List<String> images,
    String? videoUrl,
    bool isReel = false,
    String location = 'Cox\'s Bazar',
    String tourDay = 'day1',
    String filterId = 'normal',
  }) async {
    final postId = _uuid.v4();
    final post = TourPostItem(
      id: postId,
      tourId: tourId,
      authorEmail: currentEmail,
      authorName: currentDisplayName,
      authorPhoto: _auth.currentUser?.photoURL,
      caption: caption,
      images: images,
      videoUrl: videoUrl,
      isReel: isReel,
      location: location,
      tourDay: tourDay,
      filterId: filterId,
      likes: [],
      commentCount: 0,
      createdAt: DateTime.now(),
    );

    await _firestore
        .collection('tours')
        .doc(tourId)
        .collection('posts')
        .doc(postId)
        .set(post.toMap());
  }

  Future<void> toggleLikePost(String tourId, String postId) async {
    final email = currentEmail;
    final postRef = _firestore
        .collection('tours')
        .doc(tourId)
        .collection('posts')
        .doc(postId);

    final snap = await postRef.get();
    if (!snap.exists) return;

    final data = snap.data() ?? {};
    final likes = (data['likes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

    if (likes.contains(email)) {
      likes.remove(email);
    } else {
      likes.add(email);
    }
    await postRef.update({'likes': likes});
  }

  Stream<List<TourCommentItem>> watchComments(String tourId, String postId) {
    return _firestore
        .collection('tours')
        .doc(tourId)
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map((d) => TourCommentItem.fromMap(d.id, d.data())).toList())
        .handleError((Object e) {
      debugPrint('[TourGroupRepository] watchComments error: $e');
      return <TourCommentItem>[];
    });
  }

  Future<void> addComment({
    required String tourId,
    required String postId,
    required String text,
    String? reaction,
  }) async {
    final commentId = _uuid.v4();
    final comment = TourCommentItem(
      id: commentId,
      authorEmail: currentEmail,
      authorName: currentDisplayName,
      authorPhoto: _auth.currentUser?.photoURL,
      text: text,
      reaction: reaction,
      createdAt: DateTime.now(),
    );

    final postRef = _firestore
        .collection('tours')
        .doc(tourId)
        .collection('posts')
        .doc(postId);

    final batch = _firestore.batch();
    batch.set(postRef.collection('comments').doc(commentId), comment.toMap());
    batch.update(postRef, {'commentCount': FieldValue.increment(1)});
    await batch.commit();
  }

  // --- Tour Stories ---

  Stream<List<TourStoryItem>> watchStories(String tourId) {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    return _firestore
        .collection('tours')
        .doc(tourId)
        .collection('stories')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => TourStoryItem.fromMap(d.id, d.data())).toList())
        .handleError((Object e) {
      debugPrint('[TourGroupRepository] watchStories error: $e');
      return <TourStoryItem>[];
    });
  }

  Future<void> addStory({
    required String tourId,
    required String mediaUrl,
    String? caption,
  }) async {
    final storyId = _uuid.v4();
    final story = TourStoryItem(
      id: storyId,
      authorEmail: currentEmail,
      authorName: currentDisplayName,
      authorPhoto: _auth.currentUser?.photoURL,
      mediaUrl: mediaUrl,
      caption: caption,
      createdAt: DateTime.now(),
    );

    await _firestore
        .collection('tours')
        .doc(tourId)
        .collection('stories')
        .doc(storyId)
        .set(story.toMap());
  }

  // --- Member Management & Role Delegation ---

  Future<void> updateMemberRole(String tourId, String email, TourRole newRole) async {
    final membershipId = '${tourId}__$email';
    await _firestore.collection('memberships').doc(membershipId).update({
      'role': newRole.toValue(),
    });
  }

  Future<void> removeMember(String tourId, String email) async {
    final membershipId = '${tourId}__$email';
    await _firestore.collection('memberships').doc(membershipId).delete();
  }

  Future<void> transferOwnership(String tourId, String newOwnerEmail) async {
    final oldOwnerEmail = currentEmail;
    final batch = _firestore.batch();

    // 1. Update tour doc
    batch.update(_firestore.collection('tours').doc(tourId), {
      'ownerEmail': newOwnerEmail,
    });

    // 2. Update new owner membership
    batch.update(_firestore.collection('memberships').doc('${tourId}__$newOwnerEmail'), {
      'role': TourRole.owner.toValue(),
    });

    // 3. Demote old owner to admin
    batch.update(_firestore.collection('memberships').doc('${tourId}__$oldOwnerEmail'), {
      'role': TourRole.admin.toValue(),
    });

    await batch.commit();
  }

  // --- Full Tour Snapshot JSON Export ---

  Future<Map<String, dynamic>> fetchFullTourSnapshot(String tourId) async {
    final tourDoc = await _firestore.collection('tours').doc(tourId).get();
    final membersSnap = await _firestore.collection('memberships').where('tourId', isEqualTo: tourId).get();
    final expensesSnap = await _firestore.collection('tours').doc(tourId).collection('expenses').get();
    final depositsSnap = await _firestore.collection('tours').doc(tourId).collection('deposits').get();
    final noticesSnap = await _firestore.collection('tours').doc(tourId).collection('notices').get();
    final postsSnap = await _firestore.collection('tours').doc(tourId).collection('posts').get();

    return {
      'exportedAt': DateTime.now().toIso8601String(),
      'app': 'Bhromon / Family_Bhromon Hybrid 2026',
      'tour': tourDoc.data() ?? {},
      'members': membersSnap.docs.map((d) => d.data()).toList(),
      'expenses': expensesSnap.docs.map((d) => d.data()).toList(),
      'deposits': depositsSnap.docs.map((d) => d.data()).toList(),
      'notices': noticesSnap.docs.map((d) => d.data()).toList(),
      'posts': postsSnap.docs.map((d) => d.data()).toList(),
    };
  }
}
