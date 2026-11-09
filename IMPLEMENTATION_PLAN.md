# Implementation Plan: E2EE Android Native Packaging (M4) & Test Build Delivery

## Objective
Fulfill Milestone M4 of `E2EE_DESIGN.md`:
1. Package the precompiled and verified `libe2ee_olm.so` native binaries (built from `native/e2ee_olm` via the `vodozemac` Rust Olm engine) into Android's `jniLibs` for all 3 supported ABIs (`arm64-v8a`, `armeabi-v7a`, `x86_64`).
2. Configure `android/app/build.gradle` so Gradle automatically packages `libe2ee_olm.so` into the APK/AAB `lib/<abi>/` directories.
3. Update `.github/workflows/e2ee_native.yml` to build and package an E2EE-enabled test APK (`--dart-define=E2EE_ONE_TO_ONE=true`) and publish it as a downloadable GitHub Actions artifact for internal testing and dogfooding (M5).
4. Update `E2EE_DESIGN.md` to reflect the completion of Milestone M4 packaging.
5. Monotonically increment version in `pubspec.yaml` to `1.8.153+207`.
6. Pass all quality gates (`flutter analyze`, unit tests, GitHub CI checks) and create PR.

---

## Atomic Tasks

### Phase 1: Native Library Packaging & Gradle Configuration
- [x] **Task 1.1: Copy Native Libraries to Android `jniLibs`**
  - Place `libe2ee_olm.so` into `android/app/src/main/jniLibs/{arm64-v8a, armeabi-v7a, x86_64}/`.
  - Add helper scripts `tool/package_e2ee_android.sh` and `scripts/package_e2ee_android.ps1` to automate copying from `native/e2ee_olm/dist/android/`.
- [x] **Task 1.2: Configure Gradle SourceSets**
  - In `android/app/build.gradle`, ensure `sourceSets.main.jniLibs.srcDirs` explicitly includes `src/main/jniLibs` and `../../native/e2ee_olm/dist/android` when available.

### Phase 2: CI Test Build Pipeline
- [x] **Task 2.1: Update `.github/workflows/e2ee_native.yml`**
  - In the `android` job, after building the `.so` files, copy them into `android/app/src/main/jniLibs/`.
  - Add Flutter setup and build step: `flutter build apk --debug --dart-define=E2EE_ONE_TO_ONE=true`.
  - Upload `build/app/outputs/flutter-apk/app-debug.apk` as artifact `bhromon-e2ee-test-apk`.

### Phase 3: Documentation & Verification
- [x] **Task 3.1: Update `E2EE_DESIGN.md`**
  - Document that M4 Android packaging is completed.
- [x] **Task 3.2: Version Bump & Static Analysis**
  - Increment `pubspec.yaml` version to `1.8.153+207`.
  - Run `flutter analyze` to ensure 0 errors and 0 warnings (Passed, 0 issues).
  - Run unit tests to verify no regressions (Passed, 96/96 E2EE tests & all golden tests).
- [ ] **Task 3.3: GitHub PR & CI Verification**
  - Commit changes with descriptive commit messages.
  - Push branch `feat/e2ee-m4-android-packaging` to remote.
  - Open Pull Request via `gh pr create --base main`.
  - Verify all GitHub Actions CI checks turn green.
