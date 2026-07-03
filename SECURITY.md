# Bhromon — Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Bhromon, please report it **privately**:

- **Email**: security@bhromon.com
- **Subject**: `[SECURITY] <brief description>`
- Do NOT open a public GitHub Issue for security vulnerabilities.

We will acknowledge your report within **48 hours** and aim to resolve critical issues within **7 days**.

## Scope

In scope:
- Firebase Security Rules bypass
- Authentication flaws (OTP bypass, token forgery)
- Data leakage from Firestore/Storage
- Privilege escalation (accessing tier-restricted data)
- Server-Side Request Forgery (SSRF) on Cloud Functions

Out of scope:
- Rate limiting issues requiring physical device access
- Attacks requiring root/jailbreak access (app already blocks these)
- Social engineering attacks

## Responsible Disclosure

We follow responsible disclosure principles. We will:
- Acknowledge and triage your report promptly
- Keep you informed of our progress
- Credit you (with your permission) after the fix is released
- Not take legal action against researchers acting in good faith

## Severity Classification

| Severity | SLA |
|----------|-----|
| Critical | 48 hours |
| High | 7 days |
| Medium | 30 days |
| Low | 90 days |
