# External Integrations & APIs

**Analysis Date:** 2026-11-07

## 1. Firebase Suite
- **Cloud Firestore**: Primary realtime database (`tours/{id}`, `memberships/{tourId}__{email}`, `invites/{code}`, `channels`, `direct_messages`, `sos`). Configured with offline cache enabled.
- **Firebase Authentication**: Email/Password, Phone OTP, Google Sign-In with Android Credential Manager support (`serverClientId`).
- **Cloud Functions (TypeScript)**: Automated triggers for feed posts, comments, ledger transactions, SOS siren push notifications, GDPR account erasure, and daily backups.
- **Firebase Storage**: User avatars, post media, stories, and document attachments governed by `storage.rules`.
- **Firebase Hosting**: High-speed CDN hosting for Flutter Web app at `https://app.bhromon.fun` and `https://bhromon-ff801.web.app`.
- **Firebase Cloud Messaging (FCM)**: Push notification dispatch for SOS alerts, mentions, channel messages, and notice reminders.

## 2. Hostinger VPS & Media Server
- **Endpoint**: `https://bhromon.fun` (IP: `148.135.137.245`, SSH port: `2222`).
- **FastAPI Media Service**: Video transcoding, image compression, CDN proxy, and legacy SCP APK downloads.
- **Nginx Reverse Proxy**: SSL termination, caching headers, and media serving from `/var/www/bhromon/downloads/`.

## 3. WebRTC Calling Infrastructure
- **Signaling**: Firestore-based peer-to-peer signaling channels for 1-on-1 voice/video calls.
- **Voice Lounge**: Discord-style multi-party audio room inside tour groups.
- **STUN/TURN**: Configured ICE servers for NAT traversal and low-latency call connections.
- **Native Android Routing**: `flutter_callkit_incoming` for locked-screen call alerts and `audioplayers` for ringback / siren audio.

## 4. Financial & MFS Integrations
- **Bangla QR (EMVCo standard)**: Dynamic Bangla QR generation adhering to Bangladesh Bank interoperable payment standards.
- **MFS Providers**: bKash, Nagad, Rocket, Upay, Cellfin, and Bank Account transfers.
- **SMS Parser (`mfs_sms_parser.dart`)**: Regex-driven parser for extracting TrxID, sender, amount, and fee from official bank/MFS SMS notifications.
- **Verification Engine**: Admin verification and dispute states recorded per settlement.

## 5. Offline Maps & Geolocation
- **MapLibre GL**: Offline vector tile rendering using `.mbtiles` packages.
- **Geolocator**: Realtime GPS position, speed, altitude, and bearing calculations.
- **Highway & Spot Catalog (`destination_catalog.dart`)**: 40 curated Bangladesh destinations with GPS coordinates and waypoints.
