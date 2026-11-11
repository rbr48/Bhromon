# Implementation Plan: Update JAIBB BA All 8 Accounting Exams English Version & Compendiums

## Context & Objectives
1. **All 8 Accounting Exams English Edition Ingestion**:
   - The user provided `C:\Users\USER\Downloads\IBB_All_8_Accounting_Exams_English_MD_DOCX_PDF.zip` containing expanded, full problem statements and step-by-step examiner-grade English solutions for all 8 Banking Professional Examinations (BPE) for JAIBB subject Basic Accounting & Business Analytics (`BA`, book ID: `41eTecc9pVGKDjw74hVw`).
   - The archive also contains 3 comprehensive English Master Solution Compendiums:
     - 5-Exam Master (96th–5th BPE): 377,015 characters
     - 3-Exam Master (6th–8th BPE): 231,531 characters
     - Complete 8-Exam Master: 607,855 characters
2. **Database Updates**:
   - Updated all 8 chapter English solutions with complete verbatim problem statements, Trial Balances, Comparative Balance Sheets, Income Statements, journal entries, and ledger accounts.
   - Added the 3 English Master Compendiums at the book level (`chapterId: None`).
3. **Verification**:
   - Verified 8 distinct chapters in JAIBB BA, all with dual English and Bengali solutions.
   - Verified 5 Master Compendiums (2 Bengali, 3 English).
   - Total study materials in JAIBB BA: 21.

## Action Items
- [x] Ingest and update 96th BPE English solution (86,356 chars) in Chapter 1 (`cd78gCCNAKlsdUYq8HyC`).
- [x] Ingest and update 97th BPE English solution (74,325 chars) in Chapter 2 (`f4ZneP05J6e9diSTebZK`).
- [x] Ingest and update 98th BPE English solution (74,542 chars) in Chapter 3 (`68zW5IFMbcRYD9lczrNA`).
- [x] Ingest and update 99th BPE English solution (85,731 chars) in Chapter 4 (`OV7lEoq5r9uA4b6rJY5C`).
- [x] Ingest and update 5th BPE English solution (55,274 chars) in Chapter 5 (`oieZyfyOZYHv9fVqWEgl`).
- [x] Ingest and update 6th BPE English solution (60,411 chars) in Chapter 6 (`01BeLXhxRs4IeMUTMJFY`).
- [x] Ingest and update 7th BPE English solution (81,358 chars) in Chapter 7 (`mAwzzP3KPBPkWVDUzLnU`).
- [x] Ingest and update 8th BPE English solution (89,098 chars) in Chapter 8 (`BcjuHBTL5faJL8C8gNFw`).
- [x] Upload 5-Exam English Master Compendium (377,015 chars, `V8kA5HBLWgChzGvpLeEd`).
- [x] Upload 3-Exam English Master Compendium (231,531 chars, `FINNFfYbEUjfdfPfFVpC`).
- [x] Upload Complete 8-Exam English Master Compendium (607,855 chars, `4qsSnCjvRcTYiRh26DNO`).
- [x] Verify complete JAIBB BA structure across all 8 chapters and 21 materials.
- [x] Monotonically bump version in `pubspec.yaml` to `1.8.198+252`.
- [ ] Run `dart format`, `dart analyze`, and unit test suite.
- [ ] Commit and push to branch `feat/update-jaibb-ba-english-all8`.
- [ ] Create Pull Request on GitHub.
- [ ] Exchange mutual Antigravity & Claude peer review sign-offs.
- [ ] Verify green CI checks and squash-merge to `main`.
- [ ] Build Flutter Web release (`flutter build web --release`) and deploy to Firebase Hosting (`firebase deploy --only hosting`).
