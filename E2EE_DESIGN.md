# End-to-end encryption for one-to-one chat

**Status: M0 decisions recorded; M1 in progress.** Nothing in this document is implemented or enabled. Until milestone M7, no screen, store listing or app text may say that a chat is end-to-end encrypted.

**Scope:** one-to-one chats between two people who share a tour. Group chats, channels, calls, multiple devices and web are out of scope for the first slice (section 9).

This is the design and threat model that `ROADMAP.md` (Track E) requires before any build.

## 1. What the server can read today

- Each text message is sent twice, in plaintext. The app dispatches it to the VPS chat service (`lib/features/chat/presentation/pages/chat_screen.dart:1113-1124`, `lib/features/chat/data/vps_chat_service.dart:431`). It also writes the same `text` to `chats/{chatId}/messages/{id}` in Firestore (`chat_screen.dart:1127-1143`).
- The VPS chat service stores the message in a SQLite `messages` table with a `text` column (`media-server/chat.py:122-137`, saved by `save_message` at line 402).
- Push notifications are built from the text. The send route builds the push body from `req.text` (`media-server/chat.py:1177-1184`). The Firestore watcher builds previews from the text too (`media-server/notifications.py:478` and `:519`).
- Photos, video and audio are uploaded to the VPS media server without client-side encryption.
- Metadata is visible to the server in every case: sender and recipient ids, chat id, shared tour, timestamps, sizes, delivery and read state, typing and online status, and call signalling.
- The app's local data is encrypted at rest with a key held in the platform keystore (`lib/core/security/hive_encryption_service.dart:7` and `:28`). That protects a stolen device. It does not protect against the server.

## 2. Goals and non-goals

**Goals for the first slice**

- The operator, the VPS, Firebase, and anyone with database or backup access cannot read the text of one-to-one messages.
- Forward secrecy: a later key compromise does not reveal earlier messages.
- A key substitution by the server is detectable through a safety-number check.
- A message that cannot be decrypted is never shown as plaintext, and an encrypted chat never falls back to plaintext.
- The user can see whether a chat is encrypted and whether the contact is verified.

**Non-goals for the first slice**

- Group chats and channels. They need a sender-key design (`ROADMAP.md:100`).
- Calls. Media already uses DTLS-SRTP, but signalling is not yet authenticated (section 8).
- Several devices per account, message search, recovery of lost keys, and any web client.
- Hiding metadata. Who talks to whom, when, and how large the messages are stay visible.
- Protection against a compromised phone, and deletion from a recipient's device.

## 3. Threat model

**Assets:** the text and media of messages; the identity and session keys on each device; the contact graph and timing (metadata).

**Adversaries**

- **A1 Network observer.** TLS already protects the transport. The design must not weaken that.
- **A2 Curious operator or insider** with read access to Firestore, the VPS disk, backups or logs. This is the central case: it must learn no message content.
- **A3 Active operator.** It can rewrite stored data, serve other prekeys, substitute an identity key, or ship a modified client, especially a web build. The design limits this with safety-number verification and a native-only first slice. It cannot prevent it for contacts who never verify (trust on first use), so the app must say so.
- **A4 Another user.** Cannot read a chat they are not part of. Can impersonate a user only if they hold that user's device or account.
- **A5 Legal compulsion.** The operator can be compelled to hand over ciphertext, metadata and anything else it holds. If it holds no keys, it holds no content.

**Explicitly out of scope:** device compromise (malware, an unlocked stolen phone), screenshots, metadata, and a malicious client update unless builds are signed and reproducible (decision D6).

## 4. Protocol

- **Session establishment:** Olm, the one-to-one protocol: a triple Diffie-Hellman key agreement (3DH) followed by the Double Ratchet. Identity keys are Curve25519 with Ed25519 signing keys. Each device publishes a batch of signed one-time keys and a fallback key. **Implementation choice:** use vodozemac session version 2, which keeps the full MAC. Version 1 truncates the MAC and exists for libolm compatibility. Version 2 sits behind the crate's `experimental-session-config` feature, which the M6 review must cover.
- **Message body:** the encrypted payload is JSON. It carries the chat id, the sender and recipient user ids, the message id and the send time. Olm does not bind these identifiers, so the receiver must check that they match the outer envelope and the chat where the message was stored. Otherwise a server could move a ciphertext into another chat.
- **Envelope:** version, algorithm id, sender and recipient device ids, message type (pre-key or ratchet message), and ciphertext.
- **Idempotency:** the client's message id is the key. The VPS already saves a retry once (`media-server/chat.py:1160`, `save_message_once` at line 480), and receivers de-duplicate on the same id.
- **Skipped message keys:** bounded, so a malicious sender cannot make the receiver keep unlimited keys.

## 5. Library choice (decision D1)

The repository is Apache-2.0 (`LICENSE`). A library's license must allow the app to be distributed under that license. Each candidate was checked from its published package or crate:

| Option | License (checked) | Verdict |
|---|---|---|
| `libsignal_protocol_dart` 0.8.2, a pure-Dart Signal protocol | GPL-3.0 (package archive) | Not usable in this app as published. |
| `flutter_vodozemac` 0.9.0, Dart bindings to Matrix's Olm core | AGPL-3.0 (package archive) | Not usable as published. |
| `vodozemac` 0.11.2, the Rust core behind `flutter_vodozemac` | Apache-2.0 (crates.io) | Usable, if we build our own thin bindings. |
| `cryptography` 2.9.0, Dart | Apache-2.0 (package archive) | Usable for primitives only. It has no ratchet. |
| Signal's official `libsignal` | Not checked from here. Believed to be AGPL-3.0. | Verify before ruling it out. |
| A ratchet we write ourselves | Not applicable | Not acceptable without independent review. |

**Recommendation:** Olm through the Apache-2.0 `vodozemac` crate, with our own bindings for Android and iOS, and no web build in the first slice. The bindings are the main new work. They need a Rust build in CI and a measured binary-size cost. The audit history of `vodozemac` must be checked before adoption. The external review (M6) covers our integration either way.

**M1 host spike (Linux, done):** `vodozemac` 0.11.2 built here and passed a session round trip. It covered the pre-key message, a reply, ten messages across five round trips, a rejected replay of the pre-key message, and an encrypted account pickle that restores and rejects a wrong key. It took about 77 µs per message in release mode on this host. The stripped binary was 806 KB, which includes the Rust standard library. That is a host figure, not the Android or iOS cost. The spike is kept outside the repository until M1's CI job is in place.

## 6. Keys and their lifecycle

- **Storage:** the Olm account and sessions are kept in the local encrypted store, under a key in the platform keystore (`FlutterSecureStorage`). They are never exported.
- **Publication:** the signed prekey bundle (identity key, signed one-time keys, fallback key) is written to Firestore, to a collection such as `e2ee_keys/{uid}` (decision D7). Only the owner writes it. Any signed-in user can read it, because public keys are meant to be public. Rules tests cover its shape.
- **Replenishment:** one-time keys are topped up when the device starts and after each batch of messages.
- **Verification:** a safety number is a fingerprint of both identity keys, computed in a canonical order. It is shown as digits and as a QR code. The exact encoding is fixed in M2 with test vectors.
- **Key change:** if a contact's identity key changes, the chat shows a warning and marks the contact unverified. The chat is not blocked.
- **Device loss:** the new device gets a new identity, and old history is not readable there. The app says so.
- **Account deletion:** `gdprDeleteUser` removes the prekey bundle, and the client removes its sessions.

## 7. Server and storage changes

- **Firestore:** a message in an encrypted chat carries an `envelope` field only, with no `text`. Rules refuse `text` in encrypted chats and check the envelope's size and shape. Delivery and read states stay as they are, since they are metadata.
- **VPS chat service:** stores and relays envelopes for encrypted chats, with `text` empty. Push bodies become generic ("New message", localized). The push title may keep the sender's name, which the server already knows.
- **Watcher:** `media-server/notifications.py` must not read text from encrypted chats. The chat document needs an `e2ee` flag so the server can tell.
- **Existing history:** plaintext chats stay plaintext and are labelled as not encrypted. Nothing is encrypted retroactively (decision D4).
- **Backups:** the chat database stays excluded from Google Drive (`AGENTS.md:283`). Once content is ciphertext, backing it up can be revisited. Keys are not backed up, though, so a restore loses encrypted content unless D2 is decided.

## 8. Calls and other features

- **Calls:** media uses DTLS-SRTP, but the signalling that carries the certificate fingerprints goes through the VPS and Firestore. A server that rewrites those fingerprints can man-in-the-middle a call. Calls need signalling authenticated with the chat keys, which is a later slice. Until then, the call label in `lib/core/localization/translation_keys.dart:128` ("End-to-end encrypted") should be reviewed (decision D8).
- **Reactions, edits, deletes, stars, forwards, replies, polls:** these carry content, so they must be encrypted as well. The first slice disables them in encrypted chats. Each one is a separate task after that.
- **Media:** a later slice. Each file is encrypted with a random 256-bit key using an AEAD cipher. The ciphertext is uploaded, and the key and the file hash go inside the encrypted message. The server sees the blob's size and upload time.

## 9. First slice (what M2 to M4 build)

- Native Android and iOS only.
- One-to-one text messages, with delivery and read states, between two people who share a tour.
- One device per account. A second device shows the chat as not available on that device.
- Safety-number verification and key-change warnings.
- Generic push text.
- An explicit "encrypted" or "not encrypted" state in the chat header.
- Behind a compile-time flag, `kE2eeOneToOne`, which defaults to off.

## 10. Testing

- Test vectors from the chosen library, plus our own envelope and payload tests.
- Property tests for ratchet sequences: out-of-order delivery, skipped keys and replays.
- Fuzzing of envelope parsing.
- Rules tests on the emulator: encrypted chats refuse `text` and malformed envelopes.
- `media-server` pytest: encrypted messages are stored and relayed without text, and push bodies are generic.
- A device matrix with two phones: offline and online transitions, reinstall, key change, and push while the app is closed.
- An external review of the protocol integration and key handling before the flag is turned on for anyone.

## 11. Milestones and gates

- **M0 Design and threat model** (this document). Gate: the owner decides D1 to D9.
- **M1 Library spike.** Build the `vodozemac` bindings for Android and iOS in CI, check the license, pass the test vectors, and measure binary size. Gate: the build is reproducible in CI and the binary-size cost is accepted. Estimate the rest after this. Status: the host spike is done (section 5). The Android and iOS builds in CI, the official test vectors and the mobile binary-size measurement remain.
- **M2 Crypto module behind the flag.** Local only: account, sessions, envelope, verification. Unit tests and vectors. No server changes yet.
- **M3 Server support.** Envelope storage, generic push, rules and tests. Still behind the flag.
- **M4 Client send and receive** for internal test accounts, with the verification screen.
- **M5 Dogfood.** Internal testers. Count and log errors, never content.
- **M6 External review.** Protocol integration and key handling. Fix the findings.
- **M7 Limited rollout.** Then the product copy and docs change to say "end-to-end encrypted" for the chats that have rolled out.

## 12. Decisions for the owner

Decided on 2026-11-08 with the recommendations, except D6 and D9. Those were not covered by a recommendation, so they stay open.

- **D1 Library: decided.** Olm through the Apache-2.0 `vodozemac` crate, with our own bindings. Signal's own `libsignal` was not checked, and the chosen option does not depend on it.
- **D2 Lost device: decided.** Lost history is accepted in the first slice. An encrypted key backup is a separate design.
- **D3 Web: decided.** Excluded from the first slice.
- **D4 Existing history: decided.** Kept as plaintext and labelled.
- **D5 Verification: decided.** Safety numbers, with QR as the second path.
- **D6 Client integrity: open.** Signed and reproducible builds, or accept that a malicious client update is inside the threat model. Needed before M6.
- **D7 Key collection: decided.** `e2ee_keys/{uid}`.
- **D8 Calls copy: done.** The call label now reads "Encrypted call" in English and "এনক্রিপ্টেড কল" in Bengali. It no longer says "end-to-end".
- **D9 Budget and reviewer for M6: open.**

## 13. What this document does not claim

It does not claim that the current app encrypts anything end to end. Today's chats are readable by the operator, as section 1 shows.
