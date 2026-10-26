# Bhromon Chat: WhatsApp-Grade Parity Master Roadmap & Implementation Plan

This document serves as the comprehensive, engineering-grade execution plan to transform **Bhromon's Chat and Calling subsystem** (`lib/features/chat/`, WebRTC calling, and `lib/features/tour_group/`) into a high-performance, offline-first, production-grade messaging platform with full WhatsApp parity and travel-centric superpowers.

---

## 1. Architectural Target Blueprint

```mermaid
flowchart TD
    subgraph Client Application Layer
        UI[Presentation Widgets: ChatScreen, ChatsListScreen, CallScreen]
        BLOC[ChatCubit / CallCubit / CallKitHandler]
        DRIFT[(Drift SQLite: AppDatabase)]
        FTS[SQLite FTS5 Full-Text Search]
        OUTBOX[SyncOutboxTable & Queue Worker]
    end

    subgraph Transport & Sync Layer
        FCM[Firebase Cloud Messaging Background Data Worker]
        GRPC[Firestore gRPC Client Stream /chats/{chatId}]
        MEDIA_SYNC[VPS Media Uploader /var/www/bhromon-media]
        SIGNAL[WebRTC Signaling Service]
    end

    subgraph Backend & Infrastructure
        RULES[Hardened Firestore Rules]
        FUNCTIONS[Firebase Cloud Functions / FCM Push Relay]
        COTURN[Coturn STUN/TURN on Hostinger VPS 148.135.137.245]
        GEMINI[Gemini 1.5 Flash AI Travel Engine]
    end

    UI --> BLOC
    BLOC --> DRIFT
    DRIFT --> FTS
    BLOC --> OUTBOX
    OUTBOX -->|Optimistic Write + Sequential Sync| GRPC
    GRPC --> RULES
    RULES --> FUNCTIONS
    FUNCTIONS --> FCM
    FCM -->|Silent Receipt ACK & CallKit Wakeup| BLOC
    BLOC --> SIGNAL
    SIGNAL --> COTURN
    BLOC --> MEDIA_SYNC
    BLOC --> GEMINI
```

---

## 2. Phased Execution Roadmap Overview

```
ROADMAP PHASING
┌────────────────────────────────────────────────────────────────────────┐
│ Phase 0: Critical Bug Fixes & Security Hardening (P0 - Immediate)      │
│ ├─ Firestore Rule Message Deletion Fix (Tombstone + deletedFor)        │
│ ├─ WebRTC Signaling Security Isolation (caller/callee auth)           │
│ ├─ Top-Level App Incoming Call Listener (Listen everywhere)           │
│ └─ Coturn STUN/TURN Server Deployment on VPS (Carrier NAT fix)         │
├────────────────────────────────────────────────────────────────────────┤
│ Phase 1: Performance & Billing Optimization (P1)                       │
│ ├─ Metadata Denormalization (Eliminate 150-stream read explosion)      │
│ ├─ Single-stream ChatsListScreen Refactor                              │
│ ├─ Real Gemini 1.5 Flash AI Travel Advisor Integration                 │
│ └─ Activation of Dead UI Buttons (Media Share, Chat Menu)              │
├────────────────────────────────────────────────────────────────────────┤
│ Phase 2: Offline-First Engine (Drift SQLite Integration) (P1)          │
│ ├─ ChatsTable, ChatMessagesTable, and FTS5 in Drift                    │
│ ├─ Local-first optimistic message dispatch & Outbox queue              │
│ ├─ True 4-state delivery receipt lifecycle (Clock → 1✓ → 2✓ → 2✓ blue)  │
│ └─ Instant in-memory / local SQLite search                             │
├────────────────────────────────────────────────────────────────────────┤
│ Phase 3: Core Messaging UX Parity (P2)                                 │
│ ├─ Swipe-to-Reply & Quoted Message Preview with scroll jump            │
│ ├─ Message Editing (15-min window, (edited) label)                     │
│ ├─ Emoji Reactions (6 quick emojis + full picker + participant modal)  │
│ ├─ Message Pinning (24h/7d/30d sticky header) & Starred Messages       │
│ ├─ Message Forwarding Engine (up to 5 chats with anti-spam label)      │
│ └─ Multi-Select Action Bar (Bulk Copy, Delete, Forward, Star)          │
├────────────────────────────────────────────────────────────────────────┤
│ Phase 4: Media, Documents & Voice Messaging (P2)                       │
│ ├─ Extended Attachments: Docs (PDF/ZIP), Location, vCards, Audio      │
│ ├─ Multi-Media Picker (up to 30 items) + Media Captions                │
│ ├─ In-App Media Editor (Crop, 90° rotate, brush doodle, text)          │
│ ├─ True Audio Decibel Waveforms & Pause/Resume Recording               │
│ └─ Proximity Sensor Integration (Earpiece mode) & Continuous Playback  │
├────────────────────────────────────────────────────────────────────────┤
│ Phase 5: Telephony & VoIP Integration (P2/P3)                          │
│ ├─ flutter_callkit_incoming (Lockscreen native incoming call UI)       │
│ ├─ High-priority FCM VoIP push background wakeup                       │
│ ├─ Dedicated Calls Tab & Call History Log (Incoming/Outgoing/Missed)   │
│ └─ In-Call Audio Routing & Reconnecting recovery banner                │
├────────────────────────────────────────────────────────────────────────┤
│ Phase 6: Privacy, Ephemerality & Security (P3)                         │
│ ├─ Disappearing Messages (24h/7d/90d timer with TTL)                   │
│ ├─ View Once Media with screenshot blocking                            │
│ ├─ Biometric Chat Lock (Hidden Locked Chats folder)                    │
│ └─ Granular Privacy Controls (Read Receipts, Online, Last Seen)        │
├────────────────────────────────────────────────────────────────────────┤
│ Phase 7: Travel Superpowers & Tour Group Synergy (P3)                  │
│ ├─ Port /split expense ledger slash command into 1-on-1 chats          │
│ ├─ Live Itinerary Stop sharing & Route Checkpoint Drops                │
│ └─ Bus Seat & Hotel Room Badges across all direct conversations        │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Detailed Phase-by-Phase Technical Implementation Plan

### Phase 0: Critical Bug Fixes & Security Hardening (P0 - Immediate)

#### Task 0.1: Fix Message Deletion & Tombstoning in Firestore Rules
- **Problem**: In [`chat_screen.dart` L964-L1005](file:///d:/Software_and_Apps/Apps/Bhromon/lib/features/chat/presentation/pages/chat_screen.dart#L964-L1005), calling `.delete()` throws `permission-denied` because [`firestore.rules` L370](file:///d:/Software_and_Apps/Apps/Bhromon/firestore.rules#L370) has `allow delete: if false;`. Also, updating `deletedFor` fails because `affectedKeys()` rejects it and blocks the sender.
- **Implementation**:
  1. Update [`firestore.rules`](file:///d:/Software_and_Apps/Apps/Bhromon/firestore.rules) under `match /chats/{chatId}/messages/{messageId}`:
     ```firestore
     allow update: if isParticipant()
                   && (
                     // Recipient marking seen / delivery
                     (request.resource.data.diff(resource.data).affectedKeys().hasOnly(['seen', 'status', 'deliveredAt', 'readAt'])
                      && request.auth.uid != resource.data.senderId)
                     // Participant deleting for themselves
                     || (request.resource.data.diff(resource.data).affectedKeys().hasOnly(['deletedFor'])
                         && request.auth.uid in request.resource.data.deletedFor)
                     // Sender tombstoning "Delete for Everyone" within 60 hours
                     || (request.auth.uid == resource.data.senderId
                         && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['type', 'text', 'isDeleted', 'deletedAt'])
                         && request.resource.data.type == 'deleted'
                         && request.time < resource.data.timestamp + duration.value(60, 'h'))
                   );
     ```
  2. In [`chat_screen.dart`](file:///d:/Software_and_Apps/Apps/Bhromon/lib/features/chat/presentation/pages/chat_screen.dart), update `_showDeleteDialog`:
     - "Delete for Me": appends `currentUid` to `deletedFor` array.
     - "Delete for Everyone": updates message with `type: 'deleted'`, `text: 'This message was deleted'`, `isDeleted: true`.
  3. Update UI message bubble rendering to show an italicized grey tombstone icon and "🚫 *This message was deleted*".

#### Task 0.2: WebRTC Signaling Security Isolation
- **Problem**: [`firestore.rules` L375](file:///d:/Software_and_Apps/Apps/Bhromon/firestore.rules#L375) allows any authenticated user to read and write any call in `/calls/{callId}`.
- **Implementation**:
  1. Patch `firestore.rules`:
     ```firestore
     match /calls/{callId} {
       function isCallParticipant() {
         return isAuth() && (
           request.auth.uid == resource.data.callerId ||
           request.auth.uid == resource.data.calleeId ||
           (resource == null && (request.auth.uid == request.resource.data.callerId || request.auth.uid == request.resource.data.calleeId))
         );
       }
       allow read, write: if isCallParticipant();
       match /{allSubcollections=**} {
         allow read, write: if isAuth();
       }
     }
     ```

#### Task 0.3: Move WebRTC Incoming Call Listener to App/Shell Root
- **Problem**: Currently mounted in `_ChatScreenState` (L803). Calls never ring if the user is on the home screen, exploring tours, playing games, or on the feed.
- **Implementation**:
  1. Create a singleton `CallNotificationService` (`lib/features/chat/data/call_notification_service.dart`).
  2. Initialize the listener in `HomeShell` or `AppLifecycleListener` using `FirebaseAuth.instance.authStateChanges()`.
  3. When an incoming call arrives with `status == 'calling'`, show a global floating call heads-up banner or route to `CallScreen` with ringtone audio.

#### Task 0.4: Deploy & Configure Coturn TURN Server on Hostinger VPS
- **Problem**: P2P STUN-only WebRTC fails across cellular carrier CGNATs (Grameenphone, Banglalink, Robi) and symmetric firewalls.
- **Implementation**:
  1. Deploy `coturn` Docker container on the Hostinger VPS (`148.135.137.245`):
     ```bash
     docker run -d --name coturn --net=host \
       -v /etc/coturn/turnserver.conf:/etc/coturn/turnserver.conf \
       coturn/coturn
     ```
  2. Configure `turnserver.conf` with static-auth-secret, realm `turn.bhromon.fun`, listening port `3478`, and TLS port `5349`.
  3. In [`call_signaling_service.dart` L32-L39](file:///d:/Software_and_Apps/Apps/Bhromon/lib/features/chat/data/call_signaling_service.dart#L32-L39), inject both Google STUN and Bhromon TURN credentials:
     ```dart
     static const Map<String, dynamic> _iceConfig = {
       'iceServers': [
         {'urls': ['stun:stun.l.google.com:19302']},
         {
           'urls': ['turn:148.135.137.245:3478?transport=udp', 'turn:148.135.137.245:3478?transport=tcp'],
           'username': 'bhromon_guest',
           'credential': 'TURN_PASSWORD_SECRET',
         },
       ],
       'sdpSemantics': 'unified-plan',
     };
     ```

---

### Phase 1: Performance & Billing Optimization (P1)

#### Task 1.1: Denormalize Chat Document Metadata
- **Problem**: `ChatsListScreen` instantiates 3 independent streams per chat tile (150 live queries for 50 chats).
- **Implementation**:
  1. Evolve the `/chats/{chatId}` Firestore document schema:
     ```json
     {
       "participants": ["uid1", "uid2"],
       "participantDetails": {
         "uid1": {"name": "Rahim", "avatar": "https://..."},
         "uid2": {"name": "Karim", "avatar": "https://..."}
       },
       "lastMessage": "Sounds great! See you in Cox's Bazar.",
       "lastMessageType": "text",
       "lastMessageSenderId": "uid1",
       "lastMessageTime": "2026-10-26T10:00:00Z",
       "unreadCounts": {
         "uid1": 0,
         "uid2": 3
       }
     }
     ```
  2. On every message dispatch in `chat_screen.dart`, atomically increment `unreadCounts.<recipientUid>` via `FieldValue.increment(1)` and reset to `0` when recipient opens the chat.

#### Task 1.2: Refactor `ChatsListScreen` to a Single Firestore Stream
- **Implementation**:
  1. Replace `_ChatTileState` sub-queries with the denormalized data already present in the parent document.
  2. `ChatsListScreen` now listens to a **single query**:
     ```dart
     FirebaseFirestore.instance
         .collection('chats')
         .where('participants', arrayContains: currentUid)
         .orderBy('lastMessageTime', descending: true)
         .snapshots();
     ```
  3. Eliminates 149 out of 150 live streams, reducing Firestore reads by **95%** and eliminating scroll stutter.

#### Task 1.3: Real Gemini 1.5 Flash AI Travel Advisor Integration
- **Problem**: `_generateAiReply` uses 12 hardcoded substring checks inside the UI file.
- **Implementation**:
  1. Create `TravelAiService` (`lib/features/chat/data/travel_ai_service.dart`).
  2. Call Gemini API (`gemini-1.5-flash`) with structured system prompts containing Bangladesh destination databases (Cox's Bazar, Sajek, Bandarban, Sylhet, Sreemangal, Sundarbans).
  3. Stream AI responses in real-time with typing indicator animation in `ChatScreen`.

#### Task 1.4: Wire Dead UI Stubs
- **Implementation**:
  1. In [`full_screen_media_viewer.dart` L126](file:///d:/Software_and_Apps/Apps/Bhromon/lib/features/chat/presentation/pages/full_screen_media_viewer.dart#L126), wire `share_plus` to export or share the cached image/video file.
  2. Add "Save to Gallery" button using `gal` or image saving utility.
  3. In [`chats_list_screen.dart` L76-L82](file:///d:/Software_and_Apps/Apps/Bhromon/lib/features/chat/presentation/pages/chats_list_screen.dart#L76-L82), wire Camera icon to quick-capture mode and Menu icon to "New Chat", "Starred Messages", and "Settings".

---

### Phase 2: Offline-First Engine (Drift SQLite Integration) (P1)

#### Task 2.1: Add Chat Tables & FTS5 Index to Drift Database
- **Implementation**:
  1. In [`lib/core/database/app_database.dart`](file:///d:/Software_and_Apps/Apps/Bhromon/lib/core/database/app_database.dart), declare:
     ```dart
     class ChatsTable extends Table {
       TextColumn get chatId => text()();
       TextColumn get participants => text()(); // JSON list
       TextColumn get lastMessage => text().nullable()();
       TextColumn get lastMessageSenderId => text().nullable()();
       IntColumn get lastMessageTime => integer().nullable()(); // epoch ms
       IntColumn get unreadCount => integer().withDefault(const Constant(0))();
       TextColumn get otherUserName => text().nullable()();
       TextColumn get otherUserAvatar => text().nullable()();
       BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
       BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
       @override
       Set<Column> get primaryKey => {chatId};
     }

     class ChatMessagesTable extends Table {
       TextColumn get messageId => text()();
       TextColumn get chatId => text()();
       TextColumn get senderId => text()();
       TextColumn get type => text()(); // text, image, video, audio, doc, location
       TextColumn get text => text().nullable()();
       TextColumn get mediaUrl => text().nullable()();
       TextColumn get localFilePath => text().nullable()();
       IntColumn get timestamp => integer()(); // epoch ms
       TextColumn get status => text()(); // pending, sent, delivered, read
       TextColumn get replyToMessageId => text().nullable()();
       TextColumn get replyToSnippet => text().nullable()();
       BoolColumn get isStarred => boolean().withDefault(const Constant(false))();
       BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
       TextColumn get reactionsJson => text().nullable()();
       @override
       Set<Column> get primaryKey => {messageId};
     }
     ```
  2. Increment Drift `schemaVersion` to `5` with migration scripts.

#### Task 2.2: Local-First Dispatch & Outbox Synchronization
- **Implementation**:
  1. When user taps Send:
     - Generate a local UUID `messageId`.
     - Write message immediately into Drift `ChatMessagesTable` with `status: 'pending'`.
     - Message bubble appears instantly with a clock icon (0 ms latency).
     - Enqueue task in `SyncOutboxTable`.
  2. Sync worker flushes outbox to Firestore. Once written:
     - Update local status to `'sent'` (single grey tick).
  3. When recipient's background ACK arrives via FCM or Firestore listener:
     - Update status to `'delivered'` (double grey ticks).
  4. When recipient views message:
     - Update status to `'read'` (double blue ticks).

#### Task 2.3: Offline SQLite Full-Text Search (FTS5)
- **Implementation**:
  1. Add an SQLite FTS5 virtual table indexing `text` in `ChatMessagesTable`.
  2. In `ChatsListScreen` search bar, execute local SQL `MATCH` query:
     - Instant search across millions of words with zero network requests.

---

### Phase 3: Core Messaging UX Parity (P2)

#### Task 3.1: Swipe-to-Reply & Quoted Message Preview
- **Implementation**:
  1. Wrap chat bubbles with a horizontal `Dismissible` or `GestureDetector` that springs back on release.
  2. On trigger, set `_replyingToMessage` state.
  3. Show a WhatsApp-styled preview card above the input bar:
     - Colored left vertical bar, sender name, text snippet/media thumbnail, and a close button.
  4. When sending, attach `replyToId`, `replyToSender`, and `replyToSnippet` to the payload.
  5. Render quote preview block inside the message bubble; tapping it invokes `_scrollController.animateTo` to smoothly highlight the original message.

#### Task 3.2: Message Editing
- **Implementation**:
  1. Allow editing within 15 minutes of sending for author's messages.
  2. Long press $\rightarrow$ "Edit" populates the input bar with current text.
  3. On submit, update Firestore document:
     ```json
     {"text": "Updated text", "isEdited": true, "editedAt": FieldValue.serverTimestamp()}
     ```
  4. Message bubble renders an inline grey "(edited)" label next to the timestamp.

#### Task 3.3: Emoji Reactions
- **Implementation**:
  1. Long press message bubble displays WhatsApp horizontal emoji overlay: `👍 ❤️ 😂 😮 😢 🙏 ➕`.
  2. Tapping emoji updates `reactions.<uid>` in Firestore using `FieldPath`:
     ```dart
     msgRef.update({'reactions.$currentUid': emoji});
     ```
  3. Floating reaction pill displayed at bottom-right of message bubble.
  4. Tapping pill opens a bottom sheet showing which participants reacted with which emoji.

#### Task 3.4: Message Pinning & Starred Messages
- **Implementation**:
  1. Pin option in message menu: select duration (24 Hours, 7 Days, 30 Days).
  2. Pinned message ID saved in `/chats/{chatId}.pinnedMessages`.
  3. Sticky top bar renders the pinned message snippet; tapping it jumps to the message.
  4. Star option toggles `isStarred` in Drift `ChatMessagesTable` and Firestore.
  5. Add `StarredMessagesScreen` to view all bookmarked notes across chats.

#### Task 3.5: Forwarding Engine
- **Implementation**:
  1. "Forward" action opens contact selector modal with recent chats and tour groups.
  2. Selected messages forwarded with `isForwarded: true` (or `forwardingScore > 4` for "Forwarded many times").

#### Task 3.6: In-Chat Search with Next/Prev Scroll
- **Implementation**:
  1. Search icon in `ChatScreen` AppBar opens an in-chat query bar.
  2. Highlights matching text in yellow.
  3. Shows "1 of 12" counter with Up/Down arrow buttons navigating between occurrences.

#### Task 3.7: Multi-Select Action Bar
- **Implementation**:
  1. Long pressing a message initiates selection mode (`_selectedMessageIds.add(id)`).
  2. Replaces AppBar with WhatsApp action bar:
     - Selection count ("2 selected").
     - Actions: Reply (if 1), Star, Forward, Copy, Delete, Info.

---

### Phase 4: Media, Documents & Voice Messaging (P2)

#### Task 4.1: Extended Attachment Sheet
- **Implementation**:
  1. Redesign `_ChatMediaPickerSheet` to 8 circular icons:
     - 📄 **Document**: Pick PDF, DOCX, XLSX, TXT, ZIP up to 100 MB via `file_picker`.
     - 📷 **Camera**: Capture photo or video.
     - 🖼️ **Gallery**: Pick photos & videos with multi-select.
     - 🎵 **Audio**: Pick device audio files.
     - 📍 **Location**: Send live GPS coordinate or Google Maps search pin.
     - 👤 **Contact**: Send vCard (`.vcf`) from device address book.
     - 📊 **Poll**: Create 2–6 option poll (already built in tour group!).
  2. Create specialized bubble renderers:
     - `ChatDocumentBubble`: File extension badge, filename, file size, and download/open button.
     - `ChatLocationBubble`: Google Maps static preview thumbnail with pinpoint and "Open in Maps" button.

#### Task 4.2: In-App Media Editor
- **Implementation**:
  1. Intercept picked photo before upload:
     - 90-degree rotation.
     - Aspect ratio cropping (1:1, 4:3, 16:9, Free).
     - Freehand drawing canvas with color palette.
     - Text overlay with font picker.
  2. Export edited bitmap and upload via `TourMediaUploader` (VPS/Storage).

#### Task 4.3: Media Captions
- **Implementation**:
  1. In the pre-send media preview screen, provide a bottom text field: "Add a caption...".
  2. Store caption in `text` alongside `mediaUrl` in the message document.
  3. Render caption cleanly underneath image/video in the chat bubble.

#### Task 4.4: True Audio Decibel Waveforms & Voice Overhaul
- **Implementation**:
  1. In [`voice_message_recorder.dart`](file:///d:/Software_and_Apps/Apps/Bhromon/lib/features/chat/presentation/widgets/voice_message_recorder.dart):
     - Subscribe to `_recorder.onAmplitudeChanged(const Duration(milliseconds: 100))`.
     - Collect decibel values (`amp.current`) into a normalized list (0.0 to 1.0).
     - Render true responsive waveform bars matching the speaker's vocal inflections.
  2. Add **Pause & Resume** controls during recording.
  3. Add **Playback Preview** modal before sending so user can verify their recording.
  4. In [`voice_message_bubble.dart`](file:///d:/Software_and_Apps/Apps/Bhromon/lib/features/chat/presentation/widgets/voice_message_bubble.dart):
     - Store amplitude list in message JSON; render recorded waveform in the playback bubble.
     - Integrate `proximity_sensor`: when user brings phone to ear, automatically switch audio route from speaker to earpiece and turn screen off (`wakelock`).
     - Auto-advance: when voice note finishes playing, trigger playback on the next sequential voice message automatically.

---

### Phase 5: Telephony & VoIP Integration (P2/P3)

#### Task 5.1: `flutter_callkit_incoming` Integration
- **Implementation**:
  1. Configure `flutter_callkit_incoming` in `MainActivity.kt` and `AppDelegate.swift`.
  2. On receiving incoming call trigger:
     - Display full-screen native system call UI (native ringtone, caller name, avatar, "Accept" and "Decline" buttons).
  3. Handles answering when device is locked or app is terminated.
  4. Answering launches `CallScreen` directly with pre-initialized WebRTC connection.

#### Task 5.2: Dedicated Calls Tab & History
- **Implementation**:
  1. Add "Calls" tab to `ChatsListScreen` bottom navigation.
  2. Query user's `/calls` collection:
     - Display list with caller avatar, name, call type (Audio/Video), timestamp, duration, and green outgoing / red missed arrow icons.
     - Tap tile to instantly redial.

---

### Phase 6: Privacy, Ephemerality & Security (P3)

#### Task 6.1: Disappearing Messages
- **Implementation**:
  1. Chat setting: Disappearing messages (Off, 24 Hours, 7 Days, 90 Days).
  2. Stored in `/chats/{chatId}.disappearingDuration`.
  3. Outgoing messages receive `expiresAt = timestamp + duration`.
  4. Firebase TTL policy or local Drift cleanup job purges expired messages.

#### Task 6.2: View Once Media
- **Implementation**:
  1. Toggle button "①" in media preview screen before sending.
  2. Sets `viewOnce: true`.
  3. Recipient sees a bubble: "① Photo" or "① Video".
  4. Tapping opens viewer with `FLAG_SECURE` enabled (screenshot blocking).
  5. Once closed, message permanently transitions to "Opened" and media file is wiped from cache.

#### Task 6.3: Biometric Chat Lock
- **Implementation**:
  1. "Lock Chat" setting inside contact info using `local_auth` (Fingerprint / FaceID).
  2. Locked chats moved into a hidden "Locked Chats" folder at the top of `ChatsListScreen`.
  3. Folder only appears when pulling down on the chat list and requires biometric authentication to reveal.

---

### Phase 7: Travel Superpowers & Tour Group Synergy (P3)

#### Task 7.1: Port `/split` Expense Ledger to 1-on-1 Chat
- **Implementation**:
  1. Allow two travel buddies chatting 1-on-1 to type `/split 800 CNG Fare`.
  2. Creates an interactive Split Card with "Accept" or "Settled" button.
  3. Tracks personal shared travel debts with automatic balance tallying.

#### Task 7.2: Live Travel Location & Route Drops
- **Implementation**:
  1. Send dynamic itinerary checkpoint pins (e.g., "Alikadam Checkpost", "Marine Drive Stop").
  2. Tapping opens in-app Journey Tracker with live distance and route progress.

---

## 4. Verification, Testing & Quality Gates

| Verification Gate | Validation Method | Acceptance Criteria |
| :--- | :--- | :--- |
| **Firestore Rules Security** | `emulators:exec` with Jest test suite | Deletion tombstoning succeeds; unauthorized call interception fails (100% pass). |
| **Drift SQLite Migration** | `test/core/database/migration_test.dart` | Schema upgrade from v4 to v5 completes without data loss; FTS5 table queryable. |
| **WebRTC NAT Traversal** | Coturn test across cellular 4G (Grameenphone/Robi) | P2P fallback to TURN relay completes media handshake within 1200ms. |
| **Stream Efficiency** | Flutter DevTools Performance & Network Monitor | `ChatsListScreen` with 50 chats maintains exactly 1 Firestore stream; 0 frame drops. |
| **Offline Messaging** | Airplane Mode toggle test | Send message offline $\rightarrow$ clock icon $\rightarrow$ airplane mode OFF $\rightarrow$ single tick within 2s. |
| **Voice Audio Routing** | Proximity sensor test on physical Android/iOS | Audio flips from loudspeaker to earpiece when proximity sensor covered. |
| **Unit & Integration Suite** | `flutter test` across all features | All 322+ existing tests pass; 40+ new chat unit tests pass with 0 regressions. |
