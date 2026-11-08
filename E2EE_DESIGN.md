# End-to-end encryption for one-to-one chat

**Status: M0 to M4 in the repository; M5 to M7 open.** The crypto module, the server support and the client send, receive and verification are behind `kE2eeOneToOne`, which is off by default. Builds that turn it on (internal testing) can use encrypted chats between two people who share a tour. Until milestone M7, no store listing or product text may say that chats are end-to-end encrypted.

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

- **Session establishment:** Olm, the one-to-one protocol: a triple Diffie-Hellman key agreement (3DH) followed by the Double Ratchet. Identity keys are Curve25519 with Ed25519 signing keys. Each device publishes a batch of signed one-time keys and a fallback key. **Session version (D10, decided):** use vodozemac session version 1. It truncates the MAC to 8 bytes, as libolm does, and it is the crate's default. It needs no experimental feature, and it is the only version the libolm interoperability tests cover, so independent test vectors can check it. Version 2 (full MAC) is not used. Section 12 gives the reasons.
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

**M1 host spike (Linux, done):** `vodozemac` 0.11.2 built here and passed a session round trip. It covered the pre-key message, a reply, ten messages across five round trips, a rejected replay of the pre-key message, and an encrypted account pickle that restores and rejects a wrong key. It took about 77 µs per message in release mode on this host. The stripped binary was 806 KB, which includes the Rust standard library. That is a host figure, not the Android or iOS cost. The spike itself stays outside the repository, and the crate below replaces it.

**M1 crate (`native/e2ee_olm`, in the repository):** a thin C interface over `vodozemac` 0.11.2 with session version 1 (decision D10). It is ABI version 1 with 23 functions, declared in `native/e2ee_olm/include/e2ee_olm.h`. It covers accounts, one-time and fallback keys, Ed25519 signing and verification, sessions, and encrypted pickles for accounts and sessions. The Linux checks pass:

- Nine Rust unit tests. They cover a session round trip with replay refusal, a pickle with a wrong-key refusal, signatures, fallback keys, a tampered message that is refused while the session keeps working, a pre-key message refused under another identity key, a version 2 session refused, so only one session format is accepted, and null and bad arguments.
- `clippy -D warnings`, `rustfmt`, and a C smoke test compiled with `-Wall -Wextra -Werror` against the static library.
- A check that the 23 exported symbols match the header.
- Licences of the 79 locked crates. All are permissive: MIT, Apache-2.0, BSD-3-Clause, Unlicense, Unicode-3.0, or a dual licence with a permissive option. None is GPL or AGPL.
- Size, for session version 1 (decision D10). The stripped x86_64 shared library on this host is 927,528 bytes. On Android, the stripped shared libraries are 801,960 bytes (arm64-v8a), 610,588 bytes (armeabi-v7a) and 947,280 bytes (x86_64), from the CI run [42478846594](https://github.com/rbr48/Bhromon/actions/runs/42478846594). The version 2 figures were 1 to 4 KB larger on each ABI. The iOS static archives are about 24 MB each because they hold every object file, so they are not the app figure. The C smoke test linked for the iOS simulator at 15.5 is 1,913,112 bytes stripped (measured on the version 2 code, not yet repeated). It references every export, so it is an upper bound for what the library adds to an app; the real figure comes once the library is linked into the app (M2).
- Determinism. A rebuild on the same machine gives an identical SHA-256. Bit-identical output across machines needs path remapping, which is still open.
- Interoperability with libolm 3.2.16, in both directions, with fresh keys: 94 checks, including the session ids. It runs in CI.

`vodozemac`'s published crate has no complete test vectors. It has two libolm-format messages, used only by its parsing tests (`src/olm/messages/mod.rs`). The gate is therefore interoperability with libolm itself. `native/e2ee_olm/tests/interop/libolm_interop.c` links libolm 3.2.16 (`libolm-dev`) and the shipped library. On every CI run it runs both directions with fresh keys: libolm starts a session and this library replies, and this library starts a session and libolm replies. It checks 94 results, including the session ids on both ends. The test is dynamic rather than fixed files, so it commits no private keys, and both directions are checked every time. A negative control, a wrong identity key, makes it fail.

## 6. Keys and their lifecycle

- **Storage:** the Olm account and sessions are kept in the local encrypted store, under a key in the platform keystore (`FlutterSecureStorage`). They are never exported.
- **Publication:** the signed prekey bundle (identity key, signed one-time keys, fallback key) is written to Firestore, to a collection such as `e2ee_keys/{uid}` (decision D7). Only the owner writes it. Any signed-in user can read it, because public keys are meant to be public. Rules tests cover its shape. The identity key is signed by the device's Ed25519 key too, over `{"identity":"<base64>"}`, so a server cannot pair one device's signing key with another device's identity key. The verifier refuses a bundle whose identity signature is wrong, and skips a one-time key whose signature is wrong (M2, `e2ee_device.dart`). A bundle holds only the keys not yet published. The server keeps the published fallback key and adds new one-time keys (M3).
- **Replenishment:** one-time keys are topped up when the device starts and after each batch of messages. Each one-time key is one document, `e2ee_keys/{uid}/oneTimeKeys/{keyId}`. The owner removes a key after the first message that uses it, so a key is used once (M3 rules; the client does the removal in M4).
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

- Test vectors. Libolm interoperability, both directions, for session version 1 (decision D10), with fresh keys on every CI run. Plus our own envelope and payload tests.
- Property tests for ratchet sequences: out-of-order delivery, skipped keys and replays.
- Fuzzing of envelope parsing.
- Rules tests on the emulator: encrypted chats refuse `text` and malformed envelopes.
- `media-server` pytest: encrypted messages are stored and relayed without text, and push bodies are generic.
- A device matrix with two phones: offline and online transitions, reinstall, key change, and push while the app is closed.
- An external review of the protocol integration and key handling before the flag is turned on for anyone.

## 11. Milestones and gates

- **M0 Design and threat model** (this document). Gate: the owner decides D1 to D10.
- **M1 Library spike.** Build the `vodozemac` bindings for Android and iOS in CI, check the license, pass the test vectors, and measure binary size. Gate: the build is reproducible in CI and the binary-size cost is accepted. Estimate the rest after this. Status: the crate, the C interface, the tests, the licence check and the CI workflow (`.github/workflows/e2ee_native.yml`) are in place (section 5). The workflow passed on Linux, Android and iOS in run [42475757425](https://github.com/rbr48/Bhromon/actions/runs/42475757425), on the version 2 code. Decision D10 changed the session version, so the workflow runs again on the pull request. For session version 1, the workflow passed on Linux and Android in run [42478846594](https://github.com/rbr48/Bhromon/actions/runs/42478846594), including the libolm interoperability test (94 checks in both directions). Open: the owner's acceptance of the binary-size cost, and bit-identical builds across machines.
- **M2 Crypto module behind the flag.** Local only: account, sessions, envelope, verification. Unit tests and vectors. No server changes yet. Status: done, merged as [PR #397](https://github.com/rbr48/Bhromon/pull/397). The repository has the Dart bindings over the native library (`lib/features/chat/data/e2ee/`), the device logic, envelope, payload, prekey bundle and safety number (`lib/features/chat/domain/e2ee/`), the flag `kE2eeOneToOne` (off), and 48 Dart tests. The 11 native-engine tests need `E2EE_OLM_LIBRARY`, which the `dart` job of the E2EE workflow sets. The other 37 run anywhere, with a fake engine for the device logic. The safety-number vectors come from an independent computation. Resolved in M4 (see that section): (1) a changed identity key blocks that peer, and the device has no way yet to accept the new key once the user has been warned. (2) The device keeps one session per peer, so two first messages sent at the same moment, or a sender that lost its session, cannot be decrypted. M4 must pick a policy: several sessions per peer, or one deterministic winner. (3) The device creates its fallback key once and does not rotate it. M3 defines rotation and how the server merges a new bundle.
- **M3 Server support.** Envelope storage, generic push, rules and tests. Still behind the flag. Status: in progress. In the repository:
  - Rules (`firestore.rules`, `functions/tests/e2ee_rules.test.js`). The public key bundle and its one-time keys are readable by signed-in users and writable only by the owner, with the key and signature shapes checked. A chat's `e2ee` flag is set at creation and cannot change. An encrypted message is a text message whose content is an envelope and carries no `text`. A plaintext message carries no envelope. In an encrypted chat, edits, Delete for Everyone, reactions, stars, opened marks and settlements are refused. Receipts and Delete for Me stay allowed, since they carry no content.
  - Chat service (`media-server/e2ee_chat.py`, `chat.py`, `main.py`, `notifications.py`). It validates each envelope, refuses text and media in an encrypted chat, and refuses an envelope in a plaintext chat. It stores envelopes with no text. It reads the flag from the chat document in Firestore, not from the request, and keeps the answer for the life of the process. A flag that cannot be read is refused with 503. The push for an encrypted message says "New message", in the recipient's language.
  - Tests: 12 rules tests and 38 chat-service tests. CI runs both suites.
  - Owner's steps, not done here: deploy the rules, then deploy the chat service. For plaintext chats the only change is that an envelope is refused, and no client sends one yet. The chat service also makes one cached Firestore read per chat it has not seen.
- **M4 Client send and receive** for internal test accounts, with the verification screen. Status: implemented, behind the flag. Decisions made here, for the owner to redirect:
  1. **Sessions per identity (resolves M2 item 2).** A device keeps up to four Olm sessions per peer identity. It sends on the newest session the peer has answered, else the newest one. It reads a message by trying each session of that peer, and it starts a session only from a pre-key message that matches none of them. Two first messages sent at the same moment both read, and both sides keep talking. The race is tested on the native engine (`olm_native_test.dart`).
  2. **One-time keys are claimed, once (the same-key race).** A sender claims an unclaimed one-time key with a transaction before it starts a session from it: `oneTimeKeys/{keyId}` gets `claimedBy` and `claimedAt`, and nothing else can change. A second sender takes the next key, and the fallback key is used only when none can be claimed. The rules (`firestore.rules`) allow exactly that update, and `functions/tests/e2ee_rules.test.js` checks it. The owner removes a key after the first message that uses it, and the device reads the key from the pre-key message before decrypting, so the server copy goes first.
  3. **A changed identity warns and does not block (resolves M2 item 1).** The first bundle seen is pinned. A different identity is kept as pending. The chat keeps working on the new identity, a warning stays until the user accepts it, and accepting it does not verify it. The safety number of the pinned or pending identity is shown as digits and as a QR code.
  4. **Fallback key rotation (resolves M2 item 3).** The fallback key is rotated after seven days. The previous one stays valid for messages already on their way, as vodozemac keeps it.
  5. **One device per account.** A device that finds the keys belong to another device shows "set up on this device". Setting up here makes a new identity, removes the other device's one-time keys and drops its sessions. Its history is not readable here (decision D2).
  6. **Encrypted chats start only when both sides are ready.** A new chat is created encrypted when this device is set up and the other person has published keys. Existing chats keep their choice, and nothing is encrypted retroactively (D4).
  7. **Only text.** In an encrypted chat the app does not send photos, files, voice, location, expenses or `/split`. It does not edit, react to or star a message, and it does not quote a reply. The rules refuse those writes anyway. Search does not find encrypted text yet.
  8. **Gating.** The build turns encryption on with `--dart-define=E2EE_ONE_TO_ONE=true`. A web build never has it (D3). A device whose native library cannot be opened has no service, and its chats behave as before.
  9. **What the server sees.** A chat list preview is a lock, the push body is the generic text of M3, and the in-app notification says "New message". No plaintext is written to the chat document.
  Owner steps before any build with the flag can work on a device: deploy `firestore.rules`, deploy the chat service on the VPS (M3), and package the native library into the app. The Android build does not package `libe2ee_olm` yet (the native workflow only uploads it), and the iOS static link is untested. Known gaps: an account deletion does not yet remove the `e2ee_keys` bundle (section 6), and a claimed one-time key that was never used stays on the server.
- **M5 Dogfood.** Internal testers. Count and log errors, never content.
- **M6 External review.** Protocol integration and key handling. Fix the findings.
- **M7 Limited rollout.** Then the product copy and docs change to say "end-to-end encrypted" for the chats that have rolled out.

## 12. Decisions for the owner

Decided on 2026-11-08 with the recommendations, except D6 and D9. Those were not covered by a recommendation, so they stay open. D10 was delegated to the implementer, and it is decided below.

- **D1 Library: decided.** Olm through the Apache-2.0 `vodozemac` crate, with our own bindings. Signal's own `libsignal` was not checked, and the chosen option does not depend on it.
- **D2 Lost device: decided.** Lost history is accepted in the first slice. An encrypted key backup is a separate design.
- **D3 Web: decided.** Excluded from the first slice.
- **D4 Existing history: decided.** Kept as plaintext and labelled.
- **D5 Verification: decided.** Safety numbers, with QR as the second path.
- **D6 Client integrity: open.** Signed and reproducible builds, or accept that a malicious client update is inside the threat model. Needed before M6.
- **D7 Key collection: decided.** `e2ee_keys/{uid}`.
- **D8 Calls copy: done.** The call label now reads "Encrypted call" in English and "এনক্রিপ্টেড কল" in Bengali. It no longer says "end-to-end".
- **D9 Budget and reviewer for M6: open.**
- **D10 Session version for the first slice: decided, version 1.** The owner asked the implementer to decide. Version 1 is the version libolm produces and checks, so independent interoperability tests can check it. It truncates the MAC to 8 bytes, the same truncation libolm uses. Version 2 keeps the full MAC, but no independent implementation checks it, and it sits behind the crate's experimental feature. The threat model does not need a full MAC. Forging a truncated MAC takes about 2^64 attempts, and that holds only if the app sends nothing to the server when decryption fails, which is a requirement for M2. The bigger risk is an implementation error, and independent vectors are the best check for it. Consequences: the library creates and accepts only version 1 sessions, the experimental feature stays out of the shipped build, and the M1 gate needs libolm interoperability vectors. Revisit only if a review rejects the 8-byte MAC, and do it before any release. Evidence: the libolm interoperability test passes for version 1 in both directions (94 checks, libolm 3.2.16), and it fails when given a wrong identity key.

## 13. What this document does not claim

It does not claim that the current app encrypts anything end to end. Today's chats are readable by the operator, as section 1 shows.
