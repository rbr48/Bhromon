/// Whether the signed-in person and a partner can call each other inside the tour
/// they share. It follows the call rules: both membership rows must be active, and
/// the partner's row must carry the partner's uid.
enum CallPartnerStatus {
  /// Both are active members of the tour, and the partner's row is linked to them.
  ready,

  /// The signed-in person is no longer an active member of the tour.
  youLeft,

  /// The partner is no longer an active member of the tour.
  partnerLeft,

  /// The partner's row has no uid yet. The uid is written when the partner opens
  /// the app, so they have not opened Bhromon since they were added to the tour.
  partnerNotLinked,

  /// The signed-in person and the partner share no tour that either is still in.
  noSharedTour,
}

/// The status of a call between the signed-in person and a partner, given the two
/// membership rows. A row that does not exist is null.
CallPartnerStatus callPartnerStatusFor({
  required Map<String, dynamic>? myRow,
  required Map<String, dynamic>? partnerRow,
  required String partnerUid,
}) {
  if (myRow == null || myRow['status'] != 'active') {
    return CallPartnerStatus.youLeft;
  }
  if (partnerRow == null || partnerRow['status'] != 'active') {
    return CallPartnerStatus.partnerLeft;
  }
  final linkedUid = partnerRow['uid'];
  if (linkedUid is! String || linkedUid.isEmpty || linkedUid != partnerUid) {
    return CallPartnerStatus.partnerNotLinked;
  }
  return CallPartnerStatus.ready;
}
