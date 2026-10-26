# Bhromon — Travel Platform (Flutter & Firebase)

Bhromon is an offline-first travel application designed with Clean Architecture, BLoC state management, and a dual-database storage engine. It provides high-performance mapping, location pinning, media-rich travel logging, a community trust engine, and premium offline guides.

---

## Architecture Overview

Bhromon is structured around **Clean Architecture** principles to separate business concerns from external dependencies:

```
  ┌─────────────────────────────────────────────────────────┐
  │                   Presentation Layer                    │
  │        (Widgets, Pages, BLoC/Cubit Controllers)         │
  └────────────────────────────┬────────────────────────────┘
                               │ (calls)
  ┌────────────────────────────▼────────────────────────────┐
  │                      Domain Layer                       │
  │        (Pure Dart: Entities, Use Cases, Interfaces)      │
  └────────────────────────────▲────────────────────────────┘
                               │ (implements)
  ┌────────────────────────────┴────────────────────────────┐
  │                       Data Layer                        │
  │    (Models, Repositories, Drift & Hive Data Sources)    │
  └─────────────────────────────────────────────────────────┘
```

For more architectural decisions, see the [ADRs](docs/adr/):
- [ADR 001: Choice of BLoC](docs/adr/001_choice_of_bloc.md)
- [ADR 002: Dual Database Strategy (Hive + Drift)](docs/adr/002_dual_database_strategy.md)
- [ADR 003: Clean Architecture](docs/adr/003_clean_architecture.md)
- [ADR 004: Firebase Region Gating](docs/adr/004_firebase_region_gating.md)
- [ADR 005: Security Hardening](docs/adr/005_security_hardening.md)
- [ADR 006: Offline Maps via MapLibre Regions](docs/adr/006_offline_maps_via_maplibre_regions.md)

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
