import '../models/date_codec.dart';
import '../models/tour_group.dart';

/// A tour the user and a contact both belong to.
class GroupContactTour {
  final String id;
  final String name;

  const GroupContactTour({required this.id, required this.name});
}

/// A person the user may chat or call: an active member of a tour they share.
class GroupContact {
  final String uid;
  final String email;
  final String name;
  final String? photoUrl;

  /// The tours the two share, in the order the user's tours were listed.
  final List<GroupContactTour> tours;

  const GroupContact({
    required this.uid,
    required this.email,
    required this.name,
    this.photoUrl,
    required this.tours,
  });

  /// The tour a chat or call with this person is opened in.
  String get sharedTourId => tours.first.id;
}

/// Everyone the user can reach. It is built only from the members of the user's
/// own tours, so nobody outside them is listed. Invited members, people who have
/// never signed in, and the user are left out. Someone in several tours appears
/// once, with every tour they share.
List<GroupContact> groupContacts({
  required String myUid,
  required String myEmail,
  required List<({String id, String name, List<TourMember> members})> tours,
}) {
  final me = normalizeEmail(myEmail);
  final drafts = <String, _Draft>{};
  for (final tour in tours) {
    for (final member in tour.members) {
      final uid = member.uid ?? '';
      final email = normalizeEmail(member.email);
      if (member.status != TourMemberStatus.active ||
          uid.isEmpty ||
          uid == myUid ||
          email == me) {
        continue;
      }
      final draft = drafts.putIfAbsent(
        uid,
        () => _Draft(
          uid: uid,
          email: email,
          name: member.displayName.trim(),
          photoUrl: member.photoUrl,
        ),
      );
      draft.tours.add(GroupContactTour(id: tour.id, name: tour.name));
    }
  }

  final contacts = [
    for (final draft in drafts.values)
      GroupContact(
        uid: draft.uid,
        email: draft.email,
        name: draft.name.isEmpty ? 'Traveler' : draft.name,
        photoUrl: draft.photoUrl,
        tours: List.unmodifiable(draft.tours),
      ),
  ];
  contacts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return contacts;
}

/// Whether a chat or call document was opened inside one of the user's tours.
/// Documents from before tours decided who can talk have no tour, and are left out.
bool isInMyTours(Map<String, dynamic>? data, Set<String> myTourIds) {
  final participants = data?['participants'];
  if (participants is List && participants.contains(aiGuideUid)) return true;
  final tourId = data?['sharedTourId'];
  return tourId is String && myTourIds.contains(tourId);
}

/// The AI Guide's user id. A chat with the Guide is the user's own, not a tour's.
const String aiGuideUid = 'bhromon_ai_advisor';

class _Draft {
  final String uid;
  final String email;
  final String name;
  final String? photoUrl;
  final List<GroupContactTour> tours = [];

  _Draft({
    required this.uid,
    required this.email,
    required this.name,
    this.photoUrl,
  });
}
