# Implementation Plan: Remaining Track E (E2EE Activation) & Sprint 11 Delivery

## Objective
Complete the remaining milestones per the project roadmap and user directives:
1. **Track E: E2EE Activation in Code**:
   - Turn `kE2eeOneToOne` on by default (`defaultValue: true`) in `feature_flags.dart` for Android/mobile native builds.
   - Guard against Web builds (`!kIsWeb`) where native C/Rust Olm bindings are excluded by design.
   - Update and verify `e2ee_chat_controller_test.dart` and the entire 96-test E2EE suite.
2. **Sprint 11: Desktop & Platform Verification**:
   - Verify 3-column desktop layout in `trip_shell.dart` (`DesktopTourSidebar` + `DesktopRightDock` + content max width).
   - Verify Android 16 (API 36) edge-to-edge window display cutout support.
3. **Quality Gates & PR Delivery**:
   - `flutter analyze` clean (0 errors, 0 warnings).
   - `dart format .` 100% compliant.
   - All tests pass (Dart/Flutter, pytest 439/439).
   - Monotonic version bump in `pubspec.yaml` to `1.8.160+214`.
   - Feature branch → Pull Request → 100% Green CI → Merge.

---

## Atomic Tasks

### Track E: End-to-End Encryption Activation
- [x] **Task 1: Enable E2EE Flag by Default**
  - Updated `kE2eeOneToOne` in `lib/core/config/feature_flags.dart` with `defaultValue: true`.
  - Maintained `enabledInBuild => kE2eeOneToOne && !kIsWeb` to guard web platforms cleanly.
- [x] **Task 2: Update Controller Unit Tests**
  - Updated `test/features/chat/e2ee/e2ee_chat_controller_test.dart` to assert default enablement on supported native builds.
  - Verified safe fallback when native library is absent on host test runners.
  - Passed all 96 E2EE unit tests.

### Sprint 11: Desktop & Platform Integrity
- [x] **Task 3: Desktop Three-Pane Layout Integrity**
  - Verified `trip_shell.dart` 3-column responsive shell with `DesktopTourSidebar` (260px) and `DesktopRightDock` (280px-320px).
- [x] **Task 4: Android 16 Edge-to-Edge**
  - Verified `compileSdk 36`, `targetSdkVersion 36`, and `windowLayoutInDisplayCutoutMode: shortEdges`.

### Quality Gates, PR & Merge
- [x] **Task 5: Code Quality & Analysis**
  - Ran `dart format .` (0 changed).
  - Ran `flutter analyze` (0 issues found).
  - Ran `pytest media-server/tests/` (439/439 passed).
- [ ] **Task 6: PR Creation & CI Verification**
  - Monotonic version bump in `pubspec.yaml` to `1.8.160+214`.
  - Create Pull Request for `feat/enable-e2ee-and-sprint11` to `main`.
  - Strictly monitor CI checks until 100% green before merging.
