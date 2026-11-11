# Implementation Plan: User Logo Asset Integration & Study Group Poster/Booklet Refinement

## Context
1. The user explicitly provided the path to their downloaded logo:
   `C:\Users\USER\Downloads\bhromon_logo_transparent\bhromon_logo_transparent.png`.
   This is the authentic 3D emerald-green compass needle / 'B' emblem. The file contains a baked-in checkerboard pattern from a web downloader, which we clean into a 100% transparent RGBA asset with smooth anti-aliasing.
2. In the user's uploaded screenshots, the Android launcher icon is shown on a clean white squircle background (`media_1794370613293_8e7072ec.png`). The current adaptive background was set to `#121212`, which caused it to render dark instead of white.
3. In previous screenshots (`Branch Notice Board Poster` and `Booklet`), non-banking study groups (`dhh`, `gyg`) were hardcoded to or falsely detected as IBB / JAIBB because of overly broad substring matching (`ibb`) and hardcoded fallback to `subjectCode = 'JAIBB'`.

## Changes Implemented

### 1. Master Logo & Asset Replacement
- [x] Extracted 100% transparent RGBA master asset from user's provided file with anti-aliasing.
- [x] Updated `assets/logo.png` with 100% transparent 1024x1024 green 3D emblem.
- [x] Updated `assets/Bhromon.png` with 100% transparent 1024x1024 green 3D emblem.
- [x] Restored master `logo.png` (with soft shadow on white).
- [x] Configured `flutter_launcher_icons.yaml` with `adaptive_icon_background: "#FFFFFF"` and centered `assets/logo_foreground.png`.
- [x] Rebuilt launcher icons (`dart run flutter_launcher_icons`) and native splash (`dart run flutter_native_splash:create`).
- [x] Generated `web/favicon.png` and `web/icons/Icon-*.png`.

### 2. Fix Study Group Booklet & Poster Overgeneralization
- [x] Refined `isBankingContent` in `study_booklet_pdf_generator.dart` to strictly use word-boundary regex (`\b(jaibb|aibb|ibb|banking|banker)\b` / Bengali banking keywords) and excluded unrelated tour description.
- [x] In `generateBranchNoticePoster`, made headings and subtitles dynamically adopt the group's name and subject title instead of forcing "JAIBB Examination Preparation".
- [x] In `generateBookletPdf`, ensured booklet subtitle uses the actual subject title.
- [x] In `study_book_chapters_screen.dart`, eliminated fallback to `subjectCode = 'JAIBB'`. Only assign banking code if resolved via `StudyBankingMasterCatalog.resolveCodeFromText(...)`.

### 3. Verification & CI Checks
- [x] `dart format .` passed.
- [x] `dart analyze` passed with 0 issues.
- [x] Tests passed: `study_booklet_pdf_generator_test.dart` (7/7 passed), `join_group_screen_test.dart` (6/6 passed), `tour_translation_test.dart` (15/15 passed), `hub_modules_golden_test.dart` (passed).
- [x] `flutter build web --release` passed.
- [x] Bumped version monotonically in `pubspec.yaml` to `1.8.188+242`.

### 4. PR & Dual-Agent Gate
- [ ] Commit atomic changes to branch.
- [ ] Push branch and open GitHub PR.
- [ ] Dual-agent review: Antigravity review + Claude Code CLI review.
- [ ] Squash-merge into `main`, update local `main`, and deploy to Firebase Hosting (`https://app.bhromon.fun`).
