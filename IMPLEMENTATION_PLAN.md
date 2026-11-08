# Implementation Plan: Comprehensive Chat Formatting & Long-Message Ergonomics

## Objective
Fix formatting issues in Bhromon chat messages:
1. Support LaTeX math typesetting (`$...$` for inline, `$$...$$` for block equations).
2. Auto-space and restore structure for collapsed/run-on text pasted without newlines (`Step X:`, `Phase X:`, `\d+\.`, numbered lists, headings).
3. Long-message collapsible preview ("Read More" / "পুরো বার্তাটি পড়ুন") with full expansion / full-screen viewing.
4. Robust Markdown table parsing to prevent degradation into plain text.
5. Render LaTeX math and styled spans natively inside `ChatTableWidget` and `ChatTableFullscreenModal` table cells.

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

- [x] **Task 5: Extended Headings H4-H6, Escaped Brackets, Auto-wrap Raw LaTeX in Tables**
  - PR #403 merged (v1.8.146+200).

- [x] **Task 6: Native LaTeX Math & Styled Span Rendering in `ChatTableWidget`**
  - In `chat_table_widget.dart`, add `package:flutter_math_fork/flutter_math.dart`.
  - In `_span()`, handle `if (span.math)` with `WidgetSpan(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Math.tex(...)))`.
  - Verification: Widget test verifying that `ChatTableWidget` renders `Math` widgets for table cells containing LaTeX math.

- [x] **Task 7: Native LaTeX Math & Rich Spans in `ChatTableFullscreenModal`**
  - In `chat_table_fullscreen_modal.dart`, add `package:flutter_math_fork/flutter_math.dart`.
  - In `_buildGridTable()`, replace plain `Text(cell.plainText)` with rich text span rendering supporting `span.math`, bold, italic, code, etc.
  - In `_showCellDetail()`, render LaTeX formulas with `Math.tex` in the inspection bottom sheet.
  - Verification: Widget test verifying full-screen modal renders LaTeX formulas in table cells.

- [ ] **Task 8: Monotonic Version Bump to `1.8.147+201`, PR, CI Green Gate & Deploy**
  - Monotonically increment `pubspec.yaml` to `1.8.147+201`.
  - Push branch and open PR via `gh pr create --base main`.
  - Wait for CI checks to turn green.
  - Merge PR, deploy web to Firebase Hosting, compile release APK and upload to Hostinger VPS.
