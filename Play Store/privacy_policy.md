# Privacy Policy for Bhromon

**Last Updated: October 31, 2026**

Welcome to **Bhromon** (the "App" and "Platform"). Bhromon is an all-in-one universal travel companion, group tour ledger, and community platform owned and operated by **Bhromon Technologies Ltd.** ("we," "our," or "us"). 

We are deeply committed to protecting your personal privacy and safeguarding your data. Bhromon is built on privacy-first and open-source principles: **we do not sell your personal data, we do not show third-party ads, and we do not track you across other applications or services.**

This Privacy Policy explains how we collect, use, disclose, and protect your information when you use our mobile application (Android), our Progressive Web App (https://app.bhromon.fun), and our landing website (https://bhromon.fun).

---

## 1. Information We Collect

### A. Location Data
Location services power our Universal Tour Engine, multi-stop route roadmaps, and emergency response features:
* **Zero Background Tracking**: Bhromon never requests or performs background location tracking. Your location is never tracked while the app is in the background or closed.
* **Foreground Location (GPS)**: Only when the App is actively in use, we access your device's precise coordinates to display your position on the map, verify tour checkpoint arrivals, and calculate distances along travel legs.
* **Emergency SOS Location**: When you activate the emergency SOS siren in the Family Safety Hub, your approximate or precise GPS coordinates are included with the alert broadcast to other members of your active tour group.
* **User Control**: Location access is strictly opt-in. You can enable or disable location services at any time via device settings. Map browsing, group ledgers, voice channels, and offline features remain accessible even without GPS permissions.

### B. Photo & Video Picker (Android 14/15/16 Compliance)
* **Zero Broad Storage Access**: We do **not** request or utilize broad device storage permissions (`READ_MEDIA_IMAGES` or `READ_MEDIA_VIDEO`).
* **System Photo Picker**: In accordance with modern Google Play safety standards (Target SDK 36), media selection operates through the native Android System Photo Picker (`image_picker` / system contract). Bhromon only accesses the specific images or videos you explicitly select to share in your tour feed, reels, or group channels.

### C. Real-Time Communications (Voice & Video)
* **WebRTC Voice Lounges & Calls**: Bhromon provides peer-to-peer and group voice lounges and 1-on-1 audio/video calls using WebRTC.
* **Zero Voice Recording or Surveillance**: Voice and video streams are transmitted encrypted end-to-end (DTLS-SRTP) through our STUN/TURN infrastructure (Coturn). **We do not record, monitor, wiretap, or store any audio or video conversations on our servers.**
* **Microphone & Camera Permissions**: Accessed solely when you join a voice channel or initiate an audio/video call.

### D. Newspaper Hub & AdBlock Reader
* **Zero Browsing Tracking**: The in-app Smart Newspaper reader uses client-side network blocking (filtering ad networks and trackers) and cosmetic DOM filtering for distraction-free reading of public Bangladesh news outlets.
* **Local Processing**: We do not collect, log, or sell your reading history, clicked articles, or bookmarks. Text-to-Speech (TTS) runs entirely locally on your device.

### E. Account & Profile Information
* **Authentication Data**: When you register or sign in via Firebase Auth (Email/Password or Google Sign-In), we store your email address, display name, and avatar image.
* **Group Memberships & Roles**: Each tour you join stores your name, email, photo, role (`owner`, `admin`, `member`), family size, and the user ID that lets members of that tour chat and call you. Roles govern channel access, ledger permissions, and itinerary editing rights.

### F. Local Database & Offline Relational Storage
* **Drift (SQLite) & Hive**: Your tour itineraries, checklists, bus seat selections, hotel room assignments, and offline drafts are stored locally on your device using encrypted Drift SQLite and Hive boxes.
* **Local Caches**: Point-of-interest details, offline maps, and language preferences (`app_prefs`) are maintained locally so the app remains fully functional in remote hill tracts or riverine areas without cell coverage.

---

## 2. How We Use Your Information

We utilize collected data strictly for operational, safety, and coordination purposes:
1. **Universal Tour Planning**: Computing dynamic itineraries, stops, and highway waypoint checkpoints.
2. **Multi-Family Group Ledger**: Calculating shared tour expenses, family-weighted splits, and settle-up payment matrices down to integer paisa precision.
3. **Family Safety & SOS Alerts**: Sending high-priority push notifications and in-app banners to group members when an SOS siren is sounded.
4. **Offline Synchronization**: Queuing offline ledger entries, checklist updates, and seat bookings locally, securely synchronizing with Firebase Firestore once connectivity is restored.
5. **Dedicated Media Streaming**: Hosting uploaded trip photos and video reels on our dedicated media microservice (`https://bhromon.fun/api/media/`) using token-authenticated access.
6. **Community Integrity**: Enforcing tour group membership rules and preventing spam or unauthorized modifications.
7. **Notices & Reminders**: Delivering group notices to members, a reminder 30 minutes before a timed notice, and push alerts for chat messages, calls, and SOS alerts. You can turn push notifications off in your device settings.

---

## 3. Dedicated VPS Media Storage & Cloud Architecture

To protect user privacy and avoid third-party data tracking:
* **Self-Hosted VPS Media Storage**: Images and video reels are stored in an isolated Docker container on our dedicated VPS (`bhromon-media-app`), served over encrypted HTTPS with HTTP/2 Range Request streaming.
* **Token Authentication**: Every media upload and deletion request requires an active Firebase ID token verifying the user's membership in the associated tour group.
* **Automatic Orphan Sweep**: Unlinked or discarded media uploads older than 30 minutes are automatically swept and permanently erased from the server.
* **Google Firebase & Cloud Functions**: Profile metadata, encrypted chat channels, and Firestore security rules reside on Google Cloud infrastructure adhering to ISO/IEC 27001 and SOC 2 certifications.

---

## 4. Data Sharing and Disclosure

**We do NOT sell, lease, monetize, or trade your personal data.** Data is only shared in the following scenarios:
* **With Your Tour Group Members**: Posts, photos, chat, notices, ledger entries, and vehicle or room bookings are visible only to the active members of that tour. You can start a chat or a call only with a member of a tour you both belong to. Bhromon has no public profiles, no directory of users, and no search for people outside your tours.
* **Push Notifications**: Emergency SOS alerts and important channel notifications are routed through Firebase Cloud Messaging (FCM).
* **Legal Compliance**: We may disclose information only if required by valid court order or applicable law in Bangladesh.

---

## 5. Data Security

We implement enterprise-grade security practices across our platform:
* **HTTPS & TLS 1.3**: All communication between client applications, VPS media services, and Cloud APIs is encrypted in transit.
* **DTLS-SRTP Encryption**: Real-time WebRTC audio and video packets are encrypted peer-to-peer.
* **Firestore Security Rules**: Role-based access control enforces that only verified tour members can view or participate in a trip's data.
* **Local Storage Protection**: Local app storage is sandboxed within the operating system's secure container.

---

## 6. Your Rights & Data Deletion

You control your data:
* **Leaving a tour**: When you leave a tour, or an admin removes you, your posts, stories, highlights, comments, chat messages, live locations, luggage, and seat selections are permanently deleted, together with your photos and videos on our media server. You are also taken out of other members' likes, votes, reactions, and mentions. Shared records such as the ledger and notices keep their amounts and dates, and your name is replaced with a stand-in name.
* **Tours you own**: When you close your account, ownership of each tour you own passes to an admin, or else to the longest-standing member. If no one else is in a tour, the tour and everything in it is deleted.
* **Deleting a tour**: The owner can delete a tour. Everything in it is deleted, including its photos and videos.
* **Closing your account**: You can permanently delete your account from App Settings, or by emailing us. This removes your profile, your sign-in account, your device notification tokens, your trip logs, pins, follows, likes and visits, your files in our storage and on our media server (including photos and voice notes you sent in chats), your calls, your content in every tour as described above, and the messages you sent in direct chats. Those messages are removed from the conversation on our servers. A copy a recipient already saved on their own device is outside our control. Two kinds of record are kept: an audit record that an account was deleted, which includes the account's ID (kept for up to two years), and anti-abuse trust records (kept for up to one year).
* **Media removal**: Deleted photos and videos are removed from our media server. Copies held by our content-delivery network may remain for a short time until they expire.
* **Unfinished uploads**: Uploads that were never attached to a post or story are removed automatically after 30 minutes.
* **Data portability**: A tour's full record can be exported as a PDF by its owner or an admin. Ledger reports can be exported as CSV.

---

## 7. Families & Children's Privacy

Bhromon is built for families. A family circle is a private tour group: only its members see its photos, chat, notices, games, and ledger. A parent or guardian should create the circle, decide who is invited, and manage its members.
* **Children's photos**: Photos and videos of children are visible only to the members of the group they were shared in. Only the group's owner or an admin can export the group's complete record, including its photos, as a PDF.
* **What members can still do**: Members can see the photos in their group. The app has no button that saves other members' photos to a device, but a screenshot can always be taken, and scrapbook pages can be shared through the device's share menu. Please share with care.
* **Consent and age**: Bhromon does not knowingly collect personal information from children under 13 without a parent's or guardian's consent. A parent or guardian who has concerns can ask us to remove a child's content or account, and we will do so.

---

## 8. Free & Open Source Status

Bhromon is free and open-source software (FOSS). There are no advertisements, paid subscriptions, microtransactions, or data brokers involved in any part of our service.

---

## 9. Changes to This Policy

We may update this Privacy Policy periodically to reflect technological updates or legal requirements. Material updates will be highlighted on our website and in the app with an updated "Last Updated" date.

---

## 10. Contact Us

If you have any questions, inquiries, or privacy requests, please reach out to us:
* **Company**: Bhromon Technologies Ltd.
* **Email**: info@bhromon.fun / mybhromon@gmail.com
* **WhatsApp**: +880 1762 033445
* **Website**: https://bhromon.fun
* **Web App**: https://app.bhromon.fun
* **GitHub Repository**: https://github.com/rbr48/Bhromon
