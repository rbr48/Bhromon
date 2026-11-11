# Implementation Plan: Discontinue AFI from AIBB & Reassign to JAIBB BA with Complete 5 Exams

## Context & Objectives
1. **AFI Subject Restructuring**:
   - In IBB syllabus history, `AFI` (Accounting for Financial Institutions, code `206A`) was an AIBB subject up to the 5th Banking Professional Examination (BPE).
   - From the 6th BPE onward, AFI was discontinued from AIBB and introduced into JAIBB under the subject name `BA` (Basic Accounting and Business Analytics).
2. **Database Migration & Uploads**:
   - Completely remove the `AFI` subject (`FoY8SImug8QtWFYblHNR`), its 12 modules, study book (`hfel4m2OdR7fafCapc8a`), 5 chapters, and 10 materials from the AIBB study group (`b14c6f6b201b442e96eb`).
   - Reassign all 5 BPE exam solutions (96th BPE through 5th New BPE) from `IBB_AIBB_AFI_All_5_Exams_Bangla_MD_DOCX.zip` into the `JAIBB` study group (`339f54482cec417b83ae`) under subject `BA` (Book ID: `41eTecc9pVGKDjw74hVw`), populating Chapters 1 to 5 with both comprehensive Bengali and English solutions, plus the Master Compendium.
3. **Master Catalog & Mapping Alignment**:
   - In `StudyBankingMasterCatalog`:
     - Remove `codeAFI` from `aibbSubjectCodes` (AIBB now has 13 active subjects).
     - Update `resolveCodeFromText` so any query/document containing AFI/206A/Accounting for Financial Institutions keywords routes to `codeBA` (JAIBB Basic Accounting).
   - Update master catalog tests to verify 13 active AIBB subjects and verify former AFI queries map to JAIBB BA.

## Action Items
- [x] Purge AFI from AIBB group (`b14c6f6b201b442e96eb`) in Firestore: 10 materials, 5 chapters, 1 book, 12 modules, and 1 subject deleted. Verified 0 AFI left in AIBB.
- [x] Extract and upload all 5 exam sessions (96th to 5th BPE) in both Bengali and English + Master Compendium into JAIBB BA (`41eTecc9pVGKDjw74hVw`) Chapters 1–5. Verified 17 materials now live in JAIBB BA.
- [x] Update `StudyBankingMasterCatalog.aibbSubjectCodes` and `resolveCodeFromText` in `lib/features/tour_group/domain/services/study_banking_master_catalog.dart`.
- [x] Update tests in `test/features/tour_group/domain/services/study_banking_master_catalog_test.dart`.
- [ ] Monotonically bump version in `pubspec.yaml` to `1.8.196+250`.
- [ ] Format code (`dart format`) and run static analysis (`dart analyze`) & unit tests.
- [ ] Commit and push to branch `feat/reassign-afi-to-jaibb-ba`.
- [ ] Create Pull Request on GitHub.
- [ ] Conduct mutual Antigravity & Claude peer review exchange.
- [ ] Verify green CI checks and squash-merge to `main`.
- [ ] Build Flutter Web release (`flutter build web --release`) and deploy to Firebase Hosting (`firebase deploy --only hosting`).
