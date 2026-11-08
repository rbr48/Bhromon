import 'dart:async';

import 'package:bhromon/core/entities/explorer_profile.dart';
import 'package:bhromon/core/value_objects/explorer_score.dart';
import 'package:bhromon/core/value_objects/trust_tier.dart';
import 'package:bhromon/features/auth/data/profile_save_policy.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A profile as the server last stored it: a community member with a score and a badge.
  final stored = ExplorerProfile(
    uid: 'uid-save-test',
    displayName: 'Rahim',
    explorerScore: const ExplorerScore(value: 120, tier: TrustTier.community),
    tier: TrustTier.community,
    badges: const ['first_trip'],
    division: 'Sylhet',
    createdAt: DateTime(2026, 1, 2),
    isPioneer: true,
    isRegionExpert: true,
    avatarUrl: 'https://bhromon.fun/media/avatar.jpg',
    bio: 'Hello',
  );

  group('profileSavePayload', () {
    test('leaves out every server-owned field', () {
      final payload = profileSavePayload(stored.toJson());

      expect(
        payload.keys.toSet().intersection(serverOwnedProfileKeys),
        isEmpty,
      );
    });

    test('keeps the fields the owner edits, and the uid', () {
      final payload = profileSavePayload(stored.toJson());

      expect(payload['uid'], 'uid-save-test');
      expect(payload['displayName'], 'Rahim');
      expect(payload['division'], 'Sylhet');
      expect(payload['bio'], 'Hello');
      expect(payload['avatarUrl'], 'https://bhromon.fun/media/avatar.jpg');
    });

    test('does not change the map it is given', () {
      final json = stored.toJson();

      profileSavePayload(json);

      expect(json.containsKey('tier'), isTrue);
    });
  });

  group('isProfileSaveRefused', () {
    test('is true only for a refusal by the server', () {
      expect(
        isProfileSaveRefused(FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        )),
        isTrue,
      );
      expect(
        isProfileSaveRefused(FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
        )),
        isFalse,
      );
      expect(isProfileSaveRefused(TimeoutException('no answer yet')), isFalse);
    });
  });
}
