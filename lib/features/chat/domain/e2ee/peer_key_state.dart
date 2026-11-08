import 'dart:convert';
import 'dart:typed_data';

import 'package:bhromon/features/chat/domain/e2ee/e2ee_exceptions.dart';
import 'package:bhromon/features/chat/domain/e2ee/prekey_bundle.dart';
import 'package:bhromon/features/chat/domain/e2ee/safety_number.dart';

/// The device behind a contact's bundle: its device id and its identity block (the
/// Curve25519 identity key, then the Ed25519 key). Two identities are the same when
/// their identity blocks are the same.
class PeerIdentity {
  const PeerIdentity({required this.deviceId, required this.identityBlock});

  factory PeerIdentity.fromBundle(E2eePrekeyBundle bundle) {
    return PeerIdentity(
      deviceId: bundle.deviceId,
      identityBlock: bundle.identityBlock,
    );
  }

  factory PeerIdentity.fromJson(Map<String, dynamic> json) {
    final deviceId = json['deviceId'];
    final identity = json['identity'];
    if (deviceId is! String || identity is! String) {
      throw const E2eeFormatException('a stored peer identity is malformed');
    }
    final Uint8List block;
    try {
      block = base64Url.decode(identity);
    } on FormatException {
      throw const E2eeFormatException(
          'a stored peer identity is not base64url');
    }
    if (block.length != SafetyNumber.identityBlockLength) {
      throw const E2eeFormatException(
          'a stored peer identity has the wrong size');
    }
    return PeerIdentity(deviceId: deviceId, identityBlock: block);
  }

  final String deviceId;

  /// 64 bytes: the Curve25519 identity key, then the Ed25519 key.
  final Uint8List identityBlock;

  /// The identity block as text. Equal identities have equal fingerprints.
  String get fingerprint => base64Url.encode(identityBlock);

  Map<String, Object> toJson() => {
        'deviceId': deviceId,
        'identity': fingerprint,
      };
}

/// What one bundle showed about a contact's identity (E2EE_DESIGN.md, section 6).
enum KeyObservation {
  /// The first bundle seen from this contact. Its identity is pinned.
  firstSeen,

  /// The identity is the pinned one.
  unchanged,

  /// The identity differs from the pinned one. The chat keeps working, the contact
  /// is shown as unverified, and a warning stays until the user accepts the change.
  changed,
}

/// The keys this device has pinned for one contact. It is pure data: the caller
/// stores it and passes each new bundle through [observe].
///
/// A change is never applied on its own. The new identity is kept as [pending]
/// until the user accepts it with [acceptChange], so the warning stays until the
/// user has seen it.
class PeerKeyState {
  const PeerKeyState({this.pinned, this.pending, this.verifiedFingerprint});

  factory PeerKeyState.fromJson(Map<String, dynamic> json) {
    final Object? pinned = json['pinned'];
    final Object? pending = json['pending'];
    final Object? verified = json['verified'];
    if (verified != null && verified is! String) {
      throw const E2eeFormatException('a stored verification is malformed');
    }
    return PeerKeyState(
      pinned: pinned == null ? null : PeerIdentity.fromJson(_object(pinned)),
      pending: pending == null ? null : PeerIdentity.fromJson(_object(pending)),
      verifiedFingerprint: verified as String?,
    );
  }

  /// The identity this device trusts for the contact, or null before the first
  /// bundle.
  final PeerIdentity? pinned;

  /// A different identity seen since the pin, waiting for the user to accept it.
  final PeerIdentity? pending;

  /// The fingerprint the user compared in person, if any.
  final String? verifiedFingerprint;

  /// Whether the user has compared the pinned identity with the contact.
  bool get isVerified =>
      pinned != null && verifiedFingerprint == pinned!.fingerprint;

  /// Whether a changed identity is waiting for the user.
  bool get hasChange => pending != null;

  /// Records the identity a bundle presents. Returns the new state and what the
  /// bundle showed. A bundle with a different identity does not replace the pin.
  (PeerKeyState, KeyObservation) observe(E2eePrekeyBundle bundle) {
    final seen = PeerIdentity.fromBundle(bundle);
    final current = pinned;
    if (current == null) {
      return (PeerKeyState(pinned: seen), KeyObservation.firstSeen);
    }
    if (seen.fingerprint == current.fingerprint) {
      return (
        PeerKeyState(
          pinned: seen,
          pending: pending,
          verifiedFingerprint: verifiedFingerprint,
        ),
        KeyObservation.unchanged,
      );
    }
    return (
      PeerKeyState(
        pinned: current,
        pending: seen,
        verifiedFingerprint: verifiedFingerprint,
      ),
      KeyObservation.changed,
    );
  }

  /// Trusts the pending identity. Verification carries over only if the user had
  /// already compared that identity.
  PeerKeyState acceptChange() {
    final next = pending;
    if (next == null) {
      return this;
    }
    return PeerKeyState(
      pinned: next,
      verifiedFingerprint:
          verifiedFingerprint == next.fingerprint ? verifiedFingerprint : null,
    );
  }

  /// Records that the user compared [identityBlock] with the contact. It must be
  /// the pinned identity or the pending one.
  PeerKeyState verified(Uint8List identityBlock) {
    final fingerprint = base64Url.encode(identityBlock);
    if (fingerprint != pinned?.fingerprint &&
        fingerprint != pending?.fingerprint) {
      throw ArgumentError.value(
        identityBlock,
        'identityBlock',
        'not an identity this contact presented',
      );
    }
    return PeerKeyState(
      pinned: pinned,
      pending: pending,
      verifiedFingerprint: fingerprint,
    );
  }

  Map<String, Object> toJson() => {
        if (pinned != null) 'pinned': pinned!.toJson(),
        if (pending != null) 'pending': pending!.toJson(),
        if (verifiedFingerprint != null) 'verified': verifiedFingerprint!,
      };

  static Map<String, dynamic> _object(Object value) {
    if (value is! Map) {
      throw const E2eeFormatException(
          'a stored peer identity is not an object');
    }
    return Map<String, dynamic>.from(value);
  }
}
