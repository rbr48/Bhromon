---
name: bhromon-official-feed
description: >-
  Manage, publish, and maintain the Bhromon Official Feed. Use this skill when
  working on official feed features, publishing reels or photos from the app,
  handling adaptive letterboxing, or maintaining official feed UI components.
---

# Bhromon Official Feed Playbook

This skill covers the architecture, administrative controls, UI guidelines, and publishing procedures for the **Bhromon Official Feed** (`lib/features/official_feed`).

---

## 1. Overview & Identity

- **Name**: Strictly **`Bhromon Official Feed`** (translated as `'Bhromon Official Feed'` in both English and Bengali locales).
- **Presentation**: Entry cards in group hub must remain clean and decluttered. Never display unnecessary subtitle body text (`official_feed_card_body` is deprecated and excluded from `OfficialFeedEntryCard`).
- **Prompt Title**: `"Follow Bhromon Official Feed?"` (`"Bhromon Official Feed অনুসরণ করবেন?"`).

---

## 2. Administrative Authorization

- **Authorized Administrator**: `rajbrur@gmail.com`.
- Defined in code via `kOfficialFeedAdminEmail` / `isOfficialAdmin(email)`.
- When signed in with `rajbrur@gmail.com`, an administrative action bar / floating action button appears on `OfficialFeedScreen` allowing direct in-app publishing of reels (videos) and photos.
- Writes from non-admin accounts or direct client tampering are strictly blocked by Firestore security rules (`official_instafeed` collection rules) and media server token validation.

---

## 3. Media Invariants: Adaptive Letterboxing

### A. Preventing Forced Landscape-to-Portrait Distortions
Reels and photos published to the official feed may be shot in either portrait (vertical 9:16) or landscape (horizontal 16:9 / 4:3).
- **Rule**: Never force or crop landscape media into a portrait aspect ratio.
- **Implementation**:
  - `_CoverImageAdaptive` detects intrinsic image aspect ratios. If an image is landscape, it scales to fit inside the viewport with clean, subtle letterbox pillarboxing (`BoxFit.contain`).
  - `_OfficialReelPlayer` centers video playback within its natural aspect ratio.
  - Video controllers adjust letterboxing adaptively rather than using `BoxFit.cover` which would clip the sides of widescreen videos.

---

## 4. In-App Publishing Flow

When `rajbrur@gmail.com` publishes via the app:
1. Tap the add icon on `OfficialFeedScreen`.
2. Choose between **Video Reel** or **Photo**.
3. For Video:
   - File picker selects video.
   - Video thumbnail generated locally on device via `VideoCompress.getFileThumbnail`.
   - Title and optional description entered.
   - Uploaded through `TourMediaUploader` into `/media/official/`.
4. For Photo:
   - System Photo Picker selects image.
   - Title and description entered.
   - Uploaded to `/media/official/`.
5. Post document created in `official_feed` Firestore collection with `createdAt = FieldValue.serverTimestamp()`.
6. Cloud Functions / Media Server dispatches FCM push notification to subscribers on topic `official_instafeed`.

---

## 5. Testing & Verification

Unit and widget tests for official feed reside in:
- `test/features/official_feed/official_feed_screen_test.dart`
- `test/features/official_feed/official_feed_prompt_test.dart`

Run official feed tests:
```powershell
flutter test test/features/official_feed/
```
Ensure all 23+ tests pass.
