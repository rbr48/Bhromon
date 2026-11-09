# Bhromon — Roadmap and Work Plan

**Version:** 2.1, verified against `main` at `d0d6b81` (v1.8.125+179), 2026-11-07.
**Replaces:** the v2.0 draft. Every "current state" statement below was checked against the code on `main`.
**Where work is tracked:** the active queue stays in `IMPLEMENTATION_PLAN.md` (Phase 9). This file holds the wider roadmap and the decisions behind it.

## 1. Principles

- 100% free and open source. Firebase Spark plan and the Hostinger VPS only; no paid cloud services.
- Money is integer paisa everywhere (`parseTakaInput`). No floating-point currency math.
- Privacy first. Chat content stays on the VPS or in Firestore until end-to-end encryption ships (decision D-04 in `AGENTS.md`).
- Version and build numbers in `pubspec.yaml` increase monotonically.
- A change merges only after CI is green (`AGENTS.md`).

## 2. Corrections from v2.0

These items were described as missing or wrong in v2.0. The code on `main` shows otherwise.

| Item | v2.0 said | `main` shows | Change |
|---|---|---|---|
| P9.1 Live Journey flag | Enable `kLiveJourney` by default | Already `defaultValue: true` in `lib/core/config/feature_flags.dart`. The comment above it still says "off until acceptance tests" | Comment corrected in this PR. Remaining work is the device battery test |
| Remote Config keys | Set `journey_relay_enabled` and `journey_alarms_enabled` to true | Both already default to `true` | Done |
| P8.2 Picture-in-picture | Add `supportsPictureInPicture` and PiP | The manifest already has it, and `setPipAllowed` exists | Removed |
| P8.2 Reconnect | New 10-second ICE restart | `iceRestart` and `reoffer` exist, with a rebuild budget | Reconcile the new window with the existing budget |
| P8.1 Quality HUD | No visibility into poor networks | `PacketLossMeter` exists, and `AGENTS.md` documents a link-quality badge | Verify what is missing before building |
| P8.4 Voice-note speed | Add 1x, 1.5x, 2x | Already in `voice_message_bubble.dart` | Removed |
| P8.4 Chat search | Drift FTS5 over cached messages | No FTS exists. The chat cache is Hive-encrypted, not Drift | Decide where the search index lives |
| P9.2 Fare guide | Build a new guide | `local_fare_guide.dart`, `local_fare_guide_sheet.dart` and tests exist | Rescoped to a sourced content audit. The header now says estimates until entries are sourced |
| P10.1 TrxID dedup | Write path not wired; use `runTransaction` | Wired in the expense batch (`tour_group_repository.dart`). The rule allows create only. `trip_ledger_repository.dart` does not exist | Drop the transaction plan. Add the duplicate message and rules tests |
| P10.2 Statement PDF | No entry point in the ledger | `_exportMonthlyPdf` is wired in `expense_ledger_screen.dart` | Keep only the date-range choice and MFS status |
| P7.3 Acknowledgement ping | Implies an existing endpoint | `POST /notify/notice/ping` does not exist | New work |
| P11.1 Reel posters | Use ffmpeg on the VPS | No ffmpeg in `media-server/`. `AGENTS.md` says the package choice is pending | Decide the package first |
| P11.2 Desktop layout | New three-column shell | `desktop_tour_sidebar.dart` exists. No 1200 px layout exists | Build around the existing sidebar |
| Map style | "Bundled OpenFreeMap" | Bundled `assets/map/liberty_style.json` | Accurate, no change |
| Journey size | 9,100+ lines | About 8,400 Dart lines by filename match | Corrected |
| Merge gate | `gh pr merge --admin --squash` | `AGENTS.md`: CI must pass before merge | `--admin` removed |
| Document location | `docs/ROADMAP_AND_WORK_PLAN.md`, as PR #372 described | `docs/` is git-ignored (`.gitignore`), so the file never landed | Moved to `ROADMAP.md` at the root |
| Numbering | P7.x, "Wave 1", "Sprint 7" | `IMPLEMENTATION_PLAN.md` uses Phase 9 with Tasks 9.1–9.5 | Task numbers below follow the plan |

## 3. Work plan

### Sprint 7 — Everyday group specializations (Phase 9, active queue)

**Task 9.1 — Mess monthly settlement.** The meal-rate maths exists in `meal_engine.dart` (`mealTotalsForMonth`). Remaining:
- A monthly settlement view in `mess_ledger_screen.dart` (new): member, meals, cost, deposited, balance.
- An admin action that records settlement transfers in `tours/{id}/transfers`.
- A bazar duty schedule (`tours/{id}/mess_bazar_schedule/{dateKey}`) and its reminder, sent through the VPS.
- A printable 31-day meal sheet using `bangla_pdf`.

Formulas: meal rate = total bazar ÷ total logged meals; member owed = member's meals × rate; net balance = deposits − owed. Money stays in paisa.

**Task 9.2 — Society service requests.** Requests exist (`service_request_models.dart`, `society_requests_screen.dart`). Remaining:
- Up to three photos per request, uploaded through `TourMediaUploader`.
- A three-state timeline: open → in progress → resolved, with admin notes.
- Flat numbers on member profiles, with a call shortcut.
- Booking a resolved repair cost to the society maintenance ledger.

**Task 9.3 — Office and campus acknowledgements.** Remaining:
- A progress ring and counter on notices that need an answer.
- Done: the progress ring and the pending-member drawer (#425), and the admin ping to members who have not answered (`POST /notify/notice/ping`).
- A picnic and event contribution tracker. Scope to be confirmed (decision 4).

**Task 9.4 — Samity receipts.** Remaining:
- The admin attaches a signed receipt or transfer screenshot to `samity_payouts/{cycleKey}`.
- The beneficiary's confirmation sets `payoutStatus: verified`.
- Late payments show as overdue, with the amount still owed. No penalty fields are added (section 6, decision 2).

**Task 9.5 — Tests and checks.** Unit tests for the new meal and request logic, `dart format`, `flutter analyze --fatal-infos`, and `flutter test`.

### Sprint 8 — Calls and chat

Audited against the code. Most of this sprint is built; the open item needs a decision.

- **8.1 Quality HUD.** Built. The call HUD shows round-trip time, loss and outbound rate (`CallQualityHud` in `packet_loss_meter.dart`). The voice room collects round-trip and loss (`voice_room_service.dart`), but I found no HUD for it.
- **8.2 Reconnect.** Built. The 10-second window (`_reconnectTimeout` in `call_signaling_service.dart`) sits beside the rebuild budget, which is unchanged. Picture-in-picture is already done.
- **8.3 Speaking indicator.** Built. Voice-room tiles and the docked voice bar show a ring on a speaking member's avatar (`group_channels_screen.dart`, `voice_room_service.dart`).
- **8.4 Chat search.** Blocked on decision 5 (where the index lives). Voice-note speed is already done.

### Sprint 9 — Travel and Live Journey

- **9.1 Live Journey GA.** The flag and the Remote Config keys already default to on. The stale comment above the flag is corrected. Remaining: a 12-hour highway battery test on a device. This needs hardware, so it is a manual gate.
- **9.2 Fare guide.** The content and the sheet exist. Remaining: a sourced audit, with a source and an as-of date on every fare. The repository owner owns the data and reviews it quarterly (section 6, decision 3).
- **9.3 Route checkpoint overlay.** `RoutePlan` exists in `route_engine.dart`. Add GeoJSON route lines and numbered checkpoints to `offline_map_viewer_screen.dart`.
- **9.4 Itinerary PDF.** New. A multi-stop itinerary built with `bangla_pdf`.

### Sprint 10 — Ledger and FinOps

- **10.1 TrxID duplicates.** The write path and the registry rule exist. Remaining: a localized message for a duplicate TrxID, and rules tests for a second create.
- **10.2 Statement PDF.** Export exists. Remaining: a date-range choice (current month, whole tour, custom) and the MFS verification status.
- **10.3 Burn-rate alerts.** New thresholds in `fund_analytics.dart`: caution at 80%, red warning at 100%.

### Sprint 11 — Media, desktop and platform

- **11.1 Reel posters on the VPS.** Blocked on the ffmpeg package decision (`AGENTS.md`). Then a media-server worker that writes a `.webp` poster.
- **11.2 Desktop layout.** Build the three-pane layout around `desktop_tour_sidebar.dart`. Confirm the breakpoint first.
- **11.3 Android 16 edge-to-edge.** Verify on a device. Keep the APK under 175 MB.

### Track E — End-to-end encryption (Architecture & Lifecycle Complete, Rollout Open)

End-to-end encryption has completed its core architecture, implementation, and lifecycle milestones (M0–M4, M5 enablers):
- [x] A design document and a threat model ([`E2EE_DESIGN.md`](./E2EE_DESIGN.md)).
- [x] A group-channel design with Sender-Key / Megolm protocol ([`E2EE_GROUP_DESIGN.md`](./E2EE_GROUP_DESIGN.md)), covering forward/backward secrecy, `/split`, mentions, reactions, pins, and admin moderation.
- [x] Push previews are generic text on encrypted chats (`media-server/notifications.py`, `chat.py`).
- [x] Search over local decrypted messages (`domain/chat_search.dart`).
- [x] Automatic provisioning (`ensureReady`), orphaned claimed key pruning (`deleteStaleClaimedOneTimeKeys`), and safety number clipboard support.
- [ ] M6 outside cryptographic review & M7 general store copy rollout.

Google Drive backups of chat data wait for this track (decision D-04 in `AGENTS.md`).

## 4. Quality gates

1. Feature branch → PR → CI green → normal merge. No admin override.
2. `dart format` leaves no changes, checked against CI's Flutter version.
3. `flutter analyze --fatal-infos` and `flutter test` pass.
4. Money is integer paisa.
5. Firebase Spark only. Heavy compute runs on the VPS.
6. The version and build number increase monotonically in `pubspec.yaml`.
7. Rules changes ship with emulator tests in `functions/tests`.

## 5. Release and deployment

- Merging does not deploy. Firestore rules deploy only through a version tag (`v*.*.*`) or `firebase deploy --only firestore:rules`.
- Media-server changes reach the VPS through `media-server/deploy.sh`.
- A client build that depends on new rules ships only after those rules are live.

## 6. Open decisions

Decisions 1 to 3 are settled as of 2026-11-07. Decisions 4 and 5 are still open.

1. **Decided: end-to-end encryption is not in the 1.9 line.** It stays Track E, with its own design, threat model, budget and external review.
2. **Decided: samity late payments are shown, not fined.** Task 9.4 adds no penalty fields. `SamityLedger` already gives each cycle a status, overdue included, and what each member still owes. Any fine is the group's own rule, applied outside the app, because the app moves no money.
3. **Decided: fare data has one owner and a sourcing rule.** The repository owner owns the data. Each fare needs a source and an as-of date before the sheet presents it as verified. The data is reviewed once a quarter, and before any release that changes a fare.
4. Is the picnic and event tracker (task 9.3) wanted?
5. Where should the chat search index live: the encrypted Hive cache, or a new Drift table?

## 7. Decisions taken in this version

- This file is the canonical roadmap, at `ROADMAP.md` in the repository root. `IMPLEMENTATION_PLAN.md` stays the active queue.
- The `--admin` merge gate is removed.
- Task numbers follow `IMPLEMENTATION_PLAN.md`.
- End-to-end encryption is a separate track, not a sprint.
- Decisions 1 to 3 in section 6 are settled: end-to-end encryption has its own track, samity late payments are shown and not fined, and fare data has one owner and a sourcing rule.
- The flag comments and AGENTS.md now match the code: both feature flags default to on. The fare guide header says estimates, not verified fares. These are comment and documentation changes only.
