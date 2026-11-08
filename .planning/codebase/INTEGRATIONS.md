# External Integrations & APIs

**Analysis Date:** 2026-11-07

## 1. Firebase Suite
- **Cloud Firestore**: Primary realtime database (`tours/{id}`, `memberships/{tourId}__{email}`, `invites/{code}`, `channels`, `direct_messages`, `sos`). Configured with offline cache enabled.
- **Firebase Authentication**: Email/Password, Phone OTP, Google Sign-In with Android Credential Manager support (`serverClientId`).
- **Cloud Functions (TypeScript)**: Decommissioned notification triggers to run 100% on Firebase Spark plan without billing. Retains GDPR account erasure (`gdprDeleteUser`), OTP auth digests, and administrative scripts.
- **Firebase Storage**: User avatars, post media, stories, and document attachments governed by `storage.rules`.
- **Firebase Hosting**: High-speed CDN hosting for Flutter Web app at `https://app.bhromon.fun` and `https://bhromon-ff801.web.app`.
- **Firebase Cloud Messaging (FCM)**: Push notification dispatch for SOS alerts, mentions, channel messages, ledger updates, and notice reminders, dispatched directly from the Hostinger VPS notification daemon via Firebase Admin SDK.

## 2. Hostinger VPS & Microservices
- **Endpoint**: `https://bhromon.fun` (IP: `148.135.137.245`, SSH port: `2222`).
- **FastAPI Media Service (`bhromon-media-app:8210`)**: Media uploads, video streaming with byte-range support, news proxy, and 1-on-1 WebSocket chat signaling.
- **Notification Watcher Daemon (`notifications.py`)**: Realtime listener daemon on Firestore streams that dispatches FCM push notifications for SOS alerts, channels, posts, comments, notices, and ledger transactions.
- **Node 22 Games Server (`bhromon-games-app:8220`)**: Multiplayer card and board game engine running Card 29, Teen Patti, and Carrom.
- **Nginx Reverse Proxy**: SSL termination, caching headers, WebSocket upgrades, and media/APK serving from `/var/www/bhromon/downloads/`.

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
- **MapLibre GL & OpenFreeMap**: Offline vector tile rendering using OpenFreeMap Liberty style (`https://tiles.openfreemap.org/planet`) with locally bundled, coalesce-guarded style in `assets/map/liberty_style.json` and fallback sprites.
- **Geolocator**: Realtime GPS position, speed, altitude, and bearing calculations with boundary containment checks.
- **Curated Bangladesh Regions (`offline_map_regions.dart`)**: 8 curated offline regions (Sajek, Tanguar Haor, Bandarban, Sundarbans, Saint Martin's, Sylhet, etc.) with coordinates, waypoints, and emergency helplines.
