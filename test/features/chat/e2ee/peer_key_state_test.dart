import 'dart:typed_data';

import 'package:bhromon/features/chat/domain/e2ee/e2ee_exceptions.dart';
import 'package:bhromon/features/chat/domain/e2ee/peer_key_state.dart';
import 'package:bhromon/features/chat/domain/e2ee/prekey_bundle.dart';
import 'package:flutter_test/flutter_test.dart';

// The pinning rules for a contact's keys (E2EE_DESIGN.md, section 6). A changed
// identity never replaces the pin on its own: the user accepts it.

E2eePrekeyBundle bundleWith({
  required String deviceId,
  required int seed,
}) {
  return E2eePrekeyBundle(
    userId: 'uid-b',
    deviceId: deviceId,
    curve25519Key: Uint8List.fromList(List.filled(32, seed)),
    ed25519Key: Uint8List.fromList(List.filled(32, seed + 1)),
    identitySignature: Uint8List(64),
    oneTimeKeys: const [],
  );
}

void main() {
  final first = bundleWith(deviceId: 'device-b1', seed: 10);
  final second = bundleWith(deviceId: 'device-b2', seed: 50);

  test('the first bundle seen is pinned without a warning', () {
    final (state, observation) = const PeerKeyState().observe(first);
    expect(observation, KeyObservation.firstSeen);
    expect(state.pinned!.deviceId, 'device-b1');
    expect(state.hasChange, isFalse);
    expect(state.isVerified, isFalse);
  });

  test('the same identity seen again is unchanged', () {
    final (pinned, _) = const PeerKeyState().observe(first);
    final (state, observation) = pinned.observe(first);
    expect(observation, KeyObservation.unchanged);
    expect(state.hasChange, isFalse);
  });

  test('a different identity is a change: the pin stays, the new one waits',
      () {
    final (pinned, _) = const PeerKeyState().observe(first);
    final (state, observation) = pinned.observe(second);
    expect(observation, KeyObservation.changed);
    expect(state.pinned!.fingerprint, pinned.pinned!.fingerprint);
    expect(state.pending!.deviceId, 'device-b2');
    expect(state.hasChange, isTrue);
  });

  test('the warning stays when the old identity is seen again, until accepted',
      () {
    final (pinned, _) = const PeerKeyState().observe(first);
    final (changed, _) = pinned.observe(second);
    final (reverted, observation) = changed.observe(first);
    expect(observation, KeyObservation.unchanged);
    expect(reverted.hasChange, isTrue);
  });

  test('accepting a change pins the new identity and clears the warning', () {
    final (pinned, _) = const PeerKeyState().observe(first);
    final (changed, _) = pinned.observe(second);
    final accepted = changed.acceptChange();
    expect(accepted.pinned!.deviceId, 'device-b2');
    expect(accepted.hasChange, isFalse);
    expect(accepted.isVerified, isFalse);
  });

  test('verifying the pinned identity marks the contact verified', () {
    final (pinned, _) = const PeerKeyState().observe(first);
    final verified = pinned.verified(first.identityBlock);
    expect(verified.isVerified, isTrue);
  });

  test(
      'a verification of the old identity does not carry over an accepted change',
      () {
    final (pinned, _) = const PeerKeyState().observe(first);
    final (changed, _) = pinned.observe(second);
    final verifiedNew = changed.verified(second.identityBlock);
    expect(verifiedNew.acceptChange().isVerified, isTrue);

    final verifiedOld = pinned.verified(first.identityBlock);
    final (withChange, _) = verifiedOld.observe(second);
    expect(withChange.acceptChange().isVerified, isFalse);
  });

  test('refuses to verify an identity the contact never presented', () {
    final (pinned, _) = const PeerKeyState().observe(first);
    expect(
      () => pinned.verified(second.identityBlock),
      throwsArgumentError,
    );
  });

  test('round trips through its stored form', () {
    final (pinned, _) = const PeerKeyState().observe(first);
    final (changed, _) = pinned.observe(second);
    final stored = changed.verified(first.identityBlock);
    final restored = PeerKeyState.fromJson(stored.toJson());
    expect(restored.pinned!.fingerprint, stored.pinned!.fingerprint);
    expect(restored.pending!.fingerprint, stored.pending!.fingerprint);
    expect(restored.isVerified, isTrue);
  });

  test('a stored identity of the wrong size is refused', () {
    expect(
      () => PeerKeyState.fromJson({
        'pinned': {'deviceId': 'device-b1', 'identity': 'AAAA'},
      }),
      throwsA(isA<E2eeFormatException>()),
    );
  });
}
