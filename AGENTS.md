# Bhromon — Agent Memory & Project Playbook

This document serves as the persistent system memory, architectural guidelines, and operating playbook for the Bhromon project. It was compiled from comprehensive multi-session trajectory analysis.

---

## 1. Project Overview & Architecture
- **Repository**: [https://github.com/rbr48/Bhromon](https://github.com/rbr48/Bhromon)
- **Primary Branches**: `main` (active) and `master` (synchronized).
- **Architecture**: Clean Architecture (Domain, Data, Presentation) with BLoC state management, injectable DI, Drift (SQLite) for offline relational storage, and Hive for encrypted local boxes.
- **Backend**: Firebase Firestore (with offline persistence), Cloud Functions (TypeScript), Firebase Auth, Firebase Storage, and Firebase Hosting.
- **Live Deployments**:
  - **Flutter Web**: [https://app.bhromon.fun](https://app.bhromon.fun) / [https://bhromon-ff801.web.app](https://bhromon-ff801.web.app)
  - **Android Releases**: Signed release APK (`build/app/outputs/flutter-apk/app-release.apk`) & Play Store App Bundles (`aab`).

---

## 2. Google Play Store & Android Standards
1. **Target SDK**:
   - Always target **Android 16 (API Level 36)** or higher (`compileSdk 36`, `targetSdk 36`).
2. **Photo & Video Picker Compliance**:
   - Do **NOT** request broad storage permissions `READ_MEDIA_IMAGES` or `READ_MEDIA_VIDEO`.
   - Use the Android system Photo Picker via `image_picker` / system pickers.
3. **Version Numbering**:
   - In `pubspec.yaml`, increment version and version code monotonically on each release (e.g., `1.8.1+53`).
4. **Windows Gradle Build Contention**:
   - Always keep `org.gradle.vfs.watch=false` in `android/gradle.properties` to avoid Windows directory locks (`AccessDeniedException` during `mergeReleaseNativeLibs` or `packageRelease`).
   - In `android/app/build.gradle`, disable intermediate tasks: `artprofile`, `nativesymboltable`, `cleanmergereleaseassets`, and `cleanmergereleasenativelibs`.

---

## 3. Web Compatibility Invariants (`kIsWeb`)
1. **Zero `dart:io` on Web**:
   - Never call `Platform.isAndroid`, `Platform.isWindows`, or `Platform.operatingSystem` directly without guarding with `if (!kIsWeb)`.
2. **Background Services**:
   - Mobile-only background services (`SyncWorker`, `Workmanager`, `flutter_local_notifications`) must be wrapped with `if (!kIsWeb)`.
3. **Web Deployment Protocol**:
   - Build: `flutter build web --release`
   - Deploy: `firebase deploy --only hosting`

---

## 4. Key Subsystems & Business Logic

### A. Universal Tour Engine
- The app has transitioned from a hardcoded 5-day Cox's Bazar tour to a **Universal Tour Engine** (`lib/features/tour_group/`).
- Supports any destination, duration (e.g., 1-day day tour to multi-week treks), and tour style (Beach, Hill-Trek, Heritage/Cultural, Riverine, Nature/Forest).
- Computes dynamic itineraries, budget estimations, and packing checklists per person/family.

### B. Tour Group Hub & Trip Ledger
- **Firestore Security Rules**: Group owners are stored with `role: 'admin'` / `'owner'`.
- **Expense Allocation (`trip_ledger_engine.dart`)**: Always compute money in integer **paisa** (`toPaisa`) to avoid floating-point drift. Support weighted family headcounts.
- **Offline Resilience**: Offline caching in Hive/Drift with queue-based network replay.

### C. Tour Reels & Media Sharing
- Vertical reels video feed (`tour_instafeed_screen.dart`) matching Family Bhromon with video playback controls, aspect ratio fitting, upload flows, and media filters.

### D. Family Game Zone (`lib/features/game_zone/`)
1. **Card 29 (`card29/`)**:
   - 32 cards (J:3, 9:2, A:1, 10:1, K:0, Q:0, 8:0, 7:0).
   - Dynamic bidding up to 28 (not capped at 21).
   - Strict trump rule: if trump is asked and player cannot follow lead suit, they MUST play trump if held (`mustPlayTrumpIfHeld: true`).
   - Royalty pair bonus (+4 declarer points).
   - 6-pip match game tracking.
2. **Travel Chess AI (`chess/`)**:
   - Complete Kingside (`O-O`) and Queenside (`O-O-O`) castling.
   - En Passant capture logic.
   - Interactive promotion selector modal (Queen, Rook, Bishop, Knight).
   - King check visual alert and halo highlight.
   - Move history stack with Takeback (`undoMove()`).
   - Board coordinate annotations (`a-h`, `1-8`) and last-move highlights.
3. **Ludo Express (`ludo/`)**:
   - Home tokens remain docked and visible inside central home triangles.
   - Co-located tokens are displayed with clean visual offsets.
   - Three consecutive sixes forfeits the turn.
   - Pass & Play mode supporting any combination of Human and Bot players.
4. **Teen Patti (`teen_patti/`)**:
   - Sideshow / Back-Ask private comparison between adjacent seen players.
   - Dynamic bet raising up to 40 base / 80 chaal.
   - Blind turn limit (max 4).
   - Split pot on hand ties.
   - Real-time hand rank badge for seen cards.
   - Chip rebuy popup (+500 chips).

---

## 5. Testing & Quality Verification Checklist
Before shipping or pushing changes:
1. `flutter test test/features/game_zone/ test/features/tour_group/` -> All tests must pass.
2. `flutter analyze lib/` -> Must report `No issues found!` (0 errors, 0 warnings).
3. If building APK: `flutter build apk --release`.
4. If updating Web: `flutter build web --release` && `firebase deploy --only hosting`.
5. Keep `git status` clean and push to `main` and `master`.
