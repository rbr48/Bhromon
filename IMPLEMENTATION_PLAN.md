# Implementation Plan: Transparent Logo Container, Bottle Green Header Title & "Walk Together" Tag

## Context & Objectives
1. **Logo Background Transparency**:
   - The logo container in `desktop_tour_sidebar.dart`, `tour_group_hub_screen.dart`, `join_group_screen.dart`, and `login_screen.dart` was previously wrapped with dark green container backgrounds (`Color(0xFF1B4332)` or `_kCardBg`) and green circular borders.
   - Because the 3D emblem itself is green, the dark green background made the emblem's silhouette and 3D contours blend into the background, obscuring its depth.
   - Removing the circular/squircle dark green container background and making it 100% transparent allows the authentic 3D sculpted emblem to float cleanly on the header/appbar with its full geometry, highlights, and drop-shadows intact.
2. **Bottle Green "Bhromon" Title**:
   - In `tour_group_hub_screen.dart` and `join_group_screen.dart`, the app name "Bhromon" was rendered in white (`context.forest.text`), whereas `desktop_tour_sidebar.dart` rendered it in the brand bottle green (`context.forest.accentText`).
   - Standardize all app headings to use `context.forest.accentText` for "Bhromon".
3. **"Walk Together" Tag Replacement**:
   - In `tour_group_hub_screen.dart`, the header tag previously used `'hub_title'` ("Your groups" / "আপনার গ্রুপ").
   - Replace this with the official brand tagline **"Walk Together"** (Bengali: **"একসাথে পথচলা"**) across `hub_title` in `tour_translation_keys.dart` and bind to `login_tagline` with `context.forest.text54`.

## Action Items
- [x] Make logo container transparent (remove `Color(0xFF1B4332)`, `_kCardBg`, borders, and `ClipOval`/`ClipRRect` wrappers) across:
  - `lib/features/tour_group/presentation/widgets/desktop_tour_sidebar.dart`
  - `lib/features/tour_group/presentation/pages/tour_group_hub_screen.dart`
  - `lib/features/tour_group/presentation/pages/join_group_screen.dart`
  - `lib/features/auth/presentation/pages/login_screen.dart`
- [x] In `tour_group_hub_screen.dart` and `join_group_screen.dart`, change the app name "Bhromon" color to bottle green (`context.forest.accentText`).
- [x] In `tour_group_hub_screen.dart`, replace subtitle tag with "Walk Together" (`context.l10n.translate('login_tagline')` with `context.forest.text54`).
- [x] In `lib/core/localization/tour_translation_keys.dart`, update `'hub_title'` to `'Walk Together'` (EN) and `'একসাথে পথচলা'` (BN).
- [x] Monotonically bump version in `pubspec.yaml` to `1.8.190+244`.
- [x] Run `dart format`, `dart analyze` (0 issues), and `flutter test test/features/tour_group/join_group_screen_test.dart` (all 6 tests pass).
- [ ] Push to GitHub, create PR, exchange mutual Antigravity & Claude peer reviews, merge to `main`, build web, and deploy to Firebase Hosting.
