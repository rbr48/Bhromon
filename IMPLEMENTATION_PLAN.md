# Implementation Plan: Comprehensive Chat Formatting & Long-Message Ergonomics

## Objective
Fix formatting issues in Bhromon chat messages:
1. Support LaTeX math typesetting (`$...$` for inline, `$$...$$` for block equations).
2. Auto-space and restore structure for collapsed/run-on text pasted without newlines (`Step X:`, `Phase X:`, `\d+\.`, numbered lists, headings).
3. Long-message collapsible preview ("Read More" / "পুরো বার্তাটি পড়ুন") with full expansion / full-screen viewing.
4. Robust Markdown table parsing to prevent degradation into plain text.

---

## Atomic Tasks

- [x] **Task 1: Add `flutter_math_fork` dependency**
  - Verification: `flutter pub get` and `flutter analyze` pass.

- [x] **Task 2: LaTeX Math & Structure Parser in `chat_markdown.dart`**
  - Implement `ChatMathBlock` for `$$...$$` display formulas.
  - Implement inline LaTeX span parsing `$...$` in `_inline()` with fallback if malformed or literal dollar.
  - Implement heuristic text restructuring in `parseChatBlocks()` to restore line breaks when paragraphs/lists are collapsed without newlines.
  - Verification: Unit tests in `test/features/tour_group/chat_markdown_test.dart` verifying LaTeX parsing and collapsed list extraction.

- [x] **Task 3: Math and Collapsible Rendering in `ChatRichText`**
  - Render `ChatMathBlock` using `Math.tex(...)` with error fallback to raw text.
  - Render inline math spans using `WidgetSpan(child: Math.tex(...))`.
  - Add optional `maxCollapsedLength` or `collapsible: true` in `ChatRichText` or bubble container with smooth gradient fade and expandable toggle.
  - Verification: Unit tests in `test/features/chat/chat_rich_text_test.dart`.

- [x] **Task 4: Integrate Collapsible Message Bubbles in Channel and 1-on-1 Chats**
  - Update `group_channels_screen.dart` and `chat_screen.dart` to support long-message preview (> 1,400 characters) with "Read more / পুরো বার্তাটি পড়ুন" and tap-to-expand or open full screen.
  - Verification: `flutter analyze` and widget tests.

- [x] **Task 5: Version Bump, Automated Testing & Verification**
  - Increment version to `1.8.145+199` in `pubspec.yaml`.
  - Run full test suite and analyze check.
  - Git commit on green.

- [ ] **Task 6: PR Creation, CI Green Gate, and Deployment**
  - Push feature branch and open GitHub PR.
  - Watch GitHub Actions CI checks until all are green.
  - Merge PR, deploy web to Firebase Hosting, compile release APK/AAB, and upload to VPS downloads.
