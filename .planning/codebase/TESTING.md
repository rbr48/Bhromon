# Testing Strategy & Verification

**Analysis Date:** 2026-11-07

## Test Suite Overview

Bhromon maintains a comprehensive testing pyramid across client and backend:
- **Total Test Files**: 247 files in `test/`.
- **Tour Group Tests**: Over 1,024 unit, widget, and golden tests covering ledger mathematics, group permissions, invite links, vehicle maps, and UI modules.
- **Rules Emulation Tests**: Jest tests running against local Firebase Firestore and Storage emulators (`functions/tests/`).

## Key Test Suites

1. **Tour Group Hub & Modules (`test/features/tour_group/`)**:
   - `hub_modules_golden_test.dart`: Golden test verifying that every group preset and combination of flags produces the exact expected tools and tiles.
   - `join_group_screen_test.dart`: Direct link join flow, logo rendering, preset badges, and error handling.
   - `trip_ledger_engine_test.dart`: Integer paisa arithmetic, equal/exact/family split modes, debt simplification.
   - `samity_engine_test.dart`: Rotation payout cycles, overdue calculation, cycle state transitions.
   - `vehicle_seat_map_test.dart`: Multi-layout vehicle rendering and responsive tablet/phone bounds.

2. **Localization & Translations (`test/core/localization/`)**:
   - `tour_translation_test.dart`: Guarantees 100% key parity and placeholder synchronization between Bengali and English.
   - `localized_date_test.dart`: Verification of Bengali and English calendar date formatting.

3. **Firebase Security Rules (`functions/tests/`)**:
   - `tour_group_rules.test.js`: Validates read/write permissions for owners, admins, and members.
   - `tour_group_storage_rules.test.js`: Validates storage quota, avatar uploads, and member isolation.

## Running Tests

```powershell
# Run all tour group tests
flutter test test/features/tour_group/

# Run localization verification tests
flutter test test/core/localization/

# Run security rules on emulator
npx firebase-tools@13.35.1 emulators:exec --only firestore,storage,auth --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/"
```
