// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';

/// A message read from the phone's own cache, in the shape the chat shows live messages in. It
/// is shown when a chat opens, until the server's first answer replaces it.
///
/// Firestore marks its snapshot classes sealed. This one is implemented all the same, as test
/// fakes are, so a cached message goes through the same list and the same bubbles as a live one.
class CachedMessageDoc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  CachedMessageDoc({
    required this.id,
    required Map<String, dynamic> data,
    required this.reference,
  }) : _data = data;

  @override
  final String id;

  final Map<String, dynamic> _data;

  @override
  final DocumentReference<Map<String, dynamic>> reference;

  @override
  Map<String, dynamic> data() => _data;

  @override
  bool get exists => true;

  @override
  final SnapshotMetadata metadata = const _CachedMetadata();

  @override
  dynamic get(Object field) => _data[field];

  @override
  dynamic operator [](Object field) => _data[field];
}

class _CachedMetadata implements SnapshotMetadata {
  const _CachedMetadata();

  @override
  bool get hasPendingWrites => false;

  @override
  bool get isFromCache => true;
}
