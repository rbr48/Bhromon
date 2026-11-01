import 'package:bhromon/core/errors/failures.dart';
import 'package:bhromon/features/auth/data/google_sign_in_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

void main() {
  test('a phone without a Google credential provider is told the fix', () {
    const error = GoogleSignInException(
      code: GoogleSignInExceptionCode.providerConfigurationError,
      description: 'getCredentialAsync no provider dependencies found',
    );

    expect(
      googleSignInFailureReason(error),
      AuthFailureReason.googlePlayServices,
    );
  });

  test('a cancelled sign-in is a choice the user made, not an error', () {
    const error = GoogleSignInException(
      code: GoogleSignInExceptionCode.canceled,
    );

    expect(googleSignInFailureReason(error), AuthFailureReason.cancelled);
  });

  test('other failures are unknown, so the screen words them generically', () {
    const error = GoogleSignInException(
      code: GoogleSignInExceptionCode.unknownError,
    );

    expect(googleSignInFailureReason(error), AuthFailureReason.unknown);
  });
}
