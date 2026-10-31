import 'package:bhromon/features/auth/data/google_sign_in_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

void main() {
  test('a phone without a Google credential provider is told the fix', () {
    const error = GoogleSignInException(
      code: GoogleSignInExceptionCode.providerConfigurationError,
      description: 'getCredentialAsync no provider dependencies found',
    );

    final message = googleSignInFailureMessage(error);

    expect(message, contains('Google Play services'));
    expect(message, isNot(contains('GoogleSignInException')));
  });

  test('a cancelled sign-in reads as aborted, as before', () {
    const error = GoogleSignInException(
      code: GoogleSignInExceptionCode.canceled,
    );

    expect(googleSignInFailureMessage(error), 'Google Sign-In aborted.');
  });

  test('other failures keep the raw exception, so they can be diagnosed', () {
    const error = GoogleSignInException(
      code: GoogleSignInExceptionCode.unknownError,
    );

    expect(googleSignInFailureMessage(error), isNull);
  });
}
