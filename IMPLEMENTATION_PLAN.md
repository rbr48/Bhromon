# Implementation Plan: Everyday Specializations, Voice Lounge Ergonomics & FinOps Polish

## Objective
Implement Options 2, 3, and 4 from the Bhromon roadmap:
- **Sprint 7 (Everyday Group Specializations)**: Mess monthly settlement transfers & 31-day printable meal sheet PDF; Samity payout receipts and verification.
- **Sprint 8 (Voice Lounge & WebRTC)**: Participant speaking indicator with animated avatar rings; Connection quality HUD.
- **Sprint 10 (Ledger & FinOps)**: Duplicate TrxID validation & localized user feedback; Custom date-range & MFS badges in monthly statement PDF.

---

## Atomic Tasks

### Phase 1: Sprint 7 — Everyday Group Specializations
- [x] **Task 1.1: Mess Monthly Settlement Transfers**
  - In `mess_balance_sheet.dart`: Add admin action to record settlement transfer into `tours/{tourId}/transfers`.
  - Update UI so settled members show "পরিশোধিত" with settlement date.
  - Verification: Unit test verifying settlement balance updates (`test/features/tour_group/meal_engine_test.dart`).

- [x] **Task 1.2: Mess 31-Day Printable Meal Sheet PDF**
  - Create `lib/features/tour_group/data/mess_meal_sheet_pdf.dart` using `bangla_pdf`.
  - Render monthly calendar matrix (daily breakfast/lunch/dinner per member), bazar totals, meal rate, deposits, and net balances.
  - Wire PDF export in `MessBalanceSheet` and `meals_screen.dart`.
  - Verification: Unit test in `test/features/tour_group/mess_meal_sheet_pdf_test.dart`.

- [x] **Task 1.3: Samity Payout Receipts & Beneficiary Verification**
  - In `samity_models.dart`: Add `receiptUrl`, `isVerified`, and `verifiedAt` to `SamityPayout`.
  - In samity payout UI: Allow admin to attach transfer receipt image and beneficiary to verify handover.
  - Verification: Unit test for payout model serialization and verification states (`test/features/tour_group/samity_payout_test.dart`).

### Phase 2: Sprint 8 — Voice Lounge & WebRTC Ergonomics
- [x] **Task 2.1: Participant Speaking Indicator**
  - In `voice_room_service.dart`: Implement audio-level monitoring for local microphone and remote peer tracks via `getStats()`.
  - Expose `speakingEmails` set and notify listeners on speech start/stop (> 0.035 threshold).
  - In Voice Lounge avatars and docked mini-bar: Render pulsing animated green glow ring around active speakers.
  - Verification: Unit test verifying speaking state calculation (`test/features/tour_group/voice_room_service_test.dart`).

- [x] **Task 2.2: Connection Quality HUD**
  - In `call_quality.dart` / `voice_room_service.dart` / call screen: Ensure WebRTC telemetry (RTT, packet loss, bitrate) displays in a compact, tap-to-inspect network HUD.
  - Verification: Unit test verifying packet loss and latency rating thresholds.

### Phase 3: Sprint 10 — Ledger & FinOps Enhancements
- [x] **Task 3.1: Duplicate TrxID Validation & Feedback**
  - In `tour_group_repository.dart` & `expense_editor.dart`: Check `tours/{tourId}/mfs_trx_registry/{trxId}` before expense/settlement submission.
  - Display localized warning when a duplicate TrxID is detected.
  - Verification: Unit test for TrxID registry check.

- [x] **Task 3.2: Monthly Statement PDF Custom Date Range & MFS Badges**
  - In `monthly_ledger_pdf.dart`: Add support for custom date-range intervals and render MFS verification badges (`[ভেরিফাইড]` / `[অপেক্ষমান]`).
  - Add date-range selection in `monthly_ledger_pdf_export.dart` and `expense_ledger_screen.dart`.
  - Verification: Unit test verifying custom date filtering and PDF output (`test/features/tour_group/mfs_monthly_ledger_test.dart`).

### Phase 4: Release & Deployment
- [x] **Task 4.1: Monotonic Version Bump to `1.8.148+202`**
  - Increment version in `pubspec.yaml`.
  - Verify with `dart format`, `flutter analyze`, and `flutter test`.
- [ ] **Task 4.2: Pull Request, CI Green Gate & Deployments**
  - Push feature branch, open PR via `gh pr create --base main`.
  - Wait for CI checks to pass green, squash and merge into `main`.
  - Deploy Flutter Web to Firebase Hosting and release APK to Hostinger VPS.
