# ADR 005: Security Hardening Architecture

## Context
Bhromon handles personal data, location tracking, and premium purchases. Protecting user data, preventing API abuse, and securing the offline storage is paramount.

## Decision
We implemented a multi-layered security system:
1. **Device Integrity**: Jailbreak/root detection block list at startup.
2. **Secure Network Client**: Certificate pinning (SHA-256) and automated Firebase token injection via Dio interceptors.
3. **Local Encryption**: Hive box encryption with AES-256.

## Rationale
- **Jailbreak Detection**: Prevents runtime code injection and memory sniffing on compromise-vulnerable devices.
- **Dio Secure Client**: Standardizes API calls with automated retry mechanisms and validates SSL certs against trusted fingerprints.
- **Hive Encryption**: Protects local database files stored on disk from copy-paste tampering.

## Amendment (2026-10): encryption key handling
- The AES key is generated once and kept in the platform keystore
  (`flutter_secure_storage`); it is read once per process.
- Earlier versions fell back to a fixed key compiled into the app whenever
  secure storage failed. That key is no longer used to write anything. When no
  device key is available, boxes are kept in memory for the session and
  nothing is written to disk.
- Boxes written with the old fixed key, or unencrypted, are re-encrypted with
  the device key on first open, through a temporary copy so a crash can't lose
  data.
- Boxes are never opened with a key that may be wrong: with Hive's default
  crash recovery, a wrong key truncates the box to nothing. Readability is
  probed on a throwaway copy, and a per-box key fingerprint
  (`hive_key_marks`) means this happens once per box, not on every launch.
