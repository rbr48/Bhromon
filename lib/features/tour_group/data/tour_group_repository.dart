import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  String? get currentEmail => _auth.currentUser?.email?.toLowerCase().trim();
  String get currentDisplayName => _auth.currentUser?.displayName ?? 'Explorer';

  /// Stream of groups the current user is a member of.
  Stream<List<TourGroup>> watchMyGroups() {
    final email = currentEmail;
    if (email == null) return Stream.value([]);

    return _firestore
        .collection('memberships')
        .where('email', isEqualTo: email)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .asyncMap((snapshot) async {
      final tourIds = snapshot.docs.map((d) => d.data()['tourId'] as String).toList();
      if (tourIds.isEmpty) return <TourGroup>[];

      final groups = <TourGroup>[];
      for (final id in tourIds) {
        final doc = await _firestore.collection('tours').doc(id).get();
        if (doc.exists && doc.data() != null) {
          groups.add(TourGroup.fromMap(doc.id, doc.data()!));
        }
      }
      return groups;
    });
  }

  /// Creates a new tour group and registers the creator as the Owner.
  Future<TourGroup> createGroup({
    required String name,
    required String description,
    required String destination,
    required DateTime startDate,
    required DateTime endDate,
    TourModules modules = const TourModules(),
  }) async {
    final email = currentEmail;
    if (email == null) throw StateError('User must be logged in to create a tour');

    final tourId = _uuid.v4().substring(0, 20);
    final inviteCode = _uuid.v4().substring(0, 6).toUpperCase();

    final group = TourGroup(
      id: tourId,
      name: name,
      description: description,
      destination: destination,
      ownerEmail: email,
      inviteCode: inviteCode,
      startDate: startDate,
      endDate: endDate,
      modules: modules,
      createdAt: DateTime.now(),
    );

    final batch = _firestore.batch();
    final tourRef = _firestore.collection('tours').doc(tourId);
    batch.set(tourRef, group.toMap());

    final membershipId = '${tourId}__$email';
    final membershipRef = _firestore.collection('memberships').doc(membershipId);
    final member = TourMember(
      tourId: tourId,
      email: email,
      displayName: currentDisplayName,
      photoUrl: _auth.currentUser?.photoURL,
      role: TourRole.owner,
      status: TourMemberStatus.active,
      joinedAt: DateTime.now(),
    );
    batch.set(membershipRef, member.toMap());

    await batch.commit();
    return group;
  }

  /// Joins an existing tour using its 6-character invite code.
  Future<TourGroup> joinGroupWithCode(String inviteCode) async {
    final email = currentEmail;
    if (email == null) throw StateError('User must be logged in to join a tour');

    final code = inviteCode.trim().toUpperCase();
    final query = await _firestore
        .collection('tours')
        .where('inviteCode', isEqualTo: code)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw ArgumentError('Invalid invite code. No matching tour found.');
    }

    final tourDoc = query.docs.first;
    final group = TourGroup.fromMap(tourDoc.id, tourDoc.data());

    final membershipId = '${group.id}__$email';
    final memberRef = _firestore.collection('memberships').doc(membershipId);

    final member = TourMember(
      tourId: group.id,
      email: email,
      displayName: currentDisplayName,
      photoUrl: _auth.currentUser?.photoURL,
      role: TourRole.member,
      status: TourMemberStatus.active,
      joinedAt: DateTime.now(),
    );

    await memberRef.set(member.toMap(), SetOptions(merge: true));
    return group;
  }

  /// Stream of active members in a tour.
  Stream<List<TourMember>> watchMembers(String tourId) {
    return _firestore
        .collection('memberships')
        .where('tourId', isEqualTo: tourId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((d) => TourMember.fromMap(d.data())).toList());
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
            snapshot.docs.map((d) => ExpenseItem.fromMap(d.id, d.data())).toList());
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
            snapshot.docs.map((d) => DepositItem.fromMap(d.id, d.data())).toList());
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
        .map((s) => s.docs.map((d) => TourPostItem.fromMap(d.id, d.data())).toList());
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
      authorEmail: currentEmail ?? 'anonymous',
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
    if (email == null) return;
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
        .map((s) => s.docs.map((d) => TourCommentItem.fromMap(d.id, d.data())).toList());
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
      authorEmail: currentEmail ?? 'anonymous',
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
        .map((s) => s.docs.map((d) => TourStoryItem.fromMap(d.id, d.data())).toList());
  }

  Future<void> addStory({
    required String tourId,
    required String mediaUrl,
    String? caption,
  }) async {
    final storyId = _uuid.v4();
    final story = TourStoryItem(
      id: storyId,
      authorEmail: currentEmail ?? 'anonymous',
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
    if (oldOwnerEmail != null) {
      batch.update(_firestore.collection('memberships').doc('${tourId}__$oldOwnerEmail'), {
        'role': TourRole.admin.toValue(),
      });
    }

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
