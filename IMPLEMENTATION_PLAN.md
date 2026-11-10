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
- [x] **Peer Review Gate**: Submit PR, wait for Claude's review and sign-off, verify 100% green CI before merge ([PR #453](https://github.com/rbr48/Bhromon/pull/453)).

---

### Track F: Power Documents & Study Pack (Expanded Document Attachments)
- [x] **Task F1: Domain & Service MIME Expansion (`media_rules.dart`, `study_material_rules.dart`)**:
  - Added supported extensions and MIME types:
    - Markdown & Text: `.md` (`text/markdown`), `.log` (`text/plain`)
    - Data & Config: `.json` (`application/json`), `.yaml` / `.yml` (`application/x-yaml`), `.xml` (`application/xml`), `.sql` (`application/sql`)
    - Open Document & Formatted: `.odt` (`application/vnd.oasis.opendocument.text`), `.ods` (`application/vnd.oasis.opendocument.spreadsheet`), `.odp` (`application/vnd.oasis.opendocument.presentation`), `.rtf` (`application/rtf`), `.tsv` (`text/tab-separated-values`)
    - E-Books: `.epub` (`application/epub+zip`)
    - Compressed Archives: `.rar` (`application/x-rar-compressed`), `.7z` (`application/x-7z-compressed`), `.tar` (`application/x-tar`), `.gz` (`application/gzip`)
  - Exposed `kSupportedDocExtensions` canonical list (27 extensions).
- [x] **Task F2: UI Attachment Pickers & Visual Bubbles (`chat_attachment_sheet.dart`, `group_channels_screen.dart`, `study_material_composer.dart`, `chat_document_bubble.dart`)**:
  - Unified allowed extensions across 1-on-1 chats, group channels, and study materials using `kSupportedDocExtensions`.
  - Added presentation support (`ppt`, `pptx`, `odp`) to 1-on-1 chat picker.
  - Enriched `ChatDocumentBubble` extension badge colors and labels for new document types.
- [x] **Task F3: Firebase Storage Rules & VPS Media Server Update (`storage.rules`, `media-server/main.py`)**:
  - Expanded `storage.rules` `contentType.matches(...)` pattern for documents.
  - Added new extensions to `DOC_EXTENSIONS` and `FILENAME_PATTERN` in `media-server/main.py`.
- [x] **Task F4: Automated Verification & Unit Tests**:
  - Unit tests in `media_formats_test.dart` and `study_material_rules_test.dart` (all 29 tests passing).
  - Python tests for media server upload validation (`test_media_server.py`, all 502 suite tests passing).
  - Version monotonically incremented to `1.8.168+222`.
- [x] **Task F5: Peer Review, Merge & Deploy**:
  - Create feature branch `feat/power-documents-pack`.
  - Push branch, open PR, request peer review from Claude, await 100% green CI.
  - Merge after mutual review sign-off ([PR #458](https://github.com/rbr48/Bhromon/pull/458) & [PR #459](https://github.com/rbr48/Bhromon/pull/459)).

---

### Track G: Web Mobile Google Play Store Action Button (Antigravity)
- [x] **Task G1: Google Play Action Button Widget (`google_play_action_button.dart`)**:
  - Create `GooglePlayActionButton` widget with custom vector `GooglePlayLogoPainter` rendering official Google Play logo.
  - External launch handler using `url_launcher` targeting `https://play.google.com/store/apps/details?id=com.bhromon.app&pli=1`.
  - Localized tooltip support (`hub_google_play_tooltip`).
- [x] **Task G2: Tour Group Hub AppBar Integration (`tour_group_hub_screen.dart`)**:
  - Insert `if (kIsWeb) const GooglePlayActionButton()` immediately before the language globe icon in AppBar `actions`.
- [x] **Task G3: Translations & Test Verification**:
  - Add `hub_google_play_tooltip` to English and Bengali dictionaries in `tour_translation_keys.dart`.
  - Add unit and widget tests for `GooglePlayActionButton`.
  - Run `flutter test test/core/localization/tour_translation_test.dart` and `dart analyze`.
- [x] **Task G4: Version Bump & Playbook Memory Update**:
  - Increment version to `1.8.169+223` in `pubspec.yaml` and update `AGENTS.md`.
- [x] **Task G5: Peer Review & Deployment Cycle**:
  - Push branch, open PR, mutual peer review with Claude, verify 100% green CI, merge to `main` ([PR #461](https://github.com/rbr48/Bhromon/pull/461)).
  - Full deployment: Firestore rules, Storage rules, VPS media server, Web Hosting, APK to VPS, and Play Store AAB.

---

### Track H: In-App Document Viewers (Markdown & PDF)
- [x] **Task H1: Markdown In-App Viewer Screen (`markdown_viewer_screen.dart`)**:
  - Fullscreen reading screen supporting remote URLs (`signedMediaUrl`), local file paths, and raw text.
  - Integration with Bhromon's forest-themed `ChatRichText` (tables, code blocks, checklists, math, copy, share).
  - Responsive layout reading container (`maxWidth: 800`).
- [x] **Task H2: PDF In-App Viewer Screen (`pdf_viewer_screen.dart`)**:
  - Add `pdfx: ^2.11.0` to `pubspec.yaml`.
  - Fullscreen pinch-to-zoom multi-page PDF viewing with page indicator and jump slider.
  - Network streaming/caching, local file support, and "Open externally" fallback.
- [x] **Task H3: App Touchpoint Integration (`chat_document_bubble.dart`, `study_materials_screen.dart`)**:
  - Intercept `.md` and `.pdf` taps in 1-on-1 chats and group channels to launch in-app viewers.
  - Intercept `.md` and `.pdf` study materials to open in-app study reading mode.
- [x] **Task H4: Translations & Unit/Widget Tests**:
  - Add localized strings for viewer actions (`viewer_download`, `viewer_share`, `viewer_copy`, `viewer_open_external`, `viewer_page_count`).
  - Write widget and unit tests for both viewer screens (`document_viewers_test.dart` 6/6 passed).
  - Verify `tour_translation_test.dart` (9/9 passed) and full `dart analyze` (0 issues).
- [ ] **Task H5: Version Bump, Peer Review & Merge**:
  - Increment version to `1.8.170+224` in `pubspec.yaml` and update `AGENTS.md`.
  - Push branch `feat/in-app-document-viewers`, open PR, peer review with Claude, merge on green CI.
