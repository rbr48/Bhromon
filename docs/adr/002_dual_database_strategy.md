# ADR 002: Dual Database Strategy (Hive + Drift)

## Context
Bhromon needs robust offline capabilities. Users should be able to download offline vault packages (containing maps, travel guides, and trip history), queue writes (outbox) while offline, and access encrypted local settings. No single mobile database meets all of these needs efficiently.

## Decision
We implemented a dual-database architecture:
1. **Drift** (SQLite wrapper) for complex, structured relational data.
2. **Hive** for fast, simple key-value and object caching.

## Rationale
- **Drift (Relational)**:
  - Perfect for structured entities like trip logs, route points, and messages where we need tables, foreign keys, and complex queries.
  - Generates typesafe code and supports streams, enabling real-time UI updates when offline database rows change.
- **Hive (NoSQL Key-Value)**:
  - Extremely fast read/write times compared to SQLite.
  - Used for fast configuration flags, auth tokens, device encryption seeds, and lightweight cache.
  - Supports AES-256 local database encryption natively.
