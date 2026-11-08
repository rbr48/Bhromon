# Technical Concerns & Architectural Guardrails

**Analysis Date:** 2026-11-07

## 1. Windows Gradle Build Locks & Intermediate Cache
- **Risk**: Windows directory locking can cause `AccessDeniedException` during release APK/AAB compilation if Java daemons remain active.
- **Mitigation**:
  - `org.gradle.vfs.watch=false` in `android/gradle.properties`.
  - Always terminate lingering Java daemons before building (`Stop-Process -Name java -Force`).
  - Periodically clean `build/test_cache` and `.dart_tool/flutter_build` to prevent disk bloat.

## 2. Google Play App Signing vs Upload Key (Google Sign-In Error 10)
- **Risk**: Google Play strips developer upload keys and signs release builds with Google's managed App signing key.
- **Mitigation**: Both Upload Key and Google Play App Signing Key SHA-1/SHA-256 fingerprints must remain registered in Firebase Console and Google Cloud OAuth Client IDs.

## 3. Web Platform Boundaries
- **Risk**: Direct usage of `dart:io` or mobile background workers crashes on Flutter Web.
- **Mitigation**: Strict use of `kIsWeb` guards on all background workers, notifications, and file system access.

## 4. Firestore Query Boundaries & Cost Optimization
- **Risk**: Unbounded queries on feed or moments can cause high read costs and UI jank.
- **Mitigation**: Feed uses `PagedPostFeed` with fixed 60-post query boundaries (`createdAt < upper`, `>= lower`) and composite indexes.
