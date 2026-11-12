# Implementation Plan: Whole-Project Evaluation Improvements

## Context & Objectives
Following the Whole-Project Evaluation of **Bhromon** (`v1.8.204+258` / `v1.8.205+259`), the user approved executing all 5 recommended architectural, CI, and maintenance workstreams:
1. Review & merge PR #505 (`Fix exam simulator, official pack duplicates and member photo sync`).
2. Evaluate & resolve Dependabot PR #341 (`maplibre_gl 0.26.2 -> 0.28.0`).
3. Remove the 6 empty legacy feature skeletons under `lib/features/` and raise the CI LCOV line coverage regression floor from `25.5%` to `40.0%`.
4. Modularize `media-server/main.py` by extracting media purge/reminder routes (`purge_routes.py`) and notification trigger routes (`notify_routes.py`) into dedicated FastAPI routers.
5. Create cohesive sub-domain barrel entrypoints in `lib/features/tour_group/` (`study_circle/study_circle.dart` and `ledger/ledger.dart`) with unit test verification, bump version to `1.8.206+260`, and deploy the updated Flutter Web release.

---

## Tasks & Milestones

- [x] **Task 1: Review & Merge PR #505**
  - Inspect all commits and diffs on PR #505.
  - Verify green CI checks (`Dart Format`, `Analyze`, `Test`, `Build Web (release)`, `Build Android (debug APK)`).
  - Post Antigravity peer review sign-off and sync merged `main`.

- [x] **Task 2: Evaluate & Resolve Dependabot PR #341 (`maplibre_gl 0.28.0`)**
  - Inspect `maplibre_gl` usage across `lib/` and `web/index.html` plus PR #341 CI failure logs.
  - Document incompatibility with Web MapLibre GL JS 4.x and Pigeon error contracts, and close PR #341 cleanly.

- [x] **Task 3: Clean Legacy Feature Skeletons & Raise CI Coverage Floor**
  - Remove empty legacy directory trees (`feed`, `map`, `offline_vault`, `premium_guide`, `pro_tip`, `trip_log`) from `lib/features/`.
  - Raise LCOV line coverage floor in `.github/workflows/flutter_ci.yml` from `25.5%` to `40.0%`.

- [x] **Task 4: Modularize `media-server/main.py` FastAPI Routers**
  - Extract purge & ack-reminder endpoints into `media-server/purge_routes.py` (`purge_router`).
  - Extract notification & admin broadcast endpoints into `media-server/notify_routes.py` (`notify_router`).
  - Preserve dynamic attribute lookup on `main` for test monkeypatching compatibility and verify all 540 `pytest` tests pass.

- [x] **Task 5: Extract Cohesive `tour_group` Sub-Domain Entrypoints**
  - Create `lib/features/tour_group/study_circle/study_circle.dart` barrel module.
  - Create `lib/features/tour_group/ledger/ledger.dart` barrel module.
  - Add unit test `test/features/tour_group/subdomains_barrel_test.dart`.
  - Increment `pubspec.yaml` version to `1.8.206+260`.

- [x] **Task 6: Verification, Web Release Deployment & Pull Request**
  - Run `dart format`, `dart analyze`, `tool/check_dart_io.sh`, `tool/check_empty_catches.sh`, and unit tests.
  - Build Flutter Web release (`flutter build web --release`) and deploy to Firebase Hosting (`firebase deploy --only hosting`).
  - Commit changes on `chore/project-evaluation-improvements`, push branch, and open a GitHub Pull Request to `main`.
