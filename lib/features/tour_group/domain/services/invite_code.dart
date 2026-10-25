import 'dart:math';

/// Letters and digits without the look-alikes 0/O and 1/I, so codes read
/// aloud or copied from a chat are not misread.
const String inviteCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// Length of codes created from now on. Eight characters from 32 symbols is
/// about a trillion combinations, so guessing a code is not practical.
const int inviteCodeLength = 8;

/// Creates a random invite code using a cryptographically secure generator.
String generateInviteCode({Random? random, int length = inviteCodeLength}) {
  final source = random ?? Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    buffer.write(inviteCodeAlphabet[source.nextInt(inviteCodeAlphabet.length)]);
  }
  return buffer.toString();
}

/// Accepts current 8-character codes and the older 6-character codes that are
/// still in use. Input is expected in upper case with surrounding spaces removed.
bool isValidInviteCode(String code) =>
    RegExp(r'^[A-Z0-9]{6,8}$').hasMatch(code);
