# Implementation Plan: Sprint 7 — Everyday Group Specializations (Phase 9)

## Objective
Deliver Sprint 7 specializations across everyday circles (Mess, Society, Office/Campus, Samity) per `ROADMAP.md`:
1. **Task 9.1: Mess Monthly Bazar Duty Schedule & Reminders**
   - Data model: `MessBazarSchedule` (`tours/{id}/mess_bazar_schedule/{dateKey}`).
   - Firestore rules: enforce `isMessTour` and role validation.
   - UI: Duty card in `MessHomeCard` and `MealsScreen`, with admin assignment sheet.
   - VPS reminder: scheduled daily reminder dispatch for bazar duty members.
2. **Task 9.2: Society Service Requests: Photo Attachments & Ledger Booking**
   - Attach up to 3 photos per request via `TourMediaUploader`.
   - Status timeline progression (Open → In Progress → Resolved) with admin note history.
   - One-tap booking of resolved repair costs into Society Maintenance ledger.
3. **Task 9.3: Office & Campus Notice Acknowledgement Rings**
   - Circular progress indicator and response count on managed notices.
   - Pending-member drawer with response status.
4. **Task 9.4: Samity Receipts & Verification**
   - Receipt / transfer screenshot upload on samity payout handover.
   - Beneficiary confirmation status (`payoutStatus: verified`).
5. **Quality Gates & Verification**
   - Unit and emulator rules tests.
   - `flutter analyze` clean (0 errors, 0 warnings).
   - Monotonic version bump in `pubspec.yaml`.
   - GitHub PR workflow.

---

## Atomic Tasks

### Phase 1: Mess Bazar Duty Schedule (Task 9.1)
- [x] **Task 1.1: Bazar Duty Model & Repository**
  - Define `MessBazarSchedule` in `lib/features/tour_group/domain/models/mess_bazar_model.dart`.
  - Add watch and write methods in `TourGroupRepository`.
- [x] **Task 1.2: Security Rules for Mess Bazar Schedule**
  - Add rules in `firestore.rules` for `tours/{tourId}/mess_bazar_schedule/{dateKey}`.
  - Verify via `functions/tests/mess_bazar_rules.test.js`.
- [x] **Task 1.3: Mess UI Integration**
  - Display Bazar Duty badge/card in `MessHomeCard` (`mess_home_card.dart`).
  - Add Bazar Duty tab/sheet in `meals_screen.dart` with date navigation and admin assignment dialog.
- [x] **Task 1.4: VPS Bazar Duty Daily Notification**
  - Add morning duty reminder logic in `media-server/notifications.py`.

### Phase 2: Society Service Requests Upgrades (Task 9.2)
- [x] **Task 2.1: Photo Attachments in Service Requests**
  - Add `photos: List<String>` to `ServiceRequest` model.
  - Add image picker & uploader in request creation dialog in `society_requests_screen.dart`.
- [x] **Task 2.2: Status Timeline & Maintenance Ledger Booking**
  - Render 3-step visual status timeline with admin note in `society_requests_screen.dart`.
  - Add "Book to Ledger" action on resolved requests prefilling the Maintenance category.

### Phase 3: Office & Campus Notice Progress Ring (Task 9.3)
- [x] **Task 3.1: Response Progress Ring on Notices**
  - Calculate response count and total active members in `TourNoticesScreen`.
  - Display circular progress ring showing acknowledgment percentage.
- [x] **Task 3.2: Pending Members Drawer**
  - Add bottom sheet / drawer showing who answered and who is pending.

### Phase 4: Samity Receipts & Verification (Task 9.4)
- [x] **Task 4.1: Samity Payout Receipt Upload & Verification**
  - Add receipt photo URL and `isVerified` flag to `SamityPayout`.
  - Add receipt viewer and beneficiary "Confirm Received" verification button in `SamitySheet`.

### Phase 5: Verification, Web Deploy & PR
- [ ] **Task 5.1: Run Static Analysis & Unit Tests**
  - `flutter analyze` 0 errors.
  - `flutter test` all test suites green.
- [ ] **Task 5.2: Version Bump & PR**
  - Increment `pubspec.yaml` to `1.8.154+208`.
  - Create and push PR via `gh pr create --base main`.
- [ ] **Task 5.3: Web & VPS Deployment**
  - Deploy web build to `app.bhromon.fun`.
  - Pull and run updated `deploy.sh` on VPS.
