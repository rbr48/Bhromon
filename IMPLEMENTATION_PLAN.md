# Implementation Plan: JAIBB Master Exam Materials & In-App Loader

## Problem Statement
The JAIBB banking professional exam subjects (Basic Accounting, LPGB, POE, MAFS, GFI, OM, BCFI) inside study circles require high-quality, examiner-grade materials to genuinely help candidates prepare. While raw exam markdown solutions exist, there are no structured, module-wise master dossiers for:
1. Exam Tips & Tricks (Examiner standards, marking strategies, time allocations, pitfall warnings).
2. Worked Problem Solving (Detailed computational and legal scenarios with step-by-step methods).
3. Glossary & Terms (High-yield terminology with English/Bangla definitions and practical banking examples).
4. Past Exam Papers (Organized question banks with dual-language model solutions).
Additionally, subject screens in the app currently require manual posting and lack a 1-tap loader to populate these master materials.

## Scope & Milestones

- [x] Task 1: Generate comprehensive, high-yield Markdown study dossiers in `C:\Users\USER\Downloads\JAIBB_Master_Materials\` for all 7 JAIBB subjects (`BA`, `LPGB`, `POE`, `MAFS`, `GFI`, `OM`, `BCFI`).
  - Create `Exam_Tips_And_Tricks.md` for each subject.
  - Create `Problem_Solving_Masterclass.md` / `Practical_Case_Problems.md` for each subject.
  - Create `Glossary_And_Key_Terms.md` for each subject.
  - Create `Past_Exam_Papers_Master_Index.md` for each subject.
  - Package them into an organized ZIP archive in `Downloads` for immediate sharing and download (`JAIBB_Master_Exam_Materials_All_Subjects.zip`).

- [x] Task 2: Build `study_banking_master_catalog.dart` domain service in `lib/features/tour_group/domain/services/`.
  - Provide structured data accessors for each subject code (`BA`, `LPGB`, `POE`, `MAFS`, `GFI`, `OM`, `BCFI`):
    - `List<StudyMasterPostDraft> tipsFor(String subjectCode)`
    - `List<StudyMasterProblemDraft> problemsFor(String subjectCode)`
    - `List<StudyMasterGlossaryDraft> glossaryFor(String subjectCode)`
    - `List<StudyMasterPostDraft> pastPapersFor(String subjectCode)`
  - Deterministically associate subject titles/codes.

- [x] Task 3: Implement 1-Tap "Load JAIBB Master Materials" in `study_subject_screen.dart` (and module screens).
  - Add an action and button (visible when subject code or title indicates a banking subject) to load master materials into the active subject.
  - Populate Tips, Problems, Past Papers, and Glossary into Firestore through `TourGroupRepository`.
  - Provide progress feedback, success notifications, and confirmation dialogs.
  - Add localization keys to `tour_translation_keys.dart`.

- [x] Task 4: Automated Verification & Unit Tests.
  - Add unit tests for `study_banking_master_catalog_test.dart` verifying all 7 subjects have high-quality content.
  - Verify `flutter test`, `flutter analyze`, and `dart format .`.

- [ ] Task 5: Peer review with Claude Code CLI, merge to `main`, and deploy to Firebase Hosting.
