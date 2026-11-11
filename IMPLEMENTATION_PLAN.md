# Implementation Plan: Bhromon — "Walk Together" Branding & Transparent Logo Restoration

## 1. Objective
Adopt the official app tagline **"Bhromon — Walk Together"** (Bengali: **"ভ্রমণ — একসাথে পথচলা"**) across the entire app, documentation, web manifests, and localizations. Fully restore the original iconic green sculptural 3D compass needle / 'B' emblem and original vintage wordmark with 100% transparent backgrounds for all logos, app icons, favicons, splash screens, and web assets.

---

## 2. Milestones & Task Breakdown

### Milestone 1: Visual Identity & Asset Restoration (Transparent Background)
- [x] Task 1.1: Restore `assets/Bhromon.png` to original vintage transparent wordmark (blob `665da78086c304c38cf5cb82e96ef994c51d36d5`).
- [x] Task 1.2: Place the pristine 1024x1024 transparent green 3D compass/B emblem at `logo.png` and `assets/logo.png`.
- [x] Task 1.3: Remove redundant `logo_foreground.png`.
- [x] Task 1.4: Update `flutter_launcher_icons.yaml` and `flutter_native_splash.yaml`.
- [x] Task 1.5: Run `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create` to regenerate all Android mipmap/drawable and iOS launcher/splash assets.
- [x] Task 1.6: Generate `web/favicon.png` (32x32 transparent) and web icons (`Icon-192.png`, `Icon-512.png`, `Icon-maskable-192.png`, `Icon-maskable-512.png`) with clean transparent backgrounds.

### Milestone 2: App Tagline & Branding Alignment Across UI & Localizations
- [x] Task 2.1: Update `lib/core/localization/translation_keys.dart` and `tour_translation_keys.dart` with `'login_tagline'`: `'Walk Together'` (en) and `'একসাথে পথচলা'` (bn).
- [x] Task 2.2: Update `lib/features/tour_group/presentation/pages/join_group_screen.dart` to use the localized tagline instead of `'Travel with life'`.
- [x] Task 2.3: Update `lib/features/tour_group/presentation/widgets/desktop_tour_sidebar.dart` to use `'Walk Together'` / `'একসাথে পথচলা'`.
- [x] Task 2.4: Update `web/index.html` with title `"Bhromon | Walk Together — Your Groups in One App"` and meta description.
- [x] Task 2.5: Update `web/manifest.json` with "Walk together through every group" description.

### Milestone 3: Documentation & Version Increment
- [x] Task 3.1: Update `AGENTS.md` (root) Section 1 with the official brand tagline and positioning statement.
- [x] Task 3.2: Update `README.md` to feature `Bhromon — Walk Together | একসাথে পথচলা`.
- [x] Task 3.3: Increment version in `pubspec.yaml` to `1.8.187+241`.

### Milestone 4: Verification, Dual-Agent Review & Deployment Gate
- [x] Task 4.1: Run `dart format` across modified files (passed clean).
- [x] Task 4.2: Run `dart analyze` to ensure 0 issues (passed clean).
- [x] Task 4.3: Run `flutter test` for affected suites (all 15 unit tests and golden tests passed).
- [x] Task 4.4: Verify web build with `flutter build web --release` (compiled successfully in 78.6s).
- [ ] Task 4.5: Commit changes atomically, push branch `feat/brand-walk-together`, and open GitHub Pull Request.
- [ ] Task 4.6: Perform Dual-Agent peer review with Claude Code CLI and obtain mutual sign-off.
- [ ] Task 4.7: Ensure all required CI checks pass and squash-merge PR into `main`.
- [ ] Task 4.8: Deploy production build to Firebase Hosting.
