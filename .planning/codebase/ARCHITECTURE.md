# System Architecture & Design Patterns

**Analysis Date:** 2026-11-07

## Architectural Overview

Bhromon follows **Clean Architecture** combined with **Domain-Driven Design (DDD)** and feature-first modularization:

```
lib/
├── app/                  # Application bootstrap, routing (GoRouter), dependencies
├── core/                 # Shared foundations: theme, l10n, SQLite/Drift, audio, security
└── features/             # Modular feature packages
    ├── auth/             # Authentication & user profile
    ├── chat/             # Direct 1-on-1 messaging & rich markdown tables
    ├── game_zone/        # Realtime multiplayer game engines (29 Card, Ludo, Carrom, Chess)
    ├── map/              # Vector tiles, radar, waypoint calculations
    ├── tour_group/       # Universal Group Engine (Families, Messes, Samities, Offices, Trips)
    │   ├── data/         # Repositories, Firestore data sources, active group cache
    │   ├── domain/       # Immutable domain entities, ledger models, math engines
    │   └── presentation/ # Responsive screens, dialogs, custom sliver lists
    └── ...
```

## Universal Group Engine

The core domain model is `TourGroup`, supporting multiple distinct presets:
- **`GroupKind.trip`**: Full dynamic itinerary, stops, packing checklists, room/seat maps, journey tracker.
- **`GroupKind.family`**: Persistent circle without mandatory trip dates.
  - **`family` (Household)**: Family photo album, shared shopping/to-do, dependents, family dates.
  - **`office` (Office & Team)**: Team lunch/tea ledger shortcuts, admin-managed notices, member voting.
  - **`campus` (Campus & Batch)**: Campus events, canteen ledger shortcuts.
  - **`mess` (Bachelor Mess & Flat)**: Daily meal counter (breakfast, lunch, dinner), dynamic meal rate, bazar allocation.
  - **`society` (Housing Society & Building)**: Maintenance ledger, service request ticketing and resolution timeline.
  - **`samity` (Rotating Savings Group)**: Monthly pot calculation, rotation cycle schedule, payout ledger.

## State Management Philosophy

1. **Tour Group Feature**: Uses reactive `StatefulWidget` instances that subscribe directly to `TourGroupRepository` and Firestore streams. This direct pattern eliminates unnecessary BLoC boilerplate in rapid-collaboration group spaces.
2. **Auth & Cross-Cutting State**: Uses `flutter_bloc` / `Cubit` (e.g. `AuthCubit`, `LocaleController`, `ThemeCubit`).
3. **Offline Invariant**: Local Drift SQLite and Hive boxes cache documents so the UI renders instantaneously offline.

## Security & Access Control

- **Membership-Based Security (`firestore.rules`)**:
  - Access is determined by membership records at `memberships/{tourId}__{email}`.
  - Roles: `owner`, `admin`, `member`.
  - Non-members can only read 8-character invite codes from `invites/{code}` to preview group metadata.
  - Zero empty catches allowed in `lib/` (verified by CI guards).
