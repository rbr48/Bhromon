import 'package:flutter/foundation.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

// ── PII Scrubber ─────────────────────────────────────────────────────────────
// Masks Bangladeshi phone numbers, emails, and Firebase UIDs from log output
// to prevent accidental PII leakage in log aggregators.
String _maskPii(String message) {
  // BD mobile numbers: 01X-XXXXXXXX or +8801X-XXXXXXXX
  var masked = message.replaceAllMapped(
    RegExp(r'(?:\+?88)?01[3-9]\d{8}'),
    (_) => '***PHONE***',
  );
  // Email addresses
  masked = masked.replaceAllMapped(
    RegExp(r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}'),
    (_) => '***EMAIL***',
  );
  // Firebase-style UIDs (28-char alphanumeric)
  masked = masked.replaceAllMapped(
    RegExp(r'\b[A-Za-z0-9]{28}\b'),
    (_) => '***UID***',
  );
  return masked;
}

// ── Talker instance ───────────────────────────────────────────────────────────
final appLogger = TalkerFlutter.init(
  settings: TalkerSettings(
    enabled: true,
    useHistory: true,
    maxHistoryItems: 200,
  ),
);

// ── Convenience wrappers ──────────────────────────────────────────────────────

void logInfo(String message, [Object? error, StackTrace? stack]) {
  appLogger.info(_maskPii(message));
}

void logWarning(String message, [Object? error, StackTrace? stack]) {
  final safe = _maskPii(message);
  appLogger.warning(safe, error, stack);
  // Forward warnings to Crashlytics as non-fatal in release builds
  if (!kIsWeb && kReleaseMode) {
    try {
      FirebaseCrashlytics.instance.recordError(
        error ?? Exception(safe),
        stack,
        reason: safe,
        fatal: false,
      );
    } catch (_) {}
  }
}

void logError(String message, [Object? error, StackTrace? stack]) {
  final safe = _maskPii(message);
  appLogger.error(safe, error, stack);
  // Forward errors to Crashlytics as non-fatal in release builds
  if (!kIsWeb && kReleaseMode) {
    try {
      FirebaseCrashlytics.instance.recordError(
        error ?? Exception(safe),
        stack,
        reason: safe,
        fatal: false,
      );
    } catch (_) {}
  }
}

void logDebug(String message) {
  if (kDebugMode) appLogger.debug(_maskPii(message));
}
