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
2. `POST /api/media/upload`
   - Header: `X-Upload-Key: <MEDIA_UPLOAD_KEY>`
   - Form Data:
     - `file`: Multipart file (images up to 15MB, videos up to 120MB)
     - `tourId`: String
     - `folder`: String (`photos`, `reels`, `stories`, etc.)
     - `uploaderEmail`: String
   - Returns:
     ```json
     {
       "status": "success",
       "url": "https://bhromon.fun/media/{tourId}/{folder}/{filename}",
       "filename": "{filename}",
       "bytes": 12345,
       "contentType": "image/jpeg"
     }
     ```
3. `DELETE /api/media/media/{tourId}/{folder}/{filename}`
   - Header: `X-Upload-Key: <MEDIA_UPLOAD_KEY>`
   - Deletes file from disk and returns `{"status": "deleted"}`.
4. `GET /media/{tourId}/{folder}/{filename}`
   - High-speed static delivery with byte-range streaming.
