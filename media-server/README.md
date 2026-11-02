# Bhromon VPS Microservices Suite

A unified microservices suite running on the Hostinger VPS (`bhromon.fun`) designed to eliminate Firebase Blaze billing, Firebase Cloud Functions costs, and Firebase Storage rate limits. Keeps Bhromon operating 100% free on the Firebase Spark plan.

---

## 1. Architecture & Port Isolation

| Service | Container Name | Port (Host) | Technology | Path / Reverse Proxy | Purpose |
|---|---|---|---|---|---|
| **Media & Notifications** | `bhromon-media-app` | `127.0.0.1:8210` | Python 3.12 (FastAPI, Uvicorn) | `/api/media/` & `/media/` | High-speed reels/photos streaming with MP4 byte-range requests; background FCM multicast notifications |
| **Online Games Engine** | `bhromon-games-app` | `127.0.0.1:8220` | Node 20 (Express, TypeScript) | `/api/games/` | Server-authoritative table state & transactions for Card 29, Teen Patti, and Carrom |

Both services mount `/etc/bhromon/firebase-admin.json:ro` to authenticate requests and interact with Firestore/FCM via the privileged Firebase Admin SDK.

---

## 2. Endpoints Overview

### A. Games Microservice (`/api/games/`)
- `GET /api/games/health` — Service status and list of registered callables.
- `POST /api/games/:name` — Dispatches table actions with `Authorization: Bearer <Firebase ID token>`.
  - **Card 29**: `card29Start`, `card29Act`, `card29Advance`, `card29Leave`
  - **Teen Patti**: `teenPattiStart`, `teenPattiAct`, `teenPattiAdvance`, `teenPattiLeave`
  - **Carrom**: `carromStart`, `carromShoot`, `carromAdvance`, `carromLeave`

### B. Media & Notifications Microservice (`/api/media/`)
- `GET /api/media/health` — Status of media and background notification engine.
- `POST /api/media/upload` — Multipart upload with `Authorization: Bearer <token>`. The token's email must be verified; an unverified address is refused, as the Firestore and Storage rules refuse it.
- `DELETE /api/media/media/{tourId}/{folder}/{filename}` — File deletion by author or tour admin.
- `POST /api/media/purge/account` — Closing an account: the back end removes that person's files and chat-service data (key-protected, see below).
- `GET /media/{tourId}/{folder}/{filename}?u=<uid>&s=<signature>` — Nginx byte-range streaming (`206 Partial Content`), once the signed link passes the check. See "Private media links" below. `/media/apk/` stays public.
- `POST /api/media/notify/sos` — Direct emergency SOS multicast trigger.
- `POST /api/media/notify/channel` — Channel message and mention push notifications.

---

## 3. One-Command VPS Deployment

A deployment script is provided at `media-server/deploy.sh`:

```bash
cd /path/to/Bhromon/media-server
chmod +x deploy.sh
./deploy.sh
```

The script automatically:
1. Pulls the latest `main` branch.
2. Builds and starts Docker containers (`bhromon-media-app` and `bhromon-games-app`).
3. Runs health checks against `http://127.0.0.1:8210/health` and `http://127.0.0.1:8220/health`.
4. Copies `bhromon.fun.conf` to `/etc/nginx/sites-available/` and reloads Nginx.

---

## 4. Running Tests

### Media Server Tests (Python)
```bash
cd media-server
pip install -r requirements-dev.txt
pytest tests/
```

### Games Server Tests (Node)
```bash
cd functions
npm run build
npx jest tests/server.test.js
```

### Flutter Client Tests (Dart)
```bash
flutter test test/features/game_zone/game_server_api_test.dart
```

## Purging a tour's files

`POST /purge` removes files on the request of the Bhromon back end. The Cloud
Functions `onTourMembershipRemoved` and `onTourDeleted` call it when a member
leaves or is removed, and when a tour is deleted.

- The request must carry the header `X-Purge-Key`, which must equal the
  `PURGE_KEY` environment variable. With no key configured the route answers
  `503`; a wrong or missing key gets `401`.
- Body: `{"tourId": "...", "uploaderEmail": "..."}`. With an uploader, only that
  person's files in the tour are removed, matched on the sidecar each file was
  saved with. Without one, every file of the tour is removed.
- Files saved before sidecars existed have no uploader, so they only go with the
  whole tour.
- The response is `{"removed": n, "paths": [...]}`, where each path is relative
  to the tour's folder. The back end uses it to clear the receipts that pointed
  to a removed file.

## Closing an account

`POST /purge/account` takes `{"uid": "...", "email": "..."}` with the same
`X-Purge-Key`. It removes every file the email uploaded, in any space, and the
chat service's data for the uid: device tokens, the messages it sent, and its
place in other people's messages and conversations. The other person's messages
stay. It answers with the file count, the paths and the chat counts. Repeating
the call is harmless, so a closing that failed part way can be retried.

Set `PURGE_KEY` on the server, and the same value as the Functions secret
`MEDIA_PURGE_KEY`. Run the purge tests with `pytest tests/test_purge.py tests/test_account_purge.py`.

## Upload spaces

- A chat space, `chat_{uidA}_{uidB}`, takes media only from the two people in it,
  and only while they share a tour. The old shared fallback space is refused.
- A user space, `user_{uid}`, takes media only from its owner.
- The public spaces (`profiles`, `users`, `general`, `explorer`, `trip_logs`) take
  media from any signed-in person, as they always have.
- There is no shared upload key. An old app build that still sends one is refused.

## Storage limits, reshares, and the CDN

- `MEDIA_TOUR_QUOTA_BYTES` (default 20 GiB) caps what one tour may store.
- `MEDIA_UPLOADER_QUOTA_BYTES` (default 4 GiB) caps what one person may store in a tour.
- `MEDIA_MIN_FREE_BYTES` (default 5 GiB) refuses uploads while the disk has less free space.
- `MEDIA_UPLOADS_PER_MINUTE` (default 60) limits how fast one person may upload.

Usage is read from the upload sidecars, so deletes and purges free space at once. Each limit
is checked before a new file is kept. A retry of a file that is already stored is never refused.

`bhromon.fun.conf` refuses `/api/media/upload` and `/api/media/copy` requests that have no
`Authorization` header, before their body is read. After changing that file on the VPS, run
`nginx -t` before reloading nginx.

A reshare calls `POST /api/media/copy`. The copy is a hard link: the story gets its own name for
the same bytes, so deleting the original post does not remove the story's file.

Deleting a file also clears its cached copy on the CDN when `config/cdn` holds a zone and a
token. A failed purge is logged and never fails the delete.

## Private media links

Tour, chat and profile media is private. nginx serves a file only when its link carries a
valid signature for a person who may read that space (`media_access.py`).

- `POST /api/media/access-key` (signed in, verified email) returns `{uid, key}`. The key is
  derived from `MEDIA_ACCESS_SECRET`, and only its owner is given it. The app keeps it on
  the device.
- A link is the file's `/media/...` path with `?u=<uid>&s=<signature>`. The signature is
  HMAC-SHA256 of `v1|<path>` under the key, base64url without padding.
- Before it serves a file, nginx asks `/internal/media-auth`. The server checks the
  signature, then the same rules as uploads: an active member of the tour, one of the two
  people in a chat who share a tour, the owner of a user space, or any signed-in person in
  the public spaces. Each answer is remembered for 60 seconds.
- `/media/apk/` stays public. It is the Android download linked from the newspaper page.

Links do not expire, so cached copies and offline viewing keep working. A link stops
working when its person leaves the tour, when the file is deleted, or when the secret
changes, which revokes every link at once. Browsers may keep a copy for a day, and shared
caches are told not to keep one at all.

Rollout, in this order:

1. Set `MEDIA_ACCESS_SECRET` on the host. Generate it once with
   `python3 -c 'import secrets; print(secrets.token_urlsafe(48))'`. Never commit it.
2. Deploy this server with `MEDIA_ACCESS_ENFORCE=0` (the default). Requests that would be
   refused are logged as "would be refused" and still served, so the logs show what older
   app builds would lose.
3. Copy `bhromon.fun.conf` to nginx, run `nginx -t`, and reload.
4. Release the app that signs links.
5. When the logs show no more refusals from current builds, set `MEDIA_ACCESS_ENFORCE=1`
   and restart the container.

Tests: `pytest tests/test_media_access.py`. The Dart client checks the same reference
values in `test/core/media/media_signing_test.dart`.

## Backups

`backup_store.py` writes one folder per run: a consistent copy of each SQLite
database under the metadata root (taken with SQLite's online backup, so it is
safe while the server runs), a tar of the metadata, and with `--include-media` a
tar of the uploaded files. The newest `--keep` runs are kept.

```
python3 backup_store.py --dest /var/backups/bhromon --keep 14 --include-media
```

Run it daily from cron, and copy the destination off the server. A copy beside
the data does not survive the loss of its disk. Run the tests with
`pytest tests/test_backup_store.py`.

## News fetching

The reader and the web proxy fetch pages only from the newspapers in the catalog
(`ALLOWED_FETCH_DOMAINS` in `news.py`), and every redirect is checked against that
list. `POST /api/news/sync` needs a platform admin. A `refresh=true` on the headlines
runs a sync at most every 10 minutes. Run the guard tests with
`pytest tests/test_news_fetch_guard.py`.

## Answer reminders

A notice can ask its readers to answer it: an acknowledgement or a roll call. The app
shows the open ones as "needs my reply". `ack_reminders.py` pushes a reminder to the
members who have not answered yet. It runs inside the media server:

- **Cadence.** The first reminder waits two hours after the notice was posted, because
  the first push already went out then. A later reminder waits at least twelve hours
  after the previous one, and at most two are sent for one notice. A notice older than
  fourteen days is left alone, and an expired notice is in the archive, so it is never
  reminded about.
- **Once only.** Each reminder is claimed in a Firestore transaction (`ackReminderSentAt`
  and `ackReminderCount` on the notice), so overlapping runs send it once.
- **Schedule.** The scheduler checks every fifteen minutes. Deploying the image starts it
  with the other background jobs, so nothing else is needed.
- **Manual run.** `POST /internal/ack-reminders/run` with the header
  `X-Ack-Reminder-Key` runs the check once and returns the counts. Set the key in
  `ACK_REMINDER_RUN_KEY` on the server. Without it, the endpoint refuses every call.

The push opens the notice board, the same as a new notice's push. Tests:
`cd media-server && pytest tests/test_ack_reminders.py`.

## Calls: TURN over TLS and iPhone VoIP pushes

Both are off until configured, and the server works without them.

**TURN over TLS.** Some office, campus and hotel networks let only HTTPS out, so
TURN on 3478 cannot connect there. coturn can also listen with TLS:

1. Give coturn the certificate for `turn.bhromon.fun` (`cert=` and `pkey=` in
   `turnserver.conf`) and a TLS port (`tls-listening-port=5349`).
2. Port 443 on the VPS belongs to nginx. Either give coturn a second IP address
   on 443, or let nginx pass TLS for `turn.bhromon.fun` through to coturn by
   SNI (`stream { map $ssl_preread_server_name ... }` with `ssl_preread on;`).
3. Set `TURN_TLS_URLS=turns:turn.bhromon.fun:443?transport=tcp` for the media
   container and restart it. `/api/chat/ice_servers` then offers it with the
   other TURN addresses, under the same short-lived credential.

**iPhone VoIP pushes.** A closed iPhone shows the system call screen only for an
Apple VoIP push. The app registers its PushKit token with the platform
`ios-voip`; offers to that token go to Apple (`voip_push.py`), never to FCM.

1. In the Apple developer account, create an APNs key (.p8) and note its key id
   and the team id. Enable Push Notifications for the app id, and add the
   capability (an `aps-environment` entitlement) to the Runner target.
2. Put the key on the VPS outside the repository and set `APNS_KEY_PATH`,
   `APNS_KEY_ID`, `APNS_TEAM_ID` and `APNS_BUNDLE_ID` (`com.bhromon.bhromon`
   today). Set `APNS_SANDBOX=1` for development builds.
3. Rebuild the media image: Apple accepts HTTP/2 only, which `httpx[http2]`
   in `requirements.txt` provides.
