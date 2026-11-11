# Implementation Plan: Immediate Asset Cache Busting for 3D Green Emblem

## Context & Root Cause
- Mobile browsers (Chrome/Safari) aggressively cache `assets/assets/logo.png` in disk cache and PWA Service Worker CacheStorage.
- Even after deploying the authentic 3D green logo in PR #487, devices that previously visited `app.bhromon.fun` serve the stale yellow 'B' from disk cache.
- The logo appears in 4 UI locations:
  1. `desktop_tour_sidebar.dart` (desktop sidebar header)
  2. `tour_group_hub_screen.dart` (mobile group hub appbar)
  3. `login_screen.dart` (auth screen)
  4. `join_group_screen.dart` (invite link landing screen)

## Action Items
1. **Asset Renaming & Cache Busting**:
   - Create `assets/bhromon_emblem.png` containing the 100% transparent authentic 3D green compass emblem.
   - Maintain `assets/logo.png` and `assets/Bhromon.png` identically.
   - Register `assets/bhromon_emblem.png` in `pubspec.yaml`.
2. **UI Updates**:
   - Point `desktop_tour_sidebar.dart`, `tour_group_hub_screen.dart`, `login_screen.dart`, and `join_group_screen.dart` to `'assets/bhromon_emblem.png'`.
   - Update `join_group_screen_test.dart` to expect `assets/bhromon_emblem.png`.
   - Use `fit: BoxFit.contain` with slight padding so the 3D compass needle facets and tips are never clipped by `BoxFit.cover`.
3. **PWA & Firebase Hosting Cache Busting**:
   - In `web/index.html`, purge CacheStorage on startup (`caches.delete(...)`).
   - In `firebase.json`, add `Cache-Control: no-cache, no-store, must-revalidate` for `/assets/**`.
4. **Verification & Monotonic Version Bump**:
   - Bump version in `pubspec.yaml` to `1.8.189+243`.
   - Run `dart format`, `dart analyze`, and `flutter test`.
   - Build web release: `flutter build web --release`.
   - PR, dual-agent sign-offs, merge, and deploy to Firebase Hosting.
