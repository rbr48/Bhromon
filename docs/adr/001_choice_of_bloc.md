# ADR 001: Choice of BLoC State Management over Riverpod

## Context
Bhromon is an offline-first travel application with complex state flows including real-time chats, multi-step route log generation, location tracking, and an active feed. We required a state management solution that:
1. Enforces strict separation of business logic and presentation layer.
2. Simplifies testing of transitions and states.
3. Provides predictable state flows to minimize side-effects in offline synchronization.
4. Scale easily across multiple modules.

## Decision
We chose the BLoC (Business Logic Component) pattern (via the `flutter_bloc` package) over Riverpod.

## Rationale
- **Strict Architecture**: BLoC forces developers to map out explicit events and states, aligning perfectly with the Clean Architecture domain/presentation boundary.
- **Traceability & Logs**: BLoC's built-in `BlocObserver` (integrated with `talker_flutter` in Bhromon) allows uniform tracing of every user action and subsequent state change.
- **Predictable Testing**: We can write highly structured, declarative tests using `bloc_test` without setting up complex provider containers.
- **Developer Alignment**: BLoC is industry-proven for large corporate and enterprise codebases, preventing ad-hoc state mutation directly in widgets.
