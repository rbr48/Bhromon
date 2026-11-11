# Implementation Plan: Fix Document Viewer Share and Open in External App

## Context & Objectives
1. **User Issue**:
   - In the in-app document viewer (e.g., when viewing the generated "Branch Notice Board Poster", Exam Booklets, or Markdown solutions/compendiums), tapping the **Share** button (`Icons.share_rounded`) or the **Open in external app** button (`Icons.open_in_new_rounded`, tooltip `'viewer_open_external'`) did nothing or failed.
2. **Root Cause Analysis**:
   - `PdfViewerScreen` and `MarkdownViewerScreen` previously checked `if (widget.filePath != null)` or `if (widget.fileUrl != null)`.
   - When viewing dynamically generated PDFs (e.g. `bytes: pdfBytes` for Branch Notice Board Posters and Booklets) or in-memory Markdown solutions, `widget.filePath` is null and `widget.fileUrl` is null.
   - Consequently, both `_shareDocument()` and `_openExternally()` silently did nothing.
   - On Web (`kIsWeb`), `_openExternally()` did not handle blob object URLs or opening in a new tab / downloading, and `_shareDocument()` did not provide a fallback when Web Share API file sharing was unsupported.
3. **Resolution**:
   - Implemented `_ensureBytes()` and `_ensureLocalFile()` / `_ensureLocalMarkdownFile()` in both `PdfViewerScreen` and `MarkdownViewerScreen`.
   - On Mobile/Desktop (`!kIsWeb`):
     - Saves in-memory bytes/content to a temporary file in `getTemporaryDirectory()`.
     - Opens the physical file via `OpenFilex.open()` with proper MIME type (`application/pdf`, `text/markdown`, fallback `text/plain`).
     - Shares via `SharePlus.instance.share(ShareParams(files: [XFile(...)], ...))` with proper filename overrides.
     - Displays informative feedback if no external application is installed, offering a direct 1-tap fallback to Share.
   - On Web (`kIsWeb`):
     - Opens binary payloads directly in a new browser tab via `openWebBlob(bytes, mimeType: ..., filename: ...)`.
     - Falls back to `downloadWebFile(bytes, filename)` if popup blockers intercept the new tab or Web Share API file sharing is not supported.
   - Added localized UI feedback strings (`viewer_downloaded`, `viewer_no_external_app`, `viewer_open_failed`) in both English and Bengali dictionaries.
   - Monotonically incremented version in `pubspec.yaml` to `1.8.199+253`.

## Action Items
- [x] Update `tour_pdf_download_stub.dart` and `tour_pdf_download_web.dart` to support `openWebBlob` and dynamic MIME types.
- [x] Add localized feedback keys to `tour_translation_keys.dart` (EN & BN).
- [x] Fix `_shareDocument()` and `_openExternally()` in `PdfViewerScreen` with local temp caching, `SharePlus`, `OpenFilex`, and web blob export.
- [x] Fix `_shareDocument()` and `_openExternally()` in `MarkdownViewerScreen` with local temp caching, `SharePlus`, `OpenFilex`, and web blob export.
- [x] Monotonically bump version in `pubspec.yaml` to `1.8.199+253`.
- [x] Run `dart format` (0 changes needed).
- [x] Run `dart analyze lib/` (0 issues).
- [x] Run unit tests (`study_banking_master_catalog_test.dart` passed, 5/5).
- [ ] Commit changes to Git on branch `fix/viewer-share-and-open-external`.
- [ ] Push to `origin/fix/viewer-share-and-open-external`.
- [ ] Create Pull Request on GitHub.
- [ ] Exchange mutual Antigravity & Claude peer review sign-offs.
- [ ] Verify green CI checks and squash-merge to `main`.
- [ ] Build Flutter Web release (`flutter build web --release`) and deploy to Firebase Hosting (`firebase deploy --only hosting`).
