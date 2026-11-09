# Implementation Plan: Group Important Dates, Leave Calendar Profile-Only & Dynamic Meeting Points

## Objective
Address the three core user requirements:
1. **Remove Leave Calendar from All Groups & Keep in Profile Only**:
   - Remove the `HolidayCalendarScreen` tab from `TourLogisticsHubScreen` (`tour_logistics_hub_screen.dart`).
   - Remove/redirect `/group/:tourId/calendar` to the group's Important Dates screen.
   - Keep `/holiday-calendar` intact in the Profile section (`explorer_profile_screen.dart`).
2. **Add Dynamic Important Dates to Each & Every Group**:
   - Replace the legacy `'calendar'` module with dynamic dates for ALL groups in `hub_modules.dart` and `tour_group_hub_screen.dart`.
   - Update `FamilyDateKind` and add group-specific date kinds (Meeting, Deadline, Exam, Rent, Maintenance, Installment, Payout, Event, etc.) with custom emojis.
   - Adapt UI copy, headers, and quick presets dynamically per group kind/preset (Family, Office, Campus, Mess, Society, Samity, Study, Trip).
   - Support adding past dates beyond year 2000 (`firstDate: DateTime(1900)`, year picker, original start year display).
   - Update Firestore Security Rules via `firestore-rules-author` subagent to permit all active group members and allow new kinds.
3. **Dynamic Default Meeting Points**:
   - Replace the hardcoded "Hotel Lobby" default with group-aware defaults (Office conference room/reception, Campus main gate/canteen, Mess dining/common room, Society community hall, Samity venue, Study lounge, Trip landmark) in `notice_board_screen.dart` and `tour_translation_keys.dart`.

---

## Atomic Tasks

### Phase 1: Leave Calendar Removal from Groups
- [ ] **Task 1.1: Logistics Hub Tab Update**
  - In `tour_logistics_hub_screen.dart`, remove `HolidayCalendarScreen` and `tour_tab_calendar`. Change tab length from 4 to 3.
- [ ] **Task 1.2: App Router Clean-up**
  - In `router.dart`, redirect `/group/:tourId/calendar` to `/group/:tourId/family-dates` (or `/important-dates`). Verify profile route `/holiday-calendar` remains accessible.

### Phase 2: Dynamic Important Dates Engine & Past Date Support
- [ ] **Task 2.1: Model & Enum Expansion (`family_date_models.dart`)**
  - Add group-tailored kinds to `FamilyDateKind`: `meeting` (🤝), `deadline` (⏳), `exam` (📝), `rent` (🏠), `maintenance` (🛠️), `installment` (💰), `payout` (🎁), `event` (🎉).
  - Add helper methods to return relevant kinds and suggested presets by `TourGroup`.
- [ ] **Task 2.2: Past Date Selection & Year Display (`family_date_editor.dart` & `family_dates_screen.dart`)**
  - In `family_date_editor.dart`, change `firstDate: DateTime(1900)` and `lastDate: DateTime(2100)`.
  - In `family_dates_screen.dart`, display the originating year/anniversary for past dates (e.g. `(Since 1985)` or `(41st Year)` for recurring dates).
- [ ] **Task 2.3: Dynamic Hub Tile & Modules (`hub_modules.dart`, `tour_group_hub_screen.dart`)**
  - Enable Important Dates module for every group type in `hub_modules.dart`.
  - In `tour_group_hub_screen.dart`, customize the tile title and subtitle based on group type (Family, Office, Campus, Mess, Society, Samity, Study, Trip).
  - Update `hub_modules_golden.json` golden test.

### Phase 3: Dynamic Meeting Points
- [ ] **Task 3.1: Group-Aware Meeting Points (`notice_board_screen.dart`, `tour_translation_keys.dart`)**
  - Update default title and map search query based on `group.isOffice`, `group.isCampus`, `group.isMess`, `group.isSociety`, `group.isSamity`, `group.isStudy`, `group.isHousehold`, `group.isFamily`, and Trips.
  - Add localized strings for each group type's default meeting point.

### Phase 4: Firestore Security Rules Update (Specialist Subagent)
- [ ] **Task 4.1: Subagent Delegation for `firestore.rules`**
  - Invoke `firestore-rules-author` subagent to allow active members of ANY tour group (`isActiveMember(tourId)`) to create/update/delete dates in `family_dates`.
  - Expand `validFamilyDate` to validate the new kinds (`meeting`, `deadline`, `exam`, `rent`, `maintenance`, `installment`, `payout`, `event`).
  - Run rules emulator tests to confirm security policies.

### Phase 5: Automated Verification, PR & Deployment
- [ ] **Task 5.1: Test Suite & Analysis Verification**
  - Run `flutter analyze` and `flutter test`.
  - Commit changes atomically.
- [ ] **Task 5.2: Monotonic Version Bump & PR Gate**
  - Monotonically increment version in `pubspec.yaml` to `1.8.151+205`.
  - Open PR via `gh pr create --base main` and await 100% green CI.
  - Deploy rules, web hosting, and VPS updates.
