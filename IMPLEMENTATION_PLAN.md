# Implementation Plan: Sprints 8 to 10 Full Implementation

## Objective
Deliver full implementations for Sprints 8, 9, and 10 per `ROADMAP.md`:
1. **Sprint 8 — Calls & Voice Lounge**:
   - Task 8.1: Quality HUD verification & test coverage.
   - Task 8.2: Call Reconnection (10s timeout window & attempt budget).
   - Task 8.3: Voice Lounge Speaking Indicator in Docked Floating Bar.
   - Task 8.4: In-chat search tests & verification.
2. **Sprint 9 — Travel & Live Journey**:
   - Task 9.1: Live Journey GA verification & documentation.
   - Task 9.2: Local Fare Guide Sourced Audit (source & as-of date per route + UI badge).
   - Task 9.3: Route Checkpoint Overlay (numbered checkpoints & route polyline on map).
   - Task 9.4: Multi-Stop Itinerary PDF export entry point & tests.
3. **Sprint 10 — Ledger & FinOps**:
   - Task 10.1: Duplicate TrxID Prevention (UI validation, localized messages, rules tests).
   - Task 10.2: Statement PDF Date Range (current month, whole tour, custom range).
   - Task 10.3: Fund Burn-Rate Alerts (80% caution, 100% critical) unit test suite.
4. **Quality Gates & PR Delivery**:
   - `flutter analyze` clean (0 errors, 0 warnings).
   - `dart format .` 100% compliant.
   - Unit and rules tests green.
   - Monotonic version bump in `pubspec.yaml`.
   - Feature branch → Pull Request → 100% Green CI → Merge.

---

## Atomic Tasks

### Sprint 8: Calls and Chat
- [x] **Task 8.1: Quality HUD & Reconnect Tuning**
  - Verify `_reconnectTimeout` is set to 10 seconds in `CallSignalingService`.
  - Add unit tests for `CallReconnectPolicy` and `CallQualityHud` in `test/features/chat/call_quality_test.dart`.
- [x] **Task 8.2: Speaking Indicator in Docked Voice Bar**
  - In `group_channels_screen.dart`, update `_buildDockedVoiceBar` to render active speaker avatars with the animated mint-green speaking ring when participants talk.
  - Verify audio level detection and speaking indicator behavior in unit tests.
- [x] **Task 8.3: Chat Search Verification**
  - Add comprehensive unit tests in `test/features/chat/chat_search_test.dart` verifying case-insensitivity, whitespace trimming, and empty query matching.

### Sprint 9: Travel and Live Journey
- [x] **Task 9.1: Local Fare Guide Sourced Audit**
  - Add `source` and `asOf` fields to `LocalTransitRoute` in `local_fare_guide.dart`.
  - Annotate all Bangladesh transit routes with authoritative sources (e.g. BRTA, Chander Gari Samity, BIWTA) and as-of dates.
  - Render source and as-of badge on `local_fare_guide_sheet.dart`.
  - Update `test/features/tour_group/local_fare_guide_test.dart`.
- [x] **Task 9.2: Route Checkpoint Numbered Overlay**
  - In `offline_map_viewer_screen.dart`, display numbered indices (1, 2, 3...) on checkpoint markers and waypoints so travelers can follow ordered legs.
- [x] **Task 9.3: Itinerary PDF UI Entry Points & Tests**
  - Add PDF export button in `journey_tracker_screen.dart` and `itinerary_editor.dart` wired to `exportItineraryPdf`.
  - Add unit tests in `test/features/tour_group/itinerary_pdf_test.dart`.

### Sprint 10: Ledger and FinOps
- [x] **Task 10.1: Duplicate TrxID Prevention & Localized Warnings**
  - Add `mfs_trx_duplicate_error` localized string (BN & EN) to `tour_translation_keys.dart` and translation JSON files.
  - In `expense_editor.dart` and `mfs_settlement_sheet.dart`, check `isMfsTrxRegistered` before submission and display error message on duplicate.
  - Add emulator test in `functions/tests/mfs_rules.test.js` asserting second create on duplicate `trxId` fails.
- [x] **Task 10.2: Statement PDF Date Range Selection**
  - In `expense_ledger_screen.dart`, add "Whole Tour / Group History" (`whole_tour`) option to `_exportMonthlyPdf`.
  - Confirm MFS audit table reflects verification statuses (`verified`, `unverified`, `disputed`).
- [x] **Task 10.3: Fund Burn-Rate Alerts Unit Tests**
  - Add unit tests in `test/features/tour_group/fund_analytics_test.dart` verifying `BurnRateAlert.normal`, `caution` (≥80%), and `critical` (≥100%).

### Verification, Release & PR
- [x] **Task 11.1: Automated Code Quality Verification**
  - Run `dart format .`.
  - Run `flutter analyze`.
  - Run `flutter test`.
- [ ] **Task 11.2: Monotonic Version Bump & PR Delivery**
  - Bump version in `pubspec.yaml` to `1.8.159+213`.
  - Create feature branch `feat/sprint8-10-full-implementation`.
  - Push and open PR via `gh pr create --base main`.
  - Wait for ALL CI checks to pass 100% green before merging!
