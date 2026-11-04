---
name: bhromon-rules-testing
description: >-
  Run and validate Firebase Firestore and Cloud Storage security rules on the local
  Firebase emulator. Use this skill whenever modifying firestore.rules, storage.rules,
  or testing security policies across tour groups, moments, feeds, or channels.
---

# Bhromon Firebase Security Rules Testing

This skill documents how to run and test Firebase Firestore and Storage security rules for Bhromon.

---

## 1. Pinned CLI Version & Emulator Setup

### A. firebase-tools Pinned Version Invariant
- **`firebase-tools@13.35.1` is strictly required.**
- `firebase-tools 15.x` breaks cross-service security rules evaluation: Storage rules' `firestore.get()` lookups fail, resulting in universal permission denials.
- Always execute tests via `npx firebase-tools@13.35.1`.

### B. Shared Emulator Project (`bhromon-rules-test-project`)
- All test suites (`functions/tests/tour_group_rules.test.js`, `tour_group_storage_rules.test.js`, and `firestore.rules.test.js`) share one single emulator project ID: `bhromon-rules-test-project`.
- Cloud Storage security rules look up tour memberships in Firestore scoped to the exact project passed in `--project`. Omitting or changing the project name causes Storage rules lookups to return null/undefined and reject uploads.

### C. In-Band Execution (`--runInBand`)
- The Jest test suites clean up and wipe emulator state between test scenarios. Running tests concurrently leads to state race conditions.
- Always include `--runInBand` when invoking Jest.

---

## 2. Running Rules Tests

Run the full rules test suite with the following command:

```powershell
npx firebase-tools@13.35.1 emulators:exec --only firestore,storage,auth --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/"
```

To run a targeted test file:
```powershell
npx firebase-tools@13.35.1 emulators:exec --only firestore,storage,auth --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/tour_group_rules.test.js"
```

---

## 3. Key Rules Invariants Checked

1. **Tour Memberships**:
   - `memberships/{tourId}__{email}` dictates read and write permissions.
   - Roles: `owner`, `admin`, `member`.
   - Owners cannot be removed; invite codes can only be modified by owners.
2. **Feed & Moments**:
   - `createdAt == request.time` required for new posts/stories.
   - Posts editable only by original author or group admin, strictly within allowed field masks.
   - Likes and story views change only caller's own email entry (`ownEntryOnly`).
   - If `momentsEnabled == false` on a tour group document, posts and stories are rejected.
3. **Office & Campus Presets (`isManagedTour`)**:
   - Rejects dependents, shopping/todo lists, family dates, and SOS alerts.
   - Notices restricted to admin creation (`hasManagedNotices`).
4. **Mess Presets (`isMessTour`)**:
   - Rejects dependents, album, and family dates.
   - Allows meal tracking at `tours/{id}/meals/{dateKey}__{email}`.
5. **Rotating Savings (`isSamityTour`)**:
   - Validates `validSamityConfig` shape and cycle payout permissions.
