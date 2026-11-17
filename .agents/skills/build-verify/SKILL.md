---
name: build-verify
description: >-
  Two-step Worker (High) implementation followed by adversarial Verifier (Extra/XHigh)
  verification tailored to Bhromon's Flutter CI, security rules, and PR review workflow.
  Use when invoking /build-verify or splitting implementation and adversarial verification.
---

# Build & Verify Two-Phase Workflow (Bhromon)

Execute the user's task strictly in two isolated phases so verification audits the actual diff and test output without confirmation bias from implementation.

> [!NOTE]
> Use `.agents/skills/build-verify/SKILL.md` (this skill, invoked via `/build-verify`) rather than deprecated `.agents/workflows/*.md`.

---

## Phase 1 — Implementation (Gemini 4 Hydrogen: High)

1. **Branch First (Mandatory)**:
   - Never commit or push directly to `main`. Ensure you are on a feature/fix branch off up-to-date `main`:
     ```powershell
     git pull origin main
     git checkout -b <fix|feat|chore>/<short-name>
     ```
2. **Inspect Context Before Editing**:
   - Read target source files, related tests, and relevant sections of `AGENTS.md`.
   - Respect Bhromon invariants:
     - `tour_group` uses `StatefulWidget` + direct repository streams (no BLoC/Cubit, no stream creation or writes inside `build()`).
     - Cancel stream subscriptions in `dispose()` and guard `setState` with `if (!mounted) return;`.
     - Guard all `dart:io` usage with `if (!kIsWeb)` and keep web compatibility intact.
     - Use `FieldPath` for email-keyed Firestore map updates and preserve cross-layer policy parity (`lib/`, `firestore.rules`, `media-server/`) where applicable.
3. **Implement Cleanly & Add Tests**:
   - Apply minimal, surgical edits and add/update focused unit or widget tests in `test/`.
4. **Run Phase 1 Verification**:
   ```powershell
   dart format .
   flutter analyze --fatal-infos
   Remove-Item -Recurse -Force build\unit_test_assets -ErrorAction SilentlyContinue
   flutter test <targeted_test_paths>
   ```
   - If `firestore.rules` or `storage.rules` changed, follow the `bhromon-rules-testing` skill (`npx firebase-tools@13.35.1 emulators:exec ...`).
5. **Write Handoff & Pause**:
   - Summarize the requirements, edited files, design decisions, and exact check commands/results in `.agent-state.md` (gitignored, transient).
   - **STOP** after Phase 1. Ask the user to switch the model thinking level to **Extra (`xhigh`)** — ideally in a fresh chat session for zero confirmation bias — and reply `"verify"` (or `"Run Phase 2"`).

---

## Phase 2 — Adversarial Verification (Gemini 4 Hydrogen: Extra / XHigh)

1. **Clean Context Audit**:
   - Read `.agent-state.md`, `git status`, and `git diff` (and `git diff main...HEAD` if commits exist).
   - Assume the Phase 1 patch contains subtle logic bugs, missing edge cases, or `AGENTS.md` / CI violations.
2. **Bhromon Adversarial Checklist**:
   - **Formatting & Static Analysis**: Does the diff pass `dart format --output=none --set-exit-if-changed .` and `flutter analyze --fatal-infos` with zero warnings or infos?
   - **Guard Scripts**: Does it introduce unguarded `dart:io` imports (`tool/check_dart_io.sh`) or swallowed empty `catch` blocks (`tool/check_empty_catches.sh`)?
   - **State & Lifecycle**: Are streams/subscriptions created outside `build()`, disposed cleanly, and reactive to asynchronous auth state changes?
   - **UI & Overflow**: Do narrow viewports (`320px`) and `2.0x` text scale fit without `RenderFlex` overflows?
   - **Edge Cases & Security**: Null/empty/offline/unauthenticated states handled? Email casing, `FieldPath`, and Firestore/Storage rules considered? Any secrets or temporary files left behind?
   - **Test Strength**: Do tests assert real failure modes and async state transitions rather than trivial happy paths?
3. **Fix Loop (Cap at 2–3 Rounds) & Full Verification**:
   - Fix any defects uncovered, then re-run until exit code `0`:
     ```powershell
     dart format --output=none --set-exit-if-changed .
     flutter analyze --fatal-infos
     Remove-Item -Recurse -Force build\unit_test_assets -ErrorAction SilentlyContinue
     flutter test <relevant_or_full_test_suite>
     ```
   - If Git Bash / bash is available, also run CI guard checks:
     ```powershell
     bash tool/check_dart_io.sh
     bash tool/check_empty_catches.sh
     ```
4. **Cleanup, PR & Mutual Peer Review Gate**:
   - Delete `.agent-state.md` once verification passes so no transient state remains in the workspace.
   - Commit clean changes to the feature branch, push, and open/update the PR against `main`:
     ```powershell
     git add <verified-files>
     git commit -m "<type>(<scope>): <concise summary>"
     git push -u origin HEAD
     gh pr create --base main
     ```
   - Ensure all required CI checks (`Dart Format`, `Analyze`, `Build Web (release)`, `Test`, and `Build Android (debug APK)` / Functions / Media Server when triggered) are green, and complete **Mutual Peer Review** with Claude documented in PR comments before merging to `main`.
