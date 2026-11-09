# End-to-End Encryption for Tour Group Channels & Multi-Party Spaces

**Status: Architectural Design & Cryptographic Protocol Specification (Track E)**  
**Companion document to:** [`E2EE_DESIGN.md`](./E2EE_DESIGN.md) (One-to-One Olm Protocol)

---

## 1. Overview & Objectives

While `E2EE_DESIGN.md` establishes pairwise one-to-one messaging via the Olm protocol (3DH + Double Ratchet), multi-party communication in Bhromon spans:
1. **Tour Group Channels** (e.g. `Announcement`, `General`, `Expenses`, `Canteen & tea`, `Bills & chores`, `Maintenance`).
2. **Preset-Specific Group Spaces** (Family circles, Offices, Campuses, Shared Messes, Housing Societies, and Samities).

In pairwise Olm, sending a message to a group of $N$ members requires $N-1$ separate encryption operations and $N-1$ distinct ciphertexts, imposing $O(N)$ computational and bandwidth overhead on the sending mobile device. For larger tour groups or office teams (10 to 60+ members), pairwise ratchet transmission exhausts mobile device battery and cellular upload bandwidth.

This document defines the **Sender-Key / Megolm Ratchet Protocol** for Bhromon group channels, guaranteeing:
* **$O(1)$ Message Encryption**: A single ciphertext payload is broadcast to all channel participants.
* **Confidentiality**: Neither the Hostinger VPS media server, Firebase Firestore, nor network eavesdroppers can read message content, attachments, or embedded financial records.
* **Backward Secrecy**: New members joining a tour group cannot read messages sent prior to their join timestamp.
* **Forward Secrecy**: When a member leaves or is removed, remaining members rotate keys so departing members cannot decrypt subsequent channel messages.
* **Tamper-Proof Financial Records**: Embedded `/split` expense proposals and settlements carry Ed25519 author signatures to prevent adversarial server injection or modification.

---

## 2. Threat Model

### Assets
* Plaintext of channel messages, photos, voice notes, and shared documents.
* Identity keys, ratchet keys, and outbound session states on each device.
* Financial ledger proposals (`/split`) and administrative moderation actions.

### Adversaries
* **A1: Curious Server Operator or Insider** with read access to Firestore, VPS databases, backups, or logs. *Must learn zero channel message content.*
* **A2: Malicious or Compromised Server** attempting to alter expense amounts, fabricate announcements, or inject unauthorized participants. *Prevented via Ed25519 digital signatures and membership validation.*
* **A3: Former Group Member** attempting to read future messages after departure or expulsion. *Prevented via forward-secrecy key ratcheting on membership changes.*
* **A4: Newly Added Member** attempting to decrypt prior discussions or confidential receipts from before their admission. *Prevented via forward-only ratchet advancement (backward secrecy).*

### Non-Goals
* Hiding group membership metadata (the list of participants in a group remains known to the group and server).
* Preventing local screen capture or physical device theft (protected by platform hardware keystores and Hive box encryption).

---

## 3. Cryptographic Protocol: Megolm / Sender-Key Ratchet

Bhromon adopts the **Megolm** group ratchet (an extension of the Double Ratchet designed specifically for secure group communication):

```
+-------------------------------------------------------------------------+
|                        Megolm Outbound Session                          |
|                                                                         |
|  [Root Key] ---> [HKDF] ---> [Message Key 0]  ---> Encrypt(Message 0)   |
|                    |                                                    |
|                    v                                                    |
|             [Ratchet State 1] ---> [Message Key 1] ---> Encrypt(Msg 1)  |
|                    |                                                    |
|                    v                                                    |
|             [Ratchet State 2] ---> ...                                  |
+-------------------------------------------------------------------------+
```

### A. Ratchet Mechanics
1. **Outbound Session Initialization**:
   Each participant $A$ generates an **Outbound Group Session** for channel $C$ consisting of:
   * A 256-bit initial session key $K_{0}$.
   * A 32-byte Ed25519 signing key pair $(sk_A, pk_A)$ bound to their device identity.
   * A monotonically increasing ratchet counter $i = 0$.

2. **Ratchet Step**:
   Advancing from state $i$ to $i+1$ uses a one-way Hash-based Key Derivation Function:
   $$\text{State}_{i+1} = \text{HKDF-SHA256}(\text{State}_i, \text{"bhromon-megolm-advance"})$$
   Because HKDF is a one-way function, possession of $\text{State}_i$ grants no ability to compute $\text{State}_{j}$ for any $j < i$ (preserving backward secrecy).

3. **Message Encryption**:
   A message $m$ at index $i$ is encrypted using **AES-256-GCM** (or ChaCha20-Poly1305):
   $$\text{Ciphertext} = \text{AES-GCM-Encrypt}(K_i, \text{IV}_i, \text{Payload})$$
   The payload includes the message text, tour ID, channel ID, timestamp, and an Ed25519 signature:
   $$\sigma = \text{Ed25519-Sign}(sk_A, \text{Ciphertext} \parallel \text{tourId} \parallel \text{channelId} \parallel i)$$

4. **Message Envelope**:
   ```json
   {
     "v": 1,
     "type": "group_envelope",
     "tourId": "t_coxsbazar_2026",
     "channelId": "ch_general",
     "senderUid": "usr_alice",
     "sessionId": "sess_alice_ch_general_01",
     "index": 42,
     "ct": "<base64-aes-gcm-ciphertext>",
     "iv": "<base64-12-byte-nonce>",
     "sig": "<base64-ed25519-signature>"
   }
   ```

---

## 4. Key Distribution & Synchronization

A group message cannot be decrypted without the sender's ratchet state for that session. Megolm distributes outbound keys via pairwise 1-to-1 channels:

```
Alice (Sender)                         Bob (Member)                   Charlie (Member)
     |                                      |                                 |
     |-- 1. Create Outbound Group Session   |                                 |
     |-- 2. Encrypt Key via Olm to Bob ---->|                                 |
     |-- 3. Encrypt Key via Olm to Charlie ---------------------------------->|
     |                                      |                                 |
     |-- 4. Broadcast Msg (AES-GCM) ------->|-------------------------------->|
```

1. **Initial Key Exchange**:
   Before Alice sends her first message in channel $C$, she encrypts her group session key $(\text{sessionId}, \text{State}_0, i=0)$ using the established 1-to-1 **Olm Double Ratchet** to each current member of the tour group.
   * Path: `tours/{tourId}/channels/{channelId}/keys/{recipientUid}` (or via VPS WebSocket).
   * Encrypted as standard 1-to-1 Olm message envelopes.
2. **Caching**:
   Receivers store the inbound session in encrypted local Hive storage (`InboundGroupSessionStore`). Subsequent messages from Alice only require ratcheting the inbound key forward—no further 1-to-1 key exchanges are needed for regular messages.

---

## 5. Membership Lifecycle (Forward & Backward Secrecy)

### A. New Member Join (Backward Secrecy)
When user Dave joins the tour group (or accepts an invite code):
1. Existing members (Alice, Bob, Charlie) are notified via Firestore membership stream.
2. Existing members **do not** send Dave their historical session keys ($i=0$).
3. Instead, when Alice next communicates, she exports her current ratchet state at index $i_{current}$ (e.g. $i=150$) and sends it to Dave via pairwise Olm.
4. Dave can decrypt all messages from index 150 onwards, but possesses zero cryptographic capability to decrypt messages $0 \dots 149$.

### B. Member Departure or Expulsion (Forward Secrecy)
When user Bob leaves the group or is removed by an admin:
1. The removal transaction writes to `tours/{tourId}/bans` and removes Bob's membership row (`memberships/{tourId}__{email}`).
2. **Session Rotation Invariant**:
   All remaining active members (Alice, Charlie, Dave) immediately terminate their current outbound group sessions for all channels in that tour.
3. Each remaining member creates a fresh **Outbound Group Session** ($K'_{0}$) and transmits the new session key only to the verified remaining active members.
4. Bob receives no new session keys. Future channel messages are encrypted under the new keys, permanently cutting Bob off from reading further channel messages.

---

## 6. Channel Operations & Financial Ledger Integrity

### A. Expense Proposals (`/split`)
In group channels, members frequently invoke `/split <amount> <title>`:
1. The financial parameters (amount in integer paisa, category, participants, splitMode) are serialized inside the encrypted Megolm payload.
2. The payload carries the sender's Ed25519 signature.
3. When the group admin or payer confirms the expense into the ledger (`addExpenseWithSplit`), the client presents the decrypted signed payload to Firestore rules. The rules verify that the ledger entry matches the cryptographic proof signed by the creator.

### B. Mentions (`@name`)
Mentions are parsed inside the plaintext prior to encryption. To maintain push notification delivery without leaking mention targets:
* The encrypted envelope includes a list of target `mentionedUids`:
  ```json
  {
    "envelope": { ... },
    "mentionedUids": ["usr_bob", "usr_charlie"]
  }
  ```
* The VPS notification watcher (`media-server/notifications.py`) pushes a generic notification ("You were mentioned in [Tour Name]") without decrypting or storing message text.

### C. Admin Moderation & Message Deletion
* **Delete for Me**: Handled locally on the client (adding message ID to `clearedMessageIds`).
* **Delete for Everyone (Admin Moderation)**:
  An admin may remove an inappropriate message by issuing a signed deletion tombstone:
  ```json
  {
    "type": "channel_tombstone",
    "targetMessageId": "msg_42",
    "channelId": "ch_general",
    "adminUid": "usr_admin",
    "adminSig": "<base64-signature>"
  }
  ```
  Client apps verify that `adminUid` held the `admin` or `owner` role at tombstone creation time before replacing the message with *"This message was removed by group admin"*.

---

## 7. Performance & Bandwidth Budget

| Metric | Pairwise Olm ($O(N)$) | Megolm Sender-Key ($O(1)$) |
|---|---|---|
| **Ciphertext Size per 100-char msg (20 members)** | $\approx 20 \times 320\text{ B} = 6.4\text{ KB}$ | $\mathbf{\approx 380\text{ B}}$ |
| **Sender Upload Bandwidth (20 members)** | $6.4\text{ KB/msg}$ | $\mathbf{0.38\text{ KB/msg}}$ |
| **Encryption Operations on Mobile CPU** | 20 Curve25519 ratchets ($\approx 1.5\text{ ms}$) | **1 AES-GCM + 1 HKDF ($\approx 0.05\text{ ms}$)** |
| **Server Relay Complexity** | Relays $N$ distinct packets | **Relays 1 broadcast packet** |

Megolm delivers a **94% reduction in bandwidth** and **96% reduction in CPU processing**, guaranteeing silky-smooth 60fps UI performance even in large multi-family tour groups.

---

## 8. Integration Roadmap & Milestones

1. **Phase G1: Sender-Key Crate Bindings**:
   Extend `native/e2ee_olm` with `vodozemac::megolm` group session functions (outbound session, inbound session, export/import keys).
2. **Phase G2: Channel Key Distribution**:
   Implement `GroupKeyDistributionService` over pairwise Olm channels.
3. **Phase G3: Channel Screen UI & Storage**:
   Wire `GroupEnvelope` handling into `channel_messages_screen.dart` and encrypted Drift cache.
4. **Phase G4: Forward-Secrecy Automated Rekeying**:
   Trigger automated session rotation on `onTourMembershipRemoved` events.
5. **Phase G5: External Cryptographic Audit**:
   Third-party peer review alongside Milestone M6.
