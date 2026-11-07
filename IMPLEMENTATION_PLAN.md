# Implementation Plan: Push Notification VPS Consolidation & De-duplication

## Objective
Completely consolidate push notification dispatching, token tracking, and scheduling onto the Hostinger VPS (`media-server:8210`). Eliminate duplicate/ghost notifications, de-duplicate triggers, and decommission notification triggers from Firebase Cloud Functions to achieve 100% zero-cost Firebase Spark plan operation.

---

## Phases & Tasks

### Phase 1: De-duplication & Cloud Functions Decommissioning (Immediate)
- [x] **Task 1.1: Remove Duplicate Notification Functions from `functions/src/index.ts`**
  - Unexport `sendSosAlert`, `sendCallPushNotification`, and `sendChannelNotification` from Cloud Functions.
  - Verify that only server games (`card29`, `teenPatti`, `carrom`), data compliance (`gdprDeleteUser`, `tourContentPurge`), and OTP remain.
- [x] **Task 1.2: Audit & Strengthen Client-side Direct REST Triggers**
  - Verify `VpsNotificationService.notifySos()` and `notifyChannelMessage()`.
  - Add deduplication ring buffer in `FirestoreNotificationWatcher` on VPS to prevent dual pings.
- [x] **Task 1.3: Run Verification Tests**
  - Execute `pytest media-server/tests/test_notifications.py media-server/tests/test_calling.py`.

### Phase 2: Migrate Feed, Moments, and Ledger Notifications to VPS
- [x] **Task 2.1: Add Multi-language Push Strings to `media-server/push_strings.py`**
  - Add English and Bengali templates for posts, comments, notices, and ledger expenses.
- [x] **Task 2.2: Implement Notification Methods in `NotificationEngine` (`notifications.py`)**
  - Implement `send_post_notification()`, `send_comment_notification()`, `send_notice_notification()`, and `send_ledger_notification()`.
- [x] **Task 2.3: Expose REST Endpoints on VPS (`/notify/*`)**
  - Add `POST /notify/post`, `POST /notify/notice`, and `POST /notify/ledger` in `media-server/main.py`.
  - Wire client calls into `tour_post_repository.dart`, `notice_repository.dart`, and `trip_ledger_repository.dart`.
- [x] **Task 2.4: Decommission Corresponding Cloud Functions**
  - Unexport `sendTourPostNotification`, `sendTourCommentNotification`, `sendTourNoticeNotification`, and `sendTourLedgerNotification` from `functions/src/index.ts`.

### Phase 3: Background Schedulers & Reminders on VPS
- [x] **Task 3.1: Consolidate Notice Reminders into `ack_reminders.py`**
  - Verify `AckReminderScheduler` handles unanswered notices for members who have not acknowledged mandatory tour announcements.
  - Decommission `sendTourNoticeReminders.ts` and `sendGeneralNotification.ts` from Cloud Functions.
- [x] **Task 3.2: Implement Broadcast Admin Endpoint on VPS**
  - Add `POST /api/admin/broadcast` in `media-server/main.py` protected by `require_platform_admin`.
  - Decommission `sendBroadcastNotification.ts` from Cloud Functions.

### Phase 4: Unified Token Registry & Resilience Hardening
- [x] **Task 4.1: SQLite Token Schema & Index Optimization**
  - Verify `device_tokens` table on the VPS with indexes on `(uid)`, `(email)`, and `(updated_at)`.
  - Add automatic stale token pruning (>180 days).
- [x] **Task 4.2: Watcher Auto-Reconnect & Stream Heartbeat**
  - Add automatic reconnect loop with exponential backoff in `FirestoreNotificationWatcher.start()` to survive network blips.
- [x] **Task 4.3: Health Check Endpoint Expansion**
  - Expand `GET /api/media/health` to expose active listeners count, scheduler status, and delivered notification counts.

### Phase 5: Verification, Tests & Deployment
- [x] **Task 5.1: Write Python & Flutter Automated Tests**
  - Expand `media-server/tests/test_notifications.py` to cover all new methods.
  - Expand `test/features/tour_group/` tests for `vps_notification_service`.
- [x] **Task 5.2: Run Full Suite Verification**
  - Run `pytest media-server/tests/`.
  - Run `dart analyze` and `flutter test`.
  - Run `npm test` in `functions/`.
- [x] **Task 5.3: Production Deployment to Hostinger VPS**
  - Run `media-server/deploy.sh` on Hostinger VPS and deploy notification worker.

---

## Phase 6: Fix TypeScript Compilation Errors in Cloud Functions & bhromon-games Docker Build

### Objective
Resolve all TypeScript compilation errors (`tsc exit code: 2`) across `functions/src/` caused by Firebase Admin v14 type changes and strict TypeScript checks, and upgrade `functions/Dockerfile` to `node:22-alpine` so that `docker compose build bhromon-games` succeeds cleanly.

### Tasks
- [x] **Task 6.1: Fix Firestore Type Namespaces and Exports in `functions/src/gameTable/shared.ts`**
  - Import and re-export `DocumentData`, `Transaction`, `DocumentReference`, `Firestore`, and `UpdateData` from `'firebase-admin/firestore'`.
- [x] **Task 6.2: Add Explicit Transaction Types to Game Callables**
  - Update `functions/src/card29/callables.ts`, `functions/src/teenPatti/callables.ts`, and `functions/src/carrom/callables.ts` to type `(tx: Transaction)`.
- [x] **Task 6.3: Fix Type Annotations Across Cloud Functions Handlers**
  - Fix `functions/src/computeExplorerScore.ts` (`snap.forEach((doc: QueryDocumentSnapshot) => ...)`).
  - Fix `functions/src/lib/accountTours.ts` (query snapshots and safe `toMillis` conversion).
  - Fix `functions/src/sendBroadcastNotification.ts` (`QueryDocumentSnapshot`).
  - Fix `functions/src/sendOtpEmail.ts` and `functions/src/verifyOtp.ts` (`tx: Transaction`).
  - Fix `functions/src/sendTourNoticeReminders.ts` (`tx: Transaction`).
  - Fix `functions/src/sendTourReactionNotification.ts` (`email: string`).
  - Fix `functions/src/tourContentPurge.ts` (`error`, `tx: Transaction`, query snapshots).
- [x] **Task 6.4: Upgrade `functions/Dockerfile` to `node:22-alpine`**
  - Match `"engines": { "node": ">=22" }` and AGENTS.md requirement.
- [x] **Task 6.5: Verify Compilation & Build Locally and on VPS**
  - Run `npm run build` in `functions/`.
  - Test `docker compose build bhromon-games` on VPS.
  - Open GitHub PR and merge to `main` (PR #364).

---

## Phase 7: Outbox Sync Guard & Unsent Changes Sign-Out Protection (Option A)

### Objective
Protect offline, device-only writes from accidental loss during sign-out or account switching. Implement queries in `AppDatabase` to detect pending outbox entries (`SyncOutboxTable`) and unpublished drafts (`TripLogsTable`), and add a safety confirmation guard before sign-out with clear localized warnings and options to wait for sync. Defer Google Drive backup until E2EE is fully implemented.

### Tasks
- [x] **Task 7.1: Add Pending Sync Count Queries in `AppDatabase`**
  - Implement `getPendingOutboxCount()`, `getDraftTripLogsCount()`, and `getTotalUnsyncedChangesCount()` in `lib/core/database/app_database.dart`.
- [x] **Task 7.2: Add Localization Strings for Unsynced Warnings**
  - Add English and Bengali translations for unsynced changes warning title, description, and action buttons in `lib/core/localization/translation_keys.dart`.
- [x] **Task 7.3: Implement Outbox Protection Guard in `_confirmLogout`**
  - Update `lib/features/explorer/presentation/pages/explorer_profile_screen.dart` to inspect `getTotalUnsyncedChangesCount()` before showing the logout dialog.
  - Present a high-contrast warning with unsynced count and cancel/sync button when un-synced data is pending.
- [x] **Task 7.4: Automated Unit & Widget Verification**
  - Write unit tests in `test/core/database/` or `test/features/` testing the outbox query and logout guard behavior.
  - Run `flutter test` and `dart analyze`.
- [x] **Task 7.5: Commit, Pull Request & Merge**
  - Commit changes, push branch, open PR, and merge to `main` (PR #366).

---

## Phase 8: Offline Vector Maps & MapLibre Web Worker Null Filter Sanitization

### Objective
Migrate offline maps from outdated raster/demo styles to OpenFreeMap Liberty vector tiles, eliminate Web Worker parsing exceptions (`Expected value to be of type number, but found null instead`), register missing POI sprites, and bundle the sanitized style locally in `assets/map/liberty_style.json` for 100% offline reliability.

### Tasks
- [x] **Task 8.1: Migrate to OpenFreeMap Liberty Vector Style (`PR #368`)**
  - Point `MapCacheManager.defaultStyleUrl` to OpenFreeMap Liberty vector tile endpoint.
  - Enable crisp multi-zoom vector tile rendering across Bangladesh travel zones.
- [x] **Task 8.2: MapLibre CircleOptions Opacity & Blur Null Safety (`PR #369`)**
  - Provide non-null defaults for `circleOpacity`, `circleBlur`, and `circleStrokeOpacity` in waypoint circle options.
- [x] **Task 8.3: Bundle Sanitized Offline Style & Coalesce Filter Guards (`PR #371`)**
  - Create `assets/map/liberty_style.json` bundled directly within Flutter app assets.
  - Guard all numeric comparison filters (`poi_r20`, `poi_r7`, `poi_r1`, `highway-shield-*`, `road_shield_us`, `label_country_3`) with `['coalesce', ['get', '...'], 0]` to eliminate worker type exceptions.
  - Remap missing OpenMapTiles POI classes (`ferry_terminal` → `ferry`, `swimming_pool` → `""`).
  - Pre-register transparent 1x1 fallback pixels in `OfflineMapViewerScreen` via `controller.addImage()`.
- [x] **Task 8.4: Verification, PR & Multi-Platform Release (v1.8.125+179)**
  - Unit tests in `test/features/tour_group/map_cache_manager_test.dart` and `offline_map_viewer_screen_test.dart`.
  - Static analysis: `flutter analyze` clean.
  - Merged PR #371 to `main`.
  - Deployed Flutter Web release to Firebase Hosting (`app.bhromon.fun`).
  - Built signed release APK (`173.2 MB`) and deployed to Hostinger VPS (`https://bhromon.fun/media/apk/app-release.apk`).
  - Built Play Store App Bundle (`135.0 MB`, `app-release.aab`).

---

## Phase 8B: Light Theme Contrast, Profile Memory Tab Removal & SOS Alert Hardening (Completed)

### Objective
Ensure full readability in Light Theme across the Tour Magazine/Scrapbook and Family Safety Hub screens, eliminate redundant Memory/Vault tab from user profile keeping SOS exclusively in group modules, and resolve Firestore [permission-denied] when resolving SOS emergency alerts.

### Tasks
- [x] **Task 8B.1: Light Theme Contrast in Tour Magazine & Scrapbook (scrapbook_magazine.dart)**
  - Replace static _ink, _gold, _muted constants with theme-aware _MagPalette (context.mag).
  - High-contrast ink on light paper (14:1+ contrast) and deep amber gold (4.5:1+ contrast) in Light Mode.
  - Preserve dark scrim contrast on Cover Page and chip badges.
- [x] **Task 8B.2: Light Theme Contrast in Family Safety Hub (`family_safety_hub_screen.dart`)**
  - Fix SOS beacon text (title & description) to use context.forest.text and context.forest.text70 when siren is inactive.
  - Audit border and icon styling for high-contrast presentation.
- [x] **Task 8B.3: Remove Redundant "Memory" Tab from Profile (profile_tabs.dart & explorer_profile_screen.dart)**
  - Remove 'vault' from profileTabKeys().
  - Remove vault tab item, switch case, and _buildKeepsakesTab() from explorer_profile_screen.dart.
  - Update test/features/explorer/profile_tabs_test.dart.
- [x] **Task 8B.4: Fix SOS Alert Permission-Denied Issue**
  - Add _pendingRaiseFuture in amily_safety_hub_screen.dart to await pending create before resolving.
  - In TourGroupRepository.resolveSafetyAlert, verify doc existence and handle already-resolved states gracefully.
  - Ensure irestore.rules case-insensitivity on esource.data.senderEmail.lower() == tourUserEmail().
- [x] **Task 8B.5: Verification, Tests, PR & Deployment (v1.8.126+180)**
  - Monotonic version bump in pubspec.yaml to 1.8.126+180.
  - Run dart format ., lutter analyze, and unit test suite.
  - Push branch, open PR via gh pr create --base main, and merge to main.
  - Deploy Flutter Web to Firebase Hosting.

---

## Phase 9: Everyday Group Specializations (Sprint 7 — Active Queue)

### Objective
Deliver complete, automated business workflows for daily group presets so that members interact with Bhromon every single day: monthly mess meal auto-balancing and printable sheets, apartment society service request photos and resolution timelines, office/campus acknowledgment dashboards with targeted reminder pings, and samity digital payout receipts.

### Tasks
- [ ] **Task 9.1: Mess Monthly Meal Rate Auto-Balancing & Settlement Generation**
  - Implement meal rate formula in `meal_engine.dart` (`Total Bazaar / Total Meals`).
  - Calculate member meal shares, compare against deposits, and compute net balances.
  - Build monthly settlement overview in `mess_ledger_screen.dart` with one-tap transfer creation.
  - Generate printable 31-day meal sheet PDF using `bangla_pdf`.
- [ ] **Task 9.2: Housing Society Service Request Photos & 3-State Timeline**
  - Enable multi-photo attachments (up to 3 photos) via `TourMediaUploader`.
  - Implement 3-state resolution timeline (Open $\rightarrow$ In Progress $\rightarrow$ Resolved) with admin notes.
  - Add flat number associations (`4A`, `6B`) with one-tap direct call shortcut.
  - Add one-tap action to book resolved repair costs directly to Society Maintenance in Ledger.
- [ ] **Task 9.3: Office & Campus Real-Time Acknowledgment Dashboard**
  - Add progress ring & counter on notices (`28/35 acknowledged (80%)`).
  - Add pending member drawer with one-click admin reminder ping via VPS.
  - Add campus picnic/event registration and contribution tracker.
- [ ] **Task 9.4: Samity Digital Payout Receipts & Rotation Handover**
  - Allow admin to attach photo of signed payout receipt or bank slip to `samity_payouts/{cycleKey}`.
  - Add beneficiary confirmation action (`payoutStatus: verified`).
- [ ] **Task 9.5: Automated Testing, PR & Verification**
  - Add unit tests for `meal_engine.dart` and `service_request_models.dart`.
  - Format with `dart format .` and verify with `flutter analyze`.


---

## Phase 10: Cross-Group Moments Sharing & Reposting

### Objective
Allow members to seamlessly share/repost Moments photos, videos, and reels from one group to any other group they belong to. Support both reposting to the destination group's Moments feed (with true media file isolation via `/api/media/copy` and source attribution) and sending post cards into target group chat channels.

### Tasks
- [x] **Task 10.1: Domain Models & Repost Metadata**
  - Update `TourPostItem` with `resharedFromTourId`, `resharedFromTourName`, `resharedFromAuthorName`, `resharedPostId`.
  - Update `toMap`, `fromMap`, `copyWith`, and constructor.
  - Update `TourGroupRepository.addPost` to pass reshared metadata.
- [x] **Task 10.2: Localization for Cross-Group Sharing**
  - Add English and Bengali strings to `tour_translation_keys.dart` for all cross-group share actions, hints, headers, and toasts.
- [x] **Task 10.3: Cross-Group Media Duplication & Isolation Logic**
  - Safely duplicate remote media (`images`, `videoUrl`, `coverUrl`) using `TourMediaUploader.copyMedia(tourId: targetTourId, folder: 'posts')` so destination groups retain full access independently of the source group.
- [x] **Task 10.4: Cross-Group Share UI Sheet (`cross_group_share_sheet.dart`)**
  - Build `CrossGroupShareSheet` with group picker (excluding current group), Moments feed repost flow with optional caption, and target channel selection.
- [x] **Task 10.5: Post Card Attribution Display (`InstafeedPostCard`)**
  - Display reshared attribution header chip (`Icons.repeat_rounded` + source group and author name).
- [x] **Task 10.6: Integration in `InstafeedShareSheet`**
  - Add "Share to another group" action in `InstafeedShareSheet` and wire it up.
- [x] **Task 10.7: Automated Unit & Widget Tests**
  - Add tests for model serialization, cross-group UI components, and attribution rendering.
  - Verify static analysis (`dart analyze`), formatting (`dart format`), and guard rules.
- [x] **Task 10.8: PR, CI Green Check, Merge & Web Deployment**
  - Increment version to `1.8.134+188`.
  - Create GitHub PR, monitor CI until 100% green, merge to `main`, and deploy to Firebase Hosting (`app.bhromon.fun`).

---

## Phase 11: Group Search in Group Section

### Objective
Provide instant, intuitive, and comprehensive search capabilities across groups in the Group Section (`/group-hub`) and the Circle Switcher bottom sheet. Users can filter their groups by name, category/preset (both in English and Bengali), trip destination, and invite code with real-time feedback, clear controls, and empty-state guidance.

### Tasks
- [x] **Task 11.1: Localization Strings in `tour_translation_keys.dart`**
  - Add English and Bengali keys for `hub_search_groups_hint`, `hub_clear_search`, `hub_no_groups_found`, `hub_no_groups_found_query`, and `hub_no_groups_found_sub`.
- [x] **Task 11.2: Group Search Filter Engine**
  - Implement robust matching logic that searches group names, presets, localized kind badges (e.g. Friends / বন্ধু, Mess / মেস, Office / অফিস, Family / পরিবার, etc.), destinations, and invite codes.
- [x] **Task 11.3: Group Hub Search UI in `tour_group_hub_screen.dart`**
  - Add inline search field in `_buildGroupsList` above the group cards with clear button.
  - Render empty search results card (`Icons.search_off_rounded`, localized message, and quick clear action) when no groups match.
  - Properly dispose `_searchController`.
- [x] **Task 11.4: Search in Circle Switcher (`_showCircleSwitcher`)**
  - Support instant filtering inside the circle switcher modal sheet when a user has multiple circles.
- [x] **Task 11.5: Automated Unit & Widget Tests**
  - Add tests in `test/features/tour_group/group_search_test.dart` verifying search filtering across names, types, destinations, and empty states.
  - Verify static analysis (`dart analyze lib/ test/`), formatting, and stream build guard.
- [ ] **Task 11.6: PR, CI Green Check, Merge & Web Deployment**
  - Increment version to `1.8.135+189` in `pubspec.yaml`.
  - Create GitHub PR via `gh pr create --base main`.
  - Monitor CI until 100% green, squash-merge to `main`, build web release, and deploy to Firebase Hosting (`app.bhromon.fun`).
