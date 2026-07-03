# Bhromon — Flutter App Structure & Architecture

> **Version 4.0 · Pre-Seed**
> The Community-Driven Intelligence Platform for Bangladeshi Exploration
> *Flutter · Firebase · Hive · OpenStreetMap · Clean Architecture*

---

## Table of Contents

1. [Architecture Philosophy](#1-architecture-philosophy)
2. [Clean Architecture Layers](#2-clean-architecture-layers)
3. [Feature Module Organisation](#3-feature-module-organisation)
4. [Full Project File Tree](#4-full-project-file-tree)
5. [Feature Deep Dives](#5-feature-deep-dives)
6. [BLoC Events & States — Complete Reference](#6-bloc-events--states--complete-reference)
7. [Offline-First Data Flow](#7-offline-first-data-flow)
8. [Trust & Explorer Score Engine](#8-trust--explorer-score-engine)
9. [Smart Feed Algorithm](#9-smart-feed-algorithm)
10. [Hive Local Storage — Full Schema](#10-hive-local-storage--full-schema)
11. [Cloud Functions — Full Implementation](#11-cloud-functions--full-implementation)
12. [FCM Push Notification Handling](#12-fcm-push-notification-handling)
13. [Image Pipeline & Media Handling](#13-image-pipeline--media-handling)
14. [Shared Core](#14-shared-core)
15. [Dependency Injection](#15-dependency-injection)
16. [Routing & Deep Links](#16-routing--deep-links)
17. [Theme & Design Tokens](#17-theme--design-tokens)
18. [Firebase Data Model](#18-firebase-data-model)
19. [Firebase Security Rules — Full](#19-firebase-security-rules--full)
20. [Performance & Optimisation](#20-performance--optimisation)
21. [Error Handling & Crash Reporting](#21-error-handling--crash-reporting)
22. [Accessibility](#22-accessibility)
23. [Localisation (i18n)](#23-localisation-i18n)
24. [Key Dependencies](#24-key-dependencies)
25. [Code Generation](#25-code-generation)
26. [Testing Strategy — Full Suite](#26-testing-strategy--full-suite)
27. [CI/CD Pipeline](#27-cicd-pipeline)
28. [Release & Versioning](#28-release--versioning)
29. [Getting Started](#29-getting-started)
30. [Architecture Decision Records](#30-architecture-decision-records)

---

## 1. Architecture Philosophy

Bhromon uses **Flutter Clean Architecture** with a strict one-way dependency rule:

```
Presentation  →  Domain  →  Data  →  External Services
```

- **Presentation** never touches Firebase or Hive directly — only domain use-cases.
- **Domain** is pure Dart — zero Flutter imports, zero Firebase imports. It owns the truth about what the app _does_.
- **Data** implements domain interfaces and owns all I/O: Firestore, Firebase Storage, Hive encrypted boxes, SyncManager.
- **Features** are vertical slices — each feature owns its own presentation/domain/data sub-layers. Features never import each other directly.
- **Cross-feature communication** goes exclusively through shared domain interfaces defined in `core/`.

### Core Principles

| Principle | Implementation |
|---|---|
| Offline-first | Hive cache checked before every network call; writes go to an outbox queue |
| Optimistic UI | UI reflects changes immediately; sync happens in background |
| Trust-by-default | All new content is `Unverified` until community validation elevates it |
| Dependency inversion | All repositories are interfaces in domain; impls live in data |
| Testability | Domain layer has zero side-effect dependencies — pure unit testable |
| Separation of concerns | BLoC handles state, use-case handles logic, repository handles I/O |
| Immutability | All entities are `@freezed` — no mutable state escapes the data layer |
| Safety-first | Safety flags cause immediate content hiding — no delay for moderation queue |

---

## 2. Clean Architecture Layers

### 2.1 Presentation Layer

Flutter widgets + BLoC/Cubit state management. Knows nothing about Firebase or Hive.

```
lib/features/<feature>/presentation/
├── <feature>_screen.dart          # Main screen widget
├── bloc/
│   ├── <feature>_bloc.dart        # BLoC or Cubit
│   ├── <feature>_event.dart       # Sealed event classes
│   └── <feature>_state.dart       # Sealed state classes
└── widgets/
    └── *.dart                     # Reusable sub-widgets
```

**BLoCs per feature:**

| BLoC / Cubit | Responsibility |
|---|---|
| `MapBloc` | Geo-pin rendering, nearby trips, trust-tier colours, long-press drafting |
| `TripLogBloc` | Block editor, draft auto-save, completeness gate, publish, sync status |
| `TipListCubit` | Pro-tip feed, optimistic vote, decay display, re-confirm prompt |
| `VaultCubit` | District download progress, outbox count, conflict routing |
| `TrustBloc` | Real-time score stream, flag submission, tier upgrade, appeal flow |
| `AuthCubit` | Phone OTP, Google sign-in, session persistence, profile bootstrap |
| `FeedCubit` | Smart feed ranking, pagination, personalisation signals |
| `NotificationCubit` | FCM token management, notification routing |

**BLoC lifecycle in screen:**

```dart
class MapScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => getIt<MapBloc>()..add(const MapInitialised()),
      child: BlocConsumer<MapBloc, MapState>(
        listener: (ctx, state) {
          if (state is MapError) {
            ScaffoldMessenger.of(ctx)
              .showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        builder: (ctx, state) => switch (state) {
          MapLoading()  => const MapSkeletonLoader(),
          MapLoaded()   => _MapContent(state: state),
          MapError()    => MapErrorView(message: state.message),
          MapInitial()  => const SizedBox.shrink(),
        },
      ),
    );
  }
}
```

### 2.2 Domain Layer

Pure Dart. No framework imports. Defines entities, value objects, use-case interfaces, and repository interfaces.

```
lib/features/<feature>/domain/
├── entities/           # Re-exports from core/entities/ or feature-local
├── usecases/
│   └── *.dart          # One public class per use-case; callable via call()
└── repositories/
    └── i_*.dart        # Abstract interface — one per aggregate root
```

**Base use-case contract:**

```dart
// core/usecase/usecase.dart
abstract class UseCase<Type, Params> {
  Future<Either<Failure, Type>> call(Params params);
}

abstract class NoParamsUseCase<Type> {
  Future<Either<Failure, Type>> call();
}
```

**Full use-case example — publish with trust gate:**

```dart
class PublishTripLogUseCase implements UseCase<TripLog, PublishTripLogParams> {
  final ITripLogRepository _repository;
  final ITrustRepository _trust;

  PublishTripLogUseCase(this._repository, this._trust);

  @override
  Future<Either<Failure, TripLog>> call(PublishTripLogParams params) async {
    final log = params.tripLog;

    // Completeness gates
    if (log.title.trim().isEmpty)
      return Left(ValidationFailure('Title is required'));
    if (log.blocks.isEmpty)
      return Left(ValidationFailure('Add at least one content block'));
    if (!log.blocks.any((b) => b is ImageBlock))
      return Left(ValidationFailure('At least one photo is required'));
    if (log.costItems.isEmpty)
      return Left(ValidationFailure('Add a cost breakdown'));
    if (log.routePoints.length < 2)
      return Left(ValidationFailure('Draw your route on the map'));

    // Trust gate: Unverified users cannot publish full TripLogs
    final profileResult = await _trust.getProfile(params.authorId);
    return profileResult.fold(
      Left.new,
      (profile) {
        if (profile.tier == TrustTier.unverified)
          return Left(AuthFailure('Earn Community tier to publish TripLogs'));
        return _repository.publish(log);
      },
    );
  }
}

@freezed
class PublishTripLogParams with _$PublishTripLogParams {
  const factory PublishTripLogParams({
    required TripLog tripLog,
    required String authorId,
  }) = _PublishTripLogParams;
}
```

### 2.3 Data Layer

Implements domain interfaces. Cache-first reads, outbox-queued writes.

```
lib/features/<feature>/data/
├── datasources/
│   ├── firestore_*.dart          # Remote source
│   └── hive_*_dao.dart           # Local source
├── models/
│   ├── *_model.dart              # JSON + Hive serialisable DTO
│   └── *_model.g.dart            # Auto-generated
└── repositories/
    └── *_repository_impl.dart    # Implements domain interface
```

**Repository pattern — cache-first read + outbox write:**

```dart
class TripLogRepositoryImpl implements ITripLogRepository {
  final FirestoreTripLogSource _remote;
  final HiveTripLogDao _local;
  final ConnectivityService _connectivity;

  @override
  Future<Either<Failure, TripLog>> getById(String id) async {
    final cached = await _local.getById(id);
    if (cached != null && !cached.freshnessAge.isStale()) {
      return Right(cached.toEntity());
    }
    try {
      final remote = await _remote.getById(id);
      await _local.save(TripLogHiveModel.fromEntity(remote));
      return Right(remote);
    } on FirestoreException catch (e) {
      // Return stale cache rather than error if available
      if (cached != null) return Right(cached.toEntity());
      return Left(NetworkFailure(e.message));
    }
  }

  @override
  Future<Either<Failure, TripLog>> publish(TripLog tripLog) async {
    final isOnline = await _connectivity.isOnline;
    if (!isOnline) {
      await _local.enqueueOutbox(OutboxEntry(
        operation: OutboxOperation.create,
        payload: TripLogHiveModel.fromEntity(tripLog),
      ));
      return Right(tripLog.copyWith(syncStatus: SyncStatus.pendingUpload));
    }
    return _remote.publish(tripLog);
  }
}
```

---

## 3. Feature Module Organisation

```
lib/features/
├── map/             # Geospatial discovery
├── trip_log/        # Rich travel story creation & viewing
├── pro_tip/         # Bite-sized local wisdom engine
├── offline_vault/   # District download + SyncManager
├── trust/           # Explorer Score + flagging + moderation
├── auth/            # Phone OTP + Google sign-in
├── feed/            # Smart home feed aggregation
├── explorer/        # Public profile + badge showcase
├── premium_guide/   # Premium guide creation (Verified tier+)
└── notifications/   # FCM push routing
```

**Cross-feature dependency rule:**

```
✅  feature/map       → core/entities/location_pin
✅  feature/trip_log  → core/entities/trip_log
✅  feature/trust     → core/entities/explorer_profile
❌  feature/map       → feature/trip_log   (forbidden — use core interface)
❌  feature/trip_log  → feature/trust      (forbidden — use core interface)
```

**Visual layer map:**

```
┌──────────────────────────────────────────────────────────────────┐
│  PRESENTATION  (Flutter Widgets + BLoC)                          │
│  MapBloc · TripLogBloc · TipListCubit · VaultCubit · TrustBloc  │
└──────────────────────────────┬───────────────────────────────────┘
                               │ use-cases only — no framework deps
┌──────────────────────────────▼───────────────────────────────────┐
│  DOMAIN  (Pure Dart)                                             │
│  Entities · Use-cases · Repository Interfaces · Value Objects   │
└──────────────────────────────┬───────────────────────────────────┘
                               │ implements interfaces
┌──────────────────────────────▼───────────────────────────────────┐
│  DATA  (I/O)                                                     │
│  Firestore sources · Hive DAOs · SyncManager · Models           │
└──────────────────────────────┬───────────────────────────────────┘
                               │
          ┌────────────────────┴─────────────────────┐
          │ Firebase                                  │ Hive + OSM
          │ Auth · Firestore · Storage · Functions   │ Encrypted boxes
          └───────────────────────────────────────────┘
```

---

## 4. Full Project File Tree

```
bhromon/
├── lib/
│   ├── main.dart                                # Entry: initHive → setupDI → runApp
│   ├── app/
│   │   ├── app.dart                             # BhromonApp: MaterialApp.router + global BLoC providers
│   │   ├── router.dart                          # go_router: named routes, auth guard, deep links
│   │   ├── config/
│   │   │   └── env.dart                         # Constants: TTLs, thresholds, map region, tile URL
│   │   ├── di/
│   │   │   ├── injection.dart                   # @InjectableInit — registers all bindings
│   │   │   ├── injection.config.dart            # Auto-generated — do not edit
│   │   │   ├── firebase_module.dart             # @module — Firebase singletons
│   │   │   └── hive_module.dart                 # @module — Hive box singletons
│   │   └── theme/
│   │       ├── app_colors.dart                  # Brand palette + tier/decay colour helpers
│   │       ├── text_styles.dart                 # AppTextStyles: heading/body/caption/mono
│   │       ├── app_spacing.dart                 # Spacing tokens: xs/sm/md/lg/xl/xxl
│   │       ├── app_radius.dart                  # Border radius tokens: sm/md/lg/full
│   │       └── theme_data.dart                  # AppTheme.light + AppTheme.dark
│   │
│   ├── core/
│   │   ├── entities/
│   │   │   ├── trip_log.dart                    # TripLog entity (@freezed)
│   │   │   ├── pro_tip.dart                     # ProTip entity (@freezed)
│   │   │   ├── location_pin.dart                # LocationPin entity (@freezed)
│   │   │   ├── explorer_profile.dart            # ExplorerProfile entity (@freezed)
│   │   │   ├── flag_event.dart                  # FlagEvent entity (@freezed)
│   │   │   ├── offline_bundle.dart              # OfflineBundle entity (@freezed)
│   │   │   ├── cost_item.dart                   # CostItem value type (@freezed)
│   │   │   ├── trip_block.dart                  # Sealed union: Text|Image|Cost|Route|SafetyNote
│   │   │   └── notification_payload.dart        # FCM payload shape (@freezed)
│   │   ├── value_objects/
│   │   │   ├── geo_coordinate.dart              # lat/lng + toGeoHash() + distanceTo()
│   │   │   ├── explorer_score.dart              # int + tier + isPremiumEligible()
│   │   │   ├── freshness_age.dart               # isStale() + decayFactor() + status enum
│   │   │   ├── sync_status.dart                 # Enum: Synced|PendingUpload|Conflict|Failed
│   │   │   ├── trust_tier.dart                  # Enum: unverified|community|verified|regionExpert|pioneer
│   │   │   └── flag_type.dart                   # Enum: outdated|inaccurate|spam|safety
│   │   ├── error/
│   │   │   ├── failures.dart                    # Sealed Failure hierarchy (8 subtypes)
│   │   │   └── exceptions.dart                  # Internal exceptions (never leave data layer)
│   │   ├── usecase/
│   │   │   └── usecase.dart                     # Abstract UseCase<T,P> + NoParamsUseCase<T>
│   │   ├── network/
│   │   │   ├── connectivity_service.dart        # ⚠ CRITICAL — triggers SyncManager on reconnect
│   │   │   └── network_info.dart                # Wrapper for connectivity_plus
│   │   ├── extensions/
│   │   │   ├── string_extensions.dart           # .isValidBDPhone(), .toTitleCase()
│   │   │   ├── datetime_extensions.dart         # .toLocalBD(), .timeAgo(), .isStalerThan()
│   │   │   └── either_extensions.dart           # .getOrElse(), .mapRight()
│   │   ├── widgets/
│   │   │   ├── error_boundary.dart              # Global error UI fallback widget
│   │   │   ├── bhromon_error_view.dart          # Styled error with retry CTA
│   │   │   └── skeleton_loader.dart             # Shimmer loading skeleton
│   │   └── utils/
│   │       ├── date_utils.dart                  # Bangladesh timezone helpers
│   │       ├── geohash_utils.dart               # encode/decode + neighbours + bbox
│   │       └── image_utils.dart                 # compress + resize + pHash + EXIF strip
│   │
│   └── features/
│       ├── map/
│       │   ├── presentation/
│       │   │   ├── map_screen.dart
│       │   │   ├── bloc/
│       │   │   │   ├── map_bloc.dart
│       │   │   │   ├── map_event.dart
│       │   │   │   └── map_state.dart
│       │   │   └── widgets/
│       │   │       ├── pin_cluster_layer.dart   # Cluster rendering for dense pin areas
│       │   │       ├── pin_popup.dart           # Bottom sheet: trust + tips + trip count
│       │   │       ├── trust_tier_badge.dart    # Colour-coded tier pill widget
│       │   │       ├── map_filter_bar.dart      # Filter: All|Verified|Nearby|Division
│       │   │       └── draft_pin_overlay.dart   # Long-press new-pin workflow
│       │   ├── domain/
│       │   │   ├── usecases/
│       │   │   │   ├── get_nearby_trips_usecase.dart
│       │   │   │   ├── create_draft_pin_usecase.dart
│       │   │   │   └── get_pin_detail_usecase.dart
│       │   │   └── repositories/
│       │   │       └── i_location_repository.dart
│       │   └── data/
│       │       ├── datasources/
│       │       │   ├── firestore_pin_source.dart  # GeoHash range query
│       │       │   └── hive_pin_dao.dart           # Box: pins_cache · TTL 4h
│       │       ├── models/
│       │       │   └── location_pin_model.dart
│       │       └── repositories/
│       │           └── location_repository_impl.dart
│       │
│       ├── trip_log/
│       │   ├── presentation/
│       │   │   ├── trip_log_editor_screen.dart  # Block-based rich editor
│       │   │   ├── trip_log_detail_screen.dart  # Read-only rendered view
│       │   │   ├── trip_log_feed_screen.dart    # Paginated feed for a pin
│       │   │   ├── bloc/
│       │   │   │   ├── trip_log_bloc.dart
│       │   │   │   ├── trip_log_event.dart
│       │   │   │   └── trip_log_state.dart
│       │   │   └── widgets/
│       │   │       ├── block_editor.dart
│       │   │       ├── text_block_widget.dart
│       │   │       ├── image_block_widget.dart
│       │   │       ├── cost_tracker_widget.dart
│       │   │       ├── route_drawer_widget.dart  # Inline map + polyline drawing
│       │   │       ├── safety_note_widget.dart
│       │   │       ├── completeness_indicator.dart
│       │   │       └── sync_status_chip.dart
│       │   ├── domain/
│       │   │   ├── usecases/
│       │   │   │   ├── publish_trip_log_usecase.dart  # ⚠ Completeness + trust gate
│       │   │   │   ├── get_trip_log_usecase.dart
│       │   │   │   ├── save_draft_usecase.dart
│       │   │   │   ├── load_draft_usecase.dart
│       │   │   │   └── delete_trip_log_usecase.dart
│       │   │   └── repositories/
│       │   │       └── i_trip_log_repository.dart
│       │   └── data/
│       │       ├── datasources/
│       │       │   ├── firestore_triplog_source.dart
│       │       │   └── hive_triplog_dao.dart  # Boxes: triplogs_cache + triplogs_drafts
│       │       ├── models/
│       │       │   ├── trip_log_model.dart
│       │       │   └── trip_block_model.dart
│       │       └── repositories/
│       │           └── trip_log_repository_impl.dart
│       │
│       ├── pro_tip/
│       │   ├── presentation/
│       │   │   ├── tip_feed_screen.dart
│       │   │   ├── add_tip_sheet.dart
│       │   │   ├── bloc/
│       │   │   │   ├── tip_list_cubit.dart
│       │   │   │   └── tip_list_state.dart
│       │   │   └── widgets/
│       │   │       ├── tip_card.dart
│       │   │       ├── decay_badge.dart
│       │   │       ├── vote_button_row.dart
│       │   │       └── reconfirm_prompt_card.dart
│       │   ├── domain/
│       │   │   ├── usecases/
│       │   │   │   ├── vote_tip_usecase.dart
│       │   │   │   ├── confirm_tip_usecase.dart
│       │   │   │   ├── add_pro_tip_usecase.dart
│       │   │   │   └── get_tips_for_location_usecase.dart
│       │   │   └── repositories/
│       │   │       └── i_pro_tip_repository.dart
│       │   └── data/
│       │       ├── datasources/
│       │       │   ├── firestore_protip_source.dart
│       │       │   └── hive_protip_dao.dart
│       │       ├── models/
│       │       │   └── pro_tip_model.dart
│       │       └── repositories/
│       │           └── pro_tip_repository_impl.dart
│       │
│       ├── offline_vault/
│       │   ├── presentation/
│       │   │   ├── vault_screen.dart
│       │   │   ├── district_picker_screen.dart
│       │   │   ├── bloc/
│       │   │   │   ├── vault_cubit.dart
│       │   │   │   └── vault_state.dart
│       │   │   └── widgets/
│       │   │       ├── district_card.dart
│       │   │       ├── download_progress_sheet.dart
│       │   │       ├── sync_status_bar.dart       # ⚠ Persistent outbox count banner
│       │   │       └── merge_conflict_dialog.dart  # ⚠ CRITICAL 3-way merge UI
│       │   ├── domain/
│       │   │   ├── usecases/
│       │   │   │   ├── download_vault_usecase.dart  # Streams progress
│       │   │   │   ├── sync_outbox_usecase.dart     # ⚠ CRITICAL
│       │   │   │   ├── delete_vault_usecase.dart
│       │   │   │   └── get_vault_status_usecase.dart
│       │   │   └── repositories/
│       │   │       └── i_offline_repository.dart
│       │   └── data/
│       │       ├── sync/
│       │       │   ├── sync_manager.dart          # ⚠ Singleton, exponential backoff
│       │       │   └── conflict_resolver.dart     # Three-way merge logic
│       │       ├── datasources/
│       │       │   ├── hive_outbox_dao.dart       # Box: sync_outbox, FIFO
│       │       │   ├── hive_bundle_dao.dart       # Box: offline_bundles
│       │       │   └── osm_tile_cache.dart
│       │       ├── models/
│       │       │   ├── outbox_entry_model.dart
│       │       │   └── offline_bundle_model.dart
│       │       └── repositories/
│       │           └── offline_repository_impl.dart
│       │
│       ├── trust/
│       │   ├── presentation/
│       │   │   ├── flag_bottom_sheet.dart
│       │   │   ├── appeal_screen.dart
│       │   │   ├── score_breakdown_screen.dart  # "How is my score calculated?"
│       │   │   ├── bloc/
│       │   │   │   ├── trust_bloc.dart
│       │   │   │   ├── trust_event.dart
│       │   │   │   └── trust_state.dart
│       │   │   └── widgets/
│       │   │       ├── score_badge.dart
│       │   │       ├── tier_upgrade_card.dart
│       │   │       └── flag_type_selector.dart
│       │   ├── domain/
│       │   │   ├── usecases/
│       │   │   │   ├── flag_content_usecase.dart
│       │   │   │   ├── appeal_flag_usecase.dart
│       │   │   │   └── get_explorer_score_usecase.dart
│       │   │   └── repositories/
│       │   │       └── i_trust_repository.dart
│       │   └── data/
│       │       ├── datasources/
│       │       │   └── firestore_trust_source.dart
│       │       ├── models/
│       │       │   └── flag_event_model.dart
│       │       └── repositories/
│       │           └── trust_repository_impl.dart
│       │
│       ├── auth/
│       │   ├── presentation/
│       │   │   ├── login_screen.dart
│       │   │   ├── otp_screen.dart
│       │   │   └── bloc/
│       │   │       ├── auth_cubit.dart
│       │   │       └── auth_state.dart
│       │   ├── domain/
│       │   │   ├── usecases/
│       │   │   │   ├── sign_in_phone_usecase.dart
│       │   │   │   ├── verify_otp_usecase.dart
│       │   │   │   ├── sign_in_google_usecase.dart
│       │   │   │   └── sign_out_usecase.dart
│       │   │   └── repositories/
│       │   │       └── i_auth_repository.dart
│       │   └── data/
│       │       ├── datasources/
│       │       │   └── firebase_auth_source.dart
│       │       └── repositories/
│       │           └── auth_repository_impl.dart  # Upserts profile on first login
│       │
│       ├── feed/
│       │   ├── presentation/
│       │   │   ├── home_feed_screen.dart
│       │   │   └── bloc/
│       │   │       ├── feed_cubit.dart
│       │   │       └── feed_state.dart
│       │   ├── domain/
│       │   │   ├── usecases/
│       │   │   │   └── get_smart_feed_usecase.dart
│       │   │   └── repositories/
│       │   │       └── i_feed_repository.dart
│       │   └── data/
│       │       └── repositories/
│       │           └── feed_repository_impl.dart  # Aggregates + ranks content
│       │
│       ├── explorer/
│       │   ├── presentation/
│       │   │   ├── explorer_profile_screen.dart
│       │   │   └── widgets/
│       │   │       ├── badge_shelf.dart
│       │   │       ├── trip_log_grid.dart
│       │   │       └── division_map_widget.dart
│       │   └── domain/
│       │       └── usecases/
│       │           └── get_explorer_profile_usecase.dart
│       │
│       ├── premium_guide/
│       │   ├── presentation/
│       │   │   ├── guide_create_screen.dart     # Gated: Verified tier only
│       │   │   ├── guide_detail_screen.dart
│       │   │   └── guide_purchase_screen.dart
│       │   └── domain/
│       │       └── usecases/
│       │           ├── create_premium_guide_usecase.dart
│       │           └── purchase_guide_usecase.dart
│       │
│       └── notifications/
│           ├── presentation/
│           │   └── notification_settings_screen.dart
│           └── data/
│               ├── fcm_service.dart             # Token reg + routing
│               └── notification_handler.dart    # Foreground + background dispatch
│
├── test/
│   ├── unit/
│   │   ├── trust/
│   │   │   ├── compute_score_test.dart
│   │   │   └── flag_content_usecase_test.dart
│   │   ├── offline/
│   │   │   ├── sync_manager_test.dart
│   │   │   └── conflict_resolver_test.dart
│   │   ├── value_objects/
│   │   │   ├── freshness_age_test.dart
│   │   │   └── geo_coordinate_test.dart
│   │   └── trip_log/
│   │       └── publish_trip_log_usecase_test.dart
│   ├── widget/
│   │   ├── vault/
│   │   │   └── merge_conflict_dialog_test.dart
│   │   ├── trust/
│   │   │   └── score_badge_test.dart
│   │   └── trip_log/
│   │       └── cost_tracker_widget_test.dart
│   └── integration/
│       ├── trip_log_publish_flow_test.dart
│       └── offline_sync_roundtrip_test.dart
│
├── functions/                     # Firebase Cloud Functions (TypeScript)
│   ├── src/
│   │   ├── index.ts
│   │   ├── computeExplorerScore.ts
│   │   ├── decayFreshness.ts
│   │   ├── moderateContent.ts
│   │   └── sendDecayNotifications.ts
│   ├── package.json
│   └── tsconfig.json
│
├── firebase.json
├── firestore.rules
├── firestore.indexes.json
├── pubspec.yaml
├── build.yaml
├── analysis_options.yaml
└── .github/
    └── workflows/
        ├── ci.yml                 # PR checks: analyse + test + coverage
        └── cd.yml                 # Release: build + deploy to stores
```

---

## 5. Feature Deep Dives

### 5.1 Map Feature

**Purpose:** Geospatial discovery — the primary entry point into Bhromon's content graph.

**Trust-tier colour coding:**

| Tier | Map pin colour | Score threshold |
|---|---|---|
| Unverified | `#ADB5BD` grey | 0 (new account) |
| Community | `#74C69D` mint | ≥ 50 |
| Verified | `#F4A261` gold | ≥ 200 |
| Region Expert | `#1B4332` deep green | ≥ 500 + council nomination |
| Pioneer | `#E76F51` amber | Founding Explorer program |

**GeoHash proximity query:**

```dart
// features/map/data/datasources/firestore_pin_source.dart
Future<List<LocationPinModel>> getNearby(GeoCoordinate centre, double radiusKm) async {
  final hashes = GeoHashUtils.getNeighbourCells(centre, radiusKm, precision: 6);
  final snapshots = await Future.wait(
    hashes.map((hash) =>
      _db.collection('location_pins')
         .where('geoHash', isGreaterThanOrEqualTo: hash)
         .where('geoHash', isLessThan: '$hash\uf8ff')
         .where('hidden', isEqualTo: false)
         .orderBy('geoHash')
         .get()
    ),
  );
  return snapshots
    .expand((s) => s.docs)
    .map((d) => LocationPinModel.fromJson(d.data()))
    .toList();
}
```

**Debounce map pan events (prevents Firestore over-querying):**

```dart
// features/map/presentation/bloc/map_bloc.dart
on<MapMoved>(
  _onMapMoved,
  transformer: debounce(const Duration(milliseconds: 300)),
);
```

---

### 5.2 TripLog Feature

**Purpose:** Rich, structured travel stories — the core long-form content unit of Bhromon.

**TripBlock sealed class:**

```dart
// core/entities/trip_block.dart
@freezed
sealed class TripBlock with _$TripBlock {
  const factory TripBlock.text({
    required String id,
    required String content,
    @Default(false) bool isBold,
  }) = TextBlock;

  const factory TripBlock.image({
    required String id,
    required String storageUrl,
    required String caption,
    String? localPath,         // non-null when served from Offline Vault
  }) = ImageBlock;

  const factory TripBlock.costEntry({
    required String id,
    required List<CostItem> items,
    required String currency,  // 'BDT' or 'USD'
  }) = CostEntryBlock;

  const factory TripBlock.route({
    required String id,
    required List<GeoCoordinate> points,
    String? description,
  }) = RouteBlock;

  const factory TripBlock.safetyNote({
    required String id,
    required String text,
    required SafetyLevel level,  // info | warning | danger
  }) = SafetyNoteBlock;
}
```

**Auto-save draft every 30 seconds:**

```dart
// features/trip_log/presentation/bloc/trip_log_bloc.dart
TripLogBloc({required this._publish, required this._get, required this._saveDraft})
    : super(TripLogInitial()) {
  on<PublishTripLogEvent>(_onPublish);
  on<LoadTripLogEvent>(_onLoad);
  on<AddBlockEvent>(_onAddBlock);
  on<SaveDraftEvent>(_onSaveDraft);
  _autoSaveTimer = Timer.periodic(
    const Duration(seconds: 30),
    (_) { if (state is TripLogEditing) add(SaveDraftEvent(tripLog: (state as TripLogEditing).draft)); },
  );
}
```

---

### 5.3 Pro-Tip Feature

**Decay calculation:**

```dart
// core/value_objects/freshness_age.dart
class FreshnessAge {
  final DateTime lastConfirmed;
  int get daysSinceConfirmed => DateTime.now().difference(lastConfirmed).inDays;
  bool isStale() => daysSinceConfirmed > 180;
  double decayFactor() => (1.0 - (daysSinceConfirmed / 365.0)).clamp(0.0, 1.0);
  DecayStatus get status => switch (daysSinceConfirmed) {
    < 30  => DecayStatus.fresh,
    < 180 => DecayStatus.aging,
    _     => DecayStatus.stale,
  };
}
```

**Optimistic vote update pattern:**

```dart
// features/pro_tip/presentation/bloc/tip_list_cubit.dart
Future<void> voteHelpful(String tipId) async {
  final original = state.tips;
  // 1. Optimistic update
  emit(state.copyWith(
    tips: original.map((t) =>
      t.id == tipId ? t.copyWith(helpfulVotes: t.helpfulVotes + 1) : t
    ).toList(),
  ));
  // 2. Persist — roll back on failure
  final result = await _voteUseCase(VoteTipParams(tipId: tipId));
  if (result.isLeft()) emit(state.copyWith(tips: original));
}
```

---

### 5.4 Offline Vault Feature

**Download sequence:**

```
DownloadVaultUseCase(districtId)
  1. Fetch LocationPins for district bounding box
  2. Fetch all TripLogs linked to those pins
  3. Fetch all ProTips for those pins
  4. Download + compress images for each ImageBlock (max 800px, JPEG 80%)
  5. Pre-cache OSM tiles: zoom 10–16 (~50 MB per average district)
  6. Stream DownloadProgress events (0.0 → 1.0) → VaultCubit → progress bar
  7. Write encrypted OfflineBundle to Hive (AES-256 via flutter_secure_storage key)
```

**SyncManager with exponential backoff:**

```dart
// features/offline_vault/data/sync/sync_manager.dart
class SyncManager {
  static final _instance = SyncManager._internal();
  factory SyncManager() => _instance;

  final _conflictController = StreamController<ConflictEvent>.broadcast();
  Stream<ConflictEvent> get conflictStream => _conflictController.stream;

  Future<void> flushOutbox() async {
    final entries = await _outboxDao.getAllPending();
    for (final entry in entries) {
      final delay = _backoffDelay(entry.retryCount);
      if (delay > Duration.zero) await Future.delayed(delay);
      try {
        await _dispatchEntry(entry);
        await _outboxDao.markSynced(entry.id);
      } on ConflictException catch (e) {
        await _outboxDao.markConflict(entry.id, serverPayload: e.serverDoc);
        _conflictController.add(ConflictEvent(local: entry, server: e.serverDoc));
      } on NetworkException {
        await _outboxDao.incrementRetry(entry.id);
        if (entry.retryCount >= Env.maxOfflineRetries) await _outboxDao.markFailed(entry.id);
        return; // Stop — no point continuing without network
      }
    }
  }

  Duration _backoffDelay(int retryCount) => switch (retryCount) {
    0 => Duration.zero,
    1 => const Duration(seconds: 5),
    2 => const Duration(seconds: 15),
    3 => const Duration(seconds: 60),
    _ => const Duration(minutes: 5),
  };
}
```

**Three-way merge dialog (conflict resolution):**

```
MergeConflictDialog shows three panes:
┌────────────────┐  ┌────────────────┐  ┌────────────────┐
│   Original     │  │  Your version  │  │ Server version │
│  (grey bg)     │  │  (mint border) │  │  (gold border) │
│ common ancestor│  │ outbox copy    │  │ Firestore doc  │
└────────────────┘  └────────────────┘  └────────────────┘

Actions:
  [Use mine]     → onResolved(local)
  [Use server]   → onResolved(server)
  [Edit merged]  → free-text editor pre-filled with local → onResolved(edited)
```

---

### 5.5 Trust Feature

**Flag type effects:**

| Flag type | Immediate client action | Cloud Function threshold |
|---|---|---|
| `Outdated` | Visual stale badge | 3 flags → feed rank −50% |
| `Inaccurate` | None immediately | 3 flags → enters review queue |
| `Spam` | None immediately | 2 flags → hidden pending review |
| `Safety` | **Instant hide, no threshold** | 1 flag → hidden + founder FCM alert |

**Real-time score stream:**

```dart
// features/trust/data/repositories/trust_repository_impl.dart
@override
Stream<ExplorerScore> watchScore(String uid) =>
  _db.collection('explorer_scores')
    .doc(uid)
    .snapshots()
    .map((s) => s.exists
      ? ExplorerScoreModel.fromJson(s.data()!).toEntity()
      : const ExplorerScore(value: 0, tier: TrustTier.unverified));
```

---

### 5.6 Auth Feature

**Phone OTP + first-login profile bootstrap:**

```dart
// features/auth/data/repositories/auth_repository_impl.dart
Future<void> _bootstrapProfile(User firebaseUser) async {
  final ref = _db.collection('explorer_profiles').doc(firebaseUser.uid);
  if (!(await ref.get()).exists) {
    await ref.set({
      'uid': firebaseUser.uid,
      'displayName': firebaseUser.displayName ?? 'Explorer',
      'tier': 'unverified',
      'score': 0,
      'badges': <String>[],
      'isPioneer': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
```

---

## 6. BLoC Events & States — Complete Reference

### MapBloc

```dart
// map_event.dart
sealed class MapEvent { const MapEvent(); }
class MapInitialised   extends MapEvent { const MapInitialised(); }
class MapMoved         extends MapEvent {
  final GeoCoordinate centre; final double radiusKm;
  const MapMoved(this.centre, this.radiusKm);
}
class PinTapped        extends MapEvent { final String pinId; const PinTapped(this.pinId); }
class LongPressOnMap   extends MapEvent { final GeoCoordinate coordinate; const LongPressOnMap(this.coordinate); }
class FilterChanged    extends MapEvent { final MapFilter filter; const FilterChanged(this.filter); }
class PinPopupDismissed extends MapEvent { const PinPopupDismissed(); }

// map_state.dart
sealed class MapState { const MapState(); }
class MapInitial  extends MapState { const MapInitial(); }
class MapLoading  extends MapState { const MapLoading(); }
class MapLoaded   extends MapState {
  final List<LocationPin> pins;
  final MapFilter activeFilter;
  final LocationPin? selectedPin;
  const MapLoaded({required this.pins, required this.activeFilter, this.selectedPin});
}
class MapError    extends MapState { final String message; const MapError(this.message); }
```

### TripLogBloc

```dart
// trip_log_event.dart
sealed class TripLogEvent { const TripLogEvent(); }
class LoadTripLogEvent      extends TripLogEvent { final String id; const LoadTripLogEvent(this.id); }
class AddBlockEvent         extends TripLogEvent { final TripBlock block; const AddBlockEvent(this.block); }
class RemoveBlockEvent      extends TripLogEvent { final String blockId; const RemoveBlockEvent(this.blockId); }
class ReorderBlocksEvent    extends TripLogEvent { final int oldIndex, newIndex; const ReorderBlocksEvent(this.oldIndex, this.newIndex); }
class UpdateCostItemsEvent  extends TripLogEvent { final List<CostItem> items; const UpdateCostItemsEvent(this.items); }
class SaveDraftEvent        extends TripLogEvent { final TripLog tripLog; const SaveDraftEvent({required this.tripLog}); }
class PublishTripLogEvent   extends TripLogEvent { final TripLog tripLog; const PublishTripLogEvent({required this.tripLog}); }
class DeleteTripLogEvent    extends TripLogEvent { final String id; const DeleteTripLogEvent(this.id); }

// trip_log_state.dart
sealed class TripLogState { const TripLogState(); }
class TripLogInitial    extends TripLogState { const TripLogInitial(); }
class TripLogLoading    extends TripLogState { const TripLogLoading(); }
class TripLogEditing    extends TripLogState {
  final TripLog draft;
  final bool hasUnsavedChanges;
  final List<String> validationErrors;
  const TripLogEditing({required this.draft, this.hasUnsavedChanges = false, this.validationErrors = const []});
}
class TripLogLoaded     extends TripLogState { final TripLog tripLog; const TripLogLoaded(this.tripLog); }
class TripLogPublishing extends TripLogState { const TripLogPublishing(); }
class TripLogPublished  extends TripLogState { final TripLog tripLog; const TripLogPublished(this.tripLog); }
class TripLogSyncPending extends TripLogState { final TripLog tripLog; const TripLogSyncPending(this.tripLog); }
class TripLogError      extends TripLogState { final String message; const TripLogError(this.message); }
```

### VaultCubit

```dart
// vault_state.dart
sealed class VaultState { const VaultState(); }
class VaultIdle       extends VaultState {
  final List<OfflineBundle> bundles; final int outboxCount;
  const VaultIdle({required this.bundles, this.outboxCount = 0});
}
class VaultDownloading extends VaultState {
  final String districtId; final double progress; final String currentStep;
  const VaultDownloading({required this.districtId, required this.progress, required this.currentStep});
}
class VaultSyncing    extends VaultState {
  final int pendingCount; final int syncedCount;
  const VaultSyncing({required this.pendingCount, required this.syncedCount});
}
class VaultConflict   extends VaultState { final List<ConflictEvent> conflicts; const VaultConflict(this.conflicts); }
class VaultError      extends VaultState { final String message; const VaultError(this.message); }
```

### TrustBloc

```dart
// trust_event.dart
sealed class TrustEvent { const TrustEvent(); }
class LoadExplorerScore  extends TrustEvent { final String uid; const LoadExplorerScore(this.uid); }
class WatchScoreStream   extends TrustEvent { final String uid; const WatchScoreStream(this.uid); }
class FlagContentEvent   extends TrustEvent {
  final String targetId, targetType; final FlagType flagType; final String? reason;
  const FlagContentEvent({required this.targetId, required this.targetType, required this.flagType, this.reason});
}
class AppealFlagEvent    extends TrustEvent { final String flagId, reason; const AppealFlagEvent(this.flagId, this.reason); }

// trust_state.dart
sealed class TrustState { const TrustState(); }
class TrustInitial   extends TrustState { const TrustInitial(); }
class TrustLoading   extends TrustState { const TrustLoading(); }
class TrustLoaded    extends TrustState {
  final ExplorerScore score; final ExplorerProfile profile; final bool tierUpgradeAvailable;
  const TrustLoaded({required this.score, required this.profile, this.tierUpgradeAvailable = false});
}
class TrustFlagging  extends TrustState { const TrustFlagging(); }
class TrustFlagged   extends TrustState { const TrustFlagged(); }
class TrustError     extends TrustState { final String message; const TrustError(this.message); }
```

### AuthCubit

```dart
// auth_state.dart
sealed class AuthState { const AuthState(); }
class AuthInitial        extends AuthState { const AuthInitial(); }
class AuthLoading        extends AuthState { const AuthLoading(); }
class AuthOtpSent        extends AuthState { final String verificationId; const AuthOtpSent(this.verificationId); }
class Authenticated      extends AuthState { final ExplorerProfile profile; const Authenticated(this.profile); }
class Unauthenticated    extends AuthState { const Unauthenticated(); }
class AuthError          extends AuthState { final String message; const AuthError(this.message); }
```

---
## 7. Offline-First Data Flow

### Read Path (cache-first)

```
BLoC requests data
    │
    ▼
RepositoryImpl.get(id)
    │
    ├─ HiveDao.getById(id) → exists AND NOT freshnessAge.isStale()?
    │       │
    │      YES ─────────────────────► return Right(entity) → BLoC emits Loaded
    │       │
    │      NO / expired
    │       ▼
    │  FirestoreDataSource.fetch(id)
    │       │
    │       ├─ Success → HiveDao.save(model, now) → return Right(entity)
    │       │
    │       └─ NetworkException AND stale cache exists
    │               └─ return Right(stale entity) with SyncStatus.stale
    │               └─ BLoC emits Loaded + stale warning chip
    │
    └─ NetworkException AND no cache at all
          └─ return Left(NetworkFailure) → BLoC emits Error with retry CTA
```

### Freshness TTLs

| Content type | Hive TTL | Rationale |
|---|---|---|
| `LocationPin` | 4 hours | Re-fetched as user pans map |
| `TripLog` | 24 hours | Stable long-form content |
| `ProTip` | 1 hour | Decay state must be current |
| `ExplorerProfile` (others) | 30 minutes | Score changes frequently |
| `ExplorerProfile` (own) | Real-time stream | Firestore snapshot listener |
| `OfflineBundle` | Never expires | Manual delete only |

### Write Path (optimistic outbox)

```
User submits change (online or offline)
    │
    ├─ 1. Hive: write new state to main cache box (optimistic)
    ├─ 2. Hive: enqueue OutboxEntry to sync_outbox
    └─ 3. BLoC: emit SyncPending (UI shows change immediately)
           │
           ├─ Online? → SyncManager.flushOutbox() async
           │
           └─ Offline? → SyncStatusBar shows pending count
                         ConnectivityService reconnect → auto-trigger flushOutbox()

SyncManager.flushOutbox():
    ├─ Dequeue OutboxEntry (FIFO)
    ├─ Exponential backoff if retryCount > 0
    ├─ Push to Firestore
    │
    ├─ Success → markSynced, SyncStatus → Synced
    ├─ ConflictException → markConflict + emit to conflictStream → MergeConflictDialog
    └─ NetworkException → incrementRetry, stop flush
         retryCount > 5 → markFailed, notify user
```

---

## 8. Trust & Explorer Score Engine

### Score Formula

```
ExplorerScore =
    (helpfulVotes × 2)
  + (tripsPublished × freshnessDecayFactor)
  + peerEndorsements
  − (spamFlagsReceived × 5)
  − (safetyFlagsReceived × 10)
```

The full formula is displayed publicly in the "How is my score calculated?" screen.

### Trust Tier Thresholds

| Tier | Score | Extra requirement | Key privilege |
|---|---|---|---|
| Unverified | 0 | New account | Post tips (unverified label) |
| Community | ≥ 50 | 3+ helpful votes | Post full TripLogs |
| Verified Explorer | ≥ 200 | — | Create Premium Guides |
| Region Expert | ≥ 500 | Council nomination | Division moderation tools |
| Pioneer | — | Founding program | Permanent; cannot be demoted |

### Cloud Function — score pipeline

```
Flutter app writes trust_event
    │ (onWrite trigger, region: asia-south1)
    ▼
computeExplorerScore function
    ├─ Aggregate all events for targetUid
    ├─ Apply formula
    ├─ Determine tier
    └─ Write explorer_scores/{uid}
           │
           ▼ (realtime Firestore listener in TrustBloc)
       ScoreBadge widget updates live (2–10s latency, Cloud Function cold start)
```

### Auto-moderation thresholds

```
safety_flag received (any count)
    └─ Immediate: set content.hidden = true
    └─ FCM alert to founders

spam_flag count ≥ 2
    └─ set content.hidden = true (pending review)

outdated_flag count ≥ 3
    └─ set feed_rank_penalty = 0.5 (demoted, still visible with stale label)
```

---

## 9. Smart Feed Algorithm

```dart
// features/feed/data/repositories/feed_repository_impl.dart
double _rankScore(FeedItem item, ExplorerProfile viewer) {
  final freshness      = item.freshnessAge.decayFactor();           // 0.0–1.0
  final trust          = item.authorTier.numericWeight;             // 0.5–1.0
  final helpfulness    = item.helpfulVotes / (item.helpfulVotes + 10.0); // Wilson smoothing
  final divisionBoost  = item.division == viewer.division ? 1.3 : 1.0;
  final verifiedBoost  = item.authorTier.isVerifiedOrAbove ? 1.2 : 1.0;
  final safetyPenalty  = item.hasActiveSafetyFlag ? 0.0 : 1.0;

  return freshness * trust * helpfulness * divisionBoost * verifiedBoost * safetyPenalty;
}
```

| Signal | Weight | Notes |
|---|---|---|
| Content freshness | 0.0–1.0 linear | Based on `lastConfirmed` age |
| Author trust tier | 0.5–1.0 | Verified = 1.0, Unverified = 0.5 |
| Helpful vote ratio | Wilson lower bound | Penalises low-vote content |
| User's division match | 1.3× boost | From explorer profile |
| Verified badge | 1.2× boost | Author is Verified+ |
| Safety flag active | 0× multiplier | Completely hidden |

---

## 10. Hive Local Storage — Full Schema

All Hive boxes are encrypted with AES-256. Key stored in `flutter_secure_storage`.

### Box registry

```dart
// core/constants/hive_boxes.dart
class HiveBoxes {
  static const pins        = 'pins_cache';       // LocationPinHiveModel
  static const tripLogs    = 'triplogs_cache';   // TripLogHiveModel
  static const tripDrafts  = 'triplogs_drafts';  // TripLogHiveModel (unsaved)
  static const proTips     = 'protips_cache';    // ProTipHiveModel
  static const outbox      = 'sync_outbox';      // OutboxEntryHiveModel (FIFO)
  static const bundles     = 'offline_bundles';  // OfflineBundleHiveModel
  static const tileMeta    = 'tile_meta';        // Map<String, DateTime>
  static const userPrefs   = 'user_prefs';       // key-value settings
}

class HiveTypeIds {
  static const locationPin   = 1;
  static const tripLog       = 2;
  static const proTip        = 3;
  static const outboxEntry   = 4;
  static const offlineBundle = 5;
  static const costItem      = 6;
  static const tripBlock     = 7;
  static const geoCoordinate = 8;
  static const syncStatus    = 9;
  static const flagType      = 10;
  static const trustTier     = 11;
}
```

### OutboxEntry model

```dart
@HiveType(typeId: HiveTypeIds.outboxEntry)
class OutboxEntryHiveModel extends HiveObject {
  @HiveField(0) String id;
  @HiveField(1) String operation;           // 'create' | 'update' | 'delete'
  @HiveField(2) String collectionPath;      // e.g. 'trip_logs'
  @HiveField(3) String documentId;
  @HiveField(4) Map<String, dynamic> payload;
  @HiveField(5) DateTime enqueuedAt;
  @HiveField(6) int retryCount;
  @HiveField(7) String status;              // 'pending'|'synced'|'conflict'|'failed'
  @HiveField(8) Map<String, dynamic>? serverConflictPayload;
}
```

### Hive initialisation

```dart
// main.dart
Future<void> _initHive() async {
  await Hive.initFlutter();

  final secureStorage = const FlutterSecureStorage();
  var keyStr = await secureStorage.read(key: 'hive_enc_key');
  if (keyStr == null) {
    final key = Hive.generateSecureKey();
    keyStr = base64Url.encode(key);
    await secureStorage.write(key: 'hive_enc_key', value: keyStr);
  }
  final cipher = HiveAesCipher(base64Url.decode(keyStr));

  Hive
    ..registerAdapter(LocationPinHiveModelAdapter())
    ..registerAdapter(TripLogHiveModelAdapter())
    ..registerAdapter(ProTipHiveModelAdapter())
    ..registerAdapter(OutboxEntryHiveModelAdapter())
    ..registerAdapter(OfflineBundleHiveModelAdapter())
    ..registerAdapter(SyncStatusAdapter())
    ..registerAdapter(TrustTierAdapter());

  await Future.wait([
    Hive.openBox<LocationPinHiveModel>(HiveBoxes.pins,     encryptionCipher: cipher),
    Hive.openBox<TripLogHiveModel>(HiveBoxes.tripLogs,     encryptionCipher: cipher),
    Hive.openBox<TripLogHiveModel>(HiveBoxes.tripDrafts,   encryptionCipher: cipher),
    Hive.openBox<ProTipHiveModel>(HiveBoxes.proTips,       encryptionCipher: cipher),
    Hive.openBox<OutboxEntryHiveModel>(HiveBoxes.outbox,   encryptionCipher: cipher),
    Hive.openBox<OfflineBundleHiveModel>(HiveBoxes.bundles,encryptionCipher: cipher),
    Hive.openBox(HiveBoxes.tileMeta),
    Hive.openBox(HiveBoxes.userPrefs),
  ]);
}
```

---

## 11. Cloud Functions — Full Implementation

All functions run in region `asia-south1` (Mumbai) for minimum latency from Bangladesh.

### `computeExplorerScore.ts`

```typescript
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const db = admin.firestore();

export const computeExplorerScore = functions
  .region('asia-south1')
  .firestore.document('trust_events/{eventId}')
  .onWrite(async (change) => {
    const event = change.after.data();
    if (!event) return;

    const uid = event.targetUid as string;
    const snap = await db.collection('trust_events')
      .where('targetUid', '==', uid).get();

    let helpfulVotes = 0, tripsPublished = 0, endorsements = 0,
        spamFlags = 0, safetyFlags = 0;

    snap.forEach(doc => {
      switch (doc.data().type) {
        case 'helpful_vote':   helpfulVotes++;   break;
        case 'trip_published': tripsPublished++; break;
        case 'endorsement':    endorsements++;   break;
        case 'spam_flag':      spamFlags++;      break;
        case 'safety_flag':    safetyFlags++;    break;
      }
    });

    const score = Math.max(0,
      (helpfulVotes * 2) + tripsPublished + endorsements
      - (spamFlags * 5) - (safetyFlags * 10)
    );

    const tier = score >= 500 ? 'regionExpert'
               : score >= 200 ? 'verified'
               : score >= 50  ? 'community'
               : 'unverified';

    await db.collection('explorer_scores').doc(uid).set(
      { score, tier, lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        breakdown: { helpfulVotes, tripsPublished, endorsements, spamFlags, safetyFlags } },
      { merge: true }
    );
  });
```

### `decayFreshness.ts`

```typescript
export const decayFreshness = functions
  .region('asia-south1')
  .pubsub.schedule('0 20 * * *')  // 02:00 BST (UTC+6)
  .timeZone('Asia/Dhaka')
  .onRun(async () => {
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - 180);

    const stale = await db.collection('pro_tips')
      .where('lastConfirmed', '<', cutoff)
      .where('decayStatus', '!=', 'stale')
      .get();

    const batch = db.batch();
    const authorIds = new Set<string>();

    stale.forEach(doc => {
      batch.update(doc.ref, { decayStatus: 'stale' });
      authorIds.add(doc.data().authorId);
    });

    await batch.commit();
    for (const uid of authorIds) await _sendDecayFCM(uid);
    console.log(`Marked ${stale.size} tips stale, notified ${authorIds.size} authors`);
  });
```

### `moderateContent.ts`

```typescript
export const moderateContent = functions
  .region('asia-south1')
  .firestore.document('trust_events/{eventId}')
  .onCreate(async (snap) => {
    const { type, targetId, targetType } = snap.data();
    if (type !== 'spam_flag' && type !== 'safety_flag') return;

    const collection = targetType === 'trip_log' ? 'trip_logs' : 'pro_tips';
    const ref = db.collection(collection).doc(targetId);

    if (type === 'safety_flag') {
      await ref.update({ hidden: true, hiddenReason: 'safety_flag' });
      await _notifyFounders(targetId, targetType);
      return;
    }

    const spamCount = (await db.collection('trust_events')
      .where('targetId', '==', targetId)
      .where('type', '==', 'spam_flag').count().get()).data().count;

    if (spamCount >= 2) await ref.update({ hidden: true, hiddenReason: 'spam_threshold' });
  });
```

---

## 12. FCM Push Notification Handling

### Token registration & routing

```dart
// features/notifications/data/fcm_service.dart
@singleton
class FcmService {
  Future<void> init(String uid) async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await _messaging.getToken();
    if (token != null) await _saveToken(uid, token);
    _messaging.onTokenRefresh.listen((t) => _saveToken(uid, t));
    FirebaseMessaging.onMessage.listen(_handleForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _handleTap(initial);
  }

  void _handleTap(RemoteMessage message) {
    final action = message.data['action'] as String?;
    switch (action) {
      case 're_confirm_tips': getIt<AppRouter>().go('/vault');
      case 'conflict':        getIt<AppRouter>().go('/vault?tab=conflicts');
      case 'flag_appeal':     getIt<AppRouter>().go('/trust/appeals');
      case 'tier_upgrade':    getIt<AppRouter>().go('/explorer/${message.data['uid']}');
      case 'safety_review':   getIt<AppRouter>().go('/trust/flags');
    }
  }
}
```

### Notification types

| `action` | Trigger | Destination |
|---|---|---|
| `re_confirm_tips` | Nightly decay scheduler | `/vault` Re-confirm tab |
| `conflict` | SyncManager conflict | `/vault?tab=conflicts` |
| `flag_appeal` | Appeal resolved | `/trust/appeals` |
| `tier_upgrade` | Score crossed threshold | Explorer profile |
| `helpful_vote` | Vote on your content | TripLog / ProTip detail |
| `safety_review` | Safety flag on your content | Flag review screen |

---

## 13. Image Pipeline & Media Handling

### Client-side processing pipeline

```dart
// core/utils/image_utils.dart
class ImagePipeline {
  static Future<File> process(File raw) async {
    // 1. Decode to check dimensions
    final image = await decodeImageFromList(await raw.readAsBytes());
    File processed = raw;

    // 2. Resize if wider than 1200px
    if (image.width > 1200) {
      processed = await FlutterImageCompress.compressAndGetFile(
        raw.path,
        '${raw.parent.path}/compressed_${raw.uri.pathSegments.last}',
        minWidth: 1200, minHeight: 0, quality: 85,
      ) ?? raw;
    }

    // 3. Strip EXIF GPS data (privacy)
    processed = await _stripExifLocation(processed);

    return processed;
  }
}
```

### Upload with progress streaming

```dart
// features/trip_log/data/datasources/firestore_triplog_source.dart
Future<String> uploadImage(File imageFile, String tripLogId) async {
  final processed = await ImagePipeline.process(imageFile);
  final ref = _storage.ref('trip_logs/$tripLogId/${const Uuid().v4()}.jpg');
  final task = ref.putFile(processed, SettableMetadata(contentType: 'image/jpeg'));
  task.snapshotEvents.listen((snap) {
    getIt<TripLogBloc>().add(
      ImageUploadProgress(snap.bytesTransferred / snap.totalBytes)
    );
  });
  await task;
  return ref.getDownloadURL();
}
```

### Offline image cache during vault download

```
Pre-fetch for each ImageBlock in downloaded TripLogs:
  ├─ Download from Firebase Storage
  ├─ Compress to 800px max JPEG 80%
  ├─ Save to local bundle directory
  └─ Update ImageBlock.localPath in HiveModel
     → MapLibre GL + CachedNetworkImage use localPath when offline
```

---

## 14. Shared Core

### Complete entity definitions

```dart
// core/entities/explorer_profile.dart
@freezed
class ExplorerProfile with _$ExplorerProfile {
  const factory ExplorerProfile({
    required String uid,
    required String displayName,
    required ExplorerScore explorerScore,
    required TrustTier tier,
    required List<String> badges,
    required String division,
    required DateTime createdAt,
    @Default(false) bool isPioneer,
    @Default(false) bool isRegionExpert,
    String? avatarUrl,
    String? bio,
  }) = _ExplorerProfile;
  factory ExplorerProfile.fromJson(Map<String, dynamic> json) => _$ExplorerProfileFromJson(json);
}

// core/entities/offline_bundle.dart
@freezed
class OfflineBundle with _$OfflineBundle {
  const factory OfflineBundle({
    required String districtId,
    required String districtName,
    required List<LocationPin> pins,
    required List<TripLog> trips,
    required List<ProTip> tips,
    required List<String> tileKeys,
    required DateTime downloadedAt,
    required int sizeBytes,
    @Default(SyncStatus.synced) SyncStatus syncStatus,
  }) = _OfflineBundle;
}
```

### Error handling hierarchy

```dart
// core/error/failures.dart
sealed class Failure {
  final String message;
  const Failure(this.message);
}

final class NetworkFailure    extends Failure { const NetworkFailure(super.message); }
final class CacheFailure      extends Failure { const CacheFailure(super.message); }
final class AuthFailure       extends Failure { const AuthFailure(super.message); }
final class ValidationFailure extends Failure { const ValidationFailure(super.message); }
final class PermissionFailure extends Failure { const PermissionFailure(super.message); }
final class NotFoundFailure   extends Failure {
  final String resourceId;
  const NotFoundFailure(super.message, {required this.resourceId});
}
final class ConflictFailure extends Failure {
  final Map<String, dynamic> localVersion;
  final Map<String, dynamic> serverVersion;
  const ConflictFailure(super.message, {required this.localVersion, required this.serverVersion});
}

// Extension: user-facing messages
extension FailureMessage on Failure {
  String toUserMessage() => switch (this) {
    NetworkFailure()    => 'No internet. Changes saved offline.',
    CacheFailure()      => 'Could not load saved data. Restart the app.',
    AuthFailure()       => 'Session expired. Please sign in again.',
    ValidationFailure() => message,
    PermissionFailure() => 'You need a higher trust level to do this.',
    ConflictFailure()   => 'Your changes conflict with a newer version. Please review.',
    NotFoundFailure()   => 'This content no longer exists.',
    _                   => 'An unexpected error occurred.',
  };
}
```

---

## 15. Dependency Injection

```dart
// app/di/injection.dart
@InjectableInit(initializerName: 'configureDependencies', preferRelativeImports: true)
Future<void> configureDependencies(GetIt getIt) => $initGetIt(getIt);

// app/di/firebase_module.dart
@module
abstract class FirebaseModule {
  @lazySingleton FirebaseFirestore get firestore => FirebaseFirestore.instance;
  @lazySingleton FirebaseAuth get auth => FirebaseAuth.instance;
  @lazySingleton FirebaseStorage get storage => FirebaseStorage.instance;
  @lazySingleton FirebaseMessaging get messaging => FirebaseMessaging.instance;
  @lazySingleton FirebaseFunctions get functions =>
    FirebaseFunctions.instanceFor(region: Env.firestoreRegion);
}

// app/di/hive_module.dart
@module
abstract class HiveModule {
  @lazySingleton Box<LocationPinHiveModel> get pinBox =>
    Hive.box<LocationPinHiveModel>(HiveBoxes.pins);
  @lazySingleton Box<TripLogHiveModel> get tripBox =>
    Hive.box<TripLogHiveModel>(HiveBoxes.tripLogs);
  @lazySingleton Box<OutboxEntryHiveModel> get outboxBox =>
    Hive.box<OutboxEntryHiveModel>(HiveBoxes.outbox);
}
```

| Scope | Annotation | Used for |
|---|---|---|
| Eager singleton | `@singleton` | `ConnectivityService`, `SyncManager` |
| Lazy singleton | `@lazySingleton` | All repositories, data sources, Firebase modules |
| Factory | `@injectable` | BLoCs, Cubits (new instance per screen) |

---

## 16. Routing & Deep Links

```dart
// app/router.dart
final router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/map',
  redirect: _authGuard,
  routes: [
    GoRoute(path: '/login', pageBuilder: (_, __) => NoTransitionPage(child: const LoginScreen())),
    ShellRoute(
      builder: (_, __, child) => AppShell(child: child),  // bottom nav bar
      routes: [
        GoRoute(path: '/map',   builder: (_, __) => const MapScreen()),
        GoRoute(path: '/feed',  builder: (_, __) => const HomeFeedScreen()),
        GoRoute(path: '/vault', builder: (_, state) =>
          OfflineVaultScreen(initialTab: state.uri.queryParameters['tab'])),
        GoRoute(path: '/profile/:uid', builder: (_, state) =>
          ExplorerProfileScreen(uid: state.pathParameters['uid']!)),
      ],
    ),
    GoRoute(path: '/trip/:id',    builder: (_, s) => TripLogDetailScreen(id: s.pathParameters['id']!)),
    GoRoute(path: '/editor',      builder: (_, __) => const TripLogEditorScreen()),
    GoRoute(path: '/guide/:id',   builder: (_, s) => PremiumGuideDetailScreen(id: s.pathParameters['id']!)),
    GoRoute(path: '/trust/appeals', builder: (_, __) => const AppealScreen()),
    GoRoute(path: '/settings',    builder: (_, __) => const SettingsScreen()),
  ],
);
```

**Deep link URLs:**

```
https://bhromon.app/trip/{id}         → TripLog detail
https://bhromon.app/guide/{id}        → Premium guide
https://bhromon.app/profile/{uid}     → Explorer profile
https://bhromon.app/map?lat=X&lng=Y   → Map centred on coordinate
```

---

## 17. Theme & Design Tokens

```dart
// app/theme/app_colors.dart
class AppColors {
  static const darkGreen  = Color(0xFF1B4332);
  static const midGreen   = Color(0xFF2D6A4F);
  static const leafGreen  = Color(0xFF40916C);
  static const mintGreen  = Color(0xFF74C69D);
  static const paleGreen  = Color(0xFFD8F3DC);
  static const gold       = Color(0xFFF4A261);
  static const amber      = Color(0xFFE76F51);
  static const lightGold  = Color(0xFFFFD166);
  static const offWhite   = Color(0xFFF8FAFB);
  static const darkText   = Color(0xFF1A1A2E);
  static const grayText   = Color(0xFF5C6B73);
  static const error      = Color(0xFFE63946);
  static const success    = Color(0xFF40916C);

  static Color forTier(TrustTier tier) => switch (tier) {
    TrustTier.unverified   => const Color(0xFFADB5BD),
    TrustTier.community    => mintGreen,
    TrustTier.verified     => gold,
    TrustTier.regionExpert => darkGreen,
    TrustTier.pioneer      => amber,
  };

  static Color forDecay(DecayStatus s) => switch (s) {
    DecayStatus.fresh  => leafGreen,
    DecayStatus.aging  => gold,
    DecayStatus.stale  => amber,
  };
}

// app/theme/app_spacing.dart
class AppSpacing {
  static const double xs  =  4.0;
  static const double sm  =  8.0;
  static const double md  = 16.0;
  static const double lg  = 24.0;
  static const double xl  = 32.0;
  static const double xxl = 48.0;
}
```

---

## 18. Firebase Data Model

### Firestore Collections

```
firestore/
├── location_pins/{pinId}
│   ├── geoHash: string          # Precision-6 GeoHash
│   ├── lat, lng: number
│   ├── name: string
│   ├── division, district: string
│   ├── trustTier: string
│   ├── lastConfirmed: timestamp
│   ├── linkedTripIds: string[]
│   ├── linkedTipIds: string[]
│   ├── createdByUid: string
│   └── hidden: bool
│
├── trip_logs/{tripId}
│   ├── authorId: string
│   ├── title: string
│   ├── blocks: array            # Serialised TripBlock list
│   ├── routePoints: geopoint[]
│   ├── costItems: array         # { label, amountBDT, category }
│   ├── locationPinId: string
│   ├── division, district: string
│   ├── trustScore: number
│   ├── helpfulVotes: number
│   ├── lastConfirmed: timestamp
│   ├── publishedAt: timestamp
│   ├── hidden: bool
│   ├── hiddenReason: string?
│   ├── isPremiumGuide: bool
│   └── tier: string
│
├── pro_tips/{tipId}
│   ├── locationPinId: string
│   ├── authorId: string
│   ├── text: string
│   ├── category: string         # transport|food|safety|accommodation|general
│   ├── helpfulVotes: number
│   ├── outdatedVotes: number
│   ├── lastConfirmed: timestamp
│   ├── decayStatus: string      # fresh|aging|stale
│   └── hidden: bool
│
├── explorer_profiles/{uid}
│   ├── displayName: string
│   ├── division: string
│   ├── tier: string
│   ├── badges: string[]
│   ├── isPioneer, isRegionExpert: bool
│   ├── avatarUrl: string?
│   ├── bio: string?
│   └── createdAt: timestamp
│
├── explorer_scores/{uid}        # ← Cloud Function writes only
│   ├── score: number
│   ├── tier: string
│   ├── lastUpdated: timestamp
│   └── breakdown: map
│
├── trust_events/{eventId}       # Append-only event log
│   ├── type: string
│   ├── targetId, targetUid: string
│   ├── targetType: string
│   ├── actorId: string
│   ├── timestamp: timestamp
│   └── weight: number
│
├── flag_appeals/{appealId}
│   ├── flagEventId: string
│   ├── appellantUid: string
│   ├── reason: string
│   ├── status: string           # pending|upheld|dismissed
│   ├── submittedAt: timestamp
│   └── resolvedAt: timestamp?
│
└── fcm_tokens/{uid}
    ├── token: string
    ├── platform: string         # android|ios
    └── updatedAt: timestamp
```

### Firestore Indexes

```json
{
  "indexes": [
    {
      "collectionGroup": "location_pins",
      "fields": [
        { "fieldPath": "geoHash", "order": "ASCENDING" },
        { "fieldPath": "hidden",  "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "trip_logs",
      "fields": [
        { "fieldPath": "locationPinId", "order": "ASCENDING" },
        { "fieldPath": "lastConfirmed", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "trip_logs",
      "fields": [
        { "fieldPath": "division",    "order": "ASCENDING" },
        { "fieldPath": "publishedAt", "order": "DESCENDING" },
        { "fieldPath": "hidden",      "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "pro_tips",
      "fields": [
        { "fieldPath": "locationPinId", "order": "ASCENDING" },
        { "fieldPath": "decayStatus",   "order": "ASCENDING" },
        { "fieldPath": "helpfulVotes",  "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "trust_events",
      "fields": [
        { "fieldPath": "targetUid", "order": "ASCENDING" },
        { "fieldPath": "type",      "order": "ASCENDING" }
      ]
    }
  ]
}
```

---

## 19. Firebase Security Rules — Full

```javascript
// firestore.rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function isAuth()   { return request.auth != null; }
    function isOwner(uid) { return request.auth.uid == uid; }
    function profile()  {
      return get(/databases/$(database)/documents/explorer_profiles/$(request.auth.uid)).data;
    }
    function isNotUnverified()     { return isAuth() && profile().tier != 'unverified'; }
    function isVerifiedOrAbove()   { return isAuth() && profile().tier in ['verified','regionExpert','pioneer']; }
    function isRegionExpertOrAbove() { return isAuth() && profile().tier in ['regionExpert','pioneer']; }

    match /location_pins/{id} {
      allow read:   if !resource.data.hidden || isAuth();
      allow create: if isNotUnverified() && request.resource.data.createdByUid == request.auth.uid;
      allow update: if isOwner(resource.data.createdByUid) || isRegionExpertOrAbove();
      allow delete: if false;
    }

    match /trip_logs/{id} {
      allow read:   if !resource.data.hidden || (isAuth() && isOwner(resource.data.authorId));
      allow create: if isNotUnverified()
                    && request.resource.data.authorId == request.auth.uid
                    && (!request.resource.data.isPremiumGuide || isVerifiedOrAbove());
      allow update: if isOwner(resource.data.authorId)
                    && request.resource.data.authorId == resource.data.authorId;
      allow delete: if isOwner(resource.data.authorId) || isRegionExpertOrAbove();
    }

    match /pro_tips/{id} {
      allow read:   if !resource.data.hidden || (isAuth() && isOwner(resource.data.authorId));
      allow create: if isAuth() && request.resource.data.authorId == request.auth.uid;
      allow update: if isOwner(resource.data.authorId);
      allow delete: if isOwner(resource.data.authorId) || isRegionExpertOrAbove();
    }

    match /explorer_profiles/{uid} {
      allow read:   if true;
      allow create: if isOwner(uid);
      allow update: if isOwner(uid)
                    && !request.resource.data.diff(resource.data)
                       .affectedKeys().hasAny(['tier','badges','isPioneer','isRegionExpert']);
    }

    match /explorer_scores/{uid} {
      allow read:  if isAuth();
      allow write: if false;   // Cloud Functions service account only
    }

    match /trust_events/{id} {
      allow create: if isAuth() && request.resource.data.actorId == request.auth.uid;
      allow read, update, delete: if false;
    }

    match /flag_appeals/{id} {
      allow create: if isAuth() && request.resource.data.appellantUid == request.auth.uid;
      allow read:   if isAuth() && (isOwner(resource.data.appellantUid) || isRegionExpertOrAbove());
      allow update: if isRegionExpertOrAbove();
      allow delete: if false;
    }

    match /fcm_tokens/{uid} {
      allow read, write: if isOwner(uid);
    }
  }
}
```

---

## 20. Performance & Optimisation

| Technique | Applied to | Detail |
|---|---|---|
| `const` constructors | All stateless widgets | Prevents unnecessary rebuilds |
| `ListView.builder` | All feeds | Lazy rendering — only visible items built |
| `CachedNetworkImage` | All remote images | LRU memory + disk cache |
| `RepaintBoundary` | Map layer, image blocks | Isolates expensive repaints |
| `compute()` | GeoHash batch calc, JSON decode | Background isolate |
| Image compression | Upload pipeline | Max 1200px, JPEG 85% |
| Pagination | TripLog feed, Pro-Tip feed | 20 items, cursor-based |
| BLoC `debounce` transformer | Map pan events | 300 ms — prevents over-querying |
| Firestore `.select()` | Map pin tiles | Read only `id, geoHash, tier` fields |
| Batch writes | Decay scheduler | `WriteBatch` for up to 500 ops |
| Firestore `count()` | Flag thresholds | No full document reads needed |

---

## 21. Error Handling & Crash Reporting

### Global error handler

```dart
// main.dart
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    await _initHive();
    await Firebase.initializeApp();
    await configureDependencies();
    runApp(const BhromonApp());
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack);
  });
}
```

### Error boundary widget

```dart
// core/widgets/error_boundary.dart
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(Object error)? fallback;
}
// Wraps every feature screen; catches render errors and
// shows BhromonErrorView(message, onRetry) instead of red screen
```

---

## 22. Accessibility

- **Tap targets:** All interactive elements are ≥ 48 × 48 dp
- **Contrast:** All text/background pairs ≥ 4.5:1 (WCAG AA), tested with `flutter_accessibility_checker`
- **Screen reader:** All images have `Semantics(image: true, label: '...')` equivalents
- **Large text:** All font sizes relative — no hardcoded px; respects `MediaQuery.textScaler`
- **Semantic labels:** Map pins, decay badges, score widgets all include screen-reader descriptions

```dart
// Example — map pin with full semantics
Semantics(
  label: '${pin.name}, ${pin.tier.displayName} location, '
         '${pin.linkedTripIds.length} trips available',
  button: true,
  onTapHint: 'Open location details',
  child: PinGraphic(pin: pin),
)
```

---

## 23. Localisation (i18n)

Supports English (default) and Bengali (`bn`).

```yaml
# l10n.yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
```

```json
// lib/l10n/app_en.arb
{
  "appName": "Bhromon",
  "tipDecayStale": "Unconfirmed for {days} days — still accurate?",
  "@tipDecayStale": { "placeholders": { "days": { "type": "int" } } },
  "explorerTier_unverified": "New Explorer",
  "explorerTier_community": "Community Explorer",
  "explorerTier_verified": "Verified Explorer",
  "explorerTier_regionExpert": "Region Expert",
  "explorerTier_pioneer": "Pioneer"
}
```

---

## 24. Key Dependencies

```yaml
dependencies:
  flutter: { sdk: flutter }
  flutter_bloc: ^8.1.5
  bloc: ^8.1.4
  get_it: ^7.7.0
  injectable: ^2.3.5
  go_router: ^13.2.1
  firebase_core: ^2.30.1
  firebase_auth: ^4.19.5
  cloud_firestore: ^4.17.3
  firebase_storage: ^11.7.5
  cloud_functions: ^4.7.3
  firebase_messaging: ^14.9.3
  firebase_crashlytics: ^3.5.5
  firebase_performance: ^0.9.4+5
  hive_flutter: ^1.1.0
  flutter_secure_storage: ^9.2.2
  maplibre_gl: ^0.20.0
  path_provider: ^2.1.3
  connectivity_plus: ^6.0.3
  cached_network_image: ^3.3.1
  image_picker: ^1.1.2
  flutter_image_compress: ^2.2.0
  dartz: ^0.10.1
  freezed_annotation: ^2.4.1
  json_annotation: ^4.9.0
  equatable: ^2.0.5
  uuid: ^4.4.0
  intl: ^0.19.0
  rxdart: ^0.27.7
  google_sign_in: ^6.2.1
  flutter_localizations: { sdk: flutter }

dev_dependencies:
  build_runner: ^2.4.11
  freezed: ^2.5.2
  json_serializable: ^6.8.0
  injectable_generator: ^2.4.3
  hive_generator: ^2.0.1
  bloc_test: ^9.1.7
  mocktail: ^1.0.4
  flutter_test: { sdk: flutter }
  flutter_lints: ^4.0.0
```

---

## 25. Code Generation

```bash
# One-time
dart run build_runner build --delete-conflicting-outputs

# Watch mode
dart run build_runner watch --delete-conflicting-outputs
```

| Source annotation | Generated output |
|---|---|
| `@freezed` | `*.freezed.dart` — immutable copyWith/equality |
| `@JsonSerializable` | `*.g.dart` — fromJson/toJson |
| `@HiveType` + `@HiveField` | `*.g.dart` — Hive TypeAdapter |
| `@injectable` / `@lazySingleton` | `injection.config.dart` |

**`analysis_options.yaml`:**

```yaml
include: package:flutter_lints/flutter.yaml
analyzer:
  exclude: ["**/*.g.dart", "**/*.freezed.dart", "lib/app/di/injection.config.dart"]
  errors:
    missing_required_param: error
    missing_return: error
linter:
  rules:
    prefer_const_constructors: true
    avoid_print: true
    always_use_package_imports: true
    directives_ordering: true
```

---

## 26. Testing Strategy — Full Suite

### Test pyramid

```
                   ┌────────────────────────────┐
                   │  Integration tests   5%    │  Full flows with real Hive
                   ├────────────────────────────┤
                   │  Widget tests       25%    │  Critical UI with mock BLoCs
                   ├────────────────────────────┤
                   │  Unit tests         70%    │  Domain: use-cases, value objects
                   └────────────────────────────┘
```

### Unit test examples

```dart
// test/unit/trust/compute_score_test.dart
group('ExplorerScore formula', () {
  const calc = ComputeScoreUseCase.calculate;
  test('base: no activity → 0', () => expect(calc(helpfulVotes: 0, tripsPublished: 0, endorsements: 0, spamFlags: 0, safetyFlags: 0, freshnessDecay: 1.0), equals(0)));
  test('helpful votes × 2',     () => expect(calc(helpfulVotes: 10, tripsPublished: 0, endorsements: 0, spamFlags: 0, safetyFlags: 0, freshnessDecay: 1.0), equals(20)));
  test('spam penalty × 5',      () => expect(calc(helpfulVotes: 20, tripsPublished: 0, endorsements: 0, spamFlags: 2, safetyFlags: 0, freshnessDecay: 1.0), equals(30)));
  test('safety penalty × 10',   () => expect(calc(helpfulVotes: 20, tripsPublished: 0, endorsements: 0, spamFlags: 0, safetyFlags: 1, freshnessDecay: 1.0), equals(30)));
});
```

### BLoC test example

```dart
// test/unit/trip_log/trip_log_bloc_test.dart
blocTest<TripLogBloc, TripLogState>(
  'publishes TripLog and emits TripLogPublished',
  build: () {
    when(() => mockPublishUseCase(any())).thenAnswer((_) async => Right(mockTripLog));
    return TripLogBloc(publish: mockPublishUseCase, get: mockGetUseCase, saveDraft: mockSaveDraft);
  },
  act: (bloc) => bloc.add(PublishTripLogEvent(tripLog: mockTripLog)),
  expect: () => [isA<TripLogPublishing>(), isA<TripLogPublished>()],
  verify: (_) => verify(() => mockPublishUseCase(any())).called(1),
);
```

### SyncManager test example

```dart
// test/unit/offline/sync_manager_test.dart
test('stops flushing on NetworkException and increments retry', () async {
  when(() => mockOutbox.getAllPending()).thenAnswer((_) async => [entry1, entry2]);
  when(() => mockRemote.publish(any())).thenThrow(const NetworkException());
  await sut.flushOutbox();
  verify(() => mockOutbox.incrementRetry(entry1.id)).called(1);
  verifyNever(() => mockRemote.publish(entry2.payload));
});
```

---

## 27. CI/CD Pipeline

### `.github/workflows/ci.yml`

```yaml
name: CI
on:
  pull_request: { branches: [main, develop] }
  push: { branches: [develop] }

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.22.0', channel: stable }
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: flutter analyze --fatal-infos
      - run: dart format --set-exit-if-changed lib/ test/
      - run: flutter test test/unit/ test/widget/ --coverage
      - uses: codecov/codecov-action@v4
        with: { file: coverage/lcov.info }
```

### `.github/workflows/cd.yml`

```yaml
name: CD
on:
  push: { tags: ['v*.*.*'] }

jobs:
  android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.22.0' }
      - run: flutter pub get && dart run build_runner build --delete-conflicting-outputs
      - run: flutter build appbundle --release
      - uses: r0adkll/upload-google-play@v1
        with:
          serviceAccountJsonPlainText: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}
          packageName: app.bhromon.android
          releaseFiles: build/app/outputs/bundle/release/*.aab
          track: internal

  ios:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.22.0' }
      - run: flutter pub get && dart run build_runner build --delete-conflicting-outputs
      - run: flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
      - uses: apple-actions/upload-testflight-build@v1
        with:
          app-path: build/ios/ipa/*.ipa
          issuer-id: ${{ secrets.APPSTORE_ISSUER_ID }}
          api-key-id: ${{ secrets.APPSTORE_KEY_ID }}
          api-private-key: ${{ secrets.APPSTORE_PRIVATE_KEY }}
```

---

## 28. Release & Versioning

```yaml
# pubspec.yaml
version: 1.0.0+1
#        │ │ │  └─ Build number (auto-incremented by CI)
#        │ │ └── Patch: bug fixes
#        │ └──── Minor: new features, backward compatible
#        └────── Major: breaking changes
```

**Release checklist:**

```
□ All tests passing on CI
□ flutter analyze clean
□ dart format applied
□ CHANGELOG.md updated
□ Version bump in pubspec.yaml
□ firebase deploy --only firestore:rules
□ firebase deploy --only functions
□ firebase deploy --only firestore:indexes
□ git tag v1.0.0 && git push origin v1.0.0
```

---

## 29. Getting Started

```bash
# 1. Prerequisites: Flutter 3.22+, Dart 3.4+, Node.js 20+
flutter --version

# 2. Clone and install
git clone https://github.com/bhromon/bhromon-flutter.git
cd bhromon-flutter && flutter pub get

# 3. Firebase setup
npm install -g firebase-tools && firebase login
flutterfire configure --project=your-project-id
# → Generates google-services.json + GoogleService-Info.plist

# 4. Deploy backend
firebase deploy --only firestore:rules,firestore:indexes
cd functions && npm install && npm run build && cd ..
firebase deploy --only functions

# 5. Code generation
dart run build_runner build --delete-conflicting-outputs

# 6. Environment config — create lib/app/config/env.dart
cat > lib/app/config/env.dart << 'EOF'
class Env {
  static const firestoreRegion             = 'asia-south1';
  static const mapTileUrl                  = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const maxOfflineRetries           = 5;
  static const proTipStaleDays             = 180;
  static const premiumGuideScoreThreshold  = 200;
  static const communityTierThreshold      = 50;
  static const verifiedTierThreshold       = 200;
  static const regionExpertThreshold       = 500;
  static const mapDefaultLat               = 23.6850;   // Bangladesh centre
  static const mapDefaultLng               = 90.3563;
  static const mapDefaultZoom              = 7.0;
}
EOF

# 7. Run
flutter run           # Debug
flutter run --release # Release

# 8. Test
flutter test test/unit/
flutter test test/widget/
flutter test --coverage

# 9. Analyse
flutter analyze && dart format lib/ test/
```

---

## 30. Architecture Decision Records

### ADR-001 — Flutter Clean Architecture over MVC/MVVM

**Decision:** Adopt Clean Architecture with feature-sliced modules.

**Rationale:** Enforces testability by isolating domain logic from all frameworks. Feature-sliced modules prevent cross-feature coupling, making the codebase navigable by new contributors in hours. The strict dependency rule is self-enforcing — a misplaced import causes a compile error.

**Trade-off:** More boilerplate than MVC; mitigated by code generation.

---

### ADR-002 — Hive over SQLite / Isar

**Decision:** Use Hive (encrypted boxes) for all local persistence.

**Rationale:** Bhromon's access pattern is primarily fetch-by-ID and list-by-GeoHash-prefix — a natural key-value fit. Hive is Flutter-native, has first-class AES-256 encryption, and avoids the SQL query complexity of SQLite. Isar is faster but less mature at time of decision.

**Trade-off:** Complex multi-field sorting requires application-level logic. Acceptable at launch data volumes (< 50,000 items per device).

---

### ADR-003 — GeoHash prefix queries over Firestore native geo

**Decision:** Use GeoHash string prefix range queries for proximity, not Firestore's native GeoPoint.

**Rationale:** Firestore does not support native radius queries on GeoPoint fields. The GeoHash approach (querying neighbouring cell string ranges) is the established Firestore pattern, scales linearly, and requires only a single compound index per collection.

**Trade-off:** Slight over-fetching at cell boundaries; mitigated by post-fetch client-side distance filtering using `GeoCoordinate.distanceTo()`.

---

### ADR-004 — Cloud Functions for score computation, not client-side

**Decision:** `ExplorerScore` is computed exclusively by Cloud Functions; clients cannot write to `explorer_scores/`.

**Rationale:** A client-side-only score is trivially gameable. Cloud Functions + Firestore security rules (`allow write: if false`) make the score authoritative and tamper-proof. The client uses a local estimate only for optimistic UI during the 2–10 second Cloud Function response window.

---

### ADR-005 — Last-Write-Wins for ProTips, Three-Way Merge for TripLogs

**Decision:** ProTip conflicts use LWW; TripLog conflicts surface the three-way merge UI.

**Rationale:** ProTips are short-form and community-reconfirmed frequently — silent LWW loss is acceptable. TripLogs represent significant authorial effort; losing changes silently would damage trust in the offline experience. The three-way merge UI is Git-familiar and gives users explicit control.

**Consequence:** The `MergeConflictDialog` and `ConflictResolver` add complexity to `VaultCubit` and the data layer. This cost is justified for TripLogs; no merge UI for ProTips keeps the common path simple.

---

*Bhromon — ভ্রমণ · Community · Discovery · Trust*

---

> **Document version:** 4.0 · Architecture owner: Bhromon CTO / Lead Engineer
