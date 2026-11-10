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
- [x] **Task H5: Version Bump, Peer Review & Merge**:
  - Increment version to `1.8.170+224` in `pubspec.yaml` and update `AGENTS.md`.
  - Push branch `feat/in-app-document-viewers`, open PR, peer review with Claude, merge on green CI ([PR #462](https://github.com/rbr48/Bhromon/pull/462)).

---

### Track I: Exam Question Bank & Direct Bilingual Reader Experience (Redesigned Presentation)
- [x] **Task I1: Chapter Card Direct Action Buttons (`study_book_chapters_screen.dart`)**:
  - Watch `study_materials` for the book and map materials by `chapterId`.
  - On each chapter card (`_chapterCard`), display direct 1-tap action buttons:
    - 🇬🇧 **[English Solution]** (with file size)
    - 🇧🇩 **[বাংলা সমাধান]** (with file size)
  - Tapping either button immediately opens `MarkdownViewerScreen.open(...)` in full-screen with zero intermediate popups.
- [x] **Task I2: Fullscreen Direct Reading & Language Badges (`study_materials_screen.dart`)**:
  - Remove cramped `AlertDialog` popup when tapping study notes; open full-screen `MarkdownViewerScreen` directly.
  - Add clear visual language badges (`🇧🇩 বাংলা` / `🇬🇧 English`) on material cards.
- [x] **Task I3: In-Reader Question Navigator (TOC) & 1-Tap Bilingual Toggle (`markdown_viewer_screen.dart`)**:
  - Parse question headings (`### Question \d+`, `### প্রশ্ন \d+`, etc.) into an interactive Table of Contents.
  - Add an AppBar action for "Questions" (প্রশ্নসমূহ) opening a bottom sheet to jump to any question.
  - Add 1-tap language toggle button (`[বাংলায় দেখুন]` / `[View in English]`) to seamlessly switch between English and Bangla solutions.
- [x] **Task I4: Direct Exam Papers Portal (`study_subject_screen.dart`)**:
  - Route `StudyModuleKey.papers` directly to the subject's book chapters and solutions instead of empty posts screen.
- [x] **Task I5: Localization & Automated Tests**:
  - Add translation keys for reader tools and chapter actions in `tour_translation_keys.dart`.
  - Write widget and unit tests for TOC parser, direct chapter card buttons, and reader language toggle.
  - Run `flutter test test/features/tour_group/presentation/pages/document_viewers_test.dart` and `test/features/tour_group/study_material_screens_test.dart`.
- [x] **Task I6: Version Bump, Dual-Agent Review Gate, Merge & Deployment**:
  - Incremented version to `1.8.171+225` in `pubspec.yaml`.
  - Pushed feature branch `feat/exam-study-portal-redesign`, opened [PR #463](https://github.com/rbr48/Bhromon/pull/463).
  - Formal peer review sign-off by Claude CLI completed and approved.
  - 100% green required CI checks (`Dart Format`, `Analyze`, `Test`, `Build Web`, `Build Android`).
  - Squash-merged to `main`.
  - Deployed to Flutter Web (Firebase Hosting at `app.bhromon.fun`) and deployed release APK to Hostinger VPS.

---

### Track J: Document Viewers & Question Navigator Theme Contrast & Readability
- [x] **Task J1: Theme-Adaptive Typography & Contrast in Markdown Viewer (`markdown_viewer_screen.dart`)**:
  - Replace hardcoded `Colors.white` in AppBar title with `palette.text` so topic name is crisp and visible in both light and dark modes.
  - In `_openQuestionNavigator` bottom sheet, replace hardcoded `Colors.white`, `Colors.white70`, and `Colors.white12/10` with `palette.text`, `palette.text70`, and `palette.divider12/10`.
  - Update Question Navigator leading icon containers, border colors, and badge colors with `palette.accentText` and `palette.readable(...)`.
  - Update AppBar action icons and language toggle badge to use `palette.accentText` for high contrast against light surfaces.
- [x] **Task J2: Theme-Adaptive Typography in PDF Viewer (`pdf_viewer_screen.dart`)**:
  - Replace hardcoded `Colors.white` in AppBar title and bottom page indicator with `palette.text` and `palette.card`.
  - Use `palette.accentText` for AppBar action icons and controls.
- [x] **Task J3: High-Contrast Solution Action Buttons in Chapters Screen (`study_book_chapters_screen.dart`)**:
  - Adapt `English Solution` and `বাংলা সমাধান` button styles to theme: light tinted background with dark readable text in light mode, deep forest green with mint text in dark mode.
- [x] **Task J4: Test Verification & Version Bump**:
  - Add light mode and dark mode contrast tests to `document_viewers_test.dart` and `study_chapter_screens_test.dart`.
  - Bump version to `1.8.172+226`.
- [x] **Task J5: Dual-Agent Review Gate, Merge & Deployment**:
  - Open PR, run Claude CLI peer review, ensure 100% green CI, merge to `main` ([PR #466](https://github.com/rbr48/Bhromon/pull/466)).
  - Deployed to Firebase Hosting (`https://app.bhromon.fun`) and release APK deployed to Hostinger VPS (`v1.8.172+226`).

---

## 9-Pillar Banking Exam Master Plan (Pure Deterministic & Collaborative Engineering)

### Track K: Dual-Language Synchronized Split Reader (Feature 1)
- [x] **Task K1: Dual-Pane Layout Builder (`markdown_viewer_screen.dart`)**:
  - Add split-view mode when alternate content exists.
  - Automatically activate side-by-side mode on wide screens (`width >= 720`), with manual toggle icon on tablets/foldables.
  - Render English solution in left pane, Bangla solution in right pane with distinct subtle language header tags.
- [x] **Task K2: Synchronized Bidirectional Scroll Controller**:
  - Implement bidirectional synchronized scroll physics: scrolling either column smoothly drives the other column to the corresponding question anchor.
  - Jump-to-question in Question Navigator syncs both columns simultaneously.
- [x] **Task K3: Unit & Widget Tests**:
  - Test split-view rendering on wide vs narrow constraints in `document_viewers_test.dart` (all 12 tests passed).

---

### Track L: Official Syllabus & Module Tagging (Topic Filter) (Feature 2)
- [x] **Task L1: Module & Topic Taxonomy Data Model (`study_syllabus_models.dart`)**:
  - Defined IBB JAIBB official syllabus modules (Modules A, B, C, D, E) for all 7 subjects (LPGB, POE, MAFS, OM, GFI, BCFI, BA).
  - Deterministic length-prioritized, score-weighted keyword association algorithm in `StudySyllabusCatalog.identifyModule(subject, questionText)` (unit tested).
- [x] **Task L2: Topic Filter UI (`study_book_chapters_screen.dart` / `markdown_viewer_screen.dart`)**:
  - Interactive Module Filter Chips (`All Modules`, `Module A`, `Module B`, `Module C`, etc.) in Question Navigator bottom sheet and Chapter screen.
  - Question Navigator badges display `Mod A`, `Mod B` alongside question titles with module description subtitle.
  - Added official syllabus blueprint card at the top of `StudyBookChaptersScreen`.
- [x] **Task L3: Unit & Widget Test Verification**:
  - Unit tests in `study_syllabus_models_test.dart` (4/4 passed).
  - Localization parity in `tour_translation_test.dart` (9/9 passed).
  - Widget tests in `document_viewers_test.dart` (14/14 passed) and `study_chapter_screens_test.dart` (10/10 passed).

---

### Track M: Spaced-Repetition Flashcards Engine (Leitner Algorithm) (Feature 3)
- [x] **Task M1: Spaced Repetition Domain Models & Engine (`study_flashcard_rules.dart`, `study_flashcard_models.dart`)**:
  - Implemented 5-box Leitner algorithmic scheduler with deterministic review intervals (Box 1: 1 day, Box 2: 2 days, Box 3: 4 days, Box 4: 8 days, Box 5: 16 days).
  - Added 3-tier candidate rating enum `FlashcardRating` (`again`, `good`, `easy`) with corresponding box progression logic in `nextLeitnerBoxForRating`.
  - Added optional `moduleCode` property to `StudyFlashcard` with JSON serialization round-trip support.
- [x] **Task M2: Deterministic Card Extractor from Exam Solutions (`study_flashcard_extractor.dart`)**:
  - Deterministic regex-based extraction of sub-questions `1(a)` / `১(ক)` and corresponding answers from past paper Markdown solutions.
  - Automatic official syllabus module mapping via `StudySyllabusCatalog.identifyModule`.
  - Deterministic SHA-256 card IDs to prevent duplicate card creation across multiple extractions.
- [x] **Task M3: Interactive Flashcard Study Screen & Review (`study_flashcards_screen.dart`, `study_flashcard_review_screen.dart`)**:
  - Tap-to-flip card interaction with module badges (`Mod A`, `Mod B`) and box indicator (`Box 1..5`).
  - 3 self-rating assessment buttons: `Again` (resets to Box 1), `Good` (advances +1 Box), `Easy` (advances +2 Boxes).
  - One-tap "Generate from Past Papers" action in `StudyFlashcardsScreen` reading published exam solutions.
- [x] **Task M4: Unit & Widget Test Verification**:
  - Added unit test suite in `study_flashcard_extractor_test.dart` (3/3 passing).
  - Enriched `study_learning_rules_test.dart` with 3-tier rating and `moduleCode` JSON round-trip tests (all 31 tests passing).
  - Preserved translation key parity in `tour_translation_test.dart` (all 9 tests passing).
  - 0 analyzer issues, version bumped to `1.8.175+229`.

---

### Track N: 3-Hour Timed Exam Simulator (Distraction-Free) (Feature 4)
- [ ] **Task N1: Exam Simulator Screen (`study_exam_simulator_screen.dart`)**:
  - Fullscreen exam mode: pick any past paper, choose timer (3 hours standard, 1h/2h practice).
  - Floating HUD countdown timer with color shift and vibration alert at 30 min and 10 min.
- [ ] **Task N2: Digital Scratchpad & Section Navigator**:
  - Collapsible question tray to jump between questions.
  - Rich draft notepad where candidates outline points, formulas, and legal sections.
- [ ] **Task N3: Post-Exam Comparison Mode**:
  - When time expires or submitted, split-screen review comparing the candidate's scratchpad notes against the official examiner-grade model answers.

---

### Track O: Group Study Accountability & Daily Branch Streak (Feature 5)
- [x] **Task O1: Daily Study Habit & Streak Engine (`study_daily_streak_rules.dart`, `study_streak_models.dart`)**:
  - Implemented 6-tier progression (`none`, `spark`, `flame`, `blaze`, `inferno`, `legendary`) with monthly freeze pass protection.
  - Generates 7-day visual presence track (Mon–Sun).
  - Deterministic peer rankings and benchmarks across 6 top Bangladeshi banks ([PR #474](https://github.com/rbr48/Bhromon/pull/474) - Merged).
- [x] **Task O2: Branch Activity Grid & Leaderboard Widget (`study_daily_streak_card.dart`, `branch_study_hall_sheet.dart`)**:
  - Embedded `StudyDailyStreakCard` with flame counter, tier badge, and 7-day indicators.
  - Interactive `BranchStudyHallSheet` leaderboard with bank filters and peer cheer action.

---

### Track P: Markup Menu, In-App PDF Reader & Discussion Threads (Feature 6)
- [x] **Task P1: Markup Menu & Dual-Language In-App Reader**:
  - Replaced table action with comprehensive Markup Menu ([PR #468](https://github.com/rbr48/Bhromon/pull/468) - Merged).
  - PDF solutions and past exam question papers open seamlessly inside the app.
  - Chapter discussion and study notes enabled.

---

### Track Q: Full Offline Vault (1-Tap Zero-Network Mode) (Feature 7)
- [x] **Task Q1: Encrypted Hive Offline Package Vault (`study_offline_vault.dart`, `study_offline_vault_models.dart`)**:
  - Encrypted Hive storage caching complete subject packages: all chapters, examiner-grade solutions (English and Bengali), and raw markdown contents.
  - Methods: `savePackage`, `getPackage`, `isCached`, `removePackage`, `listPackages`, `totalCachedBytes`.
- [x] **Task Q2: Offline Vault Card & Zero-Network Reader Integration (`study_offline_vault_card.dart`, `study_book_chapters_screen.dart`)**:
  - 1-tap "Save Offline" download action with real-time download and compilation.
  - Dynamic status badge: `Offline Ready · X materials (Y MB) · 100% Native Zero-Data`.
  - Update and remove actions via popup menu.
  - Seamless zero-network reading fallback in `_openSolution` without requiring remote URL fetching.
- [x] **Task Q3: Automated Test Verification & Localization**:
  - 8 unit and widget tests passing across `study_offline_vault_test.dart` and `study_offline_vault_card_test.dart`.
  - 100% translation parity in English and Bengali.
  - Version incremented to `1.8.180+234`.

---

### Track R: Native Text-to-Speech Commute Audio Player (Feature 8)
- [ ] **Task R1: TTS Audio Controller (`study_tts_controller.dart`)**:
  - Integrate `flutter_tts` with background-friendly playback queue.
  - Parse markdown text into spoken paragraphs, stripping code blocks and markdown symbols.
  - Multi-language voice selection (English voice for English text, Bengali voice for Bangla text).
- [ ] **Task R2: Commute Audio Player Bar (`markdown_viewer_screen.dart`)**:
  - Bottom audio dock: Play/Pause, Previous/Next question, 1.0x / 1.25x / 1.5x speed selector.
  - Sleep timer (15m, 30m, 45m).

---

### Track S: Branch Printable PDF Booklets & Notice Board Poster Generator (Feature 9)
- [ ] **Task S1: Duplex Printable A4 PDF Generator (`study_booklet_pdf_generator.dart`)**:
  - Compile entire subject exam series into clean, printable A4 PDF.
  - Table of contents, running headers with subject code, page numbering, and clean Bengali/English typography using `bangla_pdf`.
- [ ] **Task S2: Branch Notice Board Poster Generator (`study_branch_poster_generator.dart`)**:
  - Generate branded A4 printable recruitment/study poster for bank branches.
  - Features group title, IBB emblem styling, description, and high-resolution invite QR code.
