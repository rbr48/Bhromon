# ADR 004: Firebase Region Gating (asia-south1)

## Context
Bhromon's primary target user base is located in Bangladesh (South Asia). Minimizing network latency is critical for real-time chat, travel updates, and interactive maps.

## Decision
We enforce the use of the `asia-south1` (Mumbai) region for all Cloud Functions and Firestore triggers.

## Rationale
- **Latency Reduction**: `asia-south1` is the closest GCP region to Bangladesh, reducing latency by up to 150ms compared to `us-central1`.
- **Firestore Alignment**: Directing Cloud Functions to the same region as Firestore databases avoids cross-region egress costs and optimizes write triggers.
- **Rules Consistency**: Cloud function deployment configurations enforce this region globally.
