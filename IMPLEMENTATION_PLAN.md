# Implementation Plan: Dual-Agent Roadmap Coordination (Claude & Antigravity)

## Overview
This implementation plan establishes the collaboration roadmap between **Claude** and **Antigravity** to complete all remaining project deliverables as requested by the user, tracked via [Issue #435](https://github.com/rbr48/Bhromon/issues/435).

---

## Strict Merging Invariant & Dual-Agent Review Gate (MANDATORY)
1. **Mutual Peer Review Required**: Even when all CI checks are green, **NEVER merge any PR to `main` before Antigravity and Claude review each other's PR on GitHub.**
2. **Exchanged Sign-Off**: Mutual peer review comments, guidance, and explicit sign-offs must be documented in PR comments prior to merge.
3. **Green Required CI Checks**: Zero tolerance for failing or in-progress checks on required workflows at merge time (`Dart Format`, `Analyze`, `Build Web (release)`, `Test`, and `Build Android (debug APK)` when triggered). Note: Intentionally skipped jobs (such as `Build iOS (no codesign)`) do not block merge.
4. **Zero Direct Main Commits**: Every change must go through a dedicated topic branch and PR via GitHub PR tools or `gh pr create --base main`.
5. **Branch Isolation**: Track A (Claude) uses `claude/*` branches; Track B/C (Antigravity) uses `feat/*`, `fix/*`, or `docs/*` branches.
6. **Mandatory Pre-Push Checks**: Run `dart format .`, `dart analyze`, and `pytest media-server/tests` (for media-server changes) prior to pushing to ensure zero regressions before GitHub Actions CI executes.

---

## Track Breakdown & Ownership

### Track A: Study Group Subsystem (Claude)
- [x] **Phase 9: Weekly Challenge & Today Card** ([PR #434](https://github.com/rbr48/Bhromon/pull/434) - Merged to `main` with `GroupBackButton` and `GroupPopScope`)
- [x] **Phase 10: Problem Sets, Content Reporting & Admin Reviews**
  - Problem Sets: grouping problems under named sets with due dates ([PR #441](https://github.com/rbr48/Bhromon/pull/441), [PR #451](https://github.com/rbr48/Bhromon/pull/451), [PR #452](https://github.com/rbr48/Bhromon/pull/452)).
  - Report button on problems, working, findings, and summaries ([PR #440](https://github.com/rbr48/Bhromon/pull/440), [PR #446](https://github.com/rbr48/Bhromon/pull/446), [PR #449](https://github.com/rbr48/Bhromon/pull/449)).
  - Admin reviewing member working & removing invalid reviews ([PR #438](https://github.com/rbr48/Bhromon/pull/438)).
  - **Peer Review Gate**: Submit PR, wait for Antigravity review and sign-off, verify 100% green CI before merge.

---

### Track B: Platform, Media Server & Multi-Platform UX (Antigravity)
- [x] **Task P11.1: Hostinger VPS Asynchronous Reel Poster Generation** ([PR #436](https://github.com/rbr48/Bhromon/pull/436) - Merged to `main`)
  - Created `media-server/media_utils.py` with standardized 720x1280 WebP video poster generation via FFmpeg.
  - Added full test coverage in `media-server/tests/test_media_utils.py` and `test_official_feed.py` (446/446 passed, pyflakes clean).
- [x] **Task P11.2: Desktop Web Three-Column Responsive Experience**
  - Verified 3-pane shell in `trip_shell.dart`, `desktop_tour_sidebar.dart`, and `desktop_right_dock.dart`.
  - Verified `Ctrl+K` global quick search shortcut across desktop views.
- [x] **Task P11.3: Android 16 Edge-to-Edge & Performance Hardening**
  - Verified zero system bar gesture overlap (`compileSdk 36`, `targetSdk 36`, cutout shortEdges).
- [x] **FinTech Documentation Sync**
  - Updated `AGENTS.md` with completed monthly ledger PDF export and `mfs_trx_registry` deduplication write paths.

---

### Track C: Travel Spot & Route Map Overlay / FinTech Refinements (Antigravity)
- [x] **Task P9.3: Vector Map Route Checkpoint Overlay** ([PR #439](https://github.com/rbr48/Bhromon/pull/439), [PR #443](https://github.com/rbr48/Bhromon/pull/443) - Merged to `main`):
  - Converted `RoutePlan.legs` into dynamic MapLibre GeoJSON line layers; rendered mode-specific route paths and numbered checkpoints directly on top of offline vector tiles.
- [x] **MFS Duplicate TrxID Prevention & Navigation Hardening** ([PR #448](https://github.com/rbr48/Bhromon/pull/448), [PR #450](https://github.com/rbr48/Bhromon/pull/450) - Merged to `main`):
  - Added atomic deduplication registry `tours/{id}/mfs_trx_registry/{trxId}` with rules coverage.
  - Hardened Android hardware back and top app bar navigation across group modules.

---

### Track E: Full E2EE Task (1-on-1 Lifecycle, Key Hardening & Multi-Party Group Channels Architecture)
- [x] **Task E1: E2EE Auto-Provisioning on Native (`ensureReady`)**:
  - Automatically provisions native users on sign-in or chat opening (`E2eeChatController.instance.ensureReady(uid)`).
  - Ensures new accounts publish Identity Keys and prekeys without requiring manual navigation to verification screens.
- [x] **Task E2: Key Lifecycle Hardening (Orphaned Claim Pruning)**:
  - Added `deleteStaleClaimedOneTimeKeys` to `E2eeKeyStore` and implemented in `E2eeFirestoreKeys` (querying `claimedAt < olderThan`).
  - Added periodic pruning in `E2eeService.prepare()` (default 24h stale claim window).
- [x] **Task E3: Chat List UI Indicators & Safety Number Export**:
  - Added lock badge indicator on `ChatTile` when `data['e2ee'] == true`.
  - Formatted encrypted message preview subtitle (`🔒 Encrypted` instead of raw unicode padlock marker `\u{1F512}`).
  - Added "Copy Safety Number" button in `E2eeVerificationScreen` with localized clipboard feedback.
- [x] **Task E4: Multi-Party Group Channels E2EE Architecture (`E2EE_GROUP_DESIGN.md`)**:
  - Authored comprehensive cryptographic specification for group channels using Megolm Sender-Key ratchet ($O(1)$ symmetric broadcast encryption).
  - Designed forward/backward secrecy re-keying on membership join/leave/kick events.
  - Defined Ed25519 payload signatures for `/split` expenses and integer-paisa financial ledger integrity.
  - Specified cryptographic tombstone protocol for admin message redaction.
- [x] **Task E5: Test Suite Verification**:
  - Comprehensive unit test coverage across all E2EE modules (`e2ee_service_test.dart`, `e2ee_chat_controller_test.dart`, `verification_screen_test.dart`).
- [ ] **Peer Review Gate**: Submit PR, wait for Claude's review and sign-off, verify 100% green CI before merge.
