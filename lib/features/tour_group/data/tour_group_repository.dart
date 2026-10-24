import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../domain/models/tour_group.dart';
import '../domain/models/expense_models.dart';

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
}
