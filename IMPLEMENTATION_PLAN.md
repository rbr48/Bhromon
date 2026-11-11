# Implementation Plan: Universal SVG Vector Graphics for Study Solutions & Chat Markdown

## Context & Objectives
1. **User Problem**:
   - In study notes and solutions (e.g. 5th New BPE POE Question 3(a) Indifference Curves), diagrams are currently presented as plain text code blocks (`CODE Copy` with ASCII art).
   - The user requested **Universal SVG** support so all economic diagrams, curves, flowcharts, and banking structures can be rendered dynamically as crisp, high-DPI, interactive vector graphics instead of ASCII text.
2. **Architecture**:
   - Markdown parsing (`ChatMarkdown`): Recognize ````svg ```` code fences, ````xml ```` containing `<svg>`, and raw `<svg>...</svg>` blocks, parsing them into `ChatSvgBlock`.
   - UI Rendering (`ChatRichText` & `ChatSvgWidget`): Render `ChatSvgBlock` using `flutter_svg`'s `SvgPicture.string` with theme-aware styling, responsive scaling, and safe error fallback.
   - Printable A4 PDF Booklets (`StudyBookletPdfGenerator`): Parse `StudyBookletSvgFigure` and draw vector graphics in the PDF via `pw.SvgImage` with fallback protection.
   - Database Migration: Convert 5th New BPE POE Question 3(a) Indifference Curves (and additional economic charts) in Firestore from ASCII to clean SVG.

---

## Tasks & Milestones

- [x] **Task 1: Domain AST & Markdown Parsing for Universal SVG**
  - Add `ChatSvgBlock` to `lib/features/tour_group/domain/services/chat_markdown.dart`.
  - Update `parseMarkdownIntoBlocks` to parse ````svg```` fences and raw `<svg>` blocks.
  - Add unit tests in `test/features/tour_group/domain/services/chat_markdown_chart_test.dart` verifying SVG parsing.

- [x] **Task 2: Presentation Widget for Dynamic SVG Rendering**
  - Create `lib/features/chat/presentation/widgets/chat_svg_widget.dart` using `SvgPicture.string`.
  - Add error boundary fallback to code view if SVG XML is malformed.
  - Wire `ChatSvgBlock` into `lib/features/chat/presentation/widgets/chat_rich_text.dart`.
  - Add widget test in `test/features/chat/presentation/widgets/chat_svg_widget_test.dart`.

- [x] **Task 3: Printable PDF Booklet Vector Rendering for SVG**
  - Add `StudyBookletSvgFigure` to `lib/features/tour_group/domain/services/study_booklet_pdf_generator.dart`.
  - Support `svg` in `solutionPieces`.
  - Render SVG figures via `pw.SvgImage` in PDF page flow.
  - Verify with unit tests in `test/features/tour_group/domain/services/study_booklet_figures_test.dart`.

- [x] **Task 4: Update 5th New BPE POE (and other) Diagrams in Firestore**
  - Convert 5th New BPE POE Question 3(a) Indifference Curve ($IC_1$ vs $IC_2$ proof of non-intersection) in both Bengali and English to clean, responsive SVG.
  - Update Firestore documents `6S5QeCfgJekYgBO8HSTl` (Bangla) and `O0S93YI1xDgpUyVgucGg` (English).

- [x] **Task 5: Verification, Web Release Build & Deploy**
  - Run all flutter tests and analyze (`flutter test`, `dart analyze`).
  - Build web release (`flutter build web --release`).
  - Deploy to hosting (`firebase deploy --only hosting`).
  - Open PR with peer signoff documentation.
