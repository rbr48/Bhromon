# Bhromon VPS Microservices Suite

A unified microservices suite running on the Hostinger VPS (`148.135.137.245`) designed to eliminate Firebase Blaze billing, Firebase Cloud Functions costs, and Firebase Storage rate limits. Keeps Bhromon operating 100% free on the Firebase Spark plan.

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
- `POST /api/media/upload` — Multipart upload with `Authorization: Bearer <token>`.
- `DELETE /api/media/media/{tourId}/{folder}/{filename}` — File deletion by author or tour admin.
- `POST /api/media/purge/account` — Closing an account: the back end removes that person's files and chat-service data (key-protected, see below).
- `GET /media/{tourId}/{folder}/{filename}` — Direct Nginx byte-range streaming (`206 Partial Content`).
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
