# Implementation Plan: Study Circle Generalization & Template Separation

## Problem Statement
Study features (Printable Exam Booklet, Notice Board Poster, Study Hall, and Streak Cards) currently hardcode IBB / JAIBB institutional titles, banking copy, and "JAIBB" subject codes for every study group, including non-banking study groups (e.g. school, university, BCS, medical, or arbitrary subjects like `dhh` / `gyg`).

## Scope & Milestones
- [x] Task 1: Generalize `study_booklet_pdf_generator.dart` to dynamically adapt between Banking Diploma (IBB JAIBB) context and General Study Circles.
  - Dynamically format booklet cover (institution badge, subject code, subtitle, feature highlights).
  - Dynamically format notice board poster (header badge, main title, subtitle, highlights grid, footer).
  - Never show "Subject Code: JAIBB" or "IBB" when subject/group is not an IBB banking exam circle.
- [x] Task 2: Update `study_book_chapters_screen.dart` to pass dynamic subject code and contextual fallbacks instead of hardcoding `JAIBB` and `Banking Exam Study Circle`.
  - Update action sheet labels from "Branch Notice Board Poster" to "Notice Board Poster".
- [x] Task 3: Update `study_daily_streak_rules.dart` and `study_daily_streak_card.dart` to remove hardcoded `JAIBB Study Circle` and `@bank.org` defaults.
- [x] Task 4: Generalize localization keys in `tour_translation_keys.dart` (motivation, study hall, poster, filter chips).
- [x] Task 5: Run tests & static analysis (`flutter test`, `dart analyze`, `dart format .`).
- [ ] Task 6: Commit, push branch, open PR, mutual peer review sign-off with Claude Code CLI, merge to `main`, and deploy live to Firebase Hosting.
