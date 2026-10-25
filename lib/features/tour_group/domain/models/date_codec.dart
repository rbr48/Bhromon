import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads a date that is stored either as a Firestore [Timestamp] (current
/// writes) or as an ISO-8601 string (documents written before schema 4).
/// Returns null when the value is missing or unreadable.
DateTime? readDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// Stores a date as a Firestore [Timestamp] so that queries and ordering work.
Timestamp writeDate(DateTime value) => Timestamp.fromDate(value);

/// Emails are compared case-insensitively everywhere in the tour group code.
String normalizeEmail(String email) => email.trim().toLowerCase();
