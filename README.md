# Bhromon — One App for Every Group (Flutter & Firebase)

<p align="center">
  <a href="https://play.google.com/store/apps/details?id=com.bhromon.app">
    <img src="https://img.shields.io/badge/Google_Play-Install_App-00875A?style=for-the-badge&logo=google-play&logoColor=white" alt="Google Play">
  </a>
  <a href="https://app.bhromon.fun">
    <img src="https://img.shields.io/badge/Web_App-app.bhromon.fun-10B981?style=for-the-badge&logo=google-chrome&logoColor=white" alt="Web App">
  </a>
  <a href="https://github.com/rbr48/Bhromon/releases/latest">
    <img src="https://img.shields.io/badge/Latest_Release-v1.8.73_(Build_127)-2563EB?style=for-the-badge&logo=github&logoColor=white" alt="Latest Release">
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/License-Apache_2.0-64748B?style=for-the-badge" alt="License">
  </a>
</p>

Bhromon is one app for every group you belong to: families, offices, campuses, messes, housing societies, savings groups and trips. It is an offline-first Flutter app designed with Clean Architecture, BLoC state management, and a dual-database storage engine. It provides group chat and channels, notices and roll calls, shared expenses and settle-up, calendars, safety alerts with SOS, the Game Zone, and an ad-free newspaper reader.

---

## Project Status

Bhromon is free and open source, with no business model. No feature is sold.

## License

Bhromon is licensed under the [Apache License, Version 2.0](LICENSE). See [CONTRIBUTING.md](CONTRIBUTING.md) to take part.

---

## Architecture Overview

Bhromon is structured around modular, layered architecture principles separating domain rules from external platform dependencies:

```
  ┌─────────────────────────────────────────────────────────┐
  │                   Presentation Layer                    │
  │     (Widgets, Pages, BLoC/Cubit & Direct Stream States) │
  └────────────────────────────┬────────────────────────────┘
                               │ (calls)
  ┌────────────────────────────▼────────────────────────────┐
  │                      Domain Layer                       │
  │        (Pure Dart: Entities, Use Cases, Rule Engines)   │
  └────────────────────────────▲────────────────────────────┘
                               │ (implements)
  ┌────────────────────────────┴────────────────────────────┐
  │                       Data Layer                        │
  │    (Models, Repositories, Drift & Hive Data Sources)    │
  └─────────────────────────────────────────────────────────┘
```

- **State Management**: Scoped by feature. Foundation and explorer features utilize BLoC / Cubit. The `tour_group` operating system utilizes reactive `StatefulWidget`s listening directly to repository streams for high-velocity real-time Firestore collaboration.
- **Pure-Dart Domain Engines**: Core rules (Game Zone engines: Card 29, Chess, Ludo, Teen Patti, Carrom; Group engines: Ledger Paisa Engine, Seat Layout Engine, Scrapbook Engine, Samity Ledger) are 100% pure Dart, decoupled from Flutter UI and independently unit-tested.

### Key Architectural Decisions:
- **State Management**: Scoped by feature (BLoC/Cubit for foundation and explorer; reactive direct streams for high-velocity `tour_group` real-time collaboration).
- **Dual Database Strategy**: Drift (SQLite) for offline relational queries; encrypted Hive boxes for fast key-value persistence.
- **Clean Architecture**: Domain, Data, and Presentation layers with injectable dependency injection.
- **Firebase Region Gating**: Enforces `asia-south1` routing for low-latency Firestore, Storage, and Cloud Functions.
- **Security Hardening**: Strict Firestore Security Rules, zero broad storage permissions, sandboxed local stores.
- **Offline Maps**: Public OSM tiles with client-side caching.

---

## Local Development Setup

To set up the workspace, install dependencies, and run code generators in one step, execute the setup script:

### Windows (PowerShell)
```powershell
./scripts/setup.ps1
```

### macOS / Linux (Bash)
```bash
chmod +x ./scripts/setup.sh
./scripts/setup.sh
```

---

## Workspace Script Reference

This project uses [Melos](https://github.com/invertase/melos) to manage the multi-package codebase. The following shortcuts are defined in `melos.yaml`:

| Command | Description |
|---------|-------------|
| `melos run analyze` | Runs static analysis on all workspace code |
| `melos run test` | Runs all Flutter unit and widget tests with coverage |
| `melos run build_runner` | Generates boilerplate (injectable, freezed, drift, hive) |
| `melos run build` | Compiles production Android App Bundle (AAB) with obfuscation |
| `melos run clean` | Cleans build caches across all folders |
| `melos run functions_build` | Compiles Cloud Functions TypeScript code |
| `melos run functions_test` | Runs unit tests (Jest) for Cloud Functions |
| `melos run check_all` | Runs lint checks, Dart tests, and Firebase function tests |

---

## Firebase Emulator Suite

Bhromon runs against local Firebase emulators for offline testing.

1. Install the Firebase CLI:
   ```bash
   npm install -g firebase-tools
   ```
2. Start the Emulator Suite:
   ```bash
   firebase emulators:start
   ```
3. To run Functions test locally:
   ```bash
   cd functions && npm test
   ```

---

## Security Policy & Guidelines

- **Sensitive Data**: Never commit `service-account.json` or API keys. Ensure they are added to `.gitignore` (which already excludes `.env` and `key.properties`).
- **Reporting Vulnerabilities**: See [SECURITY.md](SECURITY.md) for details on responsible disclosure.
