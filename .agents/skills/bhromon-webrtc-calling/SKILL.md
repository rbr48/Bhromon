---
name: bhromon-webrtc-calling
description: >-
  Architecture, signaling, audio routing, and in-call controls for Bhromon WebRTC
  1-on-1 audio/video calling and Discord-style group Voice Lounge. Use this skill
  when modifying WebRTC signaling, in-call speaker routing, camera controls, or CallKit.
---

# Bhromon WebRTC Calling & Voice Lounge Playbook

This skill outlines the WebRTC architecture, signaling protocols, and mobile platform audio/video routing invariants for Bhromon.

---

## 1. Subsystem Architecture

- **1-on-1 Audio/Video Calls**: Managed by `CallSignalingService`, rendered in `call_screen.dart`.
- **Group Voice Lounge**: Drop-in multi-peer mesh managed by `VoiceRoomService`, rendered in `voice_room_screen.dart` with persistent docked floating bar.
- **Relay & STUN/TURN**: Coturn server on Hostinger VPS (`turn.sottocall.com`), TLS on port 5349, UDP/TCP on port 3478.
- **Signaling**: Hybrid signaling with sub-15ms WebSocket relay on Hostinger VPS (`/api/chat/ws`) backed by Firestore `calls/{callId}` document fallback.

---

## 2. In-Call Controls & Audio Routing Invariants

### A. Mobile Audio Routing (`Helper.setSpeakerphoneOn`)
- Android uses `AudioManager.MODE_IN_COMMUNICATION`.
- Audio routing must be locked properly during lifecycle state changes:
  - When call state changes to answered.
  - When remote stream is bound.
  - When user toggles the loudspeaker button in the call screen.
- Speaker routing:
  - Default for audio calls: Earpiece / receiver (`Helper.setSpeakerphoneOn(false)`).
  - Default for video calls: Loudspeaker (`Helper.setSpeakerphoneOn(true)`).
  - Toggling speakerphone dynamically flips audio route without tearing down the audio track or session.

### B. In-Call Camera Switching
- Toggling between front-facing and rear cameras is performed using WebRTC's `Helper.switchCamera(videoTrack)` or `replaceTrack`.
- Camera flip button is located directly in the call screen bottom controls next to mute and speaker toggles.
- Switching cameras must never trigger SDP renegotiation or pause the audio session.

### C. Preventing Push End-Call Race Conditions
- A call answered on one device dispatches a push notification to cancel ringing on the user's other devices.
- In-call signaling must ensure an answered call is not accidentally terminated by its own ring-cancellation push (PR #274).

---

## 3. Mandatory WebRTC Invariants

1. **ICE Candidate Queuing**: Early ICE candidates arriving before `setRemoteDescription` completes must be buffered in `_pendingIceCandidates` and drained once remote description is set.
2. **Audio Session Release**: Every `RTCPeerConnection` must be explicitly `dispose()`d after `close()`. Disposing releases the native Android audio focus and mode back to system defaults.
3. **Continuous Audio Sink**: Audio calls and Voice Lounge must keep an invisible 1x1 `RTCVideoView` mounted in the widget tree so WebRTC audio flows reliably on Web DOM and mobile audio sinks.
4. **Bidirectional Negotiation**: Always pass `{ 'offerToReceiveAudio': 1, 'offerToReceiveVideo': 1 }` to `createOffer` and `createAnswer`.
5. **Privacy / Shared Tour Invariant**: 1-on-1 calls are permitted only between users who share an active tour membership.
