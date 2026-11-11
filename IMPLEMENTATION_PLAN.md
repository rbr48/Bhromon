# Implementation Plan: Update JAIBB BA 6th, 7th & 8th BPE Examiner-Grade Solutions & Master Compendium

## Context & Objectives
1. **JAIBB BA 6th–8th BPE Examination Expansion**:
   - The user provided `C:\Users\USER\Downloads\IBB_JAIBB_BA_6th_7th_8th_BPE_Bangla_MD_DOCX_PDF.zip` containing expanded, full problem statements and examiner-grade solutions for the 6th, 7th, and 8th Banking Professional Examinations (BPE) for JAIBB subject Basic Accounting & Business Analytics (`BA`, book ID: `41eTecc9pVGKDjw74hVw`).
   - The archive also contains the complete 3-exam Master Compendium (`JAIBB_BA_6th_7th_8th_BPE_Master_Solutions_Bangla.md` with 247,518 characters).
2. **Database Updates**:
   - Update Chapter 6 (`1KKL7YF6FJREZ9BhNSDA`) with the new, fully expanded Bangla solution (`JAIBB_Basic_Accounting_6th_BPE_2025_Solutions_Bangla.md`, 87,979 characters, 179,547 bytes) replacing the older 36k char version.
   - Update Chapter 7 (`bxqoWO7EEdsQ7gkQmpbW`) with the new, fully expanded Bangla solution (`JAIBB_Basic_Accounting_7th_Exam_2026_Solutions_Bangla.md`, 79,471 characters, 165,437 bytes) replacing the older 31k char version.
   - Update Chapter 8 (`ZkHellZ6CkyYDYv2APIX`) with the new, fully expanded Bangla solution (`JAIBB_Basic_Accounting_8th_BPE_2026_Solutions_Bangla.md`, 79,454 characters, 164,800 bytes) replacing the older 39k char version.
   - Standardize Chapter 8's chapter title to `8th New BPE (Nov 2026)` (harmonizing with Chapters 5, 6, and 7).
   - Standardize all 6th, 7th, 8th English material titles to `BA` instead of `BASIC`.
   - Upload the 3-exam Master Compendium (`JAIBB_BA_6th_7th_8th_BPE_Master_Solutions_Bangla.md`, 247,518 characters) as a book-level material (`chapterId: None`).
3. **Verification**:
   - Verified 8 distinct chapters in JAIBB BA, all with dual English and Bengali solutions.
   - Verified 2 Master Compendiums (96th–5th BPE: 363k chars, and 6th–8th BPE: 247k chars).
   - Total study materials in JAIBB BA: 18.

## Action Items
- [x] Extract and update 6th BPE Bangla solution (87,979 chars) in Firestore (`MCeOACTdcdWpYq1ojog0`).
- [x] Extract and update 7th BPE Bangla solution (79,471 chars) in Firestore (`0hY5yWsm3MBiwSuaREcT`).
- [x] Extract and update 8th BPE Bangla solution (79,454 chars) in Firestore (`PabQsuoyOO1s6RHEmTV8`).
- [x] Upload 6th-8th BPE Master Solutions Compendium (247,518 chars) in Firestore (`XrenYGAK73icuxIHboAK`).
- [x] Standardize English material titles to `BA Solutions (English)`.
- [x] Harmonize Chapter 8 title to `8th New BPE (Nov 2026)`.
- [x] Verify complete JAIBB BA structure across all 8 chapters and 18 materials.
- [x] Monotonically bump version in `pubspec.yaml` to `1.8.197+251`.
- [ ] Run `dart format`, `dart analyze`, and unit test suite.
- [ ] Commit and push to branch `feat/update-jaibb-ba-6th-8th-bpe`.
- [ ] Create Pull Request on GitHub.
- [ ] Exchange mutual Antigravity & Claude peer review sign-offs.
- [ ] Verify green CI checks and squash-merge to `main`.
- [ ] Build Flutter Web release (`flutter build web --release`) and deploy to Firebase Hosting (`firebase deploy --only hosting`).
