import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

import 'package:bhromon/core/entities/explorer_profile.dart';
import 'package:bhromon/core/value_objects/explorer_score.dart';
import 'package:bhromon/core/value_objects/trust_tier.dart';

/// FlutterSecureStorage stand-in that counts reads (each one is a
/// platform-channel round trip on a device).
class CountingSecureStorage implements FlutterSecureStorage {
  final Map<String, String> values = {};
  int reads = 0;
  int writes = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final key = invocation.namedArguments[#key] as String?;
    if (invocation.memberName == #read) {
      reads++;
      return Future<String?>.value(values[key]);
    }
    if (invocation.memberName == #write) {
      writes++;
      final value = invocation.namedArguments[#value] as String?;
      if (key != null && value != null) values[key] = value;
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

/// Points Hive at a fresh temp directory. Returns a cleanup callback.
Future<Future<void> Function()> setUpTempHive() async {
  final dir = await Directory.systemTemp.createTemp('bhromon_hive_');
  Hive.init(dir.path);
  return () async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  };
}

ExplorerProfile viewer(String uid, {String division = 'Dhaka'}) =>
    ExplorerProfile(
      uid: uid,
      displayName: 'Viewer $uid',
      explorerScore: const ExplorerScore(value: 0, tier: TrustTier.community),
      tier: TrustTier.community,
      badges: const [],
      division: division,
      createdAt: DateTime(2024),
    );

/// A trip log document as Firestore would return it.
Map<String, dynamic> tripLogDoc({
  required String authorId,
  required DateTime lastConfirmed,
  String visibility = 'community',
  String division = 'Dhaka',
  String title = 'Trip',
  String text = '',
}) =>
    {
      'authorId': authorId,
      'title': title,
      'locationPinId': 'pin_1',
      'division': division,
      'district': division,
      'blocks': [
        if (text.isNotEmpty)
          {'runtimeType': 'text', 'id': 'b1', 'content': text},
      ],
      'routePoints': <dynamic>[],
      'costItems': <dynamic>[],
      'trustScore': 50,
      'helpfulVotes': 3,
      'lastConfirmed': Timestamp.fromDate(lastConfirmed),
      'visibility': visibility,
    };

Map<String, dynamic> profileDoc(int score, {String name = 'Explorer'}) => {
      'displayName': name,
      'explorerScore': {'value': score, 'tier': 'community'},
      'tier': 'community',
      'badges': <dynamic>[],
      'division': 'Dhaka',
      'createdAt': '2024-01-01T00:00:00.000',
    };

Map<String, dynamic> tipDoc(int votes, {String pinId = 'pin_1'}) => {
      'locationPinId': pinId,
      'authorId': 'author',
      'text': 'Tip with $votes votes',
      'category': 'general',
      'helpfulVotes': votes,
      'outdatedVotes': 0,
      'lastConfirmed': '2026-01-01T00:00:00.000',
      'decayStatus': 'fresh',
    };

Map<String, dynamic> pinDoc(int i, {double? lat, double? lng}) => {
      'name': 'Pin $i',
      'geoHash': '',
      'lat': lat ?? 20.5 + (i % 600) * 0.01,
      'lng': lng ?? 88.0 + (i ~/ 600) * 0.05,
      'trustTier': 'verified',
      'lastConfirmed': '2026-01-01T00:00:00.000',
      'linkedTripIds': <dynamic>[],
      'linkedTipIds': <dynamic>[],
      'division': 'Dhaka',
      'district': 'Dhaka',
      'createdByUid': 'u',
      'category': 'place',
    };
