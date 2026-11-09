# Implementation Plan: Dual-Agent Roadmap Coordination (Claude & Antigravity)

## Overview
This implementation plan establishes the collaboration roadmap between **Claude** and **Antigravity** to complete all remaining project deliverables as requested by the user, tracked via [Issue #435](https://github.com/rbr48/Bhromon/issues/435).

---

## Track Breakdown & Ownership

### Track A: Study Group Subsystem (Claude)
- [ ] **Phase 9: Weekly Challenge & Today Card** ([PR #434](https://github.com/rbr48/Bhromon/pull/434))
  - Rebase onto latest `origin/main` (`195b32c3`).
  - Wire `GroupBackButton` and `GroupPopScope` into `study_challenge_screen.dart`.
  - Pass all 5 CI checks (`Dart Format`, `Analyze`, `Build Web`, `Test`, `Build Android`) 100% green before merge.
- [ ] **Phase 10: Problem Sets, Content Reporting & Admin Reviews**
  - Problem Sets: grouping problems under named sets with due dates.
  - Report button on problems, working, findings, and summaries.
  - Admin reviewing member working & removing invalid reviews.

---

### Track B: Platform, Media Server & Multi-Platform UX (Antigravity)
- [x] **Task P11.1: Hostinger VPS Asynchronous Reel Poster Generation**
  - Created `media-server/media_utils.py` for standardized 720x1280 WebP video poster generation with FFmpeg worker.
  - Integrated with `upload_official_post` and general reel video uploads in `media-server/main.py`.
  - Added pytest suite `media-server/tests/test_media_utils.py` and `test_official_feed.py` (446/446 passed, pyflakes clean).
- [x] **Task P11.2: Desktop Web Three-Column Responsive Experience**
  - Verified 3-pane shell in `trip_shell.dart`, `desktop_tour_sidebar.dart`, and `desktop_right_dock.dart`.
  - Verified `Ctrl+K` global quick search shortcut across desktop views.
- [x] **Task P11.3: Android 16 Edge-to-Edge & Performance Hardening**
  - Verified zero system bar gesture overlap (`compileSdk 36`, `targetSdk 36`, cutout shortEdges).
- [x] **FinTech Documentation Sync**
  - Updated `AGENTS.md` line 91 with completed monthly ledger PDF export and `mfs_trx_registry` deduplication write paths.

---

## Quality Gates & Verification Protocol
1. **Zero Direct Main Commits**: Every change must go through a dedicated topic branch and PR.
2. **Branch Isolation**: Track A uses `claude/*`; Track B uses `feat/*`.
3. **100% Green CI Gate**: Zero tolerance for failing or in-progress checks at merge time. Pre-push checks (`dart format .`, `flutter analyze`, `pytest media-server/tests`) are mandatory.
