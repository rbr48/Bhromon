# Bhromon VPS Media Server

A lightweight, high-performance media server designed for hosting and streaming Bhromon's tour photos, reels, and stories directly on the Hostinger VPS to eliminate Firebase Storage rate limits and bandwidth costs.

---

## Architecture & Isolation
- **Container**: `bhromon-media-app` running FastAPI with Uvicorn.
- **Port**: Bound exclusively to `127.0.0.1:8210` on the host, ensuring zero conflict with existing Docker containers on ports 8075–8190.
- **Persistent Storage**: Mounted at `/var/www/bhromon-media` (host) $\rightarrow$ `/data/media` (container).
- **Public Domain**: `https://bhromon.fun` (proxied through Cloudflare with Let's Encrypt SSL).

---

## Nginx Streaming & CDN Optimization
Static delivery is handled directly by Nginx at C-speed using `http_mp4_module`:
- Native **HTTP 206 Partial Content** byte-range requests for smooth video seek and reels buffering.
- Cache-Control: `public, max-age=31536000, immutable` cached at Cloudflare edge.
- Direct streaming uploads with `proxy_request_buffering off;` allowing 100MB+ video uploads without temporary buffer overhead.

---

## Endpoints
1. `GET /api/media/health`
   - Returns: `{"status": "ok", "service": "bhromon-media-server"}`
2. `POST /api/media/upload` (multipart)
   - Header: `Authorization: Bearer <Firebase ID token>`. The token must belong to an active member of the tour.
   - Form fields: `file`, `tourId` (letters, digits, `-` and `_`), `folder` (`posts`, `reels`, `stories` or `channels`), and optionally `objectId` (32 lowercase hex characters). The client picks `objectId` so it knows the URL before the upload returns. The server generates one when it is omitted.
   - The uploader is recorded from the token. Any `uploaderEmail` form field is ignored.
   - Returns:
     ```json
     {
       "status": "success",
       "url": "https://bhromon.fun/media/{tourId}/{folder}/{objectId}.jpg",
       "filename": "{objectId}.jpg",
       "bytes": 12345,
       "contentType": "image/jpeg"
     }
     ```
   - Refuses a file whose name already exists (409), an unknown folder or extension (400), and a file over the size limit (413, nothing is kept).
3. `DELETE /api/media/media/{tourId}/{folder}/{filename}`
   - Header: `Authorization: Bearer <Firebase ID token>`.
   - Allowed for the uploader, a tour owner, or an admin. A file uploaded before this version has no uploader on record, so only an admin can delete it.
   - Returns `{"status": "deleted"}`, or `{"status": "not_found"}` for a file that is already gone.
4. `GET /media/{tourId}/{folder}/{filename}`
   - High-speed static delivery with byte-range streaming. Anyone with the link can read a file.

## Configuration
| Variable | Purpose |
| --- | --- |
| `FIREBASE_CREDENTIALS` | Path to the Firebase Admin service account JSON, mounted read-only. |
| `MEDIA_ROOT` | Where files are stored (`/data/media`). |
| `MEDIA_META_ROOT` | Uploader records, kept outside the public tree (`/data/media-meta`). |
| `LEGACY_UPLOAD_KEY` | Transition only. Lets app builds without token auth keep working. Unset it once they are gone. |
| `CORS_ORIGINS` | Comma-separated web origins allowed to call the API. |

## Deploying
1. Create the Firebase service account key and place it at `/etc/bhromon/firebase-admin.json` on the VPS (not in git).
2. Create `/var/www/bhromon-media-meta`.
3. Set `LEGACY_UPLOAD_KEY` in the host environment to the old key while old app builds are still in use.
4. Deploy the server, then ship the app that sends tokens. Remove `LEGACY_UPLOAD_KEY` when no old builds are left.

## Tests
    pip install -r requirements-dev.txt
    python -m pytest -q tests
