import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

class DateTimeConverter implements JsonConverter<DateTime, dynamic> {
  const DateTimeConverter();

  @override
  DateTime fromJson(dynamic json) {
    if (json == null) return DateTime.now();
    if (json is Timestamp) {
      return json.toDate();
    }
    if (json is String) {
      return DateTime.parse(json);
    }
    if (json is int) {
      return DateTime.fromMillisecondsSinceEpoch(json);
    }
    // Handle cases where a Map representing timestamp is parsed (e.g. from some other serializers)
    if (json is Map) {
      final seconds = json['_seconds'] ?? json['seconds'];
      final nanoseconds = json['_nanoseconds'] ?? json['nanoseconds'];
      if (seconds != null) {
        return Timestamp(seconds as int, (nanoseconds ?? 0) as int).toDate();
      }
    }
    return DateTime.now();
  }

  @override
  dynamic toJson(DateTime object) => object.toIso8601String();
}

class NullableDateTimeConverter implements JsonConverter<DateTime?, dynamic> {
  const NullableDateTimeConverter();

  @override
  DateTime? fromJson(dynamic json) {
    if (json == null) return null;
    if (json is Timestamp) {
      return json.toDate();
    }
    if (json is String) {
      return DateTime.parse(json);
    }
    if (json is int) {
      return DateTime.fromMillisecondsSinceEpoch(json);
    }
    if (json is Map) {
      final seconds = json['_seconds'] ?? json['seconds'];
      final nanoseconds = json['_nanoseconds'] ?? json['nanoseconds'];
      if (seconds != null) {
        return Timestamp(seconds as int, (nanoseconds ?? 0) as int).toDate();
      }
    }
    return null;
  }

  @override
  dynamic toJson(DateTime? object) => object?.toIso8601String();
}
