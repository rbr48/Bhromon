# Privacy Policy for Bhromon

**Last Updated: October 28, 2026**

Welcome to **Bhromon** (the "App" and "Platform"). Bhromon is an all-in-one universal travel companion, group tour ledger, and community platform owned and operated by **Bhromon Technologies Ltd.** ("we," "our," or "us"). 

We are deeply committed to protecting your personal privacy and safeguarding your data. Bhromon is built on privacy-first and open-source principles: **we do not sell your personal data, we do not show third-party ads, and we do not track you across other applications or services.**

This Privacy Policy explains how we collect, use, disclose, and protect your information when you use our mobile application (Android), our Progressive Web App (https://app.bhromon.fun), and our landing website (https://bhromon.fun).

---

## 1. Information We Collect

### A. Location Data
Location services power our Universal Tour Engine, multi-stop route roadmaps, and emergency response features:
* **Foreground Location (GPS)**: When the App is in use, we access your device's precise coordinates to display your position on the map, verify tour checkpoint arrivals, and calculate distances along travel legs.
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
* **Group Memberships & Roles**: Tour group relationships (`owner`, `admin`, `member`) are stored securely to govern channel access, ledger permissions, and itinerary editing rights.

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
* **With Your Tour Group Members**: Itinerary updates, shared ledger expenses, vehicle seat bookings, and feed posts are visible only to fellow active members of that specific tour group.
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

You maintain complete ownership and control of your personal data:
* **Account Deletion**: You can request immediate and permanent deletion of your account from within App Settings or by emailing us.
* **Media & Post Deletion**: You can delete any of your photos, reels, or channel messages at any time; deleted media is permanently removed from our storage server.
* **Tour Data Portability**: Tour ledger reports can be exported directly to standard CSV format at any time.

---

## 7. Children's Privacy

Bhromon does not knowingly collect personally identifiable information from children under the age of 13. If you believe a child under 13 has provided personal data without parental consent, please contact us immediately, and we will purge the account and associated records.

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
