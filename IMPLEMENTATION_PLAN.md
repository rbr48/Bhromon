# Implementation Plan: Dual-Agent Roadmap Coordination (Claude & Antigravity)

## Overview
This implementation plan establishes the collaboration roadmap between **Claude** and **Antigravity** to complete all remaining project deliverables as requested by the user, tracked via [Issue #435](https://github.com/rbr48/Bhromon/issues/435).

---

## Strict Merging Invariant & Dual-Agent Review Gate (MANDATORY)
1. **Mutual Peer Review Required**: Even when all CI checks are 100% green, **NEVER merge any PR to `main` before Antigravity and Claude review each other's PR on GitHub.**
2. **Exchanged Sign-Off**: Mutual peer review comments, guidance, and explicit sign-offs must be documented in PR comments prior to merge.
3. **100% Green CI Required**: Zero tolerance for failing or in-progress checks at merge time (`Dart Format`, `Analyze`, `Build Web`, `Test`, `Build Android`).
4. **Zero Direct Main Commits**: Every change must go through a dedicated topic branch and PR.

---

## Track Breakdown & Ownership

### Track A: Study Group Subsystem (Claude)
- [x] **Phase 9: Weekly Challenge & Today Card** ([PR #434](https://github.com/rbr48/Bhromon/pull/434) - Merged to `main` with `GroupBackButton` and `GroupPopScope`)
- [ ] **Phase 10: Problem Sets, Content Reporting & Admin Reviews**
  - Problem Sets: grouping problems under named sets with due dates.
  - Report button on problems, working, findings, and summaries.
  - Admin reviewing member working & removing invalid reviews.
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

### Track C (Next Up): Travel Spot & Route Map Overlay / FinTech Refinements
- [ ] **Task P9.3: Vector Map Route Checkpoint Overlay**:
  - Convert `RoutePlan.legs` into dynamic MapLibre GeoJSON line layers; render mode-specific route paths and numbered checkpoints directly on top of offline vector tiles.
- [ ] **Peer Review Gate**: Submit PR, wait for Claude's review and sign-off, verify 100% green CI before merge.
