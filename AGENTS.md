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
- **Access is membership-based.** `memberships/{tourId}__{email}` decides who can read a tour. Roles are `owner`, `admin` and `member`. Only the owner changes ownership or the invite code, or promotes someone to admin. Admins edit trip details and remove members; the owner's row cannot be removed.
- **Invite codes** live in `invites/{code}`: readable by exact code, never listed. Codes are 8 characters from an unambiguous alphabet (legacy 6-character codes still work). Joining always creates a plain member and is refused for accounts in `tours/{id}/bans`. Removing a member writes a ban and deletes the row together.
- **Rules are tested on the emulator:** `functions/tests/tour_group_rules.test.js`, `tour_group_storage_rules.test.js` and `firestore.rules.test.js` all share one emulator project. Run them with `npx firebase-tools@13.35.1 emulators:exec --only firestore,storage --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/"`. `--runInBand` is required because the suites clear that project. Storage rules look up memberships on the emulator's `--project`, so the flag must name that project. The CLI is pinned: firebase-tools 15.x fails the Storage rules' firestore lookups, which denies every upload.
- **Expense allocation (`trip_ledger_engine.dart`):** always integer paisa. User amounts go through `parseTakaInput` (Bengali digits accepted; zero, negative and over-cap amounts refused). Each expense is split among its participants (default: every member), weighted by `familyCount` (1 to 20, which members can set for themselves). Payers and depositors who have left keep their balance; email matching ignores case.
- **Offline:** the tour list comes from memberships, not the cache, so tours the user left stop showing. A write that is not acknowledged within 8 seconds is reported as syncing and kept queued; a rejected write is removed from the local cache.
- **Known limits:** the bus layout is a fixed 36-seat coach. The SOS button vibrates and can share the current location, but it does not push an alert to other members. Tide times are estimates and are labelled that way.

### C. Tour Reels & Media Sharing
- Vertical reels video feed (`tour_instafeed_screen.dart`) matching Family Bhromon with video playback controls, aspect ratio fitting, upload flows, and media filters.
- **Uploads go through `TourMediaUploader`.** Size and type are checked before anything is sent. Files live under `tours/{id}/{folder}/` and are tagged with `uploadedByEmail` metadata, which the storage rules use to allow later deletes by the uploader or an admin. Limits match `storage.rules`: images 10 MB, videos 100 MB, reels 3 minutes.
- Posts never store device paths or blob URLs. A post with an unfinished upload is refused, and a failed or cancelled post deletes the files it uploaded.
- **Platform code:** `dart:io` is imported only in `tour_media_upload_io.dart`. Web uses `putData` and blob URLs.
- **Not done yet:** reel thumbnails are not generated. `video_thumbnail` resolves, but adding it downgrades five transitive packages, so it needs a decision first.

### D. Family Game Zone (`lib/features/game_zone/`)
Game rules live in pure-Dart models/engines (unit-tested); screens only render and drive timers.
Every game screen locks portrait (`common/game_zone_portrait_lock.dart`), keeps its game in a
static session while the user visits other screens, and asks before discarding a game in progress.
1. **Card 29 (`card29/`, model `card29_game.dart`)**:
   - 32 cards (J:3, 9:2, A:1, 10:1, K:0, Q:0, 8:0, 7:0) + 1 for the last trick = 29.
   - Bidding 16–28 from the dealer's left, a pass is final, dealer rotates; all-pass → dealer plays at 16.
   - Strict trump rule: once trump is revealed, any player who cannot follow lead suit MUST play trump if held (`mustPlayTrumpIfHeld: true`), on every trick. The bidder reveals trump by playing it while void and may not lead the hidden trump suit; a trump-suit discard before the reveal has no trump power (`PlayedCard.trumpEligible`).
   - Pair (royalty, K+Q of trump, after reveal): bidding team target −4 (min 16), opponents' pair → target +4 (max 28). Bots claim it too.
   - A finished trick sits in `Card29Phase.trickComplete` until `resolveTrick()`, so no card can be played during the pause.
   - 6-pip match game tracking; a new round after `matchOver` starts a fresh match.
2. **Travel Chess AI (`chess/`)**:
   - Complete Kingside (`O-O`) and Queenside (`O-O-O`) castling (needs the own rook on its corner; moving or capturing on a corner revokes the right).
   - En Passant capture logic; search uses exact make/unmake (`_doMove`/`_undoRecord`), never ad-hoc board edits.
   - Interactive promotion selector modal (Queen, Rook, Bishop, Knight); dismissing it cancels the move.
   - King check visual alert and halo highlight.
   - Move history with SAN notation and Takeback (`undoMove()` restores castling rights, en passant and clocks).
   - Draws: stalemate, insufficient material, 50-move rule, threefold repetition, draw offer; resign.
   - AI (negamax + alpha-beta + quiescence) runs via `compute(chessAiWorker, ChessAiRequest(...))`; depths Easy 1 / Medium 2 / Hard 4.
   - Board coordinate annotations (`a-h`, `1-8`) and last-move highlights.
3. **Ludo Express (`ludo/`)**:
   - Home tokens remain docked and visible inside central home triangles.
   - Tokens sharing a square split it as a 2×2 grid.
   - Three consecutive sixes forfeits the turn; the counter resets on every turn change (`passTurn()`).
   - Pass & Play mode supporting any combination of Human and Bot players (at least one human); any mode change restarts the turn flow.
   - Board grid is 6:3:6 in every band; track cells are outlined, start squares tinted, safe squares starred.
4. **Teen Patti (`teen_patti/`, model `teen_patti_game.dart`)**:
   - Ranking: Trail > Pure sequence > Sequence > Colour > Pair > High card; A-K-Q is the top run, A-2-3 the lowest.
   - Sideshow (Back-Ask): a seen player asks the previous seen player to compare privately; the target may decline; a tie packs the asker.
   - Dynamic bet raising up to 40 base / 80 chaal; every stake checks the player's chips first (no negative balances).
   - Blind turn limit (max 4).
   - Show ties split the pot between the tied players only; the pot is cleared on payout; pot limit 1280 forces a show.
   - Real-time hand rank badge for seen cards.
   - Chip rebuy popup (+500 chips) when you can't cover boot + one blind.
5. **Carrom (`carrom/`, physics `carrom_engine.dart`, rules `carrom_game.dart`)**:
   - Deterministic fixed-step physics (1/480 s) on a 0..1 board with ICF proportions: friction, cushion and coin restitution, a striker ~2.6× a coin's mass, 4 corner pockets.
   - You play white from the bottom baseline; the opponent (bot or Pass & Play) plays black from the top. Striker slides along the baseline (drag or slider) and may not touch a coin; drag back anywhere and release to shoot.
   - Own coin pocketed → shoot again; opponent-colour coins stay down and count for the opponent.
   - Strict ICF fouls: striker pocketed, own last coin before the queen is covered (including covering her with it in the same shot), or the opponent's last coin. On a foul the shot's own coins, the queen and the opponent's last coin return, one penalty coin is paid and the turn ends; with nothing to pay the penalty is due (`penaltyDue`) and taken from the next coin pocketed.
   - Queen only after an own coin; must be covered on the same or next shot or she returns.
   - First to 9 coins wins the board: 1 point per opponent coin left, +3 for covering the queen.
   - Bot (`CarromBot`) builds cut shots from ghost-ball geometry with the minimum power that carries the coin (friction + momentum transfer), simulates each candidate, and adds aim noise per difficulty (Easy 0.035 / Medium 0.018 / Hard 0.008 rad). It runs via `compute(carromBotWorker, ...)`.

---

## 5. Testing & Quality Verification Checklist
Before shipping or pushing changes:
1. `flutter test test/features/game_zone/ test/features/tour_group/` -> All tests must pass.
2. `flutter analyze lib/` -> Must report `No issues found!` (0 errors, 0 warnings).
3. If building APK: `flutter build apk --release`.
4. If updating Web: `flutter build web --release` && `firebase deploy --only hosting`.
5. Keep `git status` clean and push to `main` and `master`.
