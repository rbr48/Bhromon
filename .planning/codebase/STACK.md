# Technology Stack

**Analysis Date:** 2026-11-07

## Languages

**Primary:**
- Dart 3.3.4+ (`sdk: '>=3.3.4 <4.0.0'`) - All client application code across Web, Android, iOS, Windows, macOS, Linux.
- TypeScript 4.9.5 / 5.x - Firebase Cloud Functions backend (`functions/src/`).
- Python 3.11+ - Dedicated media and background worker server (`media-server/`).

**Secondary:**
- Kotlin & Java 17 - Android native platform layer and Gradle build plugins (`android/`).
- Bash & PowerShell - Build scripts, CI guards, deployment pipelines.

## Runtime

**Client Application:**
- Flutter 3.24+ - Multi-platform UI framework targeting Web, Android, iOS, Windows, Linux, macOS.
- Target SDK: Android 16 (API 36), compileSdk 36, minSdk 23.
- Web: HTML5 / CanvasKit with service worker caching deployed on Firebase Hosting.

**Cloud & Server:**
- Node.js 20.x runtime for Firebase Cloud Functions (v2 triggers).
- Python ASGI (FastAPI / Uvicorn) for Hostinger VPS media processing.

## Frameworks & State Management

**Core Client Architecture:**
- Clean Architecture (Domain, Data, Presentation).
- State Management by feature:
  - `tour_group`: Direct `StatefulWidget` reactive repository listeners and stream subscriptions.
  - Core / Auth / Other features: BLoC / Cubit (`flutter_bloc: ^9.1.1`, `hydrated_bloc: ^11.0.0`).
- Dependency Injection: `get_it: ^7.7.0` and `injectable: ^2.6.0`.
- Routing: Declarative routing with `go_router: ^13.2.5`.

**Local Storage & Offline Database:**
- Drift (SQLite): Relational offline caching and queries (`drift: ^2.19.2`, `sqlite3: ^2.9.4`).
- Hive: Encrypted key-value boxes and active group state.
- Flutter Secure Storage: Encrypted credentials (`flutter_secure_storage: ^9.2.4`).

## Key Dependencies & Ecosystem

| Package | Version | Purpose |
| :--- | :--- | :--- |
| `cloud_firestore` | `^5.6.5` | Realtime NoSQL document store with offline persistence |
| `firebase_auth` | `^5.5.1` | Google, phone, and email authentication |
| `flutter_webrtc` | `^0.12.5` | P2P audio/video calling and Discord-style Voice Lounge |
| `maplibre_gl` | `^0.26.2` | Offline vector map renderer & MBTiles waypoint radar |
| `audioplayers` | `^6.1.2` | In-call audio, ringback tones, SOS siren alerts |
| `fl_chart` | `^0.68.0` | Fund burn rate, expense analytics, and ledger charts |
| `bangla_pdf` | `1.9.2` | Custom local package for generating Unicode Bangla PDFs |
| `talker_flutter` | `^5.0.0` | Comprehensive logging, crash inspection, and telemetry |
