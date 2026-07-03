# ADR 003: Clean Architecture Implementation

## Context
Bhromon is an enterprise travel app designed to scale to hundreds of thousands of users. Ad-hoc development without modular separation leads to code rot, difficult refactoring, and poor testability.

## Decision
We adopted Clean Architecture principles divided into three layers: Data, Domain, and Presentation, structured across independent feature modules.

## Rationale
- **Domain Layer (Entities, Use Cases, Repositories Interfaces)**:
  - Pure Dart layer with zero external dependencies (no Firebase, no Flutter widgets, no SQLite imports).
  - Contains the core business rules (e.g., scoring validation).
- **Data Layer (Models, Repositories Implementations, Data Sources)**:
  - Maps external services (Firebase, local database) to Domain entities.
  - Implements caching strategies and network state routing.
- **Presentation Layer (BLoCs, Pages, Widgets)**:
  - Consumes use cases and triggers UI updates.
  - Strictly decoupled from repository implementations via dependency injection.
