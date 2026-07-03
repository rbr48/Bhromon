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
