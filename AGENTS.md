# Bhromon — Agent Memory & Project Playbook

This document serves as the persistent system memory, architectural guidelines, and operating playbook for the Bhromon project. It was compiled from comprehensive multi-session trajectory analysis.

---

## 1. Project Overview & Architecture
- **Repository**: [https://github.com/rbr48/Bhromon](https://github.com/rbr48/Bhromon)
- **Primary Branch**: `main` (active and default).
- **Architecture**: Clean Architecture (Domain, Data, Presentation) with injectable DI, Drift (SQLite) for offline relational storage, and Hive for encrypted local boxes.
- **State management**: by feature. `tour_group` screens use `StatefulWidget`s that call repositories directly and listen to their streams. BLoC and Cubit remain in the other features. New tour-group code follows the direct pattern; don't add BLoC there.
- **Status**: free and open source, with no business model. No feature is sold, and no paywall or payments should be added. The Game Zone is a core feature and stays.
- **Backend**: Firebase Firestore (with offline persistence), Cloud Functions (TypeScript), Firebase Auth, Firebase Storage, and Firebase Hosting.
- **Live Deployments**:
  - **Flutter Web**: [https://app.bhromon.fun](https://app.bhromon.fun) / [https://bhromon-ff801.web.app](https://bhromon-ff801.web.app)
  - **Android Releases**: Signed release APK (`build/app/outputs/flutter-apk/app-release.apk`) & Play Store App Bundles (`aab`).

---

## 2. Google Play Store & Android Standards
1. **Target SDK**:
   - Always target **Android 16 (API Level 36)** or higher (`compileSdk 36`, `targetSdk 36`).
2. **Photo & Video Picker Compliance**:
   - Do **NOT** request broad storage permissions `READ_MEDIA_IMAGES` or `READ_MEDIA_VIDEO`.
   - Use the Android system Photo Picker via `image_picker` / system pickers.
3. **Version Numbering**:
   - In `pubspec.yaml`, increment version and version code monotonically on each release (e.g., `1.8.4+58`).
4. **Windows Gradle Build Contention**:
   - Always keep `org.gradle.vfs.watch=false` in `android/gradle.properties` to avoid Windows directory locks (`AccessDeniedException` during `mergeReleaseNativeLibs` or `packageRelease`).
   - In `android/app/build.gradle`, on Windows only, disable intermediate tasks: `artprofile`, `nativesymboltable`, `nativedebugmetadata`, `cleanmergereleaseassets`, `cleanmergereleasenativelibs`, and `cleanpackagerelease`. Keep `ndk { debugSymbolLevel 'SYMBOL_TABLE' }` on every platform: the release AAB fails to strip native libraries without it.

---

## 3. Web Compatibility Invariants (`kIsWeb`)
1. **Zero `dart:io` on Web**:
   - Never call `Platform.isAndroid`, `Platform.isWindows`, or `Platform.operatingSystem` directly without guarding with `if (!kIsWeb)`.
2. **Background Services**:
   - Mobile-only background services (`SyncWorker`, `Workmanager`, `flutter_local_notifications`) must be wrapped with `if (!kIsWeb)`.
3. **Web Deployment Protocol**:
   - Build: `flutter build web --release`
   - Deploy: `firebase deploy --only hosting`

---

## 4. Key Subsystems & Business Logic

### A. Universal Tour Engine
- The app has transitioned from a hardcoded 5-day Cox's Bazar tour to a **Universal Tour Engine** (`lib/features/tour_group/`).
- Supports any destination, duration (e.g., 1-day day tour to multi-week treks), and tour style (Beach, Hill-Trek, Heritage/Cultural, Riverine, Nature/Forest).
- Computes dynamic itineraries, budget estimations, and packing checklists per person/family.
- **Multi-destination trips (`itinerary_models.dart`, `widgets/itinerary/itinerary_editor.dart`):** a tour holds an ordered list of `stops` (Cox's Bazar → Bandarban → Sajek, Sylhet → Sreemangal, ...), each with its own kind, arrive and leave dates, nights and notes. Admins edit them; `saveItinerary` keeps the tour's `destination` summary, tour type and dates in step. Tours saved before stops existed read as one stop with id `main` (`effectiveStops`). `stopOn(date)` tells which stop a day belongs to; expenses and notices use it when no stop is chosen. `destination_catalog.dart` has 40 Bangladesh presets with coordinates (longest name match wins).
- **Route roadmap (`journey_tracker_screen.dart`, `route_engine.dart`):** `RoutePlan.of(group)` turns origin → stops → (optionally) home into legs. Each leg has a transport mode (road, rail, air, river, sea, jeep, boat, trek), a straight-line distance with a per-mode detour factor, an estimated duration, and planned and actual depart and arrive times (`legPlans`, keyed `origin>stopId` with `FieldPath`). Progress, the current and next leg, ETAs and a Google Maps directions link (none when there are more than 9 waypoints) come from the plan. Checkpoints are typed (food, prayer, fuel, washroom, viewpoint, army checkpost, ferry, toll, ...), belong to a leg, and are ticked off as visited; the author or an admin edits them. `route_suggestions.dart` proposes common highway stops from Dhaka. Distances are estimates and are labelled that way.

### B. Tour Group Hub & Trip Ledger
- **Access is membership-based.** `memberships/{tourId}__{email}` decides who can read a tour. Roles are `owner`, `admin` and `member`. Only the owner changes ownership or the invite code, or promotes someone to admin. Admins edit trip details and remove members; the owner's row cannot be removed.
- **Feed writes are checked by the rules.** A post, comment or story is stamped with `createdAt == request.time` and must be under the caller's own email. Likes and story views change only the caller's own entry (`ownEntryOnly`); comment counts move by one. Post edits are limited to a fixed field list, and the author or an admin makes them. Story votes and reactions are keyed by email with `FieldPath`, never a dotted string, because an email's dots would split it. Story delete: author or admin. Highlights carry `createdByEmail`; the creator or an admin deletes them (highlights saved before this field existed can be removed by admins only). Deleting a post removes its comments first, because their delete rules read the post.
- **Feed paging (`PagedPostFeed`):** the feed is read in pages of 60 by creation time. Each page is a live query over a range (`createdAt < upper`, `>= lower`), and the bounds come from `feedPageBoundary`. Adding or deleting a post shows at once, and the pages never overlap or leave a gap. `functions/tests/paged_feed.test.js` checks the same queries on the emulator.
- **Invite codes** live in `invites/{code}`: readable by exact code, never listed. Codes are 8 characters from an unambiguous alphabet (legacy 6-character codes still work). Joining always creates a plain member and is refused for accounts in `tours/{id}/bans`. Removing a member writes a ban and deletes the row together.
- **Rules are tested on the emulator:** `functions/tests/tour_group_rules.test.js`, `tour_group_storage_rules.test.js` and `firestore.rules.test.js` all share one emulator project. Run them with `npx firebase-tools@13.35.1 emulators:exec --only firestore,storage --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/"`. `--runInBand` is required because the suites clear that project. Storage rules look up memberships on the emulator's `--project`, so the flag must name that project. The CLI is pinned: firebase-tools 15.x fails the Storage rules' firestore lookups, which denies every upload.
- **Expense allocation (`trip_ledger_engine.dart`):** always integer paisa. User amounts go through `parseTakaInput` (Bengali digits accepted; zero, negative and over-cap amounts refused). An expense's `splitMode` is `family` (the default and the only mode before this field: participants weighted by `familyCount`, 1 to 20, which members set for themselves), `equal`, `exact` (paisa per email in `splitShares`, which must add up) or `shares` (parts per email). An exact amount owed by someone who has left is spread over the rest so the books balance. Payers and depositors who have left keep their balance; email matching ignores case.
- **Fund (`expense_ledger_screen.dart`, `fund_analytics.dart`, `widgets/fund/`):** tabs Overview, Expenses, Settle up, People, Deposits. Settle-up payments live in `tours/{id}/transfers` (a null `fromId` is the fund paying out, a null `toId` is money into the fund); they move balances and the fund (`net = contributed + sent − received − share`). The rules let a member record only a payment they made or received, admins any; payments are never edited, and the author or an admin deletes them. Suggested settlements carry member ids so "Mark paid" records the right people. Admins set `fundBudget` on the tour (budget per category plus a per-person collection target, multiplied by each member's `familyCount`). `FundReport` gives budget lines, the daily burn and projection, the collection and who still owes, and spending by stop, by day and the largest expenses. A foreign-currency expense keeps `currency`, `originalMinor` and `fxRate`; the books use the BDT amount. The CSV export is UTF-8 with a BOM.

- **Offline:** the tour list comes from memberships, not the cache, so tours the user left stop showing. A write that is not acknowledged within 8 seconds is reported as syncing and kept queued; a rejected write is removed from the local cache.
- **Safety alerts (SOS):** turning the siren on raises an alert in `tours/{id}/sos` with the sender's name and, when available, their location. Every active member sees open alerts at the top of the Family Safety Hub. An alert closes when the sender turns the siren off, the sender or an admin resolves it, or it is six hours old (`kSafetyAlertWindow`). Only the sender may raise under their own email; resolving may change only the resolution fields. Raising an alert sends a push to the other active members through `sendSosAlert` (`functions/src/sendSosAlert.ts`). The function resolves each member's email to an account with the Admin SDK and reads that account's device token from `fcm_tokens`, so a member who has never signed in on a device gets no push. Alerts also show in the app.
- **Journey stops:** the member who added a journey stop, or an admin, can delete it by long press.
- **Notice board (`notice_board_screen.dart`, `notice_engine.dart`, `widgets/notice/notice_composer.dart`):** admins post, edit, pin and delete notices. A notice has a `kind` (announcement, schedule, meetup, reminder, emergency, rule, rollcall; older notices read as announcements), an optional `eventAt`, `place`, `mapUrl` and `stopId`, and `expiresAt`, after which it is in the archive (timed notices default to a few hours after they happen). With `requireAck`, or always for a roll call, members answer ("Got it" / "I'm here"): the rules let a member change only their own email in `ackBy`; admins can mark anyone. Editing keeps the author, original time and answers. The board shows the next timed notice with a countdown, today's schedule, and filters (active, pinned, upcoming, needs my reply, archive). Twelve templates are in `kNoticeTemplates`; their text is `notice_tpl_<id>_title` and `_body`. "Add to calendar" opens a Google Calendar link; there are no push reminders.

- **Group channels (`group_channels_screen.dart`, `tour_channel_repository.dart`):** the four built-in channels (`general`, `food`, `sightseeing`, `emergency`) plus any channel an admin adds at `tours/{id}/channels/{channelId}`. `adminOnly` limits posting to admins. Members edit and delete their own messages; admins delete any message and pin up to 50. Reactions and poll votes change only the member's own entry, which the rules check as a map diff. A message holds text, up to four photos or one video (uploaded through `TourMediaUploader` into the `channels` folder), a reply quote, and mentions. Markdown (`**bold**`, `*italic*`, `~~strike~~`, `` `code` ``, `||spoiler||`, `> quote`, links) and mention resolution are pure Dart in `chat_markdown.dart` and `chat_mentions.dart`. Slash commands in `chat_commands.dart`: `/split <amount> <title>` records a ledger expense paid by the sender, and `/poll Question | A | B` posts a poll of two to six options. Unread dots and mention counts come from the newest message and an `arrayContains` query; read times and mutes are kept on the device (`channel_prefs` box). Typing signals live in `channels/{id}/typing/{email}`. The sticky itinerary bar reads `meta/itinerary.currentStopId`, which admins set. Seat and room badges come from bus seats and hotel rooms. Calls are built (`call_screen.dart`, `call_signaling_service.dart`, WebRTC). Not built, because they need infrastructure this repo does not have: push-to-talk, offline BLE mesh (native plugins), link previews (server functions), bots and webhooks, threads, and presence.
- **Languages (Bengali and English):** the chosen language is `LocaleController` (`lib/core/localization/locale_controller.dart`), saved in the Hive box `app_prefs` and changed under Settings. Bengali is the default. Tour copy lives in `tour_translation_keys.dart`; read it with `context.l10n.translate('key', args: {...})`, and fill `{name}` placeholders through `args`. `test/core/localization` fails if a key used by a tour screen is missing in either language, or if the two languages use different placeholders. Converted so far: group hub, notice board, group channels, bus seats, logistics hub, transport, hotel rooms, checklist, scrapbook, trip shell tabs, journey and route, fund. Write counts and years with `context.l10n.number(n)`, which uses Bengali digits in Bengali. The checklist's default items are keys in `checklistDefaultItems`, whose order is their saved id (`default_0` ...), so new items go at the end; custom items still save the Bengali category string. Still in Dart literals: instafeed, quiz, tide guide, family safety hub. Preset destinations, tour-type labels and backup filenames stay English on purpose: the Dhaka-origin logic and stored values depend on them. Dates are still formatted in English; `initializeDateFormatting` is not called yet.
- **Theme (`ThemeController`, `lib/core/theme/theme_controller.dart`):** the user chooses System, Light or Dark under Settings, kept in the Hive box `app_prefs` (key `app_theme`). The default is still Dark, because many screens hard-code white text with no background of their own. Changing the default needs a pass over those screens first. Brand accents use `AppColors.mintGreen` and `AppColors.darkGreen`; text on mint uses dark green, never white.
- **Scrapbook magazine (`tour_scrapbook_screen.dart`):** a swipeable magazine built by `ScrapbookIssue.build` (`domain/services/scrapbook_engine.dart`) from the newest 300 posts, the members and the ledger, and laid out by `ScrapbookMagazine` (`widgets/scrapbook/`). Pages: cover (best-received photo), the trip in numbers (with money spent), the reader's own page, one chapter per tour day, most loved moments, quotes, awards, places and a back cover. A page or award appears only when real data supports it; awards have minimums and ties go to the name first in order. Each page can be shared as a PNG; when the image cannot be made (for example a cross-origin photo on web), the text summary is shared instead. Reels show the post's `coverUrl` (the first frame, taken on the device at upload), or a gradient tile when there is none.
- **Transport (`transport_screen.dart`) and hotel rooms (`hotel_room_map_screen.dart`):** the logistics hub has a Transport tab and a Hotel tab. Vehicles live in `tours/{id}/vehicles` (admins only) with a kind (coach, business coach, sleeper coach, microbus, car, train chair, train cabin, flight, launch cabins, ship) and layout settings (rows, seats across such as `2-2` or `2-3-2`, decks or floors, berths per cabin). `seat_layout_engine.dart` turns them into a seat map; seat ids follow each kind's convention (A1, 12C, L3, C2-4, 101-2). Seats are `tours/{id}/vehicle_seats/{vehicleId}__{seatNumber}`; the rules check that id, that the vehicle exists, the field list, and that a locked vehicle is changed by admins only. The tour's original 36-seat coach stays in `bus_seats` and shows while anyone sits on it or while there are no vehicles. A member holds up to `familyCount` seats per vehicle (`familySlot` 0, 1, ...); at that limit their last seat moves. `watchBusSeats` merges both collections for the seat badges in channels and the feed. Auto-seating (`seat_planner.dart`) keeps a family in the frontmost row where it fits, within one block if possible. Rooms have a hotel name, bed type and balcony; occupancy counts each guest's family; the one-room rule is per hotel; auto-rooming gives each family the tightest room that fits and never splits one. Both tabs share a passenger or room list as text.
- **Known limits:** tide times are estimates and are labelled that way. Seat maps are drawn from the layout settings, so an unusual real coach may need the closest pattern.

### C. Tour Reels & Media Sharing (VPS Microservice)
- Vertical reels video feed (`tour_instafeed_screen.dart`) matching Family Bhromon with video playback controls, aspect ratio fitting, upload flows, and media filters.
- **Dedicated VPS Media Storage**: To bypass Firebase Storage rate limits and bandwidth charges, media is hosted on the user's Hostinger VPS (`148.135.137.245`) in an isolated Docker container (`bhromon-media-app` on `127.0.0.1:8210`), saving to `/var/www/bhromon-media`.
- **High-Performance Streaming**: Nginx directly serves `/media/` using `http_mp4_module` with native HTTP Range Requests (`206 Partial Content`) for instant video reels seeking and edge caching via Cloudflare.
- **Uploads go through `TourMediaUploader`**: Uses `Dio` for chunked streaming upload (`POST https://bhromon.fun/api/media/upload`), cancellation via `CancelToken`, real-time progress stream, and deletion via `DELETE https://bhromon.fun/api/media/media/{tourId}/{folder}/{filename}` (with backward-compatible deletion fallback for legacy Firebase Storage URLs). Every request carries the signed-in member's Firebase ID token as a bearer token; there is no shared upload key in the app. The client picks the 32-hex `objectId`, so the URL is known before the response arrives. Limits: images 10 MB, videos 100 MB, reels 3 minutes.
- **Media server (`media-server/main.py`, v2):** checks the ID token and an active membership for every upload and delete. Deletes are allowed for the uploader (recorded in a sidecar under `MEDIA_META_ROOT`), a tour owner, or an admin. Folders and extensions are allowlisted; uploads never overwrite (`409`). `LEGACY_UPLOAD_KEY` is a transition aid for app builds that predate token auth and stays unset once they are gone. Run its tests with `cd media-server && pip install -r requirements-dev.txt && pytest`.
- **Orphan sweep (`TourMediaJournal`, Hive box `media_journal`):** each upload is journaled before it starts, and its entry is dropped once a post or story saves it (`commit`) or the upload is removed (`discard`). Feed open runs `sweep`: an entry older than 30 minutes that no post, story or highlight references is deleted from the server. Deletes that failed are retried the same way. Channel attachments are untracked (`TourMediaJournal.untracked`) because the sweep cannot see channel messages.
- Posts never store device paths or blob URLs. A post with an unfinished upload is refused, and a failed or cancelled post discards the files it uploaded; a post that did save keeps them even if a later step (such as the poll) fails.
- **Platform code:** `dart:io` is imported only in `tour_media_upload_io.dart`. Web uses `putData` / bytes and blob URLs.
- **Server-side reel thumbnails:** not generated. The first frame is taken on the device at upload (`VideoCompress.getFileThumbnail` in `instafeed_create_studio.dart`). Server-side generation needs a decision on the package first.

### D. Family Game Zone (`lib/features/game_zone/`)
Game rules live in pure-Dart models/engines (unit-tested); screens only render and drive timers.
Every game screen locks portrait (`common/game_zone_portrait_lock.dart`), keeps its game in a
static session while the user visits other screens, and asks before discarding a game in progress.
1. **Card 29 (`card29/`, model `card29_game.dart`)**:
   - 32 cards (J:3, 9:2, A:1, 10:1, K:0, Q:0, 8:0, 7:0) + 1 for the last trick = 29.
   - Bidding 16–28 from the dealer's left, a pass is final, dealer rotates; all-pass → dealer plays at 16.
   - Strict trump rule with partnership immunity: once trump is revealed, any player who cannot follow lead suit MUST play trump if held when an opponent is winning the trick; if their partner is already winning, they are not forced to trump and may discard or feed points. The bidder reveals trump by playing it while void and may not lead the hidden trump suit; a trump-suit discard before the reveal has no trump power (PlayedCard.trumpEligible).
   - Pair (royalty, K+Q of trump, after reveal): bidding team target −4 (min 16), opponents' pair → target +4 (max 28). Bots claim it too.
   - A finished trick sits in `Card29Phase.trickComplete` until `resolveTrick()`, so no card can be played during the pause.
   - 6-pip match game tracking; a new round after `matchOver` starts a fresh match.
2. **Travel Chess AI (`chess/`)**:
   - Complete Kingside (`O-O`) and Queenside (`O-O-O`) castling (needs the own rook on its corner; moving or capturing on a corner revokes the right).
   - En Passant capture logic; search uses exact make/unmake (`_doMove`/`_undoRecord`), never ad-hoc board edits.
   - Interactive promotion selector modal (Queen, Rook, Bishop, Knight); dismissing it cancels the move.
   - King check visual alert and halo highlight.
   - Move history with SAN notation and Takeback (`undoMove()` restores castling rights, en passant and clocks).
   - Draws: stalemate, insufficient material, 50-move rule, threefold repetition, draw offer; resign.
   - AI (negamax + alpha-beta + quiescence) runs via `compute(chessAiWorker, ChessAiRequest(...))`; depths Easy 1 / Medium 2 / Hard 4.
   - Board coordinate annotations (`a-h`, `1-8`) and last-move highlights.
   - Crisp vector Staunton pawns (_ChessPawnPainter) immune to Android NotoColorEmoji font fallback hijacking, guaranteeing authentic side colors.
3. **Ludo Express (`ludo/`)**:
   - Home tokens remain docked and visible inside central home triangles.
   - Tokens sharing a square split it as a 2×2 grid.
   - Three consecutive sixes forfeits the turn; the counter resets on every turn change (`passTurn()`).
   - Pass & Play mode supporting any combination of Human and Bot players (at least one human); any mode change restarts the turn flow.
   - Board grid is 6:3:6 in every band; track cells are outlined, start squares tinted, safe squares starred.
4. **Teen Patti (`teen_patti/`, model `teen_patti_game.dart`)**:
   - Ranking: Trail > Pure sequence > Sequence > Colour > Pair > High card; A-K-Q is the top run, A-2-3 the lowest.
   - Sideshow (Back-Ask): a seen player asks the previous seen player to compare privately; the target may decline; a tie packs the asker.
   - Dynamic bet raising up to 40 base / 80 chaal; every stake checks the player's chips first (no negative balances).
   - Blind turn limit (max 4).
   - Show ties split the pot between the tied players only; the pot is cleared on payout; pot limit 1280 forces a show.
   - Real-time hand rank badge for seen cards.
   - Chip rebuy popup (+500 chips) when you can't cover boot + one blind.
5. **Carrom (`carrom/`, physics `carrom_engine.dart`, rules `carrom_game.dart`)**:
   - Deterministic fixed-step physics (1/480 s) on a 0..1 board with ICF proportions: friction, cushion and coin restitution, a striker ~2.6× a coin's mass, 4 corner pockets.
   - You play white from the bottom baseline; the opponent (bot or Pass & Play) plays black from the top. Striker slides along the baseline (drag or slider) and may not touch a coin; drag back anywhere and release to shoot.
   - Own coin pocketed → shoot again; opponent-colour coins stay down and count for the opponent.
   - Strict ICF fouls: striker pocketed, own last coin before the queen is covered (including covering her with it in the same shot), or the opponent's last coin. On a foul the shot's own coins, the queen and the opponent's last coin return, one penalty coin is paid and the turn ends; with nothing to pay the penalty is due (`penaltyDue`) and taken from the next coin pocketed.
   - Queen only after an own coin; must be covered on the same or next shot or she returns.
   - First to 9 coins wins the board: 1 point per opponent coin left, +3 for covering the queen.
   - Bot (`CarromBot`) builds cut shots from ghost-ball geometry with the minimum power that carries the coin (friction + momentum transfer), simulates each candidate, and adds aim noise per difficulty (Easy 0.035 / Medium 0.018 / Hard 0.008 rad). It runs via `compute(carromBotWorker, ...)`.

---

## 5. Testing & Quality Verification Checklist
Before shipping or pushing changes:
1. `flutter test test/features/game_zone/ test/features/tour_group/` -> All tests must pass.
2. `flutter analyze lib/` -> Must report `No issues found!` (0 errors, 0 warnings).
3. If building APK: `flutter build apk --release`.
4. If updating Web: `flutter build web --release` && `firebase deploy --only hosting`.
5. Functions: `cd functions && npx tsc --noEmit && npx jest src` must pass.
6. Keep `git status` clean. Changes go in through a pull request; CI must pass before merge.
7. Never commit credentials or session cookies. Read them from environment variables. Facebook session cookies and a crawler credential were removed from the git history on 26 Oct 2026. Rotate any credential that was exposed.
