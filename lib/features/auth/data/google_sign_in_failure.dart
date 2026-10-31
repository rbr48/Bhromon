import 'package:google_sign_in/google_sign_in.dart';

/// The message a user can act on for a Google Sign-In failure, or null when the
/// failure has no such message and is reported as it is.
///
/// Google Sign-In asks the phone's Google credential provider, which comes with
/// Google Play services. A phone or emulator without it fails with
/// `providerConfigurationError`. The raw exception tells the user nothing they can
/// act on, so this gives the fix instead.
String? googleSignInFailureMessage(GoogleSignInException error) {
  switch (error.code) {
    case GoogleSignInExceptionCode.canceled:
      return 'Google Sign-In aborted.';
    case GoogleSignInExceptionCode.providerConfigurationError:
      return 'Google Sign-In needs Google Play services on this phone. '
          'Sign in to Google Play, update Google Play services, '
          'then try again.';
    default:
      return null;
  }
}
