# Implementation Plan: JAIBB Theory Chapters Mapping & Past Papers Relocation

## 1. Context & Architectural Motivation
In the current JAIBB study circle (`339f54482cec417b83ae`), the 6 book records (`study_books`) store 8 past examination diets (`96th BPE` through `8th BPE`) as their "chapters" (`study_books/{bookId}/chapters`). Consequently:
- Opening the **Book Module** presents exam question papers rather than structured textbook / syllabus theory.
- The dedicated **Past Exam Papers Module** (`StudyModuleKey.papers`) under each subject is currently empty (0 posts).
- The rich master textbook theory (Chapters 2 to 10 of each subject's compendium) is trapped inside a monolithic 300KB text file in `study_materials`.

### Goal & Separation of Concerns:
1. **Book Module (`study_books/{bookId}/chapters`)**: Dedicated strictly to studying the **textbook & subject theory**, organized into genuine syllabus chapters (Chapters 1 to 10) populated with master theory, diagrams, and principles.
2. **Past Exam Papers Module (`study_subjects/{subjectId}/posts` where `moduleKey == 'papers'`)**: Dedicated strictly to **examination solutions**, hosting all 8 BPE exams with both English and Bangla solutions, question matrices, and direct viewers.

---

## 2. Subjects & Entities in Scope

| Subject | Code | Subject ID | Book ID | Master Theory File |
| :--- | :---: | :---: | :---: | :--- |
| **Monetary & Financial System (MAFS)** | 101 | `XSf1ru10XVLjMTIfCAWJ` | `r5TtVNekkfuwOLZAa1RC` | `jaibb_mafs_all_exams_master_glossary_bangla.md` |
| **Basic Accounting & Business Analytics (BA)** | 102 | `5ApC2mvkAGaqykv6WbA4` | `41eTecc9pVGKDjw74hVw` | `JAIBB_Basic_Accounting_All_Exams_Master_Glossary_Bangla.md` |
| **Principles of Economics (POE)** | 103 | `KCwssrcTFd7TunTZevOV` | `ah9qgOp1e7uA2qcV6a7B` | `jaibb_poe_all_exams_master_glossary_bangla.md` |
| **Laws & Practice of General Banking (LPGB)**| 104 | `HJbR0L9Md3WoJgsc1rNk` | `QzzHcxueqg3vgAOYoUzv` | `jaibb_lpgb_all_exams_master_glossary_bangla.md` |
| **Organization and Management (OM)** | 105 | `Hh8tHslvRVBPvHSS0YOq` | `5mpQ4NSo35E20KF0KwdD` | `jaibb_om_all_exams_master_glossary_bangla.md` |
| **Business Communication in Financial Inst. (BCFI)** | 106 | `3IoY1KiEHsKyPhbZsvn4` | `8qB1g3HmZhGDUjeF7IqN` | `jaibb_bcfi_all_exams_master_glossary_bangla.md` |

---

## 3. Detailed Work Breakdown & Milestones

### Phase 1: Migration of Existing Past Paper Chapters to Subject Module
- [x] **Task 1.1: Extract & Catalog Existing Past Paper Materials**
  - Query all 96 existing past paper solution materials in `study_materials` (8 exams $\times$ 2 languages $\times$ 6 subjects).
  - Map each exam's title, exam date, question breakdown, English URL, and Bangla URL.
- [x] **Task 1.2: Populate `StudyPosts` under `study_subjects/{subjectId}/posts`**
  - For each subject, create 8 curated `StudyPost` records with `moduleKey: 'papers'`, `shown: true`, and `pinned: true` for the latest exams.
  - Set rich post text with examination topic highlights and provide direct interactive links to the full English and Bangla solutions.
- [x] **Task 1.3: Update Material References in `study_materials`**
  - Ensure materials are linked directly to `subjectId` and decouple them from `chapterId` so they belong to the subject's past papers repository.
- [x] **Task 1.4: Purge Past Paper Chapter Records from `study_books/{bookId}/chapters`**
  - Safely remove the 48 legacy past paper chapters from the 6 books to prepare clean slate for genuine syllabus chapters.

### Phase 2: Syllabus Theory Chapter Ingestion into Books
- [x] **Task 2.1: Decompose Master Compendiums into Structured Chapters**
  - Parse Chapters 1 through 10 of each master markdown file.
  - Extract for each chapter: `number`, `title`, `guide` (learning outcomes), and `readingContent` (complete formatted markdown theory with formulas and tables).
- [x] **Task 2.2: Batch Ingest Syllabus Chapters into `study_books/{bookId}/chapters`**
  - **MAFS**: 12 Chapters (Concepts of Money, Monetary Theories, Money Aggregates M0-M3, Central Banking & IRC, Financial System & ALM, Basel III & Supervision, Money & Capital Markets, Islamic Finance, Payment Systems & BOP, Master Problems Playbook, Master Glossary).
  - **BA**: 5 Core Chapters/Modules (Exam Appearance Matrix, Double-Entry & Accounting Cycle, Master Formulas & 18 Financial Ratios, Comparative Part-D Matrix, Banking & Shariah Accounting with IFRS 9).
  - **POE**: 12 Chapters (Scarcity & PPC, Utility & IC Curves, Demand/Supply & Elasticity, Production & Cost Curves, Market Structures, Market Failure & Externalities, National Income & Keynesian Economics, Inflation & Unemployment, Fiscal Policy & BOP, Master Atlas, Master Glossary).
  - **LPGB**: 12 Chapters (Banker-Customer Relationship, Account Operations, Negotiable Instruments & Clearing, Securities & Charges, Loan Recovery & Artha Rin Adalat, Foreign Trade & LCs, AML/CFT & BFIU Guidelines, Banking Regulation, Customer Rights, Acts & Precedents, Master Glossary).
  - **OM**: 12 Chapters (Management Principles & Fayol's 14, Organizational Environment, SMART Goals & MBO, Organizational Design & Span of Control, HRM & Staffing, QWL & Stress Management, 7 Motivation Theories, Leadership & Power, BPM & Change Management, Case Playbook, Master Glossary).
  - **BCFI**: 8 Chapters (Communication Process & 7 Cs, Organizational Flows & Non-Verbal, Ethics & Etiquette, Active Listening & Public Speaking, Business Letters & AIDA, Official Memos & Circulars, Reports & Proposals, Digital Banking Communication, Meetings & Minutes).
- [x] **Task 2.3: Ingest Chapter Reading Materials into `study_materials`**
  - Create dedicated chapter reading material documents with `kind: 'note'` and `chapterId: chapter.id` so students can view individual chapter notes with 1-click in the app.

### Phase 3: Frontend UX Verification & Testing
- [x] **Task 3.1: Verify Book Chapters Screen (`StudyBookChaptersScreen`)**
  - Verify that opening any of the 6 books now shows clean, pedagogical textbook chapters (1 to 10) instead of exam diets.
  - Verify chapter reading progress, offline vault caching, and markdown rendering.
- [x] **Task 3.2: Verify Past Exam Papers Screen (`StudyModulePostsScreen`)**
  - Verify that opening "Past Exam Papers" (বিগত পরীক্ষার প্রশ্নপত্র ও সমাধান) displays all 8 exams with bilingual access.
  - Verify that tapping "Open" launches the English and Bangla solution markdown viewers seamlessly.
- [x] **Task 3.3: Automated Regression & Unit Tests**
  - Run `flutter test` across all study module unit tests.
  - Verify `StudyBankingMasterCatalog` compatibility.

### Phase 4: Glossary Search & Markdown Rich Rendering
- [x] **Task 4.1: Rich Markdown Rendering in Glossary Cards**
  - Replace raw `Text` with `StudyRichText` in `StudyGlossaryScreen._termCard` for both `term.term` and `term.definition`.
  - Enhance `_span` in `ChatRichText` for `span.code` with proper Bengali font fallback (`fontFamilyFallback`) and adaptive light/dark theme background colors.
- [x] **Task 4.2: Full Glossary Search & Filtering**
  - Add interactive search in AppBar and persistent search bar at the top of the glossary list.
  - Real-time case-insensitive filtering across terms (English/Bangla), definitions, and acronyms.
  - Add chapter filter chips for 1-tap filtering by syllabus chapter.
  - Add result count indicator and clean empty state for searches with no match.
  - Add English and Bengali localization strings for glossary search.
- [x] **Task 4.3: Automated Tests & Verification**
  - Add unit and widget tests for glossary search, filtering, and rich text rendering in `test/features/tour_group/`.
  - Run `flutter test` and `flutter analyze` to ensure 0 errors and clean green state.

### Phase 5: Subject Differences Module & Broad Questions / Problems Resolution
- [x] **Task 5.1: Problems Module & Formula Cheatsheet Resolution**
  - Remove "MAFS গাণিতিক সমস্যার ১০টি অব্যর্থ সূত্র (Math Formula Master Matrix)" from `study_subjects/{id}/problems` (as it is a reference formula guide, not a peer exercise problem).
  - Clean up `<br>` tags in formula table markdown to render cleanly across all screens.
  - Unlock reference solutions for actual problems (Padma Bank Basel-III, Bond YTM/Gordon) with `releaseAt` set to past and reference solution populated under `problems/{id}/reference/solution`.
- [x] **Task 5.2: Chapter 1 Broad Questions & Model Solutions Integration**
  - Update Chapter 1's primary note (`35L3pLqPp0u411KxdIsK`) so that clicking "বাংলা সমাধান / নোট" on Chapter 1 directly presents:
    1. বিগত ৮টি পরীক্ষার সিলেবাস ও টপিক ম্যাট্রিক্স
    2. Part-A রচনামূলক ১৫টি সর্বাধিক গুরুত্বপূর্ণ প্রশ্নের রেডি-টু-রাইট উত্তর কাঠামো
    3. ১০০ নম্বরের পূর্বাভাসকৃত মডেল টেস্টের বিভাগ-ক (রচনামূলক প্রশ্ন ১–৪ এর পুঙ্খানুপুঙ্খ মডেল সমাধান)
  - Remove any shadowed duplicate materials on Chapter 1 so the broad questions are immediately accessible.
- [x] **Task 5.3: Implement New "Differences" (`differences` / তুলনামূলক পার্থক্য) Subject Module**
  - Delegate Firestore Security Rules to `firestore-rules-author` subagent to add `/differences/{postId}` subcollection and include `'differences'` in `studyPostKeys`.
  - Add `differences` to `StudyModuleKey` enum in `study_subject_models.dart`.
  - Add localized strings: `study_module_differences` ("Differences" / "তুলনামূলক পার্থক্য") and `study_difference_add` in `tour_translation_keys.dart`.
  - Update `study_subject_screen.dart`, `study_labels.dart`, and `study_module_posts_screen.dart`.
  - Update tour content purge and automated tests in `test/features/tour_group/`.
- [x] **Task 5.4: Ingest Part-D 8 Differences into MAFS Subject**
  - Enable `differences` module in MAFS subject (`XSf1ru10XVLjMTIfCAWJ`).
  - Batch create 8 high-yield comparative difference posts in `study_subjects/{subjectId}/differences` with rich markdown comparison tables from the playbook.
- [x] **Task 5.5: Quality Gate & Verification**
  - Run `flutter analyze` and `flutter test`.
  - Verify all 8 differences in Firestore and confirm Chapter 1 broad questions render correctly.

### Phase 6: Math Fraction & Bengali Formula Engine Fix and BCFI Playbook Ingestion
- [x] **Task 6.1: Fix Math Fraction & Bengali LaTeX Formula Engine (`chat_markdown.dart`)**
  - Fix the literal `$1` bug by replacing `s.replaceAll(..., r'$1')` with `s.replaceAllMapped(..., (m) => m.group(1) ?? '')`.
  - Fix nested braces failure in `\frac` by recursively resolving `\frac{A}{B}` and unwrapping `\text{...}` first.
  - Fix `\le` word-boundary collision breaking `\left(`.
  - Cleanly unwrap `\left`, `\right`, `\%`, and standard TeX operators into readable Unicode math.
  - Write comprehensive unit tests in `test/features/tour_group/chat_markdown_test.dart` asserting that formulas and fractions (LCR, YTM, Current Yield, Repo, CRAR) render without raw `$1`, `\frac`, or broken brackets.
- [x] **Task 6.2: Enable Differences Module & Ingest Part-D Comparative Distinctions for BCFI**
  - Enable `differences` module on BCFI subject (`3IoY1KiEHsKyPhbZsvn4`).
  - Batch create 8 high-yield comparative difference posts in `study_subjects/{id}/differences`:
    1. উল্লম্ব বনাম সমান্তরাল যোগাযোগ (`Vertical vs. Horizontal Communication`)
    2. সার্কুলার বনাম সার্কুলার লেটার (`Circular vs. Circular Letter`)
    3. আলোচ্যসূচি বনাম কার্যবিবরণী (`Agenda vs. Minutes`)
    4. অনুসন্ধান বনাম ফরমায়েশ পত্র (`Inquiry vs. Order Letter`)
    5. RfP বনাম EoI (`Request for Proposal vs. Expression of Interest`)
    6. KYC বনাম CDD (`Know Your Customer vs. Customer Due Diligence`)
    7. ক্রেডিট রেটিং বনাম ক্রেডিট স্কোরিং (`Credit Rating vs. Credit Scoring`)
    8. SWIFT বনাম NPSB (`SWIFT vs. NPSB`)
- [x] **Task 6.3: Ingest BCFI Playbook into Book Chapters & Reference Materials**
  - Chapter 1 (`6fbT3ahwpIoDTJSxnryF`): Ingest 8-exam trend blueprint, Part-A 15 master questions/answer structures, and 100-mark model test section A solutions into `study_materials`.
  - Chapter 11 (`YeF8jjticss1vFqS2Xng`): Ingest Part-B 6 practical drafting blueprints (Office Memo, Persuasive Letter via AIDA, Loan Rejection Letter, Appreciation Letter, Notice/Agenda/Minutes, Analytical Report).
  - Seed 3-hour exam time management and 1-page master cheatsheet into BCFI `tips`.
  - Ingest crisis communication case study (Eid ATM/App Outage & flood SME recovery) into `problems` with unlocked reference solutions.
- [x] **Task 6.4: Fix MAFS Formulas Text in Firestore**
  - Fix stray `$` symbols and ensure formulas in MAFS differences and tips match the clean standard.
- [ ] **Task 6.5: Quality Gate & Verification**
  - Run `flutter analyze` and `flutter test`.
  - Build and deploy web release and test live.


---

## 4. Verification Commands & Acceptance Criteria
1. **Firestore Verification Command**:
   ```bash
   python scratch/verify_theory_and_past_papers.py
   ```
   *Acceptance Criteria*:
   - Each of the 6 subjects has exactly 8 `StudyPost` entries in `study_subjects/{id}/posts` under `moduleKey: 'papers'`.
   - Each of the 6 books has 5–10 genuine syllabus chapters in `study_books/{id}/chapters`.
   - Zero past paper chapters remaining in `study_books`.
2. **Flutter Code & Unit Tests**:
   ```bash
   flutter test test/features/tour_group/
   flutter test test/features/chat/
   ```
   *Acceptance Criteria*: All tests pass with zero regressions.
3. **End-to-End Visual Verification**:
   - Web: Verified on `app.bhromon.fun` / local emulator.
   - Mobile: Verified on Android build.
