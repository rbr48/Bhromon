---
name: bhromon-release
description: >-
  End-to-end release and deployment playbook for Bhromon. Use this skill whenever
  building, deploying, or releasing a new version of Bhromon across Flutter Web
  (Firebase Hosting), Android Release APK (Hostinger VPS), or Play Store App Bundle (AAB).
---

# Bhromon Release & Deployment Playbook

This skill outlines the strict, verified procedures for releasing new versions of the Bhromon application.

---

## 1. Pre-Flight Verification & Formatting

Always ensure the local workspace is clean, tests pass, and code adheres to formatting rules before starting a release:

1. **Check Working Tree**:
   ```powershell
   git status
   ```
2. **Run Static Analysis & Tests**:
   ```powershell
   flutter analyze lib/
   flutter test test/features/game_zone/ test/features/tour_group/
   ```
3. **Format Code (MANDATORY)**:
   CI enforces strict `dart format`. Always format before committing:
   ```powershell
   dart format .
   ```

---

## 2. Version Bump Invariant

Bhromon releases require strictly monotonic version and version code increments in `pubspec.yaml`.

- Inspect the current version in `pubspec.yaml` (e.g., `1.8.84+138`).
- Increment the patch version and build number (e.g., `1.8.85+139`).
- Commit the version bump on a dedicated branch (e.g. `chore/bump-v1.8.85+139` or `release/1.8.85+139`).

---

## 3. GitHub PR Workflow (MANDATORY)

**Never push directly to `main` on GitHub.** Always use a pull request:

1. Create and switch to a release or feature branch:
   ```powershell
   git checkout -b release/1.8.85+139
   git add pubspec.yaml
   git commit -m "chore(release): bump version to 1.8.85+139"
   git push -u origin release/1.8.85+139
   ```
2. Open a Pull Request:
   ```powershell
   gh pr create --base main --title "chore(release): bump version to 1.8.85+139" --body "Monotonic version bump for release 1.8.85+139."
   ```
3. Merge via squash and admin override (once CI passes):
   ```powershell
   gh pr merge --squash --delete-branch --admin
   git checkout main
   git pull origin main
   ```

---

## 4. Flutter Web Deployment

Deploy the web application to Firebase Hosting:

1. Build release web bundle:
   ```powershell
   flutter build web --release
   ```
2. Deploy to Firebase Hosting:
   ```powershell
   firebase deploy --only hosting
   ```
3. Verify live deployment:
   ```powershell
   curl.exe -I https://app.bhromon.fun
   ```
   Must return `HTTP/2 200` or `HTTP/1.1 200 OK`.

---

## 5. Android Native Builds & Windows Invariants

### A. Preventing Windows Gradle Directory Locks
On Windows, file locking during native symbol table extraction or native lib merging can trigger `AccessDeniedException`.
Before building release APK or AAB:
1. Ensure `android/gradle.properties` contains `org.gradle.vfs.watch=false`.
2. Stop lingering Java/Gradle background daemons:
   ```powershell
   Stop-Process -Name java -Force -ErrorAction SilentlyContinue
   ```
3. Clean locked intermediate directories if locks persist:
   ```powershell
   Remove-Item -Recurse -Force build\app\intermediates -ErrorAction SilentlyContinue
   ```

### B. Building Signed Release APK
1. Build release APK:
   ```powershell
   flutter build apk --release
   ```
2. Verify output file exists:
   `build\app\outputs\flutter-apk\app-release.apk` (~168 MB).

### C. Building Play Store App Bundle (AAB)
1. Build release AAB:
   ```powershell
   flutter build appbundle --release
   ```
2. Verify output bundle exists:
   `build\app\outputs\bundle\release\app-release.aab` (~130 MB).

---

## 6. Hostinger VPS APK Deployment

Hostinger VPS hosts release downloads for direct mobile installation and update checking.

### A. Legacy SCP Protocol (`-O` Flag) Invariant
Newer Windows OpenSSH clients (OpenSSH 9.0+) default to the SFTP subsystem. The Hostinger VPS SSH server disables the SFTP subsystem (`subsystem request failed on channel 0`).
**Always specify `-O` (legacy SCP protocol)** and port `2222`:

```powershell
scp -O -P 2222 -i $env:USERPROFILE\.ssh\id_rsa_dbm -o StrictHostKeyChecking=no build\app\outputs\flutter-apk\app-release.apk root@148.135.137.245:/var/www/bhromon/downloads/app-release.apk
```

### B. Storage Recovery, Deduplication & Permissions
To prevent VPS disk bloat, **never retain previous versions** of APKs or AABs:
1. Delete all older APK files from `/var/www/bhromon/downloads/`.
2. Keep only the single latest version file as `bhromon-latest.apk`.
3. Use hardlinks (`ln -f`) for aliases (`app-release.apk`, `Bhromon_Release.apk`, and versioned tag `bhromon-v<version>.apk`) so all download links work without consuming duplicate disk space.
4. Keep the directory at `755` and files at `644` with `www-data:www-data` ownership.
- `/var/www/bhromon-media/apk/app-release.apk` is a symlink pointing to `/var/www/bhromon/downloads/app-release.apk`.

Execute via SSH:
```powershell
ssh -p 2222 -i $env:USERPROFILE\.ssh\id_rsa_dbm -o StrictHostKeyChecking=no root@148.135.137.245 '
cd /var/www/bhromon/downloads
find . -maxdepth 1 -name "bhromon-*.apk" ! -name "bhromon-latest.apk" ! -name "bhromon-v1.8.149+203.apk" -delete
ln -f app-release.apk bhromon-latest.apk
ln -f app-release.apk Bhromon_Release.apk
ln -f app-release.apk bhromon-v1.8.149+203.apk
chmod 755 /var/www/bhromon/downloads
chmod 644 /var/www/bhromon/downloads/*.apk
chown www-data:www-data /var/www/bhromon/downloads/*.apk
'
```

### C. Verify Download URL
Check headers on the public endpoint:
```powershell
curl.exe -I https://bhromon.fun/media/apk/app-release.apk
```
Ensure `HTTP/1.1 200 OK` with valid `Content-Length`.
