import 'package:google_sign_in/google_sign_in.dart';
import '../../../core/errors/failures.dart';

/// Why a Google Sign-In attempt failed, so the sign-in screen can tell the user
/// what to do.
///
/// Google Sign-In asks the phone's Google credential provider, which comes with
/// Google Play services. A phone or emulator without it fails with
/// `providerConfigurationError`, and the fix is to sign in to Google Play and
/// update Google Play services. Any other code is [AuthFailureReason.unknown],
/// so the screen shows a generic message and the raw exception goes to the log.
AuthFailureReason googleSignInFailureReason(GoogleSignInException error) =>
    switch (error.code) {
      GoogleSignInExceptionCode.canceled => AuthFailureReason.cancelled,
      GoogleSignInExceptionCode.providerConfigurationError =>
        AuthFailureReason.googlePlayServices,
      _ => AuthFailureReason.unknown,
    };
