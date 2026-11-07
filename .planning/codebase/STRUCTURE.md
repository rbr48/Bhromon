# Directory Layout & File Structure

**Analysis Date:** 2026-11-07

```
E:\Projects\Bhromon
├── android/                 # Android Gradle wrapper, native configuration, permissions
├── assets/                  # App logo (`assets/logo.png`), fonts, game cards, sound effects
├── build/                   # Compilation outputs, release APK & AAB
├── functions/               # Firebase Cloud Functions (TypeScript)
│   ├── src/                 # Triggers, notification dispatchers, GDPR erasure
│   └── tests/               # Jest emulator test suites for security rules
├── lib/
│   ├── app/                 # Root app widget, router (`router.dart`), DI bindings
│   ├── core/
│   │   ├── audio/           # Audio route managers & ringback players
│   │   ├── database/        # Drift database tables, SQLite migrations
│   │   ├── localization/    # Bilingual translation tables (bn/en)
│   │   ├── security/        # Cryptographic primitives & token stores
│   │   └── theme/           # Forest palette, AppColors, typography (NotoSans / HindSiliguri)
│   └── features/
│       ├── auth/            # Auth cubit, login UI, explorer scores
│       ├── chat/            # 1-on-1 direct messages, rich tables, formatting toolbar
│       ├── game_zone/       # 29 Card Game, Carrom, Chess, Ludo, Teen Patti
│       ├── map/             # MapLibre offline vector viewer, GPS tracks
│       ├── official_feed/   # Official reels, verified feed players
│       ├── tour_group/      # Universal Group Engine
│       │   ├── data/        # Repositories & Firestore data sources
│       │   ├── domain/      # Models, engines (ledger, route, samity, meal)
│       │   └── presentation/# Hub screen, desktop sidebar, right dock, modals
│       └── ...
├── media-server/            # Python FastAPI service for media transcoding
├── packages/
│   └── bangla_pdf/          # Custom embedded package for Unicode Bangla PDF rendering
├── test/                    # 247 Unit, widget, and golden test files
└── tool/                    # CI guard scripts (`check_empty_catches.sh`)
```

## Key Architectural Files
- **Router**: `lib/app/router.dart` (Declarative GoRouter with deep-linking support for `/join/:code`).
- **Main Tour Repository**: `lib/features/tour_group/data/tour_group_repository.dart`.
- **Desktop 3-Column Shell**: `lib/features/tour_group/presentation/widgets/desktop_tour_sidebar.dart` & `desktop_right_dock.dart`.
- **Trip Ledger Engine**: `lib/features/tour_group/domain/services/trip_ledger_engine.dart`.
- **Security Rules**: `firestore.rules` & `storage.rules`.
