# Coding Standards & Conventions

**Analysis Date:** 2026-11-07

## 1. Zero Empty Catch Blocks
- **CI Rule**: `tool/check_empty_catches.sh` scans all `.dart` files in `lib/`.
- Every `catch` block MUST contain either:
  - An explanatory comment explaining why ignoring the failure is safe (e.g. `// Safe fallback if GoRouter is unattached.`), OR
  - Proper logging or rethrowing.
- An empty catch `catch (_) {}` without a comment causes CI build failure.

## 2. Formatting & Static Analysis
- **Code Style**: Strictly enforced by `dart format` (line length 80).
- **Linter Rules**: `analysis_options.yaml` with zero warnings / zero fatal infos allowed.
- Format check runs on every pull request (`dart format --output=none --set-exit-if-changed lib/ test/`).

## 3. Web Compatibility (`kIsWeb`)
- Never import or use `dart:io` without guarding with `if (!kIsWeb)`.
- Background services (`Workmanager`, `flutter_local_notifications`, file system operations) are strictly mobile-only.

## 4. Bilingual Localization
- Every user-facing string must have translations in both **Bengali (`bn`)** and **English (`en`)** in `lib/core/localization/`.
- Verified by automated tests in `test/core/localization/tour_translation_test.dart` and `translation_keys_test.dart`.
- Placeholders must match across both language dictionaries.

## 5. Ledger & Financial Arithmetic
- All financial numbers must be stored in **integer paisa** (never floating point).
- User input must pass through `parseTakaInput` (which handles Bengali numeral conversion and input bounds checking).
