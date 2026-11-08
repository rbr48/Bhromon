import 'package:cloud_firestore/cloud_firestore.dart';

/// Profile fields only the server sets. The rules on `explorer_profiles` refuse an
/// owner's write that changes one of them, and refuse the whole document with it.
/// Keep this list in step with the protected fields in `firestore.rules`.
const serverOwnedProfileKeys = <String>{
  'explorerScore',
  'tier',
  'badges',
  'isPioneer',
  'isRegionExpert',
  'promotedBy',
};

/// What an owner's profile save writes: [profileJson] without the server-owned
/// fields. A copy loaded before the server changed a score, a badge or a tier
/// still holds the old value, and writing it back would be refused.
Map<String, dynamic> profileSavePayload(Map<String, dynamic> profileJson) {
  return {
    for (final entry in profileJson.entries)
      if (!serverOwnedProfileKeys.contains(entry.key)) entry.key: entry.value,
  };
}

/// Whether the server refused a profile save. A refusal is final and nothing was
/// stored. A timeout or a dropped connection is not: Firestore keeps that write
/// queued until the connection returns.
bool isProfileSaveRefused(Object error) =>
    error is FirebaseException && error.code == 'permission-denied';
