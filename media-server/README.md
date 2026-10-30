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

Set `PURGE_KEY` on the server, and the same value as the Functions secret
`MEDIA_PURGE_KEY`. Run the purge tests with `pytest tests/test_purge.py`.
