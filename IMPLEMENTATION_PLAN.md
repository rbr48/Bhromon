# Implementation Plan: Push Notification VPS Consolidation & De-duplication

## Objective
Completely consolidate push notification dispatching, token tracking, and scheduling onto the Hostinger VPS (`media-server:8210`). Eliminate duplicate/ghost notifications, de-duplicate triggers, and decommission notification triggers from Firebase Cloud Functions to achieve 100% zero-cost Firebase Spark plan operation.

---

## Phases & Tasks

### Phase 1: De-duplication & Cloud Functions Decommissioning (Immediate)
- [x] **Task 1.1: Remove Duplicate Notification Functions from `functions/src/index.ts`**
  - Unexport `sendSosAlert`, `sendCallPushNotification`, and `sendChannelNotification` from Cloud Functions.
  - Verify that only server games (`card29`, `teenPatti`, `carrom`), data compliance (`gdprDeleteUser`, `tourContentPurge`), and OTP remain.
- [x] **Task 1.2: Audit & Strengthen Client-side Direct REST Triggers**
  - Verify `VpsNotificationService.notifySos()` and `notifyChannelMessage()`.
  - Add deduplication ring buffer in `FirestoreNotificationWatcher` on VPS to prevent dual pings.
- [x] **Task 1.3: Run Verification Tests**
  - Execute `pytest media-server/tests/test_notifications.py media-server/tests/test_calling.py`.

### Phase 2: Migrate Feed, Moments, and Ledger Notifications to VPS
- [x] **Task 2.1: Add Multi-language Push Strings to `media-server/push_strings.py`**
  - Add English and Bengali templates for posts, comments, notices, and ledger expenses.
- [x] **Task 2.2: Implement Notification Methods in `NotificationEngine` (`notifications.py`)**
  - Implement `send_post_notification()`, `send_comment_notification()`, `send_notice_notification()`, and `send_ledger_notification()`.
- [x] **Task 2.3: Expose REST Endpoints on VPS (`/notify/*`)**
  - Add `POST /notify/post`, `POST /notify/notice`, and `POST /notify/ledger` in `media-server/main.py`.
  - Wire client calls into `tour_post_repository.dart`, `notice_repository.dart`, and `trip_ledger_repository.dart`.
- [x] **Task 2.4: Decommission Corresponding Cloud Functions**
  - Unexport `sendTourPostNotification`, `sendTourCommentNotification`, `sendTourNoticeNotification`, and `sendTourLedgerNotification` from `functions/src/index.ts`.

### Phase 3: Background Schedulers & Reminders on VPS
- [x] **Task 3.1: Consolidate Notice Reminders into `ack_reminders.py`**
  - Verify `AckReminderScheduler` handles unanswered notices for members who have not acknowledged mandatory tour announcements.
  - Decommission `sendTourNoticeReminders.ts` and `sendGeneralNotification.ts` from Cloud Functions.
- [x] **Task 3.2: Implement Broadcast Admin Endpoint on VPS**
  - Add `POST /api/admin/broadcast` in `media-server/main.py` protected by `require_platform_admin`.
  - Decommission `sendBroadcastNotification.ts` from Cloud Functions.

### Phase 4: Unified Token Registry & Resilience Hardening
- [x] **Task 4.1: SQLite Token Schema & Index Optimization**
  - Verify `device_tokens` table on the VPS with indexes on `(uid)`, `(email)`, and `(updated_at)`.
  - Add automatic stale token pruning (>180 days).
- [x] **Task 4.2: Watcher Auto-Reconnect & Stream Heartbeat**
  - Add automatic reconnect loop with exponential backoff in `FirestoreNotificationWatcher.start()` to survive network blips.
- [x] **Task 4.3: Health Check Endpoint Expansion**
  - Expand `GET /api/media/health` to expose active listeners count, scheduler status, and delivered notification counts.

### Phase 5: Verification, Tests & Deployment
- [x] **Task 5.1: Write Python & Flutter Automated Tests**
  - Expand `media-server/tests/test_notifications.py` to cover all new methods.
  - Expand `test/features/tour_group/` tests for `vps_notification_service`.
- [x] **Task 5.2: Run Full Suite Verification**
  - Run `pytest media-server/tests/`.
  - Run `dart analyze` and `flutter test`.
  - Run `npm test` in `functions/`.
- [ ] **Task 5.3: Production Deployment to Hostinger VPS**
  - Run `media-server/deploy.sh` on Hostinger VPS.
